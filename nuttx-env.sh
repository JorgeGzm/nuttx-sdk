# shellcheck shell=bash
# NuttX SDK environment.
#
# Usage:
#   source nuttx-env.sh                 # activate in current shell
#   source nuttx-env.sh /path/to/nuttx  # also set NUTTX_BASE / NUTTX_APPS
#
# Re-source-able. Designed to be safely sourced from VSCode integrated
# terminals via terminal.integrated.profiles.linux.

# --- Preserve the user's shell setup --------------------------------------
# When launched as `bash --rcfile nuttx-env.sh` (VSCode terminal profile),
# bash reads THIS file INSTEAD of ~/.bashrc, which would drop the user's
# colored prompt, aliases and LS_COLORS.  Source ~/.bashrc first so the
# normal shell experience is kept; the guard prevents recursion.
if [ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ] \
   && [ -z "${__nuttx_bashrc_done:-}" ]; then
  __nuttx_bashrc_done=1
  # shellcheck disable=SC1091
  source "$HOME/.bashrc"
fi

# --- Resolve SDK root (works whether sourced or executed) -----------------
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  __nuttx_env_src="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
  __nuttx_env_src="${(%):-%x}"
else
  __nuttx_env_src="$0"
fi
NUTTX_SDK_HOME="$(cd "$(dirname "$__nuttx_env_src")" && pwd)"
export NUTTX_SDK_HOME
unset __nuttx_env_src

# --- Optional: locate nuttx + apps source trees ---------------------------
# Pass an explicit path, or let it auto-detect ../nuttx and ../apps next to
# the SDK directory.
__nuttx_arg="${1:-}"
if [ -n "$__nuttx_arg" ] && [ -d "$__nuttx_arg" ]; then
  export NUTTX_BASE="$(cd "$__nuttx_arg" && pwd)"
elif [ -d "$NUTTX_SDK_HOME/../nuttx" ]; then
  export NUTTX_BASE="$(cd "$NUTTX_SDK_HOME/../nuttx" && pwd)"
fi

if [ -n "${NUTTX_BASE:-}" ]; then
  if [ -d "$NUTTX_BASE/../apps" ]; then
    export NUTTX_APPS="$(cd "$NUTTX_BASE/../apps" && pwd)"
  fi
fi
unset __nuttx_arg

# --- PATH helper: prepend without duplicates ------------------------------
__nuttx_prepend_path() {
  local d="$1"
  [ -d "$d" ] || return 0
  case ":$PATH:" in
    *":$d:"*) ;;
    *) PATH="$d:$PATH" ;;
  esac
}

# --- SDK commands (nuttx-install, ...) ----------------------------------------
__nuttx_prepend_path "$NUTTX_SDK_HOME/bin"

# --- SDK Python venv (esptool, kconfiglib, imgtool...) --------------------
# Created by nuttx-install. Goes on PATH BEFORE the system esptool lookup below.
__nuttx_prepend_path "$NUTTX_SDK_HOME/python-venv/bin"

# --- Toolchains (SDK-installed) -------------------------------------------
# Directory names follow nuttx/tools/ci/platforms/ubuntu.sh ($NUTTXTOOLS
# layout), the same names the NuttX CI uses inside Docker.
__nuttx_prepend_path "$NUTTX_SDK_HOME/toolchains/clang-arm-none-eabi/bin"
__nuttx_prepend_path "$NUTTX_SDK_HOME/toolchains/gcc-arm-none-eabi/bin"
__nuttx_prepend_path "$NUTTX_SDK_HOME/toolchains/gcc-aarch64-none-elf/bin"
__nuttx_prepend_path "$NUTTX_SDK_HOME/toolchains/gcc-avr32-gnu/bin"
__nuttx_prepend_path "$NUTTX_SDK_HOME/toolchains/pinguino-compilers/p32/bin"
__nuttx_prepend_path "$NUTTX_SDK_HOME/toolchains/renesas-toolchain/rx-elf-gcc/bin"
__nuttx_prepend_path "$NUTTX_SDK_HOME/toolchains/riscv-none-elf-gcc/bin"
__nuttx_prepend_path "$NUTTX_SDK_HOME/toolchains/sparc-gaisler-elf-gcc/bin"
__nuttx_prepend_path "$NUTTX_SDK_HOME/toolchains/xtensa-esp-elf/bin"
__nuttx_prepend_path "$NUTTX_SDK_HOME/toolchains/xtensa-esp-elf-gcc/bin"
__nuttx_prepend_path "$NUTTX_SDK_HOME/toolchains/openocd-esp32/bin"

