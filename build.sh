#!/usr/bin/env bash
#
# WeKan-Lite build script — Linux / macOS / *BSD / Haiku shells.
# Cross-compiles src/wlhttp.lpr with FreePascal (fpc). See README.md / docs/static.md.
#
# Cross targets need the matching FPC cross build (cross binutils + RTL) installed; if a target's
# toolchain is missing, fpc errors out for that target — that is expected, not a bug here.
# Some targets are experimental in FPC and may be unsupported by your version (e.g. Linux s390x,
# AROS arm64) — they are listed for completeness and will simply fail if unsupported.
#
# Env overrides:
#   FPC=...       path to the fpc compiler            (default: fpc)
#   FPCFLAGS=...  extra flags appended to every build (e.g. -dWLDB_CLI to use the external
#                 sqlite3 CLI instead of linked SQLite, which avoids needing the amalgamation)
#
set -u
cd "$(dirname "$0")" || exit 1

FPC="${FPC:-fpc}"
SRC="src/wlhttp.lpr"
OUTDIR="build"
BINDIR="$OUTDIR/bin"        # collected binaries: build/bin/w<code>.exe
ARCHROOT="$OUTDIR/arch"     # per-platform build dirs:   build/arch/<code>/
BASEFLAGS="-O3 -Xs -Fusrc"
FPCFLAGS="${FPCFLAGS:-}"

# DOS 8.3 layout (see CLAUDE.md): each platform builds into build/arch/<code>/ (exe +
# .o/.ppu/link intermediates), then the finished executable is copied to build/bin/w<code>.exe.
# <code> is a <=7-char platform name so the binary base "w"+<code> stays <=8 chars; every path
# component is <=8 chars and the extension is .exe, so the whole tree is DOS 8.3 / Amiga safe.
# label | fpc -P (cpu) | fpc -T (os) | extra flags | code (<=7 chars)
PLATFORMS=(
  "Linux amd64|x86_64|linux||linx64"
  "Linux arm64|aarch64|linux||lina64"
  "Linux armhf|arm|linux|-CaEABIHF -CfVFPV3|linahf"
  "Linux armv7|arm|linux|-Cparmv7a -CfVFPV3 -CaEABIHF|linav7"
  "Linux s390x|s390x|linux||lins390"
  "Linux ppc|powerpc|linux||linppc"
  "Linux ppc64le|powerpc64|linux|-Caelfv2|linp64l"
  "macOS arm64|aarch64|darwin||maca64"
  "Windows x86|i386|win32||winx86"
  "Windows amd64|x86_64|win64||winx64"
  "DOS|i386|go32v2||dos"
  "Haiku|x86_64|haiku||haiku"
  "Amiga m68k|m68k|amiga||ami68k"
  "AmigaOS 4.1 PPC|powerpc|amiga||amios4"
  "MorphOS|powerpc|morphos||morphos"
  "AROS x86|i386|aros||arosx86"
  "AROS amd64|x86_64|aros||arosx64"
  "AROS arm64|aarch64|aros||arosa64"
  "AROS m68k|m68k|aros||aros68k"
  "AROS ppc|powerpc|aros||arosppc"
)

# Build into build/arch/<code>/ then copy the executable to build/bin/w<code>.exe.
do_build() {  # $1=code  $2=label  $3.. = fpc target/flags
  local code="$1" label="$2"; shift 2
  local arch="$ARCHROOT/$code" bin="w$code.exe"
  mkdir -p "$arch" "$BINDIR"
  echo ">> Building $label  -> $arch/$bin"
  # shellcheck disable=SC2086
  if "$FPC" $BASEFLAGS $FPCFLAGS "$@" -FU"$arch" -FE"$arch" -o"$arch/$bin" "$SRC"; then
    cp -f "$arch/$bin" "$BINDIR/$bin"
    echo "   copied -> $BINDIR/$bin"
  else
    return 1
  fi
}

build_current() {
  do_build current "current platform"
}

build_platform() {  # $1 = a PLATFORMS entry
  local entry="$1" label cpu os flags code
  IFS='|' read -r label cpu os flags code <<< "$entry"
  # shellcheck disable=SC2086
  do_build "$code" "$label  (-P$cpu -T$os $flags)" -P"$cpu" -T"$os" $flags
}

build_all() {
  local entry ok=0 fail=0 label
  for entry in "${PLATFORMS[@]}"; do
    if build_platform "$entry"; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1)); label="${entry%%|*}"; echo "!! $label failed"
    fi
  done
  echo "== done: $ok built, $fail failed =="
}

select_platform() {
  local i=1 entry label n
  echo
  for entry in "${PLATFORMS[@]}"; do
    label="${entry%%|*}"
    printf "  %2d) %s\n" "$i" "$label"
    i=$((i + 1))
  done
  printf "  Platform number (or 0 to cancel): "
  read -r n || return
  case "$n" in
    ''|*[!0-9]*) echo "  Not a number."; return ;;
  esac
  if [ "$n" -eq 0 ]; then
    return
  elif [ "$n" -ge 1 ] && [ "$n" -le "${#PLATFORMS[@]}" ]; then
    build_platform "${PLATFORMS[$((n - 1))]}"
  else
    echo "  Out of range."
  fi
}

