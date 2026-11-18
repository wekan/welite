# WeKan-Lite — cross-compiling for all targets (build.sh option 4)

How `build.sh` installs FreePascal cross-compilers and cross-builds `welite` for every target,
what actually works, and the gotchas found getting it running on Ubuntu 26.04.

Companion to the build scripts (`build.sh` / `build.bat` / `build.ami`) and `CLAUDE.md`
(DOS 8.3 layout). Verified 2026-06-25 on an **aarch64 (Apple Silicon) Ubuntu** host with
FPC 3.2.3 (the `fixes-3.2` branch) built via fpcupdeluxe.

## Expanded language catalog build checks (2026-11-18)

The 245-language catalog cross-build passed for disk and embedded WeLite on
Linux amd64 and Windows x86 and amd64, using both SQLite backends. Linux armhf
and armv7 also passed the disk and embedded CLI build checks. These checks
inspect the executable format and platform metadata. Runtime verification
on Windows and ARM remains open.

## Current Linux amd64 verification (2026-11-17)

The matrix below records the June sweep; it is not a verification of today's source
on every target. On the current **aarch64 Freedesktop SDK 25.08** host, the current
server builds as a Linux x86-64 ELF in both disk and full embedded CLI modes.
No foreign runtime or platform-specific behavior is implied by this link check.

The isolated toolchain uses GNU Binutils 2.47 targeting `x86_64-linux-gnu`, FPC
3.2.3 source revision `12e49a77d1c5b801fe8e4a2f77df27aa3dce848b`, and Debian
trixie `libc6-amd64-cross` / `libc6-dev-amd64-cross` 2.41-11cross1. Downloads
were checked against the official Binutils release hash and Debian package index
SHA256 values. Extract library packages into a private sysroot; do not install
foreign packages over the host libraries.

Given a native `ppca64`, target binutils in `$PREFIX/bin`, and the FPC source tree,
build and install the compiler/units serially (run each make separately):

```sh
make -j1 crossall CPU_TARGET=x86_64 OS_TARGET=linux FPC="$NATIVE_PPC" \
  BINUTILSPREFIX=x86_64-linux-gnu- CROSSBINDIR="$PREFIX/bin" \
  INSTALL_PREFIX="$PREFIX" OPT='-O2 -dFPC_SOFT_FPUX80' CROSSOPT='-n -O2'
make -j1 crossinstall CPU_TARGET=x86_64 OS_TARGET=linux FPC="$NATIVE_PPC" \
  BINUTILSPREFIX=x86_64-linux-gnu- CROSSBINDIR="$PREFIX/bin" \
  INSTALL_PREFIX="$PREFIX" OPT='-O2 -dFPC_SOFT_FPUX80' CROSSOPT='-n -O2'
```

`FPC_SOFT_FPUX80` is needed when building this compiler on aarch64: without it,
80-bit target constants fail with internal errors during RTL compilation. Merely
selecting the external assembler does not fix that failure.

Extract both Debian packages beneath `$PREFIX/sysroot`, retaining their
`usr/x86_64-linux-gnu/lib` and `lib64` layout. Pass both `-Fl` for that library
directory and `-k--sysroot=$PREFIX/sysroot` to the application build. `-XR` alone
did not rebase the absolute paths in Debian's `libc.so` linker script.

```sh
export TMPDIR=/absolute/path/to/wekan/.tools/tmp
mkdir -p "$TMPDIR"
WELITE_CROSS64="$PREFIX" FPCRES=/absolute/path/to/native/fpcres \
  python3 tests/cross64.py
```

The check explicitly selects the native `fpcres` with `-FR` (the default cross
prefix otherwise makes FPC search for `x86_64-linux-gnu-fpcres`). It compiles today's complete server twice, generates the full embedded
asset/private-SQL resource bundle, and validates ELF64/little-endian/x86-64 headers.
Build products are temporary and removed.

### Emulated amd64 embedded runtime (2026-11-17)

The full directory-free embedded CLI HTTP acceptance also passes with Debian's
ARM64 `qemu-user` 10.0.13 and the above target sysroot. Add the verified Debian
`libgcc-s1-amd64-cross` 14.2.0-19cross1 package to the sysroot: glibc thread exit
otherwise aborts with a missing `libgcc_s.so.1`. No binfmt registration or host
package installation is needed.

