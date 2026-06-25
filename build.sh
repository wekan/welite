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

# build.sh target -> fpcupdeluxe cpu/os. Used by both the fpclazup and GUI paths.
FPCUP_CROSS=(
  "Linux amd64|x86_64|linux"   "Linux arm64|aarch64|linux"  "Linux armhf/armv7|arm|linux"
  "Linux s390x|s390x|linux"    "Linux ppc|powerpc|linux"    "Linux ppc64le|powerpc64|linux"
  "macOS arm64|aarch64|darwin" "Windows x86|i386|win32"     "Windows amd64|x86_64|win64"
  "DOS|i386|go32v2"            "Haiku|x86_64|haiku"         "Amiga m68k|m68k|amiga"
  "AmigaOS 4.1 PPC|powerpc|amiga" "MorphOS|powerpc|morphos" "AROS x86|i386|aros"
  "AROS amd64|x86_64|aros"     "AROS arm64|aarch64|aros"    "AROS m68k|m68k|aros"
  "AROS ppc|powerpc|aros"
)

# Automated path: build fpcupdeluxe's real console tool `fpclazup` (LCL nogui widgetset) with
# lazbuild, then run it headless to fetch the FPC source and build the cross compiler +
# cross-binutils per target. Returns 0 only if base FPC was installed; 1 on any setup failure so
# the caller can fall back to the GUI. Verbose output -> $log.   args: host inst src log SUDO
_fpcup_build_fpclazup() {
  local host="$1" inst="$2" src="$3" log="$4" SUDO="$5"
  echo ">> apt-get: Lazarus (lazbuild + nogui LCL) and build prerequisites"
  $SUDO apt-get update            || return 1
  $SUDO apt-get install -y lazarus lcl-nogui git subversion build-essential make unzip \
        curl ca-certificates      || return 1
  command -v lazbuild >/dev/null 2>&1 || { echo "  lazbuild not found after install."; return 1; }

  echo ">> Cloning fpcupdeluxe and building headless fpclazup (nogui)  [verbose -> $log]"
  rm -rf "$src"
  git clone --depth 1 https://github.com/LongDirtyAnimAlf/fpcupdeluxe "$src" >>"$log" 2>&1 || return 1
  ( cd "$src" && lazbuild --ws=nogui fpclazup.lpi ) >>"$log" 2>&1
  local fpclazup
  fpclazup="$(find "$src" -maxdepth 2 -type f -name fpclazup -perm -u+x 2>/dev/null | head -1)"
  [ -n "$fpclazup" ] || { echo "  lazbuild did not produce fpclazup — see $log."; return 1; }

  echo ">> Installing base (native) FPC into $inst  [LONG — watch: tail -f $log]"
  "$fpclazup" --installdir="$inst" --noconfirm --verbose --skip=lazarus >>"$log" 2>&1 \
    || { echo "  base FPC install failed — see $log."; return 1; }

  local entry label cpu os ok=0 fail=0 skip=0
  for entry in "${FPCUP_CROSS[@]}"; do
    IFS='|' read -r label cpu os <<< "$entry"
    if [ "$os" = linux ] && [ "$cpu" = "$host" ]; then
      echo "   -- $label  (host-native, already built)"; skip=$((skip + 1)); continue
    fi
    echo "   -- $label  ($cpu-$os)  [LONG]"
    if "$fpclazup" --installdir="$inst" --noconfirm --verbose --skip=lazarus \
         --cputarget="$cpu" --ostarget="$os" >>"$log" 2>&1; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1)); echo "      FAILED ($cpu-$os) — see $log (target may be unsupported)"
    fi
  done
  echo "== cross compilers: $ok built, $fail failed, $skip native =="
  return 0
}

# Fallback path: the released fpcupdeluxe is GUI-only and will not run headless, so download it and
# (if a display exists) launch it for the user to install FPC + tick the cross targets by hand.
_fpcup_launch_gui() {
  local host="$1" inst="$2"
  local gui="$inst/fpcupdeluxe"
  if [ ! -x "$gui" ]; then
    local url="https://github.com/LongDirtyAnimAlf/fpcupdeluxe/releases/latest/download/fpcupdeluxe-$host-linux"
    echo "   Downloading $url"
    curl -fSL --retry 3 -o "$gui" "$url" || { echo "   download failed."; return 1; }
    chmod +x "$gui"
  fi
  echo "   In the GUI: set the install directory to $inst, install FPC, then tick the cross"
  echo "   targets you need (Amiga/AROS/MorphOS/Haiku/Windows/DOS/macOS) and install them."
  echo "   Afterwards build here with:  FPC=$inst/fpc/bin/$host-linux/fpc ./build.sh"
  if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    echo "   Launching the GUI now..."
    ( "$gui" >/dev/null 2>&1 & )
  else
    echo "   No display detected — run it on a desktop session:  $gui"
  fi
}

# Install FPC cross-compilers (Ubuntu/Debian, amd64/arm64). apt can't provide them (no packaged
# cross compilers; fpc-source ships without the build Makefiles; exotic OSes have no Ubuntu
# binutils), so this uses fpcupdeluxe. It first builds fpcupdeluxe's headless console tool
# `fpclazup` and runs it to build the cross compiler + cross-binutils per target (Amiga/AROS/
# MorphOS/Haiku included). If that can't be set up it falls back to launching the fpcupdeluxe GUI.
# LONG-running; per-target results + verbose output go to build/log/xtools.log.
install_toolchains() {
  case "$(uname -s)" in Linux) ;; *) echo "  Linux host required."; return 1 ;; esac
  local host; host="$(uname -m)"     # x86_64 / aarch64 — matches the fpcupdeluxe asset arch
  case "$host" in
    x86_64|aarch64) ;;
    *) echo "  Host arch $host unsupported (need amd64/arm64). Aborting."; return 1 ;;
  esac
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "  apt-get not found — this installer targets Ubuntu/Debian. Aborting."; return 1
  fi
  local SUDO=""
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else
      echo "  Need root or sudo to apt-get install. Re-run as root."; return 1; fi
  fi
  local inst="${FPCUP_DIR:-$HOME/fpcupdeluxe}"
  local src="$inst/fpcupsrc"
  mkdir -p "$inst" "$OUTDIR/log"
  local log="$OUTDIR/log/xtools.log"; : > "$log"

  if _fpcup_build_fpclazup "$host" "$inst" "$src" "$log" "$SUDO"; then
    local newfpc="$inst/fpc/bin/$host-linux/fpc"
    if [ -x "$newfpc" ]; then
      FPC="$newfpc"; echo "   Using FPC=$FPC for this session (export it to make it permanent)."
    fi
    return 0
  fi

  echo "!! Automated fpclazup path unavailable — see $log. Falling back to the fpcupdeluxe GUI."
  _fpcup_launch_gui "$host" "$inst"
}

while true; do
  cat <<MENU

  WeKan-Lite build  (fpc: $FPC)
  1) Build for current platform
  2) Build for all platforms
  3) Select platform and build for it
  4) Install FPC cross-compilers via fpcupdeluxe (Ubuntu amd64/arm64)
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
