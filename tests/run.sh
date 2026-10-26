#!/bin/sh
#
# Test which.exe under DOSBox-X.
#
# One batch file runs every DOS-side step, and the results are checked
# on the host afterwards.  Each step N records which's exit status in
# RN.TXT and its standard output in ON.TXT.  DOS cannot redirect
# standard error, so diagnostics are not checked.  rc.bat uses goto
# rather than "if errorlevel N echo ... >file" because the DOSBox-X
# shell opens the redirection even when the test is false.
#
# To add a test: add a step to steps.bat (command, then "call rc N")
# and the matching rc/expect/check lines below.
#
# Usage: tests/run.sh [path/to/which.exe]
# Environment: DOSBOX (default dosbox-x), KEEP=1 to keep the work
#              directory.

set -u

top=$(cd "$(dirname "$0")/.." && pwd)
exe=${1:-$top/which.exe}
DOSBOX=${DOSBOX:-dosbox-x}

command -v "$DOSBOX" >/dev/null || { echo "$DOSBOX not found" >&2; exit 2; }
[ -f "$exe" ] || { echo "$exe not found" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/doswhich.XXXXXX")
pass=0
fail=0
LC_ALL=C
export LC_ALL

# ------------------------------------------------------------------
# fixtures
#
#   c:\       which.exe (or .com) local.bat qux.exe
#   c:\bin1   foo.com foo.exe bar.bat longname.com plain
#             hid.com (hidden) sys.com (system)
#   c:\bin2   foo.exe qux.com readme.txt dir.exe\ (a directory)
#   d:\       empty, for drive-relative names

cd "$work" || exit 2
ext=$(echo "${exe##*.}" | tr A-Z a-z)
cp "$exe" "which.$ext"
mkdir bin1 bin2 bin2/dir.exe d
for f in local.bat qux.exe bin1/foo.com bin1/foo.exe bin1/bar.bat \
         bin1/longname.com bin1/plain bin1/hid.com bin1/sys.com \
         bin2/foo.exe bin2/qux.com bin2/readme.txt; do
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

cat > steps.bat <<'EOS'
@echo off
attrib +h c:\bin1\hid.com
attrib +s c:\bin1\sys.com
set PATH=C:\BIN1;C:\BIN2
rem --- first match: .COM before .EXE before .BAT
which foo >o1.txt
call rc 1
which -a foo >o2.txt
call rc 2
which bar >o3.txt
call rc 3
rem --- explicit extension
which foo.exe >o4.txt
call rc 4
which -a FOO.EXE >o5.txt
call rc 5
which readme.txt >o6.txt
call rc 6
which readme >o7.txt
call rc 7
which bar.com >o8.txt
call rc 8
rem --- current directory before PATH
which qux >o9.txt
call rc 9
which -a qux >o10.txt
call rc 10
which local >o11.txt
call rc 11
rem --- explicit directory: no PATH search
which c:\bin2\foo >o12.txt
call rc 12
which bin2\foo >o13.txt
call rc 13
which bin2\bar >o14.txt
call rc 14
which -a C:\BIN1\FOO >o15.txt
call rc 15
rem --- directories and wildcards are not programs
which dir >o16.txt
call rc 16
which fo* >o17.txt
call rc 17
rem --- several names
which foo nope bar >o18.txt
call rc 18
rem --- silent
which -s foo >o19.txt
call rc 19
which -s nope >o20.txt
call rc 20
which -as foo bar >o21.txt
call rc 21
which --silent foo nope >o22.txt
call rc 22
rem --- PATH entries are normalized and deduplicated
set PATH=c:\bin1\;bin2;C:\BIN1;c:\
which -a foo >o23.txt
call rc 23
which --all qux >o24.txt
call rc 24
rem --- from another directory
set PATH=C:\BIN1;C:\BIN2
cd bin2
c:\which -a foo >c:\o25.txt
call c:\rc 25
c:\which ..\local >c:\o26.txt
call c:\rc 26
cd \
rem --- empty PATH: current directory only
set PATH=
which -a foo qux >o27.txt
call rc 27
rem --- help and version
which --help >o28.txt
call rc 28
which -h >o29.txt
call rc 29
which --version >o30.txt
call rc 30
rem --- errors
which --bogus >o31.txt
call rc 31
which -x foo >o32.txt
call rc 32
which >o33.txt
call rc 33
rem --- -- ends options
set PATH=C:\BIN1;C:\BIN2
which -- foo >o34.txt
call rc 34
rem --- names are passed to DOS, so 8.3 rules apply
which -a foo.comx >o35.txt
call rc 35
which foo.exe.com >o36.txt
call rc 36
which longnameextra >o37.txt
call rc 37
which plain. >o38.txt
call rc 38
which plain >o39.txt
call rc 39
rem --- hidden files are found, system files are not
which hid >o40.txt
call rc 40
which sys >o41.txt
call rc 41
rem --- explicit directories
which .\qux >o42.txt
call rc 42
which .\foo >o43.txt
call rc 43
which bin2/foo >o44.txt
call rc 44
rem --- drive-relative names, from another drive
cd bin2
d:
c:\which -a c:foo >c:\o45.txt
call c:\rc 45
c:\which c:bar >c:\o46.txt
call c:\rc 46
c:\which c:..\local >c:\o47.txt
call c:\rc 47
c:\which \local >c:\o48.txt
call c:\rc 48
c:\which .\foo >c:\o49.txt
call c:\rc 49
c:
rem --- root of the current drive
c:\which \local >c:\o50.txt
call c:\rc 50
c:\which \foo >c:\o51.txt
call c:\rc 51
cd \
EOS

SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 300 \
    "$DOSBOX" -defaultconf -silent -nogui -nomenu \
    -set "cpu cycles=max" \
    -c "mount c \"$work\"" -c "mount d \"$work/d\"" -c "c:" \
    -c "steps.bat" -c "exit" >dosbox.log 2>&1

# ------------------------------------------------------------------
# checks

ok()     { pass=$((pass + 1)); }
not_ok() { echo "FAIL: $*"; fail=$((fail + 1)); }

# check NAME COMMAND...
check() {
    name=$1
    shift
    if "$@"; then ok; else not_ok "$name"; fi
}

# rc STEP EXPECTED-STATUS
rc() {
    got=$(tr -d ' \r' < "R$1.TXT" 2>/dev/null | sed 's/^rc//')
    if [ "$got" = "$2" ]; then
        ok
    else
        not_ok "step $1: exit status ${got:-missing}, expected $2"
    fi
}

# expect STEP < expected-lines; compares ON.TXT with CRs removed
expect() {
    tr -d '\r' < "O$1.TXT" 2>/dev/null > got.txt
    cat > want.txt
    if cmp -s got.txt want.txt; then
        ok
    else
        not_ok "step $1: output differs"
        diff want.txt got.txt | sed 's/^/    /'
    fi
}

# first match
rc 1 0
expect 1 <<'EOS'
c:\bin1\foo.com
EOS
rc 2 0
expect 2 <<'EOS'
c:\bin1\foo.com
c:\bin1\foo.exe
c:\bin2\foo.exe
EOS
rc 3 0
expect 3 <<'EOS'
c:\bin1\bar.bat
EOS

# explicit extension
rc 4 0
expect 4 <<'EOS'
c:\bin1\foo.exe
EOS
rc 5 0
expect 5 <<'EOS'
c:\bin1\foo.exe
c:\bin2\foo.exe
EOS
rc 6 1
expect 6 < /dev/null
rc 7 1
expect 7 < /dev/null
rc 8 1
expect 8 < /dev/null

# current directory before PATH
rc 9 0
expect 9 <<'EOS'
c:\qux.exe
EOS
rc 10 0
expect 10 <<'EOS'
c:\qux.exe
c:\bin2\qux.com
EOS
rc 11 0
expect 11 <<'EOS'
c:\local.bat
EOS

# explicit directory
rc 12 0
expect 12 <<'EOS'
c:\bin2\foo.exe
EOS
rc 13 0
expect 13 <<'EOS'
c:\bin2\foo.exe
EOS
rc 14 1
expect 14 < /dev/null
rc 15 0
expect 15 <<'EOS'
c:\bin1\foo.com
c:\bin1\foo.exe
EOS

# directories and wildcards
rc 16 1
expect 16 < /dev/null
rc 17 1
expect 17 < /dev/null

# several names
rc 18 1
expect 18 <<'EOS'
c:\bin1\foo.com
c:\bin1\bar.bat
EOS

# silent
rc 19 0
expect 19 < /dev/null
rc 20 1
expect 20 < /dev/null
rc 21 0
expect 21 < /dev/null
rc 22 1
expect 22 < /dev/null

# PATH normalized and deduplicated
rc 23 0
expect 23 <<'EOS'
c:\bin1\foo.com
c:\bin1\foo.exe
c:\bin2\foo.exe
EOS
rc 24 0
expect 24 <<'EOS'
c:\qux.exe
c:\bin2\qux.com
EOS

# from another directory
rc 25 0
expect 25 <<'EOS'
c:\bin2\foo.exe
c:\bin1\foo.com
c:\bin1\foo.exe
EOS
rc 26 0
expect 26 <<'EOS'
c:\local.bat
EOS

# empty PATH
rc 27 1
expect 27 <<'EOS'
c:\qux.exe
EOS

# help and version
rc 28 0
check "step 28: help" grep -q '^Usage: which' O28.TXT
rc 29 0
check "step 29: -h same as --help" cmp -s O28.TXT O29.TXT
rc 30 0
expect 30 <<EOS
which (dos-which16) $(cat "$top/VERSION")
EOS

# errors
rc 31 1
expect 31 < /dev/null
rc 32 1
expect 32 < /dev/null
rc 33 1
expect 33 < /dev/null

# -- ends options
rc 34 0
expect 34 <<'EOS'
c:\bin1\foo.com
EOS

# 8.3 rules
rc 35 0
expect 35 <<'EOS'
c:\bin1\foo.com
EOS
rc 36 1
expect 36 < /dev/null
rc 37 0
expect 37 <<'EOS'
c:\bin1\longname.com
EOS
rc 38 1
expect 38 < /dev/null
rc 39 1
expect 39 < /dev/null

# attributes
rc 40 0
expect 40 <<'EOS'
c:\bin1\hid.com
EOS
rc 41 1
expect 41 < /dev/null

# explicit directories
rc 42 0
expect 42 <<'EOS'
c:\qux.exe
EOS
rc 43 1
expect 43 < /dev/null
rc 44 0
expect 44 <<'EOS'
c:\bin2\foo.exe
EOS

# drive-relative, from d: with c: in \bin2
rc 45 0
expect 45 <<'EOS'
c:\bin2\foo.exe
c:\bin1\foo.com
c:\bin1\foo.exe
EOS
rc 46 0
expect 46 <<'EOS'
c:\bin1\bar.bat
EOS
rc 47 0
expect 47 <<'EOS'
c:\local.bat
EOS
rc 48 1
expect 48 < /dev/null
rc 49 1
expect 49 < /dev/null

# root of the current drive
rc 50 0
expect 50 <<'EOS'
c:\local.bat
EOS
rc 51 1
expect 51 < /dev/null

# ------------------------------------------------------------------

echo "$pass passed, $fail failed"
if [ "$fail" -ne 0 ] || [ "${KEEP:-0}" = 1 ]; then
    echo "work directory: $work"
else
    rm -rf "$work"
fi
[ "$fail" -eq 0 ]
