# WeKan-Lite — cross-compiling for all targets (build.sh option 4)

How `build.sh` installs FreePascal cross-compilers and cross-builds `welite` for every target,
what actually works, and the gotchas found getting it running on Ubuntu 26.04.

Companion to the build scripts (`build.sh` / `build.bat` / `build.ami`) and `CLAUDE.md`
(DOS 8.3 layout). Verified 2026-06-25 on an **aarch64 (Apple Silicon) Ubuntu** host with
FPC 3.2.3 (the `fixes-3.2` branch) built via fpcupdeluxe.

---

## TL;DR

```sh
./build.sh            # menu option 4: install FPC cross-compilers (Ubuntu/Debian, amd64/arm64)
# then, with the freshly built compiler:
FPC=~/fpcupdeluxe/fpc/bin/aarch64-linux/fpc ./build.sh    # option 2 (all) or 3 (select)
```

Working binaries land in `build/bin/w<code>.exe`; intermediates in `build/arch/<code>/`.
Targets whose cross-compiler is not installed report a failure and are skipped.

---

## Why fpcupdeluxe (apt can't do it)

apt cannot provide FPC cross-compilers on Ubuntu/Debian:

- no packaged FPC cross-compilers exist;
- `fpc-source` is **stripped of the top-level build Makefiles** (`/usr/share/fpcsrc/<ver>/` has
  only `compiler/ packages/ rtl/`), so `make crossinstall` has no rule;
- the exotic OSes (Amiga/AROS/MorphOS/Haiku/DOS/macOS) have **no Ubuntu binutils** at all.

So `build.sh` option 4 uses [fpcupdeluxe](https://github.com/LongDirtyAnimAlf/fpcupdeluxe), which
downloads the FPC source and builds the cross compiler + cross-binutils per target. The released
`fpcupdeluxe-*-linux` binary is **GUI-only** and does nothing when driven headless, so the script
builds fpcupdeluxe's real console tool **`fpclazup`** from source (its `fpclazup.lpi`, built with
`lazbuild` and the **nogui** LCL widgetset) and runs that headlessly. If any of that can't be set
up it falls back to launching the fpcupdeluxe GUI (run it from **outside** the repo — see below).

---

## The build chain (every gotcha, all handled automatically)

Getting a working FPC + cross-compilers on Ubuntu 26.04 needed a long chain of fixes; each is now
applied by `build.sh`:

| Stage | Symptom | Fix |
|-------|---------|-----|
| build `fpclazup` | lazbuild used a non-existent `/usr/share/lazarus/<ver>` | `--lazarusdir=/usr/lib/lazarus/<ver>` (matched to `lazbuild --version`) |
| build `fpclazup` | `.lpi` active mode targets `x86_64-openbsd` → `ppcx64 … code 127` | force host `--cpu/--os`; output is `upbin/fpclazup-<host>-linux` |
| base FPC | `EFOpenError: .../fpcbootstrap/ppca64: No such file` | seed the bootstrap dir with the **system** FPC compiler (`/usr/bin/ppc<arch>`) |
| base FPC | parallel RTL build raced (`unixtype.s` vanished mid-assemble) | `--disablejobs` |
| base FPC | FPC 3.2.2 won't link on glibc ≥ 2.34 — `cprt0` references the removed `__libc_csu_init/_fini` (Ubuntu 26.04 = glibc 2.43) | `--fpcVersion=fixes-3.2.gitlab` (3.2.3-dev, has the fix) |
| base FPC | non-zero exit from the trailing **LCLCross** module | `--only=FPC`; treat "a working `fpc` binary exists" as success, not the exit code |
| re-runs | `Error: wrong command line options given: fpcVersion=…` | fpcupdeluxe pins the version once `fpcsrc` exists → pass `--fpcVersion` only on a fresh tree |
| cross | `Failed to get crossbinutils / crosslibrary` | `--autotools` (auto-download per-target cross-bins/libs) |
| using the FPC | static compiler ignored its own `fpc.cfg`, fell back to `/etc/fpc.cfg` (wrong units) | `do_build` exports `PPC_CONFIG_PATH=$(dirname "$FPC")` |

The install dir defaults to `~/fpcupdeluxe` (override with `FPCUP_DIR`) and **must be outside the
git repo** — fpcupdeluxe derives its basedir from the working directory and aborts if a fresh
`fpcsrc/` resolves up to another repo's `.git`. The script guards against an in-repo `FPCUP_DIR`.
Verbose output goes to `build/log/xtools.log`.

---

## SQLite: why cross builds use `-dWLDB_CLI`

