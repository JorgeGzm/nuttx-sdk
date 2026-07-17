#!/usr/bin/env bash
# Extract NuttX toolchains from the official CI Docker image.
# Mirrors the COPY --from=... directives in tools/ci/docker/linux/Dockerfile
# of apache/nuttx, so the resulting layout matches what the CI validates.
#
# Usage: extract-toolchains.sh GROUP [GROUP ...]
# Use scripts/setup.sh for the friendly CLI; this script is the worker.

set -euo pipefail

IMAGE="${NUTTX_CI_IMAGE:-ghcr.io/apache/nuttx/apache-nuttx-ci-linux:latest}"
SDK_ROOT="${NUTTX_SDK_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"
CONTAINER="nuttx-sdk-extract-$$"

# --- Group definitions ----------------------------------------------------
# Each entry: src-in-container:dest-relative-to-SDK_ROOT [more...]
declare -A GROUP_PATHS=(
  [arm]="/tools/gcc-arm-none-eabi:toolchains/gcc-arm-none-eabi /tools/clang-arm-none-eabi:toolchains/clang-arm-none-eabi"
  [arm64]="/tools/gcc-aarch64-none-elf:toolchains/gcc-aarch64-none-elf"
  [riscv]="/tools/riscv-none-elf-gcc:toolchains/riscv-none-elf-gcc"
  [xtensa]="/tools/xtensa-esp-elf-gcc:toolchains/xtensa-esp-elf-gcc /tools/blobs:tools/blobs"
  [blobs]="/tools/blobs:tools/blobs"
  [avr32]="/tools/gcc-avr32-gnu:toolchains/gcc-avr32-gnu"
  [mips]="/tools/pinguino-compilers:toolchains/pinguino-compilers"
  [renesas]="/tools/renesas-toolchain:toolchains/renesas-toolchain"
  [sparc]="/tools/sparc-gaisler-elf-gcc:toolchains/sparc-gaisler-elf-gcc"
  [wasm]="/tools/wasi-sdk:toolchains/wasi-sdk"
  [pico]="/tools/pico-sdk:tools/pico-sdk /tools/picotool:tools/picotool"

  [kconfig]="/tools/kconfig-frontends:tools/kconfig-frontends"

  [rust]="/tools/rust:tools/rust"
  [zig]="/tools/zig:tools/zig"
  [d]="/tools/ldc2:tools/ldc2"

  [gn]="/tools/gn:tools/gn"
  [zap]="/tools/zap:tools/zap /tools/zap_release:tools/zap_release"
)

declare -A GROUP_DESC=(
  [arm]="ARM Cortex-M (gcc + LLVM-embedded). STM32/nRF/RP2040/SAMD/etc.   ~700 MB"
  [arm64]="ARM64 (aarch64-none-elf). RPi3/4, Allwinner A64, etc.           ~250 MB"
  [riscv]="RISC-V (riscv-none-elf). CH32V, K210, BL602, ESP32-C/H/P4.     ~600 MB"
  [xtensa]="Xtensa (ESP32, ESP32-S2, ESP32-S3) + ESP bootloader blobs.      ~300 MB"
  [blobs]="ESP bootloader/ROM blobs only (mcuboot, elf2image, etc).        ~100 MB"
  [avr32]="AVR32 GCC (Atmel UC3).                                          ~150 MB"
  [mips]="MIPS Pinguino (PIC32).                                          ~100 MB"
  [renesas]="Renesas RX-elf (RX MCUs).                                       ~250 MB"
  [sparc]="SPARC (Gaisler LEON3/4).                                        ~150 MB"
  [wasm]="WASI-SDK (WebAssembly via clang).                                ~300 MB"
  [pico]="Raspberry Pi pico-sdk + picotool.                                ~50 MB"
  [kconfig]="kconfig-frontends (kconfig-mconf for menuconfig).               ~5 MB"
  [rust]="Rust toolchain + thumbv6m/thumbv7m/riscv64 targets.              ~500 MB"
  [zig]="Zig 0.13.                                                        ~150 MB"
  [d]="LDC2 1.39 (D language).                                           ~150 MB"
  [gn]="Google gn build tool (Matter builds).                             ~10 MB"
  [zap]="ZAP (Zigbee/Matter cluster generator).                           ~200 MB"
)

