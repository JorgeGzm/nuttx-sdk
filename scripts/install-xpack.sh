#!/usr/bin/env bash
# Install extra tools that are NOT part of the NuttX CI toolchain set.
# (Toolchains themselves come from scripts/install-from-ci.sh, which runs
# the NuttX CI's own installer, keep versions in ONE place, upstream.)
#
# Currently: openocd-esp32 (JTAG debug for ESP32-family chips).
#
# Usage:
#   ./scripts/install-xpack.sh openocd
#   ./scripts/install-xpack.sh --list

set -euo pipefail

SDK_ROOT="${NUTTX_SDK_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"
TOOLCHAINS_DIR="$SDK_ROOT/toolchains"

err()  { printf '\033[1;31m[err]\033[0m  %s\n' "$*" >&2; }
info() { printf '\033[1;34m[*]\033[0m   %s\n' "$*"; }
ok()   { printf '\033[1;32m[ok]\033[0m  %s\n' "$*"; }
skip() { printf '\033[2m[skip]\033[0m %s\n' "$*"; }

# openocd-esp32 (Espressif GitHub releases)
# Includes ESP32-P4, C6, S3, S2, C3 targets + esp_usb_jtag driver (built-in JTAG).
OPENOCD_VER="v0.12.0-esp32-20251215"
OPENOCD_URL="https://github.com/espressif/openocd-esp32/releases/download/${OPENOCD_VER}/openocd-esp32-linux-amd64-0.12.0-esp32-20251215.tar.gz"
OPENOCD_PREFIX="openocd-esp32"
OPENOCD_DEST="openocd-esp32"

list_groups() {
  printf '\nAvailable extras:\n\n'
  printf '  \033[1m%-10s\033[0m openocd-esp32 %s, JTAG debug for all ESP32 chips  ~10 MB\n' "openocd" "$OPENOCD_VER"
  printf '\nInstalled to: %s/toolchains/<name>/\n\n' "$SDK_ROOT"
}

install_pkg() {
  local group="$1" url="$2" prefix="$3" dest_name="$4"
  local dest="$TOOLCHAINS_DIR/$dest_name"

  if [ -d "$dest" ]; then
    skip "$dest_name already installed ($dest)"
    return 0
  fi

  local archive
  archive="$(mktemp --suffix=".tar.gz")"
  # shellcheck disable=SC2064
  trap "rm -f '$archive'" RETURN

  info "downloading $group ($url)..."
  curl -L --progress-bar -o "$archive" "$url"

  info "extracting $group..."
  local tmpdir
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  tar -xf "$archive" -C "$tmpdir"

  mkdir -p "$TOOLCHAINS_DIR"
  mv "$tmpdir/$prefix" "$dest"
  ok "$dest_name installed → $dest"
}

if [ "${1:-}" = "--list" ] || [ "${1:-}" = "-l" ]; then
  list_groups; exit 0
fi

if [ $# -eq 0 ]; then
  list_groups; exit 2
fi

command -v curl >/dev/null 2>&1 || { err "curl is required"; exit 1; }
command -v tar  >/dev/null 2>&1 || { err "tar is required";  exit 1; }

for group in "$@"; do
  case "$group" in
    openocd) install_pkg openocd "$OPENOCD_URL" "$OPENOCD_PREFIX" "$OPENOCD_DEST" ;;
    *)       err "unknown extra: $group (run --list)"; exit 1 ;;
  esac
done
