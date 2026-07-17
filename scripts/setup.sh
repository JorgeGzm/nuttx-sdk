#!/usr/bin/env bash
# NuttX SDK setup, toolchain installer front-end.
#
# DEFAULT: runs the NuttX CI's own installer functions
#          (nuttx/tools/ci/platforms/ubuntu.sh) with NUTTXTOOLS pointed at
#          this SDK, you get exactly the toolchain versions the NuttX tree
#          you build against pins in CI. No Docker needed.
#
# DOCKER:  use --docker to extract prebuilt toolchains from the official CI
#          image (ghcr.io/apache/nuttx/apache-nuttx-ci-linux) instead.
#          Same versions, no compiling (useful for rx/kconfig which
#          otherwise build from source), but pulls a ~6 GB image.
#
# Usage:
#   ./scripts/setup.sh                       # INTERACTIVE, pick groups from a menu
#   ./scripts/setup.sh riscv                 # e.g. GD32VW55x, ESP32-C6, K210
#   ./scripts/setup.sh arm riscv xtensa      # multiple groups
#   ./scripts/setup.sh --nuttx ~/nuttxspace/nuttx riscv   # pin to a tree
#   ./scripts/setup.sh --list                # show available groups
#   ./scripts/setup.sh --docker riscv        # extract from CI image
#   ./scripts/setup.sh openocd               # openocd-esp32 (JTAG debug, xPack-style dl)

set -euo pipefail

SDK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CI_INSTALLER="$SDK_ROOT/scripts/install-from-ci.sh"
XPACK_INSTALLER="$SDK_ROOT/scripts/install-xpack.sh"
DOCKER_EXTRACTOR="$SDK_ROOT/scripts/extract-toolchains.sh"

err()  { printf '\033[1;31m[err]\033[0m  %s\n' "$*" >&2; }
info() { printf '\033[1;34m[*]\033[0m   %s\n' "$*"; }
ok()   { printf '\033[1;32m[ok]\033[0m  %s\n' "$*"; }

usage() {
  cat <<EOF
NuttX SDK setup

Usage:
  $0                                   interactive menu (make menuconfig)
  $0 [--nuttx DIR] GROUP [GROUP ...]   install via the NuttX CI installer (default)
  $0 --list                            show available groups
  $0 --docker GROUP [GROUP ...]        extract from the NuttX CI Docker image (~6 GB)
  $0 openocd                           openocd-esp32 (ESP JTAG debug)
  $0 -h | --help                       this message

Toolchain versions are read from nuttx/tools/ci/platforms/ubuntu.sh of the
nuttx tree in use (--nuttx, \$NUTTX_BASE, ../nuttx or ~/nuttxspace/nuttx),
the same script NuttX CI runs inside Docker.

Examples:
  $0 riscv               # RISC-V: GD32VW55x, ESP32-C/H/P, CH32V, K210
  $0 arm riscv           # ARM + RISC-V
  $0 --docker riscv      # same versions, prebuilt (no compiling), needs Docker
EOF
}

# No args (or explicit 'menuconfig'): open the SDK menuconfig (kconfig UI).
if [ $# -eq 0 ]; then
  exec "$SDK_ROOT/scripts/sdk-menuconfig.sh"
fi

case "$1" in
  menuconfig|-m)
    exec "$SDK_ROOT/scripts/sdk-menuconfig.sh"
    ;;
  --list|-l)
    "$CI_INSTALLER" --list
    printf '\nExtra (not part of the CI toolchain set):\n\n'
    printf '  openocd   openocd-esp32, JTAG debug for ESP32 chips\n'
    printf '\n=== Docker / CI image extraction (--docker --list) ===\n'
    "$DOCKER_EXTRACTOR" --list
    exit 0
    ;;
  --docker)
    shift
    command -v docker >/dev/null 2>&1 || { err "docker not found"; exit 1; }
    docker info >/dev/null 2>&1        || { err "docker daemon not reachable"; exit 1; }
    info "using Docker / NuttX CI image"
    "$DOCKER_EXTRACTOR" "$@"
    ;;
  -h|--help)
    usage; exit 0
    ;;
  *)
    # Split off groups handled by other installers (openocd), pass the rest
    # to the CI-driven installer.
    CI_ARGS=()
    XPACK_ARGS=()
    while [ $# -gt 0 ]; do
      case "$1" in
        openocd) XPACK_ARGS+=("$1"); shift ;;
        *)       CI_ARGS+=("$1"); shift ;;
      esac
    done
    if [ ${#CI_ARGS[@]} -gt 0 ]; then
      command -v curl >/dev/null 2>&1 || { err "curl is required"; exit 1; }
      "$CI_INSTALLER" "${CI_ARGS[@]}"
    fi
    if [ ${#XPACK_ARGS[@]} -gt 0 ]; then
      "$XPACK_INSTALLER" "${XPACK_ARGS[@]}"
    fi
    ;;
esac

cat <<EOF

$(ok "Setup complete.")

Activate in current shell:
  source $SDK_ROOT/nuttx-env.sh

To activate automatically on every new terminal, add to ~/.bashrc:
  source $SDK_ROOT/nuttx-env.sh
EOF
