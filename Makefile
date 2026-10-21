# Build which.exe for 16-bit MS-DOS with Open Watcom.
#   make WATCOM=~/opt/watcom

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

clean:
	rm -f *.o *.obj *.err which.exe

.PHONY: test clean
