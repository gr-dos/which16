# Build which.exe for 16-bit MS-DOS with Open Watcom.
#   make WATCOM=~/opt/watcom
#
# Optionally, build whichsc.exe with Smaller C instead (see SMALLERC.md).
#   make smallerc

WATCOM ?= $(HOME)/opt/watcom
export WATCOM
export INCLUDE := $(WATCOM)/h
export PATH := $(WATCOM)/binl64:$(WATCOM)/binl:$(PATH)

VERSION := $(shell cat VERSION)

CC     = wcl
CFLAGS = -q -bt=dos -ms -0 -os -s -wx -we -zq '-DVERSION="$(VERSION)"'

SRCS = which.c

which.exe: $(SRCS) VERSION
	$(CC) $(CFLAGS) -fe=$@ $(SRCS)

test: which.exe
	sh tests/run.sh $(CURDIR)/which.exe

# Smaller C, with an 8086 build of its library in $(SMLRC_TC)
SMLRCC   ?= smlrcc
SMLRC_TC ?= $(CURDIR)/smallerc/toolchain
SCFLAGS   = -doss -Wall -asm $(CURDIR)/smallerc/nasm8086 \
            -SI $(SMLRC_TC)/include -SI $(CURDIR)/smallerc \
            -SL $(SMLRC_TC)/lib '-DVERSION="$(VERSION)"'
SCSRCS    = $(SRCS) smallerc/dos.c

smallerc: whichsc.exe

whichsc.exe: $(SCSRCS) smallerc/dos.h VERSION $(SMLRC_TC)/lib/lcds.a
	$(SMLRCC) $(SCFLAGS) -o $@ $(SCSRCS)

$(SMLRC_TC)/lib/lcds.a: smallerc/toolchain.sh smallerc/nasm8086 \
                        smallerc/8086.inc smallerc/lcds-8086.patch
	SMLRCC=$(SMLRCC) sh smallerc/toolchain.sh $(SMLRC_TC)

test-smallerc: whichsc.exe
	sh tests/run.sh $(CURDIR)/whichsc.exe

# smallerc/dos.c's _fullpath against Open Watcom's; needs both compilers
fpwc.exe: tests/fullpath.c
	$(CC) -q -bt=dos -ms -0 -os -s -zq -fe=$@ tests/fullpath.c

fpsc.exe: tests/fullpath.c smallerc/dos.c smallerc/dos.h $(SMLRC_TC)/lib/lcds.a
	$(SMLRCC) $(SCFLAGS) -o $@ tests/fullpath.c smallerc/dos.c

test-fullpath: fpwc.exe fpsc.exe
	sh tests/fullpath.sh fpwc.exe fpsc.exe

clean:
	rm -f *.o *.obj *.err which.exe whichsc.exe fpwc.exe fpsc.exe

.PHONY: test smallerc test-smallerc test-fullpath clean
