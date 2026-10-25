#!/bin/sh
#
# Build an 8086 small-model C library (lcds.a) for Smaller C.
#
# The lcds.a that Smaller C ships needs a 386.  This rebuilds it from
# the upstream library source of the same release, assembling with
# nasm8086 so that, like the program, it runs on an 8086.  The two
# library functions written in 386 assembly, rand() and system(), are
# ported by lcds-8086.patch.  The compiler itself is the installed
# smlrcc (Debian and Ubuntu package smallerc).
#
# Leaves OUTDIR/include (the matching headers) and OUTDIR/lib/lcds.a.
# The source archive is kept in OUTDIR, and checked against its hash.
#
# Usage: smallerc/toolchain.sh [OUTDIR]   (default smallerc/toolchain)
# Needs: curl, tar, sha256sum, patch, smlrcc (SMLRCC) and nasm (NASM).

set -eu

# Smaller C 1.0.2: the tag v1.0.2+dos.win.b120a9c, packaged as smallerc
# 1.0.2+dfsg-1 in Debian and Ubuntu.
SMLRC_COMMIT=b120a9c389146bc2049dfff5fa16673210c8a12a
SMLRC_SHA256=9a6ead385ce7c214cab015a30ffaa93b500ad606375ec95f40ce483c5a21cec5

here=$(cd "$(dirname "$0")" && pwd)
out=${1:-$here/toolchain}
SMLRCC=${SMLRCC:-smlrcc}
tarball=SmallerC-$SMLRC_COMMIT.tar.gz

mkdir -p "$out"
out=$(cd "$out" && pwd)
cd "$out"

if [ ! -f "$tarball" ]; then
    curl -fsSL -o "$tarball.tmp" \
        "https://github.com/alexfru/SmallerC/archive/$SMLRC_COMMIT.tar.gz"
    mv "$tarball.tmp" "$tarball"
fi
echo "$SMLRC_SHA256  $tarball" | sha256sum -c --quiet -

# smlrcc writes its intermediate files next to the sources, so build in
# a fresh copy.
rm -rf build include lib
mkdir build
tar -xzf "$tarball" -C build --strip-components=1 \
    "SmallerC-$SMLRC_COMMIT/license.txt" \
    "SmallerC-$SMLRC_COMMIT/v0100/include" \
    "SmallerC-$SMLRC_COMMIT/v0100/srclib"
patch -s -d build -p1 < "$here/lcds-8086.patch"
(
    cd build/v0100/srclib
    "$SMLRCC" -asm "$here/nasm8086" -SI ../include -I . @lcds.txt
)
mkdir lib
mv build/v0100/srclib/lcds.a lib/
mv build/v0100/include include
mv build/license.txt lib/license.txt
rm -rf build

echo "$out/lib/lcds.a"
