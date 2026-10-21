/*
 * which - locate a program the way COMMAND.COM would
 *
 * The lookup follows MS-DOS 4.0 COMMAND.COM (PATH1.ASM, PATH2.ASM):
 *
 *   - NAME is first looked for where it says: the current directory,
 *     the current directory of its drive (C:FOO), or its directory
 *     (C:\BIN\FOO, BIN\FOO, .\FOO).  Unless NAME contains a directory,
 *     each directory in PATH is then searched in turn.
 *   - Without an extension, NAME.COM, NAME.EXE and NAME.BAT are tried in
 *     that order.  With one (a dot anywhere in the name), NAME is passed
 *     to DOS as typed, so DOS's 8.3 rules apply, and the file found
 *     counts only if its extension is .COM, .EXE or .BAT.
 *   - Read-only and hidden files are found; system files are not.
 *   - Wildcards are not allowed.
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
#define ATTRS     (_A_RDONLY | _A_HIDDEN)

static const char *progname = "which";
static const char *const exts[] = { "com", "exe", "bat" };
#define NEXTS     (sizeof exts / sizeof exts[0])

static int opt_all;
static int opt_silent;

static char *dirs[MAXDIRS];   /* PATH, normalized and deduplicated */
static int ndirs;

static void usage(FILE *fp)
{
    fprintf(fp,
        "Usage: which [OPTION]... NAME...\n"
        "Show the full path of the program COMMAND.COM runs for each NAME.\n"
        "\n"
        "The current directory is searched, then each directory in PATH,\n"
        "for NAME.COM, NAME.EXE and NAME.BAT.  A NAME with an extension is\n"
        "looked for only as given, and one with a directory only there.\n"
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

/* Add DIR to the PATH list unless it is already there. */
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

/* Print DIR\NAME, if F is a program.  Returns 1 if it was. */
static int found(const char *dir, struct find_t *f)
{
    const char *dot = strrchr(f->name, '.');
    size_t i;

    if (f->attrib & (_A_SUBDIR | _A_SYSTEM) || dot == NULL)
        return 0;
    for (i = 0; i < NEXTS; i++)
        if (stricmp(dot + 1, exts[i]) == 0)
            break;
    if (i == NEXTS)
        return 0;
    if (!opt_silent) {
        strlwr(f->name);
        printf("%s%s%s\n", dir,
               dir[strlen(dir) - 1] == '\\' ? "" : "\\", f->name);
    }
    return 1;
}

/*
 * Look in DIR (normalized) for BASE: as given if it has an extension,
 * otherwise with each program extension in turn.  Prints what is found,
 * stopping at the first match unless -a.  Returns the number of matches.
 */
static int search_dir(const char *dir, const char *base)
{
    char pat[_MAX_PATH + 16];
    struct find_t f;
    int n = 0;
    size_t i;

    if (strlen(dir) + strlen(base) + 6 > sizeof pat)
        return 0;
    if (strchr(base, '.') != NULL) {
        sprintf(pat, "%s\\%s", dir, base);
        if (_dos_findfirst(pat, ATTRS, &f) == 0)
            n = found(dir, &f);
        return n;
    }
    for (i = 0; i < NEXTS; i++) {
        sprintf(pat, "%s\\%s.%s", dir, base, exts[i]);
        if (_dos_findfirst(pat, ATTRS, &f) == 0 && found(dir, &f)) {
            n++;
            if (!opt_all)
                break;
        }
    }
    return n;
}

/* Returns 1 if NAME was found. */
static int which(const char *name)
{
    char dir[_MAX_PATH], first[_MAX_PATH];
    const char *base, *p;
    int has_dir = 0;
    int n, i;

    if (strchr(name, '*') || strchr(name, '?'))
        return 0;

    /* split off any drive or directory */
    base = name;
    for (p = name; *p; p++) {
        if (*p == '\\' || *p == '/') {
            base = p + 1;
            has_dir = 1;
        } else if (*p == ':') {
            base = p + 1;
        }
    }
    if (*base == '\0' || (size_t)(base - name) >= sizeof dir)
        return 0;

    /* first where NAME says: "C:" alone is C's current directory */
    memcpy(dir, name, base - name);
    dir[base - name] = '\0';
    if (base - name == 2 && dir[1] == ':')
        strcat(dir, ".");
    if (normalize(first, dir) != 0)
        return 0;
    n = search_dir(first, base);

    /* then PATH, unless NAME has a directory */
    if (has_dir)
        return n > 0;
    for (i = 0; i < ndirs && (n == 0 || opt_all); i++)
        if (strcmp(dirs[i], first) != 0)
            n += search_dir(dirs[i], base);
    return n > 0;
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
