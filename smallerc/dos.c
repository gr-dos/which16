/*
 * Open Watcom library functions used by which.c, for Smaller C's small
 * model (DS = ES = SS, near pointers).  See dos.h.
 *
 * Smaller C passes arguments on the stack, the first at [bp + 4], and
 * returns in ax.  Only bp and sp need to be preserved.
 */

#include <stdlib.h>
#include <string.h>
#include <dos.h>

/* Set the disk transfer area to DTA. */
static void dos_setdta(void *dta)
{
    asm("mov ah, 0x1a\n"
        "mov dx, [bp + 4]\n"
        "int 0x21");
}

/* Find the first match for PATH; 0 or a DOS error code. */
static unsigned dos_findfirst(const char *path, unsigned attr)
{
    asm("mov ah, 0x4e\n"
        "mov dx, [bp + 4]\n"
        "mov cx, [bp + 6]\n"
        "int 0x21\n"
        "sbb bx, bx\n"
        "and ax, bx");
}

/* The current drive, 0 = A. */
static int dos_getdrive(void)
{
    asm("mov ah, 0x19\n"
        "int 0x21\n"
        "mov ah, 0");
}

/* The current directory of DRIVE (1 = A), without drive or leading
 * backslash, into BUF (64 bytes); 0 or a DOS error code. */
static unsigned dos_getcwd(int drive, char *buf)
{
    asm("mov ah, 0x47\n"
        "mov dl, [bp + 4]\n"
        "mov si, [bp + 6]\n"
        "int 0x21\n"
        "sbb bx, bx\n"
        "and ax, bx");
}

unsigned _dos_findfirst(const char *path, unsigned attr, struct find_t *buf)
{
    dos_setdta(buf);
    return dos_findfirst(path, attr);
}

/*
 * Make PATH absolute in BUF, the way Open Watcom's DOS _fullpath does,
 * so that both builds print and deduplicate the same paths.  Add the
 * drive (as typed, or the current one) and, unless PATH starts with a
 * separator, that drive's current directory and (unless PATH is empty)
 * a backslash.  Then:
 *
 *   - a relative PATH is copied with "." and ".." resolved (".." stops
 *     at the root, and a trailing "." is dropped); an absolute one is
 *     copied as it is;
 *   - slashes become backslashes, and repeated ones are kept.
 *
 * NULL if the drive is not valid, ".." follows something other than a
 * separator, or the result does not fit in SIZE.
 */
char *_fullpath(char *buf, const char *path, size_t size)
{
    char tmp[_MAX_PATH + 64];
    char *q = tmp;
    char *end = tmp + _MAX_PATH;
    int empty = *path == '\0';
    int drive;
    size_t n;

    if (((path[0] | 0x20) >= 'a' && (path[0] | 0x20) <= 'z') &&
        path[1] == ':') {
        drive = (path[0] | 0x20) - 'a';
        *q++ = path[0];
        path += 2;
    } else {
        drive = dos_getdrive();
        *q++ = 'A' + drive;
    }
    *q++ = ':';

    if (*path == '\\' || *path == '/') {
        n = strlen(path);
        if (n >= (size_t)(end - q))
            return NULL;
        memcpy(q, path, n);
        q += n;
    } else {
        *q++ = '\\';
        if (dos_getcwd(drive + 1, q) != 0)
            return NULL;
        q += strlen(q);
        if (q[-1] != '\\' && !empty)
            *q++ = '\\';
        while (*path != '\0' && q < end) {
            if (*path != '.') {
                *q++ = *path++;
                continue;
            }
            path++;
            if (*path == '\\' || *path == '/') {      /* "./" */
                if (q[-1] != '\\' && q[-1] != '/')
                    *q++ = '\\';
                path++;
            } else if (*path == '.') {                  /* ".." */
                path++;
                if (*path == '\\' || *path == '/')
                    path++;
                if (q[-1] != '\\' && q[-1] != '/')
                    return NULL;
                for (q -= 2; *q != '\\' && *q != '/'; q--)
                    if (*q == ':') {
                        *++q = '\\';
                        break;
                    }
                q++;
            } else if (*path != '\0') {
                *q++ = '.';
            }
        }
        if (q >= end)
            return NULL;
    }
    *q = '\0';

    for (q = tmp; *q != '\0'; q++)
        if (*q == '/')
            *q = '\\';
    n = q - tmp + 1;
    if (buf == NULL) {
        if ((buf = malloc(n)) == NULL)
            return NULL;
    } else if (n > size) {
        return NULL;
    }
    return memcpy(buf, tmp, n);
}

char *strlwr(char *s)
{
    char *p;

    for (p = s; *p; p++)
        if (*p >= 'A' && *p <= 'Z')
            *p += 'a' - 'A';
    return s;
}

int stricmp(const char *a, const char *b)
{
    int ca, cb;

    do {
        ca = (unsigned char)*a++;
        cb = (unsigned char)*b++;
        if (ca >= 'A' && ca <= 'Z')
            ca += 'a' - 'A';
        if (cb >= 'A' && cb <= 'Z')
            cb += 'a' - 'A';
    } while (ca == cb && ca != 0);
    return ca - cb;
}

char *strdup(const char *s)
{
    size_t n = strlen(s) + 1;
    char *p = malloc(n);

    return p ? memcpy(p, s, n) : NULL;
}
