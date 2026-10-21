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

The version is the one line in `VERSION`, DOS style (0.01, 0.02, ...
1.00), not semantic versioning. When a PR that changes it is merged to
`main`, the release workflow tags the merge commit `v<VERSION>` and
publishes a GitHub release with `which.exe` attached.

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

`which` follows `COMMAND.COM`:

- The current directory is searched first, then each directory in
  `PATH`, in order.
- In each directory `NAME.COM`, `NAME.EXE` and `NAME.BAT` are tried, in
  that order. Without `-a`, the first one found is the answer, so a
  `FOO.EXE` in the current directory wins over a `FOO.COM` in `PATH`.
- An explicit extension restricts the search to that file: `which
  foo.exe` never reports `foo.com`. Only `.COM`, `.EXE` and `.BAT` name a
  program, so `which readme.txt` finds nothing even if the file exists.
- A NAME with a drive or directory (`C:\BIN\FOO`, `BIN\FOO`, `..\FOO`,
  `C:FOO`) is looked for only there; `PATH` is not searched.
- Wildcards are not allowed, and directories are never matches.

Results are printed as full paths in lower case, with the extension
(`c:\bin\foo.exe`). `PATH` entries are made absolute, so relative
entries and trailing backslashes are handled, and a directory that
appears twice (or is also the current directory) is searched only once.

## Files

- `which.c`: the program
- `Makefile`: Open Watcom build (`make`, `make test`, `make clean`)
- `VERSION`: the version, compiled in and printed by `--version`
- `tests/run.sh`: the test suite, run under DOSBox-X by `make test`
- `.github/workflows/ci.yml`: build and test on PRs and pushes to `main`
- `.github/workflows/release.yml`: tag and release when `VERSION` changes

## License

MIT. See `LICENSE`.