# Aliases / meta-groups
declare -A META=(
  [all]="arm arm64 riscv xtensa blobs avr32 mips renesas sparc wasm pico kconfig rust zig d gn zap"
  [common]="arm riscv xtensa kconfig"
  [minimal]="arm kconfig"
  [esp]="xtensa riscv blobs kconfig"
  [esp32p4]="riscv blobs kconfig"
  [embedded]="arm arm64 riscv xtensa blobs kconfig"
  [languages]="rust zig d"
  [matter]="gn zap"
)

err()  { printf '\033[1;31m[err]\033[0m  %s\n' "$*" >&2; }
info() { printf '\033[1;34m[*]\033[0m   %s\n' "$*"; }
ok()   { printf '\033[1;32m[ok]\033[0m  %s\n' "$*"; }
skip() { printf '\033[2m[skip]\033[0m %s\n' "$*"; }

list_groups() {
  echo "Toolchain groups:"
  echo
  for g in arm arm64 riscv xtensa avr32 mips renesas sparc wasm pico; do
    printf '  \033[1m%-10s\033[0m %s\n' "$g" "${GROUP_DESC[$g]}"
  done
  echo
  echo "Build / config tools:"
  for g in kconfig; do
    printf '  \033[1m%-10s\033[0m %s\n' "$g" "${GROUP_DESC[$g]}"
  done
  echo
  echo "Language ecosystems:"
  for g in rust zig d; do
    printf '  \033[1m%-10s\033[0m %s\n' "$g" "${GROUP_DESC[$g]}"
  done
  echo
  echo "Specialty (rare):"
  for g in gn zap; do
    printf '  \033[1m%-10s\033[0m %s\n' "$g" "${GROUP_DESC[$g]}"
  done
  echo
  echo "Meta-aliases:"
  for m in all common minimal esp esp32p4 embedded languages matter; do
    printf '  \033[1m%-10s\033[0m = %s\n' "$m" "${META[$m]}"
  done
}

resolve_groups() {
  # Expand meta-aliases recursively, dedupe.
  local input=("$@")
  declare -A seen=()
  local resolved=()
  for g in "${input[@]}"; do
    if [ -n "${META[$g]:-}" ]; then
      # shellcheck disable=SC2206
      local sub=(${META[$g]})
      for s in "${sub[@]}"; do
        if [ -z "${seen[$s]:-}" ]; then
          seen[$s]=1
          resolved+=("$s")
        fi
      done
    elif [ -n "${GROUP_PATHS[$g]:-}" ]; then
      if [ -z "${seen[$g]:-}" ]; then
        seen[$g]=1
        resolved+=("$g")
      fi
    else
      err "unknown group: $g (run --list to see available)"
      return 1
    fi
  done
  echo "${resolved[@]}"
}

# --- Argument handling ----------------------------------------------------
if [ "${1:-}" = "--list" ] || [ "${1:-}" = "-l" ]; then
  list_groups
  exit 0
fi

if [ $# -eq 0 ]; then
  err "no groups requested. Run with --list to see options or pass groups e.g.: arm riscv"
  exit 2
fi

GROUPS=()
read -ra GROUPS <<< "$(resolve_groups "$@")"

# --- Sanity ---------------------------------------------------------------
command -v docker >/dev/null 2>&1 || { err "docker not in PATH"; exit 1; }
docker info >/dev/null 2>&1 || { err "docker daemon not reachable"; exit 1; }

info "SDK root:    $SDK_ROOT"
info "Image:       $IMAGE"
info "Groups:      ${GROUPS[*]}"

# --- Pull image if needed -------------------------------------------------
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  info "image not local, pulling (this can take several GB)..."
  docker pull "$IMAGE"
fi

# --- Create extraction container ------------------------------------------
cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

info "creating extraction container..."
docker create --name "$CONTAINER" "$IMAGE" /bin/true >/dev/null

# --- Extract ---------------------------------------------------------------
for g in "${GROUPS[@]}"; do
  info "group: $g"
  # shellcheck disable=SC2206
  pairs=(${GROUP_PATHS[$g]})
  for spec in "${pairs[@]}"; do
    src="${spec%%:*}"
    rel="${spec##*:}"
    dst="$SDK_ROOT/$rel"

    if [ -d "$dst" ]; then
      skip "$rel already exists"
      continue
    fi
    parent="$(dirname "$dst")"
    mkdir -p "$parent"
    if docker cp "$CONTAINER:$src" "$parent/" 2>&1; then
      ok "$src -> $rel"
    else
      err "$src not found in image (skipping)"
    fi
  done
done

# --- Summary --------------------------------------------------------------
info "extraction complete"
du -sh "$SDK_ROOT"/{toolchains,tools} 2>/dev/null || true
