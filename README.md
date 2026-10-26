# which16

A `which` for 16-bit MS-DOS, built with Open Watcom.

`which` shows the full path of the program `COMMAND.COM` would run for
a command name. The resulting `which.exe` is a small-model, real-mode
8086 executable (about 13 KB) that runs on any DOS from an original PC
up.

## Building

Requires Open Watcom (tested with the Linux-hosted toolchain).

    make                         # uses ~/opt/watcom by default
    make WATCOM=/path/to/watcom  # or point it elsewhere
    make test                    # runs tests/run.sh under DOSBox-X
    make clean

The tests need `dosbox-x` on the host (override with `DOSBOX=`); set
`KEEP=1` to keep the work directory.

`make asm` builds `which.com`, an 8086 assembly version of the same
program (needs `nasm`). `make test-asm` runs the tests on it and
compares it with the Watcom build. It is released alongside
`which.exe`: see [ASM.md](ASM.md).

The version is the one line in `VERSION`, DOS style (0.01, 0.02, ...
1.00), not semantic versioning. When a PR that changes it is merged to
`main`, the release workflow tags the merge commit `v<VERSION>` and
publishes a GitHub release with `which.exe` and `which.com` attached.

## Usage

    which [OPTION]... NAME...

| Option | Meaning |
| --- | --- |
| `-a`, `--all` | print every match, not just the first |
| `-s`, `--silent` | print nothing; the exit code shows the result |
| `-h`, `-?`, `--help` | show help |
| `--version` | show version |

Options may be combined (`-as`), and `--` ends them.

The exit code is 0 if every NAME was found, and 1 if any was not or for
a bad option or a missing NAME. A NAME that is not found is reported on
standard error unless `-s` is given.

### Examples

    C:\>which edit
    c:\dos\edit.com
    C:\>which -a foo
    c:\bin\foo.com
    c:\bin\foo.exe
    c:\util\foo.exe
    C:\>which -s pkzip
    C:\>if errorlevel 1 echo pkzip is not installed

## How names are looked up

`which` follows the lookup in the MS-DOS 4.0 `COMMAND.COM` source
(`PATH1.ASM` and `PATH2.ASM` in
[microsoft/MS-DOS](https://github.com/microsoft/MS-DOS)):

- NAME is looked for first where it says: the current directory, or
  for `C:FOO` the current directory of drive C, or for `C:\BIN\FOO`,
  `BIN\FOO`, `.\FOO`, `..\FOO` or `\FOO` that directory.
- Then, unless NAME contains a directory, each directory in `PATH` is
  searched in order. A drive alone is not a directory: `C:FOO` falls
  back to `PATH` just as `FOO` does.
- Without an extension, `NAME.COM`, `NAME.EXE` and `NAME.BAT` are tried
  in each directory, in that order. Without `-a`, the first one found is
  the answer, so a `FOO.EXE` in the current directory wins over a
  `FOO.COM` in `PATH`.
- With an extension (any dot in the name), NAME is handed to DOS as
  typed, and the file found counts only if its extension is `.COM`,
  `.EXE` or `.BAT`. So `which foo.exe` never reports `foo.com`, `which
  readme.txt` finds nothing even if the file exists, and `foo.` finds
  nothing. Because DOS applies its 8.3 rules, an overlong name or
  extension is truncated: `longnameextra` finds `LONGNAME.COM` and
  `foo.comx` finds `FOO.COM`, as they would at the prompt.
- Hidden and read-only programs are found; system files are not.
- Wildcards are not allowed, and directories are never matches.

One deliberate difference: `/` is accepted as a directory separator
(`which bin/foo`), where `COMMAND.COM` would take it as a switch.

Results are printed as full paths in lower case, with the extension
(`c:\bin\foo.exe`). `PATH` entries are made absolute, so relative
entries and trailing backslashes are handled, and a directory that
appears twice (or is also the current directory) is searched only once.

## Files

- `which.c`: the program
- `Makefile`: Open Watcom build (`make`, `make test`, `make clean`)
- `VERSION`: the version, compiled in and printed by `--version`
- `tests/run.sh`: the test suite, run under DOSBox-X by `make test`
- `which.asm`, `tests/compare.sh`, `ASM.md`: the assembly experiment
- `.github/workflows/ci.yml`: build and test both versions on PRs and
  pushes to `main`
- `.github/workflows/release.yml`: tag and release when `VERSION` changes

## License

MIT. See `LICENSE`.
