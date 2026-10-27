# 8086 assembly build (experiment)

This experiment rewrites `which` in 8086 assembly (`which.asm`, NASM) to
see how small a program with no runtime library can be. `which.c`,
built with Open Watcom and libc16, is still the default build. Releases include both
`which.exe` and `which.com`, and CI tests both. `which.c` and its tests
are the specification for the assembly version.

## Result

| Build | Format | Bytes | vs C |
| --- | --- | ---: | ---: |
| `which.exe`, Open Watcom with libc16 (default) | `.EXE` | 4,252 | — |
| **`which.com`, NASM** | `.COM` | **2,530** | **−40.5%** |
| `which.exe` with Open Watcom 2.0's own runtime (before libc16) | `.EXE` | 13,220 | +211% |
| `whichsc.exe`, Smaller C 1.0.2, 8086 (PR #3) | `.EXE` | 13,598 | +220% |

The `.COM` file is 1,708 bytes of code and 822 bytes of data. More than
half of the data (about 600 bytes) is the `--help` text.

Space taken on disk, in FAT clusters:

| Cluster size (typical media) | `which.exe` | `which.com` |
| --- | ---: | ---: |
| 512 B (1.2 MB, 1.44 MB floppies) | 9 = 4,608 | 5 = 2,560 |
| 1 KB (360 KB, 720 KB floppies) | 5 = 5,120 | 3 = 3,072 |
| 2 KB (FAT16, 64–128 MB) | 3 = 6,144 | 2 = 4,096 |
| 4 KB (FAT12 hard disk; FAT16, 128–256 MB) | 2 = 8,192 | 1 = 4,096 |

On a 360 KB distribution floppy, this saves 2 KB (2 clusters) per copy
of `which`. Before libc16 it saved 10.

## Memory

| | `which.exe` (libc16) | `which.com` |
| --- | ---: | ---: |
| needed to load and run | about 7.1 KB (PSP 256 + image 4,204 + 2,768 minimum allocation) | about 4.8 KB |

The `.COM` uses its 256-byte PSP, the 2,530-byte image, 1,585 bytes of
uninitialised data (buffers and variables), and a 512-byte stack. On
top of that is a small heap, which holds a copy of `PATH` and the
deduplicated directories. With an ordinary `PATH` that is a few
hundred bytes. In the worst case (64 directories of 79 characters) it
is about 5.4 KB. (With Open Watcom's own runtime, `which.exe` needed
about 15 KB.)

At startup the program checks that the stack and its buffers fit
below SP. If they do not, it prints `which: not enough memory` and
exits with status 1. As with any `.COM`, DOS gives the program the
largest free memory block while it runs and frees it on exit. That
does not matter for a utility that does not stay resident.

## Compatibility

- **8086:** the source starts with `cpu 8086`, so NASM rejects any
  later instruction.
- **DOS 2.0 and later:** the program uses only DOS 2.0 functions:
  09h, 19h, 1Ah, 40h, 47h, 4Ch and 4Eh, plus the PSP command tail and
  environment segment. `tests/compare.sh` runs every comparison a
  second time with DOSBox-X reporting DOS 2.11, and all pass. DOSBox-X
  still provides its newer functions when it reports 2.11, so this
  checks for version gating only. The guarantee of DOS 2 compatibility
  is that list of functions. The program has not been run on a real
  DOS 2.11.

## Behaviour and tests

| Test | Result |
| --- | --- |
| `tests/run.sh` (102 checks, the existing suite) | 102 passed |
| `tests/compare.sh` (83 steps, run once normally and once under DOS 2.11) | 166 passed |

`tests/compare.sh` is new. It runs the same commands with the C build
and the assembly build in the same fixture, and requires the
standard output (byte for byte, including CR LF) and the exit status
to be the same. It covers what `run.sh` does not:

- the 38 path-normalization cases from PR #3, turned into PATH entries
  and names: `.`, `..` and `...`, `..` past the root, doubled and
  forward slashes, absolute paths containing `.` or `..`, `c:`, `c:.`
  and `c:..\x` from another drive,
  invalid drives `q:` and `1:`, and trailing dots and separators;
- PATH handling: spaces around entries, empty entries, duplicates in
  different case or spelling, entries on other drives, an entry over
  79 characters, and a `PATH` of 71 entries, longer than the 255
  characters libc16's `getenv` returns, so treated as unset;
- arguments: quoting (`"foo"`, `"fo"o`, `"foo bar"`, `a\"b`, `""`,
  and runs of backslashes before a quote),
  `-`, `--`, repeated and combined options, and `--help`, `--version`
  and bad options before or after names;
- every `--help` and `--version` output, compared in full.

The harness has been checked to catch a difference: a build with a
different version fails the four `--version` steps.

Standard error is not compared, because DOS cannot redirect it. The
messages are the same strings as in `which.c`: `unrecognized option`,
`invalid option`, `missing operand`, the `Try 'which --help'` line,
and `NAME: not found`.

## Building

    make asm          # which.com
    make test-asm     # tests/run.sh on which.com, then tests/compare.sh
                      # against which.exe (so it needs libc16 too)

Tools, as tested:

| Tool | Version |
| --- | --- |
| NASM | 3.01 (any NASM 2.x that supports `-f bin` should do) |
| DOSBox-X | 2026.01.02, for the tests |
| libc16 | the revision pinned in `scripts/fetch-libc16`, with its Open Watcom snapshot, for `which.exe`, which `compare.sh` uses as the reference |

Build flags: `nasm -f bin -DVERSION="<VERSION>" -o which.com which.asm`.

## How it differs from which.c

The assembly version is a separate implementation, written from
`which.c`. It contains no C runtime code. The libc16 pieces that
`which.c` relies on are reimplemented from libc16's specifications (its
`docs/spec/`):

