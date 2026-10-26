# 8086 assembly build (experiment)

This experiment rewrites `which` in 8086 assembly (`which.asm`, NASM) to
see how small a program with no runtime library can be. `which.c` with
Open Watcom is still the default build. Releases include both
`which.exe` and `which.com`, and CI tests both. `which.c` and its tests
are the specification for the assembly version.

## Result

| Build | Format | Bytes | vs Watcom |
| --- | --- | ---: | ---: |
| `which.exe`, Open Watcom 2.0 (default) | `.EXE` | 13,220 | — |
| `whichsc.exe`, Smaller C 1.0.2, 8086 (PR #3) | `.EXE` | 13,598 | +2.9% |
| **`which.com`, NASM** | `.COM` | **2,538** | **−80.8%** |

The `.COM` file is 1,716 bytes of code and 822 bytes of data. More than
half of the data (about 600 bytes) is the `--help` text.

Space taken on disk, in FAT clusters:

| Cluster size (typical media) | `which.exe` | `whichsc.exe` | `which.com` |
| --- | ---: | ---: | ---: |
| 512 B (1.2 MB, 1.44 MB floppies) | 26 = 13,312 | 27 = 13,824 | 5 = 2,560 |
| 1 KB (360 KB, 720 KB floppies) | 13 = 13,312 | 14 = 14,336 | 3 = 3,072 |
| 2 KB (FAT16, 64–128 MB) | 7 = 14,336 | 7 = 14,336 | 2 = 4,096 |
| 4 KB (FAT12 hard disk; FAT16, 128–256 MB) | 4 = 16,384 | 4 = 16,384 | 1 = 4,096 |

On a 360 KB distribution floppy, this saves 10 KB (10 clusters) per
copy of `which`.

## Memory

| | `which.exe` (Watcom) | `which.com` |
| --- | ---: | ---: |
| needed to load and run | about 15 KB (image 13,172 + 2,480 minimum allocation) | about 5.2 KB |

The `.COM` uses its 256-byte PSP, the 2,538-byte image, 1,802 bytes of
uninitialised data (buffers and variables), and a 512-byte stack. On
top of that is a small heap, which holds a copy of `PATH` and the
deduplicated directories. With an ordinary `PATH` that is a few
hundred bytes. In the worst case (64 directories of 143 characters)
it is about 9 KB.

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
| `tests/compare.sh` (81 steps, run once normally and once under DOS 2.11) | 162 passed |

`tests/compare.sh` is new. It runs the same commands with the Watcom
build and the assembly build in the same fixture, and requires the
standard output (byte for byte, including CR LF) and the exit status
to be the same. It covers what `run.sh` does not:

- the 38 path-normalization cases from PR #3, turned into PATH entries
  and names: `.`, `..` and `...`, `..` past the root, doubled and
  forward slashes, absolute paths containing `.` or `..` (which Watcom
  does not resolve), `c:`, `c:.` and `c:..\x` from another drive,
  invalid drives `q:` and `1:`, and trailing dots and separators;
- PATH handling: spaces around entries, empty entries, duplicates in
  different case or spelling, entries on other drives, an entry over
  143 characters, and 71 entries (only the first 64 are used);
- arguments: quoting (`"foo"`, `"fo"o`, `"foo bar"`, `a\"b`, `""`),
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
                      # against which.exe (so it needs Watcom too)

Tools, as tested:

| Tool | Version |
| --- | --- |
| NASM | 3.01 (any NASM 2.x that supports `-f bin` should do) |
| DOSBox-X | 2026.01.02, for the tests |
| Open Watcom | 2.0 beta, for `which.exe`, which `compare.sh` uses as the reference |

Build flags: `nasm -f bin -DVERSION="<VERSION>" -o which.com which.asm`.

## How it differs from which.c

The assembly version is a separate implementation, written from
`which.c` and the behaviour of the Watcom build. It contains no Open
Watcom runtime code. The C runtime pieces that `which.c` relies on are
reimplemented to match their observed behaviour:

- **Argument splitting** (`parse_tail`): spaces and tabs separate
  arguments, double quotes group and are removed, and `\"` is a literal
  quote. It matches Watcom on every quoting case tested, but other
  unusual cases (such as backslashes before a quote inside quotes) are
  not proven.
- **`_fullpath`** (`fullpath`): it copies Watcom's quirks, as checked by
  the path cases above. For example, `.` and `..` are resolved only in
  relative paths, and repeated separators are kept.
- **`getenv`**: it matches `PATH=` exactly, in upper case.
  `COMMAND.COM` stores variable names in upper case, so a lower-case
  `path` does not occur in practice. Whether Watcom ignores case here
  was not checked.
- **Out of memory:** the C version would fail inside its runtime. The
  assembly version prints its own message, as described above. If the
  heap runs out while copying `PATH` (which takes a machine with almost
  no free memory), `PATH` is cut short and the directories that are
  left are skipped.
- **Output:** each line is written to DOS as soon as it is found, with
  `\n` written as CR LF. The C version writes through the C runtime's
  stdio buffering instead. The bytes on standard output are the same,
  but on the screen a "not found" message on stderr could appear in a
  different place among the found lines.

## Maintenance cost

`which.asm` is 1,021 lines (about 640 instructions), against 272 lines
of C. Every change in behaviour has to be made twice, in C and in
assembly, and the assembly is harder to review. `tests/compare.sh`
reduces the risk: any difference in output or exit status for the
cases it covers fails the test. Still, a new feature needs both its
code and its comparison cases written twice.

`which` is small and its behaviour is settled (it follows the lookup in
MS-DOS 4.0 `COMMAND.COM`), so changes should be rare.

## Recommendation

**Keep the experiment.** It is the only approach so far that saves
real space. It is 81% smaller than Watcom (2.5 KB against 13 KB on
disk), where Smaller C made the program bigger. It also needs about a
third of the memory and runs on DOS 2.0 and the 8086.

For the GR-DOS distribution, where small binaries come first, ship
`which.com` in place of `which.exe` once:

1. `make test-asm` runs in CI. It does now, with `nasm` from apt, and
   the release workflow runs it before attaching `which.com`.
2. A rule is agreed that a PR that changes `which.c` also changes
   `which.asm` and adds comparison cases.

Keep `which.c` as the specification and reference build. If keeping
two implementations in step turns out to cost more than it saves,
retire `which.asm` and use the Watcom build. For one stable utility,
saving 10 KB per floppy is likely worth it. Doing the same for every
`dos-*16` utility would need a separate decision for each one.
