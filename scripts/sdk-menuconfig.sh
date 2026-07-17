#!/usr/bin/env bash
# NuttX SDK menuconfig, the SAME interface as NuttX's `make menuconfig`
# (kconfig-mconf) for choosing which toolchains to install.
#
# Flow:
#   1. Generates .sdkconfig marking [*] what is already in toolchains/
#   2. Opens the SDK Kconfig in kconfig-mconf (or kconfiglib as fallback)
#   3. On save and exit: installs what was marked (via install-from-ci.sh,
#      versions pinned by NuttX's CI) and offers to remove what was
#      unmarked.
#
# Called by `make menuconfig` (SDK Makefile) and by `setup.sh` with no args.

set -euo pipefail

SDK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KCONFIG_FILE="$SDK_ROOT/Kconfig"
CONFIG_FILE="$SDK_ROOT/.sdkconfig"

err()  { printf '\033[1;31m[err]\033[0m  %s\n' "$*" >&2; }
info() { printf '\033[1;34m[*]\033[0m   %s\n' "$*"; }
ok()   { printf '\033[1;32m[ok]\033[0m  %s\n' "$*"; }

# --- Registry: Kconfig symbol | installer group | dir in toolchains/ ---
# The "group" is the argument to install-from-ci.sh (or install-xpack.sh for
# openocd). The dir marks presence (initial [*]) and is the removal target.
REGISTRY="\
SDK_ARM|arm|gcc-arm-none-eabi
SDK_ARMCLANG|armclang|clang-arm-none-eabi
SDK_ARM64|arm64|gcc-aarch64-none-elf
SDK_RISCV|riscv|riscv-none-elf-gcc
SDK_XTENSA|xtensa|xtensa-esp-elf
SDK_MIPS|mips|pinguino-compilers
SDK_SPARC|sparc|sparc-gaisler-elf-gcc
SDK_RX|rx|renesas-toolchain
SDK_WASI|wasi|wasi-sdk
SDK_PICO|pico|pico-sdk
SDK_OPENOCD_ESP32|openocd|openocd-esp32"

installed() { [ -d "$SDK_ROOT/toolchains/$1" ]; }

# --- 1. Seed the .sdkconfig with the current state --------------------------
seed_config() {
  : > "$CONFIG_FILE"
  local sym group dir
  while IFS='|' read -r sym group dir; do
    if installed "$dir"; then
      echo "CONFIG_${sym}=y" >> "$CONFIG_FILE"
    else
      echo "# CONFIG_${sym} is not set" >> "$CONFIG_FILE"
    fi
  done <<< "$REGISTRY"
}

# --- 2. Frontend: same look as NuttX ----------------------------------------
# kconfig-mconf requires a terminal >= 80x19. Check first and give a friendly
# hint + the command-line shortcut (which works at any size).
check_term_size() {
  [ -t 1 ] || return 0   # no TTY (pipe/CI): let the frontend decide
  local c l
  c="$(tput cols 2>/dev/null || echo 80)"
  l="$(tput lines 2>/dev/null || echo 24)"
  if [ "${c:-80}" -lt 80 ] || [ "${l:-24}" -lt 19 ]; then
    err "menuconfig needs a terminal >= 80x19 (current: ${c}x${l})."
    err "enlarge the window (or the VSCode terminal panel) and try again."
    err "without menu (works at any size):"
    err "  $SDK_ROOT/scripts/setup.sh <group>     (e.g.: arm riscv xtensa)"
    err "  $SDK_ROOT/scripts/setup.sh --list      (lists the groups)"
    exit 1
  fi
}

run_menuconfig() {
  cd "$SDK_ROOT"
  # SDK version shown in the menu title (read from the VERSION file).
  NUTTX_SDK_VERSION="$(cat "$SDK_ROOT/VERSION" 2>/dev/null || echo '?')"
  export NUTTX_SDK_VERSION
  if command -v kconfig-mconf >/dev/null 2>&1; then
    check_term_size
    KCONFIG_CONFIG="$CONFIG_FILE" kconfig-mconf "$KCONFIG_FILE"
  elif python3 -c 'import menuconfig' >/dev/null 2>&1; then
    check_term_size
    KCONFIG_CONFIG="$CONFIG_FILE" python3 -m menuconfig "$KCONFIG_FILE"
  else
    err "no menuconfig frontend found."
    err "install one:  sudo apt install kconfig-frontends   (kconfig-mconf)"
    err "         or:  pip3 install kconfiglib              (python)"
    exit 1
  fi
}

selected() { grep -q "^CONFIG_${1}=y" "$CONFIG_FILE"; }

# --- 3. Apply: install the marked, offer to remove the unmarked -------------
apply_config() {
  local sym group dir
  local -a to_install=() to_remove=()

  while IFS='|' read -r sym group dir; do
    if selected "$sym" && ! installed "$dir"; then
      to_install+=("$group")
    elif ! selected "$sym" && installed "$dir"; then
      to_remove+=("$group:$dir")
    fi
  done <<< "$REGISTRY"

  if [ ${#to_install[@]} -eq 0 ] && [ ${#to_remove[@]} -eq 0 ]; then
    ok "nothing to do, selection already matches what is installed."
    return 0
  fi

  # Install
  if [ ${#to_install[@]} -gt 0 ]; then
    info "installing: ${to_install[*]}"
    local -a ci_groups=() xpack_groups=()
    local g
    for g in "${to_install[@]}"; do
      case "$g" in
        openocd) xpack_groups+=("$g") ;;
        *)       ci_groups+=("$g") ;;
      esac
    done
    [ ${#ci_groups[@]} -gt 0 ]    && "$SDK_ROOT/scripts/install-from-ci.sh" "${ci_groups[@]}"
    [ ${#xpack_groups[@]} -gt 0 ] && "$SDK_ROOT/scripts/install-xpack.sh" "${xpack_groups[@]}"
  fi

  # Remove (always asks, never removes on its own)
  if [ ${#to_remove[@]} -gt 0 ]; then
    local entry
    printf '\nUnmarked but installed:\n'
    for entry in "${to_remove[@]}"; do
      printf '  - %-10s (toolchains/%s)\n' "${entry%%:*}" "${entry##*:}"
    done
    printf 'Remove from disk? [y/N] '
    local ans=""
    read -r ans || true
    if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
      for entry in "${to_remove[@]}"; do
        rm -rf "$SDK_ROOT/toolchains/${entry##*:}"
        ok "removed: toolchains/${entry##*:}"
      done
    else
      info "kept (unmark was ignored)."
    fi
  fi

  printf '\n'
  ok "done. Activate this terminal with:  get_nuttx"
  echo "      (or: source $SDK_ROOT/nuttx-env.sh)"
}

# --- main --------------------------------------------------------------------
[ -f "$KCONFIG_FILE" ] || { err "Kconfig not found in $SDK_ROOT"; exit 1; }

seed_config
run_menuconfig
apply_config
