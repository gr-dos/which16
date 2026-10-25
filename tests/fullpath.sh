#!/bin/sh
#
# Check that smallerc/dos.c's _fullpath() matches Open Watcom's.
#
# tests/fullpath.c is built with each compiler and run under DOSBox-X
# from C:\A\B, with D: in \X; the two outputs must be the same.
#
# Usage: tests/fullpath.sh WATCOM.EXE SMALLERC.EXE
# Environment: DOSBOX (default dosbox-x), KEEP=1 to keep the work
#              directory.

set -u

DOSBOX=${DOSBOX:-dosbox-x}

[ $# -eq 2 ] || { echo "usage: $0 watcom.exe smallerc.exe" >&2; exit 2; }
command -v "$DOSBOX" >/dev/null || { echo "$DOSBOX not found" >&2; exit 2; }
for f in "$@"; do
    [ -f "$f" ] || { echo "$f not found" >&2; exit 2; }
done

work=$(mktemp -d "${TMPDIR:-/tmp}/dosfp.XXXXXX")
cp "$1" "$work/fpwc.exe"
cp "$2" "$work/fpsc.exe"
cd "$work" || exit 2
mkdir -p a/b d/x
printf '@echo off\r\ncd a\\b\r\nd:\r\ncd x\r\nc:\r\n' > run.bat
printf 'c:\\fpwc >c:\\wc.txt\r\nc:\\fpsc >c:\\sc.txt\r\n' >> run.bat

SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 120 \
    "$DOSBOX" -defaultconf -silent -nogui -nomenu \
    -set "cpu cycles=max" \
    -c "mount c \"$work\"" -c "mount d \"$work/d\"" -c "c:" \
    -c "run.bat" -c "exit" >dosbox.log 2>&1

tr -d '\r' < WC.TXT > wc 2>/dev/null
tr -d '\r' < SC.TXT > sc 2>/dev/null
if [ -s wc ] && cmp -s wc sc; then
    echo "$(wc -l < wc) paths, same"
    rc=0
else
    echo "FAIL: _fullpath differs (< Watcom, > Smaller C)"
    diff wc sc | sed 's/^/    /'
    rc=1
fi
if [ "$rc" -ne 0 ] || [ "${KEEP:-0}" = 1 ]; then
    echo "work directory: $work"
else
    rm -rf "$work"
fi
exit $rc
