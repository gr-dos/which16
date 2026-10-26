# Build which.exe for 16-bit MS-DOS with Open Watcom.
#   make WATCOM=~/opt/watcom
#
# Optionally, build which.com from 8086 assembly instead (see ASM.md).
#   make asm

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

# 8086 assembly, as a .COM
NASM ?= nasm

asm: which.com

which.com: which.asm VERSION
	$(NASM) -f bin '-DVERSION="$(VERSION)"' -o $@ which.asm

# tests/run.sh, then the same commands as the Watcom build
test-asm: which.com which.exe
	sh tests/run.sh $(CURDIR)/which.com
	sh tests/compare.sh which.exe which.com

clean:
	rm -f *.o *.obj *.err which.exe which.com

.PHONY: test asm test-asm clean
