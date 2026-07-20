#!/usr/bin/env bash
# Install toolchains by running the NuttX CI's own installer functions
# (nuttx/tools/ci/platforms/ubuntu.sh) with NUTTXTOOLS pointed at the SDK.
#
# This is the whole point of the SDK: the versions installed are EXACTLY the
# versions pinned by the NuttX tree you build against, no version list is
# duplicated here. When upstream bumps a toolchain, re-run this against the
# updated tree and you get the new pinned version.
#
# Usage:
#   ./scripts/install-from-ci.sh [--nuttx DIR] GROUP [GROUP ...]
#   ./scripts/install-from-ci.sh --list
#
# The nuttx tree is located via --nuttx, $NUTTX_BASE, ../nuttx (next to the
# SDK), or ~/nuttxspace/nuttx. If none exists, the CI script is fetched from
# GitHub (master) as a fallback.

set -euo pipefail

SDK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export NUTTXTOOLS="$SDK_ROOT/toolchains"
CI_SCRIPT_REL="tools/ci/platforms/ubuntu.sh"
CI_SCRIPT_URL="https://raw.githubusercontent.com/apache/nuttx/master/$CI_SCRIPT_REL"

err()  { printf '\033[1;31m[err]\033[0m  %s\n' "$*" >&2; }
info() { printf '\033[1;34m[*]\033[0m   %s\n' "$*"; }
ok()   { printf '\033[1;32m[ok]\033[0m  %s\n' "$*"; }

# --- group -> CI function map ----------------------------------------------
# Only groups that install into NUTTXTOOLS (no sudo/apt) are exposed.
# avr/rust/dlang/binutils etc. come from the distro, same as CI, which also
# apt-installs those; see README.
ci_func_for() {
  case "$1" in
    arm)      echo arm_gcc_toolchain ;;
    armclang) echo arm_clang_toolchain ;;
    arm64)    echo arm64_gcc_toolchain ;;
    riscv)    echo riscv_gcc_toolchain ;;
    xtensa)   echo xtensa_esp_gcc_toolchain ;;
    mips)     echo mips_gcc_toolchain ;;
    sparc)    echo sparc_gcc_toolchain ;;
    rx)       echo rx_gcc_toolchain ;;
    wasi)     echo wasi_sdk ;;
    pico)     echo raspberrypi_pico_sdk ;;
    kconfig)  echo kconfig_frontends ;;
    *)        echo "" ;;
  esac
}

GROUPS_ALL="arm armclang arm64 riscv xtensa mips sparc rx wasi pico kconfig"

list_groups() {
  cat <<EOF

Groups (each maps to a function in nuttx/$CI_SCRIPT_REL):

  arm       arm_gcc_toolchain         arm-none-eabi-gcc (ARM release)
  armclang  arm_clang_toolchain       LLVM-embedded (ARM)
  arm64     arm64_gcc_toolchain       aarch64-none-elf-gcc
  riscv     riscv_gcc_toolchain       riscv-none-elf-gcc (xPack), GD32VW55x, ESP32-C/H/P, K210…
  xtensa    xtensa_esp_gcc_toolchain  xtensa-esp32/s2/s3-elf-gcc (Espressif)
  mips      mips_gcc_toolchain        p32-gcc (Pinguino)
  sparc     sparc_gcc_toolchain       sparc-gaisler-elf-gcc (BCC)
  rx        rx_gcc_toolchain          rx-elf-gcc (BUILDS FROM SOURCE, slow)
  wasi      wasi_sdk                  WASI-SDK + wamrc
  pico      raspberrypi_pico_sdk      Raspberry Pi pico-sdk
  kconfig   kconfig_frontends         kconfig-conf/mconf (builds from source)

  all       everything above

Versions come from the nuttx tree in use, run with --nuttx to pick one.
Installed into: $NUTTXTOOLS/
EOF
}

