/*
 * Print _fullpath() for awkward inputs, one per line, so the Open
 * Watcom library and smallerc/dos.c can be compared (fullpath.sh).
 */

#include <stdio.h>
#include <stdlib.h>
#include <dos.h>

static const char *const tests[] = {
    "", ".", "..", "...", "x", "x.", " x", "a.b", "a.\\b", "..x", "a..",
    "a\\b", "a/b/", "a//b", "x/.", "./", ".\\.\\x", "a\\..",
    "..\\..\\x", "a\\b\\..\\..\\..", "..\\a\\.\\..\\b.c\\",
    "\\", "/x", "\\a\\.\\b\\..", "c:\\\\x", "c:/a/../b",
    "c:", "c:.", "c:a\\..\\..", "c:..\\..\\..\\x",
    "d:", "d:x", "D:\\X\\", "A:x", "q:x", "q:\\x", "1:x",
    "c:\\a\\b\\c\\d\\e\\f\\g\\h\\i\\j\\k\\l\\m\\n\\o\\p\\q\\r\\s\\t\\u\\v"
    "\\w\\x\\y\\z\\aaaaaaaa\\bbbbbbbb\\cccccccc\\dddddddd\\eeeeeeee"
    "\\ffffffff\\gggggggg\\hhhhhhhh",
};

int main(void)
{
    char buf[_MAX_PATH];
    unsigned i;

    for (i = 0; i < sizeof tests / sizeof tests[0]; i++) {
        char *r = _fullpath(buf, tests[i], sizeof buf);

        printf("[%s] [%s]\n", tests[i], r ? r : "(null)");
    }
    return 0;
}
