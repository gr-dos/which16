/*
 * which - locate a program the way COMMAND.COM would
 *
 * Searches the current directory and then each directory in PATH for
 * NAME.COM, NAME.EXE and NAME.BAT, in that order, and prints the full
 * path of the program COMMAND.COM would run.  As with COMMAND.COM:
 *
 *   - an explicit extension restricts the search to that file, and only
 *     .COM, .EXE and .BAT name a program (FOO.TXT is never found);
 *   - a NAME with a drive or directory (C:\BIN\FOO, BIN\FOO, C:FOO) is
 *     looked for only there, and PATH is not searched;
 *   - wildcards are not allowed.
 *
 * Paths are printed in full and in lower case, with the extension.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dos.h>

#ifndef VERSION
#define VERSION   "unknown"
#endif

#define MAXDIRS   64

static const char *progname = "which";
static const char *const exts[] = { "com", "exe", "bat" };
#define NEXTS     (sizeof exts / sizeof exts[0])

static int opt_all;
static int opt_silent;

static char *dirs[MAXDIRS];   /* search list: current directory, then PATH */
static int ndirs;

static void usage(FILE *fp)
{
    fprintf(fp,
        "Usage: which [OPTION]... NAME...\n"
        "Show the full path of the program COMMAND.COM runs for each NAME.\n"
        "\n"
        "The current directory is searched, then each directory in PATH,\n"
        "for NAME.COM, NAME.EXE and NAME.BAT.  A NAME with an extension or\n"
        "a directory is looked for only as given.\n"
        "\n"
        "  -a, --all      print every match, not just the first\n"
        "  -s, --silent   print nothing; the exit status shows the result\n"
        "  -h, --help     display this help and exit\n"
        "      --version  output version information and exit\n"
        "\n"
        "Exit status is 0 if every NAME was found, 1 otherwise.\n");
}

/* Make DIR absolute in OUT (no trailing backslash except at a root). */
static int normalize(char *out, const char *dir)
{
    size_t n;

    if (_fullpath(out, *dir ? dir : ".", _MAX_PATH) == NULL)
        return -1;
    n = strlen(out);
    if (n > 3 && out[n - 1] == '\\')
        out[n - 1] = '\0';
    strlwr(out);
    return 0;
}

/* Add DIR to the search list unless it is already there. */
static void add_dir(const char *dir)
{
    char buf[_MAX_PATH];
    int i;

    if (ndirs >= MAXDIRS || normalize(buf, dir) != 0)
        return;
    for (i = 0; i < ndirs; i++)
        if (strcmp(dirs[i], buf) == 0)
            return;
    if ((dirs[ndirs] = strdup(buf)) != NULL)
        ndirs++;
}

static void build_dirs(void)
{
    const char *path = getenv("PATH");
    char buf[_MAX_PATH];

    add_dir("");
    while (path != NULL && *path) {
        const char *end = strchr(path, ';');
        size_t n = end ? (size_t)(end - path) : strlen(path);

        while (n > 0 && path[n - 1] == ' ')
            n--;
        while (n > 0 && *path == ' ')
            path++, n--;
        if (n > 0 && n < sizeof buf) {
            memcpy(buf, path, n);
            buf[n] = '\0';
            add_dir(buf);
        }
        path = end ? end + 1 : NULL;
    }
}

/*
 * Look in DIR (normalized) for BASE with each of the extensions in EXTS.
 * Print what is found, stopping at the first match unless -a.
 * Returns the number of matches.
 */
static int search_dir(const char *dir, const char *base,
                      const char *const *e, int ne)
{
    char pat[_MAX_PATH + 16];
    const char *sep = dir[strlen(dir) - 1] == '\\' ? "" : "\\";
    struct find_t f;
    int i, found = 0;

    for (i = 0; i < ne; i++) {
        if (strlen(dir) + strlen(base) + 6 > sizeof pat)
            return found;
        sprintf(pat, "%s%s%s.%s", dir, sep, base, e[i]);
        if (_dos_findfirst(pat, _A_RDONLY | _A_HIDDEN | _A_SYSTEM | _A_ARCH,
                           &f) != 0)
            continue;
        if (f.attrib & (_A_SUBDIR | _A_VOLID))
            continue;
        found++;
        if (!opt_silent) {
            strlwr(f.name);
            printf("%s%s%s\n", dir, sep, f.name);
        }
        if (!opt_all)
            break;
    }
    return found;
}

