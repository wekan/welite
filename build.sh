#!/usr/bin/env bash
#
# WeKan-Lite build script — Linux / macOS / *BSD / Haiku shells.
# Cross-compiles src/wlhttp.lpr with FreePascal (fpc). See README.md / docs/static-assets.md.
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
BASEFLAGS="-O3 -Xs -Fusrc"
FPCFLAGS="${FPCFLAGS:-}"

# label | fpc -P (cpu) | fpc -T (os) | extra flags | output file
PLATFORMS=(
  "Linux amd64|x86_64|linux||wekanlite-linux-amd64"
  "Linux arm64|aarch64|linux||wekanlite-linux-arm64"
  "Linux armhf|arm|linux|-CaEABIHF -CfVFPV3|wekanlite-linux-armhf"
  "Linux armv7|arm|linux|-Cparmv7a -CfVFPV3 -CaEABIHF|wekanlite-linux-armv7"
  "Linux s390x|s390x|linux||wekanlite-linux-s390x"
  "Linux ppc|powerpc|linux||wekanlite-linux-ppc"
  "Linux ppc64le|powerpc64|linux|-Caelfv2|wekanlite-linux-ppc64le"
  "macOS arm64|aarch64|darwin||wekanlite-macos-arm64"
  "Windows x86|i386|win32||wekanlite-windows-x86.exe"
  "Windows amd64|x86_64|win64||wekanlite-windows-amd64.exe"
  "DOS|i386|go32v2||wekanlite-dos.exe"
  "Haiku|x86_64|haiku||wekanlite-haiku"
  "Amiga m68k|m68k|amiga||wekanlite-amiga-m68k"
  "AmigaOS 4.1 PPC|powerpc|amiga||wekanlite-amigaos4-ppc"
  "MorphOS|powerpc|morphos||wekanlite-morphos"
  "AROS x86|i386|aros||wekanlite-aros-x86"
  "AROS amd64|x86_64|aros||wekanlite-aros-amd64"
  "AROS arm64|aarch64|aros||wekanlite-aros-arm64"
  "AROS m68k|m68k|aros||wekanlite-aros-m68k"
  "AROS ppc|powerpc|aros||wekanlite-aros-ppc"
)

build_current() {
  mkdir -p "$OUTDIR"
  echo ">> Building for current platform"
  # shellcheck disable=SC2086
  "$FPC" $BASEFLAGS $FPCFLAGS -o"$OUTDIR/wekanlite" "$SRC"
}

build_platform() {  # $1 = a PLATFORMS entry
  local entry="$1" label cpu os flags out
  IFS='|' read -r label cpu os flags out <<< "$entry"
  mkdir -p "$OUTDIR"
  echo ">> Building $label  (-P$cpu -T$os $flags)"
  # shellcheck disable=SC2086
  "$FPC" $BASEFLAGS $FPCFLAGS -P"$cpu" -T"$os" $flags -o"$OUTDIR/$out" "$SRC"
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

while true; do
  cat <<MENU

  WeKan-Lite build  (fpc: $FPC)
  1) Build for current platform
  2) Build for all platforms
  3) Select platform and build for it
  4) Quit
MENU
  printf "  Choice: "
  read -r c || exit 0
  case "$c" in
    1) build_current ;;
    2) build_all ;;
    3) select_platform ;;
    4) exit 0 ;;
    *) echo "  Pick 1-4." ;;
  esac
done