- **Argument splitting** (`parse_tail`): Microsoft C's rule, as libc16
  uses. Spaces and tabs separate arguments, double quotes group and are
  removed, a run of 2n backslashes before a quote gives n backslashes
  and a toggle, 2n + 1 give n backslashes and a literal quote, and any
  other backslash is literal.
- **`_fullpath`** (`fullpath`): the drive, then the current directory
  unless the path starts with a separator, then the path, with `/` read
  as `\`, `.` and `..` resolved (stopping at the root) and repeated
  separators collapsed; a drive that is not a letter, or not valid, is
  an error, and so is a result of 80 bytes or more (`_MAX_PATH`).
- **`getenv`**: it matches `PATH=` exactly, as libc16 does, and treats
  a value longer than 255 characters as unset.
- **Out of memory:** the C version would fail to load. The
  assembly version prints its own message, as described above. If the
  heap runs out while copying `PATH` (which takes a machine with almost
  no free memory), `PATH` is cut short and the directories that are
  left are skipped.
- **Output:** each line is written to DOS as soon as it is found, with
  `\n` written as CR LF, as libc16's unbuffered streams do.

## Maintenance cost

`which.asm` is 1,029 lines, against 297 lines of C. Every change in behaviour has to be made twice, in C and in
assembly, and the assembly is harder to review. `tests/compare.sh`
reduces the risk: any difference in output or exit status for the
cases it covers fails the test. Still, a new feature needs both its
code and its comparison cases written twice.

`which` is small and its behaviour is settled (it follows the lookup in
MS-DOS 4.0 `COMMAND.COM`), so changes should be rare.

## Recommendation

**Keep the experiment.** It is 40% smaller than the libc16 build (2.5
KB against 4.2 KB on disk, 3 clusters against 5 on a 360 KB floppy)
and needs about two thirds of the memory. Against Open Watcom's own
runtime it was 81% smaller, where Smaller C made the program bigger.
It runs on DOS 2.0 and the 8086.

For the GR-DOS distribution, where small binaries come first, ship
`which.com` in place of `which.exe` once:

1. `make test-asm` runs in CI. It does now, with `nasm` from apt, and
   the release workflow runs it before attaching `which.com`.
2. A rule is agreed that a PR that changes `which.c` also changes
   `which.asm` and adds comparison cases.

Keep `which.c` as the specification and reference build. If keeping
two implementations in step turns out to cost more than it saves,
retire `which.asm` and use the C build. With libc16 the saving is 2 KB
per floppy, down from 10, which makes that more likely. Doing the same for every
`dos-*16` utility would need a separate decision for each one.
