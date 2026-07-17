# shellcheck shell=bash
# get_nuttx.sh, defines the 'get_nuttx' command (opt-in activation of the NuttX SDK).
#
# Does NOT activate anything when sourced: it only DEFINES the function. Add to ~/.bashrc:
#
#   source /path/to/nuttx-sdk/get_nuttx.sh
#
# Then, in each terminal:
#   get_nuttx              activates the SDK only in this terminal (like 'get_idf' from ESP-IDF)
#   get_nuttx menuconfig   opens the toolchains menu and re-activates the environment
#   get_nuttx install ...  runs the installer (doctor + venv + repos + toolchains)

# SDK root = directory of this file (resolved on source).
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  __NUTTX_SDK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [ -n "${ZSH_VERSION:-}" ]; then
  __NUTTX_SDK_ROOT="$(cd "$(dirname "${(%):-%x}")" && pwd)"
fi
export __NUTTX_SDK_ROOT

get_nuttx() {
  local sdk="${__NUTTX_SDK_ROOT:?get_nuttx.sh was not sourced correctly}"
  case "${1:-}" in
    ""|activate)
      __nuttx_bashrc_done=1              # tells nuttx-env.sh that .bashrc already ran
      source "$sdk/nuttx-env.sh"
      ;;
    menuconfig|-m)
      # Graphical interface (ncurses) to select the toolchains to install.
      # Navigation: arrows move, Space toggles, Enter enters submenu,
      # Esc Esc exits and saves. On save, the selected groups are installed.
      if ! command -v kconfig-mconf >/dev/null 2>&1 \
         && ! python3 -c 'import menuconfig' >/dev/null 2>&1; then
        echo "get_nuttx: menuconfig needs a kconfig frontend." >&2
        echo "  install one:  sudo apt install kconfig-frontends   (kconfig-mconf)" >&2
        echo "          or:  pip3 install kconfiglib" >&2
        return 1
      fi
      if [ ! -t 0 ] || [ ! -t 1 ]; then
        echo "get_nuttx: menuconfig needs an interactive terminal (TTY)." >&2
        return 1
      fi
      # kconfig-mconf requires at least 80 columns x 19 lines.
      local __c __l
      __c="$(tput cols 2>/dev/null || echo 80)"
      __l="$(tput lines 2>/dev/null || echo 24)"
      if [ "${__c:-80}" -lt 80 ] || [ "${__l:-24}" -lt 19 ]; then
        echo "get_nuttx: menuconfig needs a terminal >= 80x19 (current: ${__c}x${__l})." >&2
        echo "  enlarge the window (or the VSCode terminal panel) and try again." >&2
        echo "  shortcut without menu:  $sdk/scripts/setup.sh <group>   (e.g.: xtensa)" >&2
        return 1
      fi
      if make -C "$sdk" menuconfig; then   # toolchains menu (install/remove)
        __nuttx_bashrc_done=1
        source "$sdk/nuttx-env.sh"         # re-activate: newly installed toolchain enters the PATH
      else
        echo "get_nuttx: menuconfig did not open (see the message above)." >&2
        return 1
      fi
      ;;
    install)
      "$sdk/scripts/nuttx-install.sh" "${@:2}"
      ;;
    -h|--help|help)
      echo "get_nuttx                 activates the NuttX SDK in this terminal"
      echo "get_nuttx menuconfig | -m opens the graphical toolchains menu and re-activates"
      echo "get_nuttx install ...     runs the installer (doctor + venv + repos + toolchains)"
      echo "get_nuttx help            this help"
      ;;
    *)
      echo "get_nuttx: unknown subcommand '$1' (use: get_nuttx help)" >&2
      return 2
      ;;
  esac
}