# --- locate the CI script ---------------------------------------------------
NUTTX_DIR=""
find_ci_script() {
  local cand
  for cand in "${NUTTX_DIR:-}" "${NUTTX_BASE:-}" "$SDK_ROOT/../nuttx" "$HOME/nuttxspace/nuttx"; do
    [ -n "$cand" ] && [ -f "$cand/$CI_SCRIPT_REL" ] || continue
    echo "$cand/$CI_SCRIPT_REL"
    return 0
  done
  return 1
}

# --- main --------------------------------------------------------------------
GROUPS_SEL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --list|-l) list_groups; exit 0 ;;
    --nuttx)   NUTTX_DIR="$2"; shift 2 ;;
    --nuttx=*) NUTTX_DIR="${1#--nuttx=}"; shift ;;
    all)       read -r -a GROUPS_SEL <<< "$GROUPS_ALL"; shift ;;
    -*)        err "unknown option: $1"; exit 2 ;;
    *)         GROUPS_SEL+=("$1"); shift ;;
  esac
done

if [ ${#GROUPS_SEL[@]} -eq 0 ]; then
  err "no groups given (try --list)"; exit 2
fi

for g in "${GROUPS_SEL[@]}"; do
  if [ -z "$(ci_func_for "$g")" ]; then
    err "unknown group '$g' (try --list)"; exit 2
  fi
done

if CI_SCRIPT="$(find_ci_script)"; then
  info "CI script: $CI_SCRIPT"
else
  CI_SCRIPT="$(mktemp --suffix=-ubuntu.sh)"
  info "no local nuttx tree found, fetching $CI_SCRIPT_URL"
  curl -fsSL -o "$CI_SCRIPT" "$CI_SCRIPT_URL"
fi

# Source the CI script with its top-level side effects neutralized:
#  - drop the bare `install_build_tools` call at the bottom (installs ALL)
#  - drop `set -o xtrace` / `set -e` (we manage our own error handling)
CI_FUNCS="$(mktemp --suffix=-ci-funcs.sh)"
trap 'rm -f "$CI_FUNCS"' EXIT
grep -vx 'install_build_tools' "$CI_SCRIPT" \
  | grep -vx 'set -e' | grep -vx 'set -o xtrace' > "$CI_FUNCS"

# shellcheck disable=SC1090
. "$CI_FUNCS"

mkdir -p "$NUTTXTOOLS"
[ -f "$NUTTXTOOLS/env.sh" ] || echo "#!/usr/bin/env sh" > "$NUTTXTOOLS/env.sh"

# Run one install function with a live spinner. The CI functions download
# (curl -s) and extract (xz/tar) silently and a toolchain can be ~1.5 GB, so
# without feedback it looks frozen. Output goes to a log; on failure we show it.
run_group() {
  local g="$1" func="$2" log
  log="$(mktemp)"
  ( set -e; "$func" ) >"$log" 2>&1 &
  local pid=$! secs=0 i=0
  local frames='|/-\'
  if [ -t 1 ]; then
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r\033[K\033[1;34m[*]\033[0m   installing %-8s %s  %ds (downloading + extracting, please wait)' \
        "$g" "${frames:$((i%4)):1}" "$secs"
      sleep 1; secs=$((secs+1)); i=$((i+1))
    done
    printf '\r\033[K'
  fi
  if wait "$pid"; then
    ok "group '$g' done (${secs}s)"
    rm -f "$log"
    return 0
  else
    err "group '$g' failed after ${secs}s:"
    tail -25 "$log" >&2
    rm -f "$log"
    return 1
  fi
}

rc=0
for g in "${GROUPS_SEL[@]}"; do
  func="$(ci_func_for "$g")"
  if ! type "$func" >/dev/null 2>&1; then
    err "CI script has no function '$func', group '$g' not available in this nuttx tree"
    rc=1; continue
  fi
  info "installing group '$g' ($func)…"
  run_group "$g" "$func" || rc=1
done

printf '\n'
if [ "$rc" -eq 0 ]; then
  ok "Toolchains in $NUTTXTOOLS (versions pinned by ${CI_SCRIPT})"
  printf '      Activate with:  get_nuttx  (or: source %s/nuttx-env.sh)\n\n' "$SDK_ROOT"
else
  err "one or more groups failed (see above)."
fi
exit "$rc"
