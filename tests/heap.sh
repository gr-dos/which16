#!/bin/sh
#
# Test that which.com fails cleanly when its heap runs out, rather than
# searching only part of PATH.  The heap holds a copy of PATH and the
# deduplicated directories; with real DOS memory it runs out only on a
# machine with almost none free, so this test uses a build made with
# -DTEST_HEAP=40 (make which-heap.com), whose heap is 40 bytes and
# whose version is "heap".  That option is for tests only: which.com
# is not built with it.
#
# On running out, which prints "which: not enough memory" on standard
# error (not checked: DOS cannot redirect it), prints nothing on
# standard output, even for names it would have found, and exits with
# status 1.
#
# Usage: tests/heap.sh path/to/which-heap.com
# Environment: DOSBOX (default dosbox-x), KEEP=1 to keep the work
#              directory.

set -u

DOSBOX=${DOSBOX:-dosbox-x}

[ $# -eq 1 ] || { echo "usage: $0 which-heap.com" >&2; exit 2; }
command -v "$DOSBOX" >/dev/null || { echo "$DOSBOX not found" >&2; exit 2; }
[ -f "$1" ] || { echo "$1 not found" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/dosheap.XXXXXX")
cp "$1" "$work/which.com"
cd "$work" || exit 2
pass=0
fail=0
LC_ALL=C
export LC_ALL

# ------------------------------------------------------------------
# fixtures
#
#   c:\       which.com local.bat
#   c:\bin1   foo.com
#   c:\bin2   foo.exe
#   c:\a\b    ab.com

mkdir -p bin1 bin2 a/b
for f in local.bat bin1/foo.com bin2/foo.exe a/b/ab.com; do
    echo x > "$f"
done

cat > rc.bat <<'EOS'
@echo off
if errorlevel 2 goto rc2
if errorlevel 1 goto rc1
echo rc0 >c:\r%1.txt
goto end
:rc1
echo rc1 >c:\r%1.txt
goto end
:rc2
echo rc2 >c:\r%1.txt
:end
EOS

# Heap use is the length of PATH plus 1, then each directory's length
# plus 1.
{
    cat <<'EOS'
@echo off
rem --- fits: 17 + 8 + 8 = 33 bytes
set PATH=C:\BIN1;C:\BIN2
which -a foo >o1.txt
call rc 1
rem --- the third directory does not fit: 23 + 8 + 8 + 7 = 46 bytes
set PATH=C:\BIN1;C:\BIN2;C:\A\B
which -a local foo >o2.txt
call rc 2
which -s local >o3.txt
call rc 3
rem --- PATH itself does not fit: 48 bytes
set PATH=C:\BIN1;C:\BIN1;C:\BIN1;C:\BIN1;C:\BIN1;C:\BIN2
which local >o4.txt
call rc 4
which --version >o5.txt
call rc 5
rem --- over 255 characters, PATH is unset, so the heap is not used
set PATH=C:\BIN1
EOS
    i=0
    while [ $i -lt 40 ]; do
        echo 'set PATH=%PATH%;C:\BIN2'
        i=$((i + 1))
    done
    cat <<'EOS'
which -a local foo >o6.txt
call rc 6
EOS
} | sed 's/$/\r/' > steps.bat

SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 300 \
    "$DOSBOX" -defaultconf -silent -nogui -nomenu \
    -set "cpu cycles=max" \
    -c "mount c \"$work\"" -c "c:" \
    -c "steps.bat" -c "exit" >dosbox.log 2>&1

# ------------------------------------------------------------------
# checks

not_ok() { echo "FAIL: $*"; fail=$((fail + 1)); }

rc() {
    got=$(tr -d '\r ' < "R$1.TXT" 2>/dev/null)
    if [ "$got" = "rc$2" ]; then
        pass=$((pass + 1))
    else
        not_ok "step $1: exit status ${got:-missing}, expected $2"
    fi
}

# expect STEP < expected-lines; compares ON.TXT with CRs removed
expect() {
    tr -d '\r' < "O$1.TXT" 2>/dev/null > got.txt
    cat > want.txt
    if [ -f "O$1.TXT" ] && cmp -s got.txt want.txt; then
        pass=$((pass + 1))
    else
        not_ok "step $1: output differs"
        diff want.txt got.txt | sed 's/^/    /'
    fi
}

rc 1 0
expect 1 <<'EOS'
c:\bin1\foo.com
c:\bin2\foo.exe
EOS
# out of memory: nothing printed, even for names in the current
# directory, and status 1
rc 2 1
expect 2 < /dev/null
rc 3 1
expect 3 < /dev/null
rc 4 1
expect 4 < /dev/null
# --version does not need the heap
rc 5 0
expect 5 <<'EOS'
which (dos-which16) heap
EOS
rc 6 1
expect 6 <<'EOS'
c:\local.bat
EOS

echo "$pass passed, $fail failed"
if [ "$fail" -ne 0 ] || [ "${KEEP:-0}" = 1 ]; then
    echo "work directory: $work"
else
    rm -rf "$work"
fi
[ "$fail" -eq 0 ]