`welite`'s default build links `libsqlite3` (`uses sqlite3`). That can't be **cross-linked** — the
toolchain has no `libsqlite3` for the target arch — so the default cross build fails to link on
Linux. The `-dWLDB_CLI` mode (in `wldb.pas`) shells out to the external `sqlite3` binary via
`TProcess` and links nothing, so it cross-compiles cleanly.

Therefore every **non-Windows** `PLATFORMS` entry in `build.sh` carries `-dWLDB_CLI`. Windows keeps
the linked default (FPC loads `sqlite3.dll` at runtime, not at link time). "Build for current
platform" (option 1) also keeps the native linked-SQLite default.

A `-dWLDB_CLI` binary needs the `sqlite3` command-line tool present at runtime on the target.

---

## Verified support matrix (aarch64 host)

`ok` = cross compiler builds **and** `welite` cross-compiles to a real foreign binary.

| Target | cpu-os | result | notes |
|--------|--------|--------|-------|
| Linux amd64    | x86_64-linux    | **ok** | `-dWLDB_CLI` → x86-64 ELF |
| Linux arm64    | aarch64-linux   | **ok** | native on this host |
| Linux arm (plain) | arm-linux    | **ok** | soft-float EABI5 ARM ELF |
| Linux armhf    | arm-linux       | needs hard-float arm RTL | the `-CaEABIHF -CfVFPV3` flags clash with fpcupdeluxe's soft-float arm RTL ("different FPU mode") |
| Linux armv7    | arm-linux       | needs hard-float arm RTL | same as armhf |
| Windows x86    | i386-win32      | **ok** | linked SQLite → Win32 PE |
| Windows amd64  | x86_64-win64    | **ok** | linked SQLite → Win64 PE |
| Linux s390x    | s390x-linux     | no | fpcupdeluxe rejects `s390x` (`Invalid CPU name`) |
| Linux ppc      | powerpc-linux   | needs x-bins | no aarch64-host crosslib |
| Linux ppc64le  | powerpc64-linux | needs x-bins | no aarch64-host crosslib |
| macOS arm64    | aarch64-darwin  | needs x-bins | no aarch64-host crossbins |
| DOS            | i386-go32v2     | needs x-bins | no aarch64-host crossbins |
| Haiku          | x86_64-haiku    | needs x-bins | no aarch64-host crossbins |
| Amiga m68k     | m68k-amiga      | needs x-bins | no aarch64-host crossbins |
| AmigaOS 4.1 PPC| powerpc-amiga   | needs x-bins | no aarch64-host crossbins |
| MorphOS        | powerpc-morphos | needs x-bins | no aarch64-host crossbins |
| AROS x86/amd64/arm64/m68k/ppc | *-aros | needs x-bins | no aarch64-host crossbins |

`build all` on this host therefore produces 4 binaries — `wlinx64.exe`, `wlina64.exe`,
`wwinx86.exe`, `wwinx64.exe` — and reports the rest as failures (no cross-compiler installed).

### "needs x-bins" is a host limitation, not a welite bug

`needs x-bins` means fpcupdeluxe has **no prebuilt cross-binutils/libs for an aarch64 host**
targeting that platform. fpcupdeluxe's cross-bins are mostly built for **x86_64 hosts**, which have
prebuilt cross-bins for Amiga/AROS/MorphOS/Haiku/DOS/macOS/ppc. So the realistic way to cross-build
`welite` for the exotic retro targets today is to run `build.sh` option 4 on an **x86_64 Ubuntu
host**. The full `PLATFORMS` list is kept in `build.sh` precisely because it is correct there.

(Beyond the toolchain, `welite` is a threaded socket HTTP server; whether its server units compile
for DOS/Amiga/etc. is a separate question this sweep did not reach.)

---

## Reproducing the sweep

The per-target sweep installs each cross FPC and cross-builds `welite` two ways (default and
`-dWLDB_CLI`):

```sh
INST=~/fpcupdeluxe
FPCLAZUP=$INST/fpcupsrc/upbin/fpclazup-$(uname -m)-linux
# install one cross compiler (no --fpcVersion on re-runs; --autotools fetches cross-bins/libs):
"$FPCLAZUP" --installdir=$INST --fpcbootstrapdir=$INST/fpcbootstrap --disablejobs --only=FPC \
            --autotools --noconfirm --verbose --cputarget=<cpu> --ostarget=<os>
# cross-build welite for it:
PPC_CONFIG_PATH=$INST/fpc/bin/$(uname -m)-linux \
  $INST/fpc/bin/$(uname -m)-linux/fpc -P<cpu> -T<os> -dWLDB_CLI -O3 -Xs -Fusrc \
  -o/tmp/welite-<cpu>-<os> src/wlhttp.lpr
```