Use an executable compiler wrapper containing the flags from `tests/cross64.py`,
forwarding arguments with `"$@"`, then run:

```sh
FPC=/absolute/path/to/cross-wrapper FPCRES=/absolute/path/to/native/fpcres \
WELITE_EMBED_BACKENDS=cli \
WELITE_RUNNER='/absolute/path/to/qemu-x86_64 -L /absolute/prefix/sysroot/usr/x86_64-linux-gnu' \
  python3 tests/embhttp.py
```

This checks private SQL bootstrap/refusal, exact public/catalog/locale bytes,
registration/login, translated auth, Designer creation, RTL published pages,
non-public SQL and clean SIGTERM shutdown. The process runs x86-64 application
and libc code, but executes the **host's native sqlite3 CLI child process**.
It does not establish a target-native SQLite deployment, linked amd64 SQLite,
physical amd64 hardware, or other operating-system acceptance.

### Emulated linked amd64 SQLite (2026-11-17)

A subsequent check adds Debian trixie's verified amd64 `libsqlite3-0` and
`libsqlite3-dev` 3.46.1-7+deb13u2 packages beneath the same sysroot. The complete
embedded HTTP suite passes with `WELITE_EMBED_BACKENDS=linked`: the application,
libc and SQLite engine all execute as x86-64 code, with no SQLite CLI child needed.

Add `-Fl$PREFIX/sysroot/usr/lib/x86_64-linux-gnu` to the compiler wrapper, and
append this QEMU argument (substitute absolute paths):

```sh
-E LD_LIBRARY_PATH=/absolute/prefix/sysroot/usr/lib/x86_64-linux-gnu:/absolute/prefix/sysroot/usr/x86_64-linux-gnu/lib
```

Do not export the target library path into the host compiler or Python process.
QEMU's `-E` applies it to the foreign process only. For all four disk/embedded
and CLI/linked build checks, set `WELITE_CROSS_BACKENDS=cli,linked` when running
`tests/cross64.py`; the default remains CLI-only for toolchains without SQLite.
The 2026-11-18 rerun at `6b30a9c` passed the linked and CLI embedded HTTP
suites under QEMU, including the new RTL HTML4 board and viewport check.
The CLI run still uses the host SQLite process.

### Emulated amd64 SQLite command-line process (2026-11-18)

