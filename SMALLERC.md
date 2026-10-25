# Smaller C build (experiment)

This is an evaluation of [Smaller C](https://github.com/alexfru/SmallerC)
(2-clause BSD) as an alternative to Open Watcom for building
`which.exe`, with the size of the DOS executable as the main measure.
Open Watcom remains the default compiler and the only one used for releases.
The Smaller C build is opt-in and produces `whichsc.exe`.

## Result

| Build | Compiler | Library | CPU | `.exe` bytes | vs Watcom |
| --- | --- | --- | --- | ---: | ---: |
| `which.exe` (default) | Open Watcom 2.0 | clibs | 8086 | **13,220** | — |
| `whichsc.exe` | Smaller C 1.0.2 | `lcds.a` rebuilt for 8086 | 8086 | **13,598** | +378 (+2.9%) |
| reference only | Smaller C 1.0.2 | `lcds.a` as shipped | 386 | 12,430 | −790 (−6.0%) |

The program is the same in every row: `which.c` at version 0.01. The
third row uses the library and code as Smaller C ships them and needs
a 386, so it does not meet the 8086 target. It is listed only to show
what the 8086 compatibility work costs.

**Smaller C gives no size advantage for `which`.** Its 8086 build is
2.9% bigger than Watcom's. Even the 386-only build saves just 790
bytes. Watcom stays the default.

Where the bytes go (`.text` only, from the linker maps):

| | Watcom | Smaller C 8086 | Smaller C 386 |
| --- | ---: | ---: | ---: |
| `which.c` | 1,253 | 2,805 | 2,389 |
| Watcom library functions (`smallerc/dos.c`) | (in library) | 1,459 | 1,359 |
| C library and startup | 10,202 | 7,759 | 7,113 |
| **total code** | 11,455 | 12,023 | 10,861 |

Smaller C's library is about 2.4 KB smaller than Watcom's. Its code
generator undoes that saving. It is a single-pass compiler with no
optimizer: `which.c` comes out 2.2 times larger than Watcom's `-os`
output, and the Watcom functions that Smaller C lacks (`dos.c`) add
another 1.4 KB. The 8086 shim adds about 10% to code size, mostly from
`push imm` (27 uses in `which.c`, about 7 bytes more each) and `setcc`.

For a larger program the balance would shift further toward Watcom,
because the compiler's output grows with the program and the library
mostly does not.

## Behaviour

Both builds pass the full test suite (`tests/run.sh`, 102 checks of
output and exit status). The extra test `tests/fullpath.sh` checks
that `dos.c`'s `_fullpath` gives the same result as Watcom's on 38
awkward paths. Error messages come from the same `fprintf` calls in
`which.c`. The tests do not check them, because DOS cannot redirect
standard error.

Differences found in the sanity check (DOSBox-X):

- **DOS version.** Smaller C's startup code refuses to run before DOS
  3.0 (`DOS 3+ required!`). The Watcom build runs on DOS 2.11.
- **Memory.** A Smaller C small-model program always takes a full 64 KB
  data segment, so the MZ header asks for about 76 KB to load. The
  Watcom build needs about 15 KB. That is not a problem on any DOS
  machine, but it is wasteful for a small utility.
- Smaller C's startup hooks interrupts 0, 4 and 6 and Ctrl-C, and puts
  them back on exit.

Startup and run time showed nothing unusual. Speed was not measured.

## Building

    make smallerc         # whichsc.exe
    make test-smallerc    # tests/run.sh on whichsc.exe
    make test-fullpath    # _fullpath against Watcom (needs both)

Tools, as tested:

| Tool | Version | Notes |
| --- | --- | --- |
| Smaller C | 1.0.2 (`smallerc` 1.0.2+dfsg-1build1, Ubuntu) | `smlrcc`, `smlrc`, `smlrpp`, `smlrl`; the Ubuntu package (25.04 and later) or Debian's, or upstream tag `v1.0.2+dos.win.b120a9c` |
| NASM | 3.01 | Smaller C's assembler, also wrapped by `nasm8086` |
| Smaller C library source | commit `b120a9c389146bc2049dfff5fa16673210c8a12a` | fetched by `smallerc/toolchain.sh`, checked against its SHA-256 |
| curl, tar, sha256sum, patch | any | to fetch and prepare the library source |
| Open Watcom | 2.0 beta (Oct 2026) | default build and `make test-fullpath` |
| DOSBox-X | 2026.01.02 | tests |

Override the tools with `make SMLRCC=... SMLRC_TC=...` (`SMLRC_TC` is
where the 8086 library is built, default `smallerc/toolchain`). The
first build downloads the library source. After that the archive is
kept and checked again on each rebuild.

Flags:

| Compiler | Flags |
| --- | --- |
| Watcom | `wcl -q -bt=dos -ms -0 -os -s -wx -we -zq` |
| Smaller C | `smlrcc -doss -Wall -asm smallerc/nasm8086` with `-SI`/`-SL` for the 8086 library and `smallerc/` |

## What it took

`which.c` builds with Smaller C **unchanged**. Everything else is in
`smallerc/`:

- **`dos.h`, `dos.c`**: the Watcom functions `which.c` uses that
  Smaller C lacks: `_dos_findfirst`, `_fullpath`, `strlwr`, `stricmp`
  and `strdup`, with `struct find_t`, `_A_*` and `_MAX_PATH`. Smaller
  C has no `<dos.h>`, so `-SI smallerc` puts this one first. The DOS
  calls use Smaller C's inline `asm()`. `_fullpath` copies Watcom's
  quirks (for example, `.` and `..` are resolved only in relative
  paths), so the two builds print and deduplicate paths the same way.
  The small model has no `long`, so `find_t.size` is two words.
- **`8086.inc`, `nasm8086`**: Smaller C's 16-bit code generator emits
  some 80186 and 80386 instructions (`movzx`, `movsx`, `setcc`, `push
  imm`, `leave`, `imul reg, r/m, imm`, shifts by a count other than 1). `8086.inc`
  is a set of NASM macros that replace them with 8086 code and sets
  `cpu 8086`, so NASM rejects anything left over. `nasm8086` runs NASM
  with it pre-included and is passed to `smlrcc -asm`. The `movzx`,
  `movsx` and `setcc` macros come from Smaller C's own
  `include/sys/80186.h`.
- **`toolchain.sh`, `lcds-8086.patch`**: the `lcds.a` that Smaller C
  ships needs a 386 (its documentation says so). The script rebuilds
  it from the matching upstream source with `nasm8086`.
  The patch ports the only two library functions written in 386
  assembly, `rand()` and `system()`. `which` uses neither, but the
  patch keeps the whole library 8086-clean.

Nothing in `which.c` needed a construct Smaller C does not support.

## Not changed

The default `make`, `make test`, CI and the release workflow still use
Watcom only, and `VERSION` is not changed. CI does not build the Smaller C
variant: `ubuntu-24.04` has no `smallerc` package, and building
Smaller C from source in CI is left for a follow-up if this is
pursued.
