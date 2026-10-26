#!/bin/sh
#
# Compare two builds of which under DOSBox-X: the same commands are run
# with each, and their standard output and exit status must be the
# same.  The test build is run twice, the second time with DOS
# reporting version 2.11.  This covers what tests/run.sh does not: path normalization of
# PATH entries and names, argument quoting, option order, limits and
# odd input.  The first build is the reference (which.exe from Open
# Watcom).
#
# Each line of the step list below is a step.  A line starting with
# "!" is a DOS command run as it is; any other line is the arguments
# for which, run as a step with its output and status recorded.
#
# Usage: tests/compare.sh REFERENCE TEST
# Environment: DOSBOX (default dosbox-x), KEEP=1 to keep the work
#              directory.

set -u

DOSBOX=${DOSBOX:-dosbox-x}

[ $# -eq 2 ] || { echo "usage: $0 reference test" >&2; exit 2; }
command -v "$DOSBOX" >/dev/null || { echo "$DOSBOX not found" >&2; exit 2; }
for f in "$@"; do
    [ -f "$f" ] || { echo "$f not found" >&2; exit 2; }
done

ext() { echo "${1##*.}" | tr 'A-Z' 'a-z'; }

work=$(mktemp -d "${TMPDIR:-/tmp}/doscmp.XXXXXX")
cp "$1" "$work/ref.$(ext "$1")"
cp "$2" "$work/tst.$(ext "$2")"
cd "$work" || exit 2
LC_ALL=C
export LC_ALL

# ------------------------------------------------------------------
# fixtures
#
#   c:\        local.bat qux.exe
#   c:\bin1    foo.com foo.exe bar.bat
#   c:\bin2    foo.exe qux.com
#   c:\a\b     ab.com
#   c:\a.b     dot.exe
#   d:\x       dx.com
#   c:\p00..p69  empty but for p69\deep.com; PATH gets all 70 (over
#              the limit of 64)

mkdir -p bin1 bin2 a/b a.b d/x out/ref out/tst out/t211
for f in local.bat qux.exe bin1/foo.com bin1/foo.exe bin1/bar.bat \
         bin2/foo.exe bin2/qux.com a/b/ab.com a.b/dot.exe d/x/dx.com; do
    echo x > "$f"
done
many=
i=0
while [ $i -lt 70 ]; do
    d=$(printf 'p%02d' $i)
    mkdir "$d"
    many="$many!set PATH=%PATH%;c:\\$d
"
    i=$((i + 1))
done
echo x > p69/deep.com
long=c:\\$(printf 'x%.0s' $(seq 1 150))

steps() {
    cat <<EOS
!set PATH=C:\\BIN1;C:\\BIN2
-a foo qux local bar
--help
-h
--version
-?
-a --help
--version -x
-x --version
foo --bogus
-- -a foo
- foo
-
--
-as foo nope
-sa nope
--all --silent foo
-aa foo
"foo"
"fo"o
"foo bar"
fo"o b"ar
a\\"b
"" foo
FOO.Com
foo.BAT
foo.
foo.e
.\\qux
..\\local
c:local
c:.\\local
c:..\\local
\\local
/local
c:/bin1/foo
c:\\bin1\\\\foo
c:\\\\bin1\\foo
bin1/./foo
bin1/../bin2/foo
c:\\bin1\\..\\bin2\\foo
c:\\bin1\\.\\foo
a.b\\dot
a.b/dot
q:foo
q:\\foo
1:foo
*
fo?
c:
c:\\
\\
.
..
...
a\\b\\
a\\b\\ab
!cd a\\b
-a ab foo
..\\..\\local
c:..\\..\\..\\local
..\\b\\ab
...\\local
.\\.\\ab
!d:
!cd x
c:ab
c:..\\..\\bin1\\foo
dx
d:dx
c:\\local
!c:
!cd \\
!set PATH=c:\\bin1\\..\\bin2
-a foo
!set PATH=c:/bin1//;bin2/.
-a foo
!set PATH=bin1;.\\bin2;..;c:..\\bin1
-a foo qux
!set PATH=  c:\\bin2  ; ;;c:\\bin1;
-a foo
!set PATH=C:\\BIN1;c:\\bin1;c:\\bin1\\;C:/BIN1
-a foo
!set PATH=q:\\x;q:x;1:x;c:\\bin2
-a foo
!set PATH=d:;d:\\x;c:\\bin1
-a dx foo
!set PATH=bin1.;c:\\a.b;a.b\\
-a foo dot
!set PATH=\\bin1;/bin2
-a foo
!set PATH=$long;c:\\bin1
-a foo
!set PATH=c:\\bin1
$many-a deep foo
!set PATH=c:\\bin1
$(printf 'f%.0s' $(seq 1 90))
!set PATH=;
foo
!set PATH=
foo qux
EOS
}

# ------------------------------------------------------------------
# the batch file: steps.bat PROGRAM runs every step with PROGRAM

cat > rc.bat <<'EOS'
@echo off
if errorlevel 2 goto rc2
if errorlevel 1 goto rc1
echo rc0 >>%1
goto end
:rc1
echo rc1 >>%1
goto end
:rc2
echo rc2 >>%1
:end
EOS

n=0
{
    printf '@echo off\r\n'
    steps | while IFS= read -r line; do
        case $line in
        !*) printf '%s\r\n' "${line#!}" ;;
        *)
            n=$((n + 1))
            printf 'c:\\%%1 %s >c:\\out\\%%1\\%d.txt\r\n' "$line" $n
            printf 'call c:\\rc c:\\out\\%%1\\%d.txt\r\n' $n
            ;;
        esac
    done
    printf 'c:\r\ncd \\\r\n'
} > steps.bat

steps | grep -v '^!' > steps.txt
cmds=$(wc -l < steps.txt)

# Then the test build again with DOS reporting version 2.11.
cat > run.bat <<'EOS'
@echo off
call steps ref
call steps tst
ver set 2 11
copy tst.* t211.* >nul
call steps t211
EOS

SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 600 \
    "$DOSBOX" -defaultconf -silent -nogui -nomenu \
    -set "cpu cycles=max" \
    -c "mount c \"$work\"" -c "mount d \"$work/d\"" -c "c:" \
    -c "run.bat" -c "exit" >dosbox.log 2>&1

# ------------------------------------------------------------------
# checks

pass=0
fail=0
for run in tst t211; do
    i=1
    while [ $i -le "$cmds" ]; do
        args=$(sed -n "${i}p" steps.txt)
        r=$(ls out/ref 2>/dev/null | grep -ix "$i.txt")
        t=$(ls out/$run 2>/dev/null | grep -ix "$i.txt")
        if [ -z "$r" ] || [ -z "$t" ]; then
            echo "FAIL: $run step $i ($args): no output"
            fail=$((fail + 1))
        elif cmp -s "out/ref/$r" "out/$run/$t"; then
            pass=$((pass + 1))
        else
            echo "FAIL: $run step $i ($args): differs (< reference, > test)"
            diff "out/ref/$r" "out/$run/$t" | sed 's/^/    /'
            fail=$((fail + 1))
        fi
        i=$((i + 1))
    done
done

echo "$pass passed, $fail failed"
if [ "$fail" -ne 0 ] || [ "${KEEP:-0}" = 1 ]; then
    echo "work directory: $work"
else
    rm -rf "$work"
fi
[ "$fail" -eq 0 ]
