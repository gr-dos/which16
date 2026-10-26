# Build which.exe for 16-bit MS-DOS with Open Watcom and libc16.
#   make                         fetch and build the pinned libc16 into
#                                build/libc16, then build which.exe
#   make LIBC16_ROOT=../libc16   use a libc16 checkout built with its make
#
# which.exe is compiled and linked against libc16 only (its ABI is in
# libc16's docs/ABI.md), with the Open Watcom toolchain libc16 was built
# with, named in $(LIBC16_ROOT)/build/tools.env.
#
# Optionally, build which.com from 8086 assembly instead (see ASM.md).
#   make asm

LIBC16_ROOT ?= build/libc16
LIBC16      := $(LIBC16_ROOT)/build/LIBC16.LIB
WATCOM_ENV   = . $(LIBC16_ROOT)/build/tools.env && PATH=$$WATCOM/binl64:$$PATH

VERSION := $(shell cat VERSION)

CC     = wcc
CFLAGS = -q -zq -zl -zld -x -ms -0 -os -s -bt=dos -wx -we \
         -I$(LIBC16_ROOT)/include '-DVERSION="$(VERSION)"'

which.exe: which.obj $(LIBC16)
	$(WATCOM_ENV) && wlink option quiet, nodefaultlibs, map=which.map \
	  format dos name $@ file which.obj library $(LIBC16)

which.obj: which.c VERSION $(LIBC16)
	$(WATCOM_ENV) && $(CC) $(CFLAGS) -fo=$@ which.c

# The pinned libc16 (scripts/fetch-libc16). A LIBC16_ROOT given on the
# command line must already be built.
ifeq ($(LIBC16_ROOT),build/libc16)
$(LIBC16): scripts/fetch-libc16
	scripts/fetch-libc16 $(LIBC16_ROOT)
endif

test: which.exe
	sh tests/run.sh $(CURDIR)/which.exe

# 8086 assembly, as a .COM
NASM ?= nasm

asm: which.com

which.com: which.asm VERSION
	$(NASM) -f bin '-DVERSION="$(VERSION)"' -o $@ which.asm

# tests/run.sh, then the same commands as the C build
test-asm: which.com which.exe
	sh tests/run.sh $(CURDIR)/which.com
	sh tests/compare.sh which.exe which.com

clean:
	rm -f *.o *.obj *.err *.map which.exe which.com

.PHONY: test asm test-asm clean