# Ubuntu 26.04 (amd64/arm64 host) convenience: install the host FPC + RTL source + the Linux
# cross-binutils Ubuntu ships, then build the FPC cross compilers/RTLs for the targets Ubuntu can
# support. The Linux CPU variants need cross-binutils; the Windows/DOS targets use FPC's internal
# assembler+linker (no binutils). macOS, Amiga, AmigaOS4, MorphOS, AROS and Haiku are NOT in
# Ubuntu's repos — build those with fpcupdeluxe (https://github.com/LongDirtyAnimAlf/fpcupdeluxe).
install_toolchains() {
  if [ ! -r /etc/os-release ] || ! grep -qi '^ID=ubuntu' /etc/os-release; then
    echo "  Not Ubuntu (per /etc/os-release) — this installer is Ubuntu-only. Aborting."; return 1
  fi
  case "$(uname -m)" in
    x86_64|aarch64) ;;
    *) echo "  Host arch $(uname -m) unsupported (expected amd64/arm64). Aborting."; return 1 ;;
  esac
  local SUDO=""
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else
      echo "  Need root or sudo to apt-get install. Re-run as root."; return 1; fi
  fi

  echo ">> apt-get: host FPC, RTL source, and Linux cross-binutils"
  $SUDO apt-get update || { echo "  apt-get update failed."; return 1; }
  $SUDO apt-get install -y fpc fpc-source make \
    binutils-x86-64-linux-gnu \
    binutils-aarch64-linux-gnu \
    binutils-arm-linux-gnueabihf \
    binutils-s390x-linux-gnu \
    binutils-powerpc-linux-gnu \
    binutils-powerpc64le-linux-gnu \
    || { echo "  apt-get install failed."; return 1; }

  local fpcsrc
  fpcsrc="$(ls -d /usr/share/fpcsrc/* 2>/dev/null | sort -V | tail -1)"
  if [ -z "$fpcsrc" ] || [ ! -d "$fpcsrc" ]; then
    echo "  Cross-binutils installed, but the FPC source tree (fpc-source) was not found under"
    echo "  /usr/share/fpcsrc — cannot build cross RTLs. Install 'fpc-source' and re-run."
    return 1
  fi

  mkdir -p "$OUTDIR/log"
  local log="$OUTDIR/log/xtools.log"
  : > "$log"
  echo ">> Building FPC cross compilers from $fpcsrc  (verbose output -> $log)"

  # feasible cross targets:  cpu | os | binutils-prefix (empty = FPC-internal) | CROSSOPT
  local CROSS=(
    "x86_64|linux|x86_64-linux-gnu-|"
    "aarch64|linux|aarch64-linux-gnu-|"
    "arm|linux|arm-linux-gnueabihf-|-CaEABIHF -CfVFPV3"
    "s390x|linux|s390x-linux-gnu-|"
    "powerpc|linux|powerpc-linux-gnu-|"
    "powerpc64|linux|powerpc64le-linux-gnu-|-Caelfv2"
    "x86_64|win64||"
    "i386|win32||"
    "i386|go32v2||"
  )
  local entry cpu os pfx copt ok=0 fail=0
  for entry in "${CROSS[@]}"; do
    IFS='|' read -r cpu os pfx copt <<< "$entry"
    echo "   -- $cpu-$os"
    local -a margs=( -C "$fpcsrc" crossinstall
                     CPU_TARGET="$cpu" OS_TARGET="$os"
                     FPC="$(command -v fpc)" INSTALL_PREFIX=/usr )
    [ -n "$pfx" ]  && margs+=( BINUTILSPREFIX="$pfx" )
    [ -n "$copt" ] && margs+=( CROSSOPT="$copt" )
    if $SUDO make "${margs[@]}" >>"$log" 2>&1; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1)); echo "      FAILED ($cpu-$os) — see $log"
    fi
  done
  echo "== cross toolchains: $ok built, $fail failed (host-native target already present) =="
  echo "   Not available via Ubuntu apt (use fpcupdeluxe): macOS arm64, Amiga m68k,"
  echo "   AmigaOS 4.1 PPC, MorphOS, AROS x86/amd64/arm64/m68k/ppc, Haiku."
}

while true; do
  cat <<MENU

  WeKan-Lite build  (fpc: $FPC)
  1) Build for current platform
  2) Build for all platforms
  3) Select platform and build for it
  4) Install FPC cross-toolchains (Ubuntu 26.04 amd64/arm64)
  5) Quit
MENU
  printf "  Choice: "
  read -r c || exit 0
  case "$c" in
    1) build_current ;;
    2) build_all ;;
    3) select_platform ;;
    4) install_toolchains ;;
    5) exit 0 ;;
    *) echo "  Pick 1-5." ;;
  esac
done