# --- Build / config tooling -----------------------------------------------
# CI installer puts these under toolchains/ (NUTTXTOOLS); the Docker
# extractor historically used tools/, accept both.
for __nuttx_base in "$NUTTX_SDK_HOME/toolchains" "$NUTTX_SDK_HOME/tools"; do
  __nuttx_prepend_path "$__nuttx_base/kconfig-frontends/bin"
  __nuttx_prepend_path "$__nuttx_base/wamrc"
done
unset __nuttx_base
__nuttx_prepend_path "$NUTTX_SDK_HOME/tools/gn"
__nuttx_prepend_path "$NUTTX_SDK_HOME/tools/picotool"

# --- Languages ------------------------------------------------------------
if [ -d "$NUTTX_SDK_HOME/tools/rust" ]; then
  export RUST_HOME="$NUTTX_SDK_HOME/tools/rust"
  export CARGO_HOME="$RUST_HOME/cargo"
  export RUSTUP_HOME="$RUST_HOME/rustup"
  __nuttx_prepend_path "$CARGO_HOME/bin"
fi

if [ -d "$NUTTX_SDK_HOME/tools/zig/0.13.0/files" ]; then
  __nuttx_prepend_path "$NUTTX_SDK_HOME/tools/zig/0.13.0/files"
fi

if [ -d "$NUTTX_SDK_HOME/tools/ldc2/ldc2-1.39.0-linux-x86_64/bin" ]; then
  __nuttx_prepend_path "$NUTTX_SDK_HOME/tools/ldc2/ldc2-1.39.0-linux-x86_64/bin"
fi

# --- Vendor SDKs ----------------------------------------------------------
if [ -d "$NUTTX_SDK_HOME/toolchains/wasi-sdk" ]; then
  export WASI_SDK_PATH="$NUTTX_SDK_HOME/toolchains/wasi-sdk"
fi

if [ -d "$NUTTX_SDK_HOME/toolchains/pico-sdk" ]; then
  export PICO_SDK_PATH="$NUTTX_SDK_HOME/toolchains/pico-sdk"
elif [ -d "$NUTTX_SDK_HOME/tools/pico-sdk" ]; then
  export PICO_SDK_PATH="$NUTTX_SDK_HOME/tools/pico-sdk"
fi

if [ -d "$NUTTX_SDK_HOME/tools/blobs" ]; then
  export BLOBDIR="$NUTTX_SDK_HOME/tools/blobs/esp-bins"
  [ -d "$NUTTX_SDK_HOME/tools/blobs/esp-bins" ] || export BLOBDIR="$NUTTX_SDK_HOME/tools/blobs"
fi

if [ -d "$NUTTX_SDK_HOME/tools/zap" ]; then
  export ZAP_DEVELOPMENT_PATH="$NUTTX_SDK_HOME/tools/zap"
fi
if [ -d "$NUTTX_SDK_HOME/tools/zap_release" ]; then
  export ZAP_INSTALL_PATH="$NUTTX_SDK_HOME/tools/zap_release"
fi

# --- ESP tooling (esptool, idf_monitor) auto-detection -------------------
# Looks for esptool.py in pip user install or Espressif python venv.
# Needed by NuttX Makefiles for ESP32 elf2image/flash steps.
if ! command -v esptool.py >/dev/null 2>&1; then
  # pip install --user esptool
  __nuttx_prepend_path "$HOME/.local/bin"

  # Espressif python venv (created by esp-idf install.sh).
  # Pick the newest idf5.x_py3.x_env that has esptool.py.
  if [ -d "$HOME/.espressif/python_env" ]; then
    for __nuttx_pyenv in $(ls -1d "$HOME/.espressif/python_env"/idf5.*_env 2>/dev/null | sort -rV); do
      if [ -x "$__nuttx_pyenv/bin/esptool.py" ]; then
        __nuttx_prepend_path "$__nuttx_pyenv/bin"
        break
      fi
    done
    unset __nuttx_pyenv
  fi
fi

# --- ccache (optional, only if user has it installed) ---------------------
if command -v ccache >/dev/null 2>&1; then
  export CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache}"
fi

export PATH
unset -f __nuttx_prepend_path

# --- Status banner --------------------------------------------------------
if [ -t 1 ] && [ -z "${NUTTX_ENV_QUIET:-}" ]; then
  __nuttx_ver=""
  [ -f "$NUTTX_SDK_HOME/VERSION" ] && __nuttx_ver="$(cat "$NUTTX_SDK_HOME/VERSION" 2>/dev/null)"
  printf '\033[1;32m[nuttx-sdk %s]\033[0m active (NUTTX_SDK_HOME=%s)\n' "$__nuttx_ver" "$NUTTX_SDK_HOME"
  if [ -n "${NUTTX_BASE:-}" ]; then
    printf '            NUTTX_BASE=%s\n' "$NUTTX_BASE"
  fi
  unset __nuttx_ver
fi
