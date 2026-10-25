/*
 * The parts of Open Watcom's <dos.h> (and the non-standard string and
 * stdlib functions) that which.c uses, for Smaller C's small model.
 * Smaller C has no <dos.h>; dos.c implements these.
 */

#ifndef SMALLERC_DOS_H
#define SMALLERC_DOS_H

#include <stddef.h>

#define _MAX_PATH   144

#define _A_NORMAL   0x00
#define _A_RDONLY   0x01
#define _A_HIDDEN   0x02
#define _A_SYSTEM   0x04
#define _A_VOLID    0x08
#define _A_SUBDIR   0x10
#define _A_ARCH     0x20

/* The DOS find data (DTA).  The small model has no long, so size is
 * two words, low first. */
struct find_t {
    char            reserved[21];
    char            attrib;
    unsigned short  wr_time;
    unsigned short  wr_date;
    unsigned short  size[2];
    char            name[13];
};

unsigned _dos_findfirst(const char *path, unsigned attr, struct find_t *buf);
char *_fullpath(char *buf, const char *path, size_t size);
char *strlwr(char *s);
int stricmp(const char *a, const char *b);
char *strdup(const char *s);

#endif