/* Returns 1 if NAME was found. */
static int which(const char *name)
{
    char dir[_MAX_PATH], tmp[_MAX_PATH], buf[_MAX_PATH];
    const char *base, *dot, *p;
    const char *const *e = exts;
    int ne = NEXTS;
    int found = 0, i;
    size_t n;

    if (strchr(name, '*') || strchr(name, '?'))
        return 0;

    /* split off any drive or directory */
    base = name;
    for (p = name; *p; p++)
        if (*p == '\\' || *p == '/' || *p == ':')
            base = p + 1;
    if (*base == '\0' || strlen(base) >= sizeof buf)
        return 0;

    /* an explicit extension must name a program, and is the only one tried */
    strcpy(buf, base);
    dot = strrchr(buf, '.');
    if (dot != NULL) {
        buf[dot - buf] = '\0';
        if (dot[1] != '\0') {
            for (i = 0; i < (int)NEXTS; i++)
                if (stricmp(dot + 1, exts[i]) == 0)
                    break;
            if (i == (int)NEXTS)
                return 0;
            e = &exts[i];
            ne = 1;
        }
    }
    if (buf[0] == '\0')
        return 0;

    if (base != name) {
        /* drive or directory given: look only there */
        n = base - name;
        if (n >= sizeof dir)
            return 0;
        memcpy(dir, name, n);
        dir[n] = '\0';
        /* "C:" alone means the current directory of drive C */
        if (n == 2 && dir[1] == ':')
            strcat(dir, ".");
        if (normalize(tmp, dir) != 0)
            return 0;
        return search_dir(tmp, buf, e, ne) > 0;
    }

    for (i = 0; i < ndirs; i++) {
        found += search_dir(dirs[i], buf, e, ne);
        if (found && !opt_all)
            break;
    }
    return found > 0;
}

int main(int argc, char **argv)
{
    int i, nnames = 0, endopts = 0;
    int rc = 0;

    for (i = 1; i < argc; i++) {
        const char *a = argv[i];

        if (endopts || a[0] != '-' || a[1] == '\0') {
            nnames++;
            continue;
        }
        if (a[1] == '-') {
            if (a[2] == '\0')                       endopts = 1;
            else if (strcmp(a, "--all") == 0)       opt_all = 1;
            else if (strcmp(a, "--silent") == 0)    opt_silent = 1;
            else if (strcmp(a, "--help") == 0) {
                usage(stdout);
                return 0;
            } else if (strcmp(a, "--version") == 0) {
                printf("which (dos-which16) %s\n", VERSION);
                return 0;
            } else {
                fprintf(stderr, "%s: unrecognized option '%s'\n", progname, a);
                fprintf(stderr, "Try 'which --help' for more information.\n");
                return 1;
            }
            argv[i] = NULL;
            continue;
        }
        for (a++; *a; a++) {
            switch (*a) {
            case 'a': opt_all = 1; break;
            case 's': opt_silent = 1; break;
            case 'h':
            case '?':
                usage(stdout);
                return 0;
            default:
                fprintf(stderr, "%s: invalid option -- '%c'\n", progname, *a);
                fprintf(stderr, "Try 'which --help' for more information.\n");
                return 1;
            }
        }
        argv[i] = NULL;
    }

    if (nnames == 0) {
        fprintf(stderr, "%s: missing operand\n", progname);
        fprintf(stderr, "Try 'which --help' for more information.\n");
        return 1;
    }

    build_dirs();

    for (i = 1; i < argc; i++) {
        const char *a = argv[i];

        if (a == NULL)
            continue;
        if (!which(a)) {
            if (!opt_silent)
                fprintf(stderr, "%s: %s: not found\n", progname, a);
            rc = 1;
        }
    }
    return rc;
}