The CLI embedded HTTP suite also passed with Debian's amd64 SQLite 3.46.1
CLI. Extract [the verified Debian package](https://packages.debian.org/trixie/amd64/sqlite3/download)
and its amd64 Readline, tinfo, and zlib libraries into a separate test
directory. Put a wrapper named `sqlite3` first on the test process's `PATH`.
The wrapper runs the amd64 CLI under the same QEMU loader and passes the
target library paths through QEMU's `-E LD_LIBRARY_PATH` option. With
`WELITE_EMBED_BACKENDS=cli`, the harness verified bootstrap, RTL HTML4 board
rendering, private SQL, and shutdown. The wrapper recorded 327 invocations.

Physical amd64 hardware and other platforms remain open.

## Amiga m68k toolchain on ARM64 Linux (2026-11-18)

The pinned FPC source at `12e49a77d1` built and installed the
`m68k-amiga` compiler and target packages on ARM64 Linux. The host tools
came from the [vasm source mirror](https://github.com/StarWolf3000/vasm-mirror/tree/a13e7e7)
and [vlink source mirror](https://github.com/retro-vault/vlink/tree/47a7f70).
Build vasm with `CPU=m68k SYNTAX=std`, then place the resulting tools in a
private bin directory as `m68k-amiga-vasmm68k_std` and `m68k-amiga-vlink`.
Use `CPU_TARGET=m68k OS_TARGET=amiga BINUTILSPREFIX=m68k-amiga-` and
`CROSSOPT='-n -O2 -XV -Avasm'` in the serial FPC cross build and installation.

A stripped Pascal probe linked as an AmigaOS loadable executable. The older
linker did not recognize the section flags emitted by FPC. Build
[vlink 0.18a](https://github.com/erique/vbcc_vasm_vlink/blob/647720b/vlink.tar.gz)
and use it with the same assembler and FPC units. The full WeLite server
links with `-dWLDB_CLI -Xs` and is recognized as an AmigaOS executable.

The resource build also links with `-dWLEMBED`. For this target, FPC uses
external resources. Provide the ARM64 host `fpcres` as
`m68k-amiga-fpcres` in the cross-tools directory and keep `wlhttp.fpcres`
next to `wlhttp`. The companion resource file contains the exact public
asset, locale, and private bootstrap SQL bytes checked on the build host.
An m68k probe executed in [vamos](https://github.com/cnvogelg/amitools/blob/main/docs/vamos.md)
and read the exact schema bytes from the full resource bundle with
`TResourceStream`. The server executable reached tenant registry
initialization in the same emulator but stopped there. The tested
[GFOpenSQLite package](https://github.com/DalsinAI/gfopensqlite/releases/tag/v3.53.4-1)
supplies static libraries. The CLI build still needs an Amiga `sqlite3`
executable. The CLI from the
[Amiga SQLite 3.34 port](https://aminet.net/package/biz/dbase/sqlite-3.34.0.a-amiga)
executes under vamos and can create, write and read a native SQLite file.
This build lacks `json()`, which WeLite uses, and its `-init` script test
stopped in the emulator's DOS file-handle implementation. Full server
startup, networking and a compatible SQLite CLI remain open.

A newer shell experiment links SQLite 3.53.4's `shell.c` against the
GFOpenSQLite hard-float library. The
[Amiga GCC release](https://github.com/AmigaPorts/m68k-amigaos-gcc/releases/tag/v16.2-rc25)
runs via x86-64 QEMU on the ARM64 build host. The shell uses libnix and
libpthread. Its home-directory lookup skips `getpwuid()`, which libnix
does not export. The resulting executable reports SQLite 3.53.4 under
vamos with an emulated 68040. Running the first SQL statement reaches an
invalid memory access in the emulator. The shell has not passed database
execution or been tested on AmigaOS.

With the same VFS patches and `SQLITE_THREADSAFE=0`, the shell avoids the
pthread path and completes JSON and JSONB queries in vamos. An inline SQL
probe writes and reads a persistent table. Host SQLite reads back the
same value and reports `integrity_check = ok`. The emulator reports an
error during cleanup after the write, and the `-init` startup script
still fails before schema creation. This is partial emulation evidence
for standalone SQLite. The WeLite CLI subprocess and HTTP runtime remain open.

## Current Windows amd64 cross-build verification (2026-11-17)

The same pinned FPC source builds a separate Windows compiler/unit prefix with
`CPU_TARGET=x86_64 OS_TARGET=win64` in the serial `crossall` / `crossinstall`
commands above. Keep `OPT='-O2 -dFPC_SOFT_FPUX80'` for the aarch64 host. FPC's
internal assembler/linker sufficed; this check needed no Windows binutils/sysroot.

```sh
WELITE_WIN64=/absolute/windows/toolchain FPCRES=/absolute/native/fpcres \
  python3 tests/wincross.py
```

All four current disk/embedded and linked/CLI variants pass. The check validates
MZ/PE signatures, AMD64 machine, PE32+ format and console subsystem; linked
variants contain the SQLite DLL reference. Embedded generation conditionally
imports `Windows` for `RT_RCDATA`, whose declaration is not in `Classes` there.
Native resource lookup/private-seed checks and all four Linux amd64 build checks
also pass after this correction. A PE build is not Windows runtime acceptance:
SQLite DLL distribution, secure OS randomness, threading, resource lookup and
console shutdown still require execution on Windows.

## Current Windows x86 cross-build verification (2026-11-17)

The pinned compiler source also passes serial `crossall` / `crossinstall` with
`CPU_TARGET=i386 OS_TARGET=win32` into a separate prefix. Its compiler is
`lib/fpc/3.2.3/ppcross386` and units are `units/i386-win32`; no external Windows
binutils/sysroot was required. Run one or both installed target prefixes:

```sh
WELITE_WIN32=/absolute/windows32/toolchain \
WELITE_WIN64=/absolute/windows64/toolchain FPCRES=/absolute/native/fpcres \
  python3 tests/wincross.py
```

All eight current target/backend/resource combinations pass. x86 checks require
i386 machine/PE32 headers; amd64 checks require AMD64/PE32+. Both require the
console subsystem. The check now resolves real PE import-directory RVAs through
section headers, requires kernel32.dll, and verifies sqlite3.dll is imported
exactly by linked variants. All variants also require the Winsock address
resolution imports used by webhook validation. This extends source/build coverage to 32-bit widths;
Windows runtime, resource bytes, entropy, DLL deployment and shutdown acceptance
remain open for both targets.

### Windows webhook resolver probe

The Windows cross-build check compiles a resolver probe for every selected
architecture. Set `WELITE_WIN_RUNNER` to a command that can run the resulting
Windows executables. The probe checks public IPv4 and IPv6 literals and rejects
loopback destinations. When running the probe directly, pass a public webhook
URL as its sole argument to check DNS resolution through the platform resolver.
Windows runtime results remain open.

## Current Linux ARM hard-float build checks (2026-11-17)

Both advertised `armhf` and `armv7` CLI variants now compile in disk and full
embedded modes using a separate toolchain. Build GNU Binutils 2.47 for
`arm-linux-gnueabihf`, and extract verified Debian cross libc/runtime packages
under a private sysroot (`libc6-armhf-cross`, `libc6-dev-armhf-cross` 2.41-11cross1;
`libgcc-s1-armhf-cross` 14.2.0-19cross1).

For pinned FPC source, use the serial commands above with `CPU_TARGET=arm`,
`OS_TARGET=linux`, `BINUTILSPREFIX=arm-linux-gnueabihf-`, and these options:

```sh
OPT='-O2 -dFPC_SOFT_FPUX80 -dFPC_ARMHF'
CROSSOPT='-n -O2 -CaEABIHF -CfVFPV3'
```

Clean the isolated source build before changing these options: existing FPC build
markers otherwise reuse the old compiler. `-dFPC_ARMHF` is a **compiler build**
define, not an application define; without it this revision advertises ARMEL and
selects `/lib/ld-linux.so.3` despite application `-CaEABIHF`. The corrected compiler
advertises ARMHF and selects `/lib/ld-linux-armhf.so.3`. Matching CROSSOPT produces
RTL units compatible with both build-menu application variants.

```sh
WELITE_ARMHF=/absolute/armhf/toolchain FPCRES=/absolute/native/fpcres \
  python3 tests/armhf.py
```

All four current builds pass ELF32/little-endian/ARM/EABI5 and exact hard-float
loader checks. The pinned compiler still emits a soft-float ELF flag, matching
[FPC issue 40374](https://gitlab.com/freepascal.org/fpc/source/-/issues/40374).
The regression reports its actual flags and accepts only the known soft/hard
metadata values; it does not claim the flag is corrected. It also compiles a
hard-float-only ABI probe for libc `strtod` returns and libm `pow` arguments/returns.
Set `WELITE_ARM_RUNNER` to an executable/argument list to execute that probe.

Runtime acceptance is **not verified on this host**. Both the ABI probe and fresh
embedded CLI HTTP suite fail inside the target loader while mapping libc/libm.
This host has 16 KiB pages, matching the reproduction in
[Debian QEMU bug 1114725](https://bugs-devel.debian.org/cgi-bin/bugreport.cgi?bug=1114725).
QEMU 10.0.13's deprecated `-p 4096` reports that it cannot change the host page
size and does not resolve the failure. Run the ABI probe and copied-executable
HTTP suite on a suitable host/emulator or physical ARM target before claiming
runtime, floating-point-call or embedded-resource acceptance.

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
`TProcess` and avoids the SQLite library dependency. Target OS C/thread libraries
may still be required, as the current Linux sysroot check above demonstrates.

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
| Amiga m68k     | m68k-amiga      | builds | CLI SQLite builds link from ARM64 Linux, runtime pending |
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
