#!/usr/bin/env bash
# Copy the VSCode template into a NuttX project, substituting SDK placeholders.
#
# Usage:
#   nx-init-project.sh [--arch arm|riscv|xtensa] [project-dir]
#
# --arch selects the default IntelliSense toolchain (default: arm).
#   arm    -> arm-none-eabi-gcc   (STM32, nRF, RP2040, ...)
#   riscv  -> riscv-none-elf-gcc  (ESP32-C/H/P4, CH32V, ...)
#   xtensa -> xtensa-esp32s3-elf-gcc (ESP32-S2/S3, ...)

set -euo pipefail

SDK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$SDK_ROOT/vscode-template/.vscode"

ARCH="arm"
TARGET_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --arch) ARCH="$2"; shift 2 ;;
    --arch=*) ARCH="${1#--arch=}"; shift ;;
    -*) echo "[err] unknown option: $1" >&2; exit 2 ;;
    *) TARGET_DIR="$1"; shift ;;
  esac
done
TARGET_DIR="${TARGET_DIR:-$PWD}"

if [ ! -d "$TARGET_DIR" ]; then
  echo "[err] target directory does not exist: $TARGET_DIR" >&2
  exit 1
fi

# Resolve toolchain compiler path and IntelliSense mode from arch
# SDK_OPENOCD/CFG are debug defaults, edit .vscode/settings.json
# (nuttxSdk.openocd / nuttxSdk.openocdCfg) for your board/probe.
SDK_OPENOCD="$SDK_ROOT/toolchains/openocd-esp32/bin/openocd"
SDK_OPENOCD_CFG=""
case "$ARCH" in
  arm)
    TOOLCHAIN_COMPILER="$SDK_ROOT/toolchains/gcc-arm-none-eabi/bin/arm-none-eabi-gcc"
    INTELLISENSE_MODE="linux-gcc-arm"
    TOOLCHAIN_SIZE="arm-none-eabi-size"
    TOOLCHAIN_GDB="$SDK_ROOT/toolchains/gcc-arm-none-eabi/bin/arm-none-eabi-gdb"
    ;;
  riscv)
    TOOLCHAIN_COMPILER="$SDK_ROOT/toolchains/riscv-none-elf-gcc/bin/riscv-none-elf-gcc"
    INTELLISENSE_MODE="linux-gcc-x64"
    TOOLCHAIN_SIZE="riscv-none-elf-size"
    TOOLCHAIN_GDB="$SDK_ROOT/toolchains/riscv-none-elf-gcc/bin/riscv-none-elf-gdb"
    SDK_OPENOCD_CFG="board/esp32c6-builtin.cfg"
    ;;
  xtensa)
    TOOLCHAIN_COMPILER="$SDK_ROOT/toolchains/xtensa-esp-elf/bin/xtensa-esp32s3-elf-gcc"
    INTELLISENSE_MODE="linux-gcc-x64"
    TOOLCHAIN_SIZE="xtensa-esp32s3-elf-size"
    # Espressif ships the Xtensa gdb separately (esp-gdb); falls back to the host gdb
    TOOLCHAIN_GDB="/usr/bin/gdb"
    SDK_OPENOCD_CFG="board/esp32s3-builtin.cfg"
    ;;
  *)
    echo "[err] unknown --arch '$ARCH'. Valid values: arm, riscv, xtensa" >&2
    exit 2
    ;;
esac

DEST="$TARGET_DIR/.vscode"
mkdir -p "$DEST"

for f in "$TEMPLATE"/*.json; do
  name="$(basename "$f")"
  out="$DEST/$name"
  if [ -e "$out" ]; then
    echo "[skip] $out already exists (delete it to regenerate)"
    continue
  fi
  sed \
    -e "s|__NUTTX_SDK_HOME__|$SDK_ROOT|g" \
    -e "s|__TOOLCHAIN_COMPILER__|$TOOLCHAIN_COMPILER|g" \
    -e "s|__INTELLISENSE_MODE__|$INTELLISENSE_MODE|g" \
    -e "s|__TOOLCHAIN_SIZE__|$TOOLCHAIN_SIZE|g" \
    -e "s|__TOOLCHAIN_GDB__|$TOOLCHAIN_GDB|g" \
    -e "s|__SDK_OPENOCD__|$SDK_OPENOCD|g" \
    -e "s|__SDK_OPENOCD_CFG__|$SDK_OPENOCD_CFG|g" \
    "$f" > "$out"
  echo "[ok]   $out"
done

cat <<EOF

Done. Open the project in VSCode:
  code "$TARGET_DIR"

Arch: $ARCH | Toolchain: $TOOLCHAIN_COMPILER
Any new integrated terminal will auto-source the NuttX SDK env.
EOF
