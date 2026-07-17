#!/usr/bin/env bash
# nuttx-install, sets up (or updates) the complete NuttX environment, once.
#
# Role: this is the INSTALLER (equivalent to ESP-IDF's install.sh). Run once
# to prepare everything. To ACTIVATE the environment in your day-to-day
# terminal, use the alias 'get_nuttx' (= source nuttx-env.sh), like ESP-IDF's
# 'get_idf'.
#
# What it does, in this order, each step is IDEMPOTENT (whatever already
# exists is checked and skipped; running again = update, never reinstall):
#
#   1. doctor      checks host prerequisites (shows the exact apt install)
#   2. python-venv creates the SDK venv with NuttX's pip tools (esptool...)
#   3. repos       clones apache/nuttx + apache/nuttx-apps (or git pull if clean)
#   4. toolchains  if none installed, opens the SDK menuconfig
#   5. prints the next steps (starting with the simulator, no hardware)
#
# Usage (1st time, by full path, before activating anything):
#   ./scripts/nuttx-install.sh                 # everything (workspace: ~/nuttxspace)
#   ./scripts/nuttx-install.sh --workspace DIR # another workspace directory
#   ./scripts/nuttx-install.sh --shallow       # shallow clone (faster)
#   ./scripts/nuttx-install.sh --check         # doctor only, changes nothing
#
# Sanctioned upstream equivalent: nuttx/tools/ci/cibuild.sh -i -s -c
# (this script is the selective/quiet version of it, without the chicken-egg
# of needing the cloned tree to already exist).

set -euo pipefail

SDK_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
WORKSPACE="${NUTTX_WORKSPACE:-$HOME/nuttxspace}"
VENV_DIR="$SDK_ROOT/python-venv"
SHALLOW=0
CHECK_ONLY=0

err()  { printf '\033[1;31m[err]\033[0m  %s\n' "$*" >&2; }
info() { printf '\033[1;34m[*]\033[0m   %s\n' "$*"; }
ok()   { printf '\033[1;32m[ok]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m   %s\n' "$*"; }
step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --workspace)   WORKSPACE="$2"; shift 2 ;;
    --workspace=*) WORKSPACE="${1#--workspace=}"; shift ;;
    --shallow)     SHALLOW=1; shift ;;
    --check)       CHECK_ONLY=1; shift ;;
    -h|--help)     sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) err "unknown option: $1 (use --help)"; exit 2 ;;
  esac
done

# --- 1. Doctor ---------------------------------------------------------------
# command_to_test|apt_package|required(1)/optional(0)|what_it_is_for
DOCTOR_TABLE="\
git|git|1|clone nuttx/apps
curl|curl|1|download toolchains
make|make|1|build NuttX
gcc|gcc|1|build host tools and the simulator (sim:nsh)
g++|g++|1|build host tools
python3|python3|1|build scripts and esptool
bison|bison|1|kconfig parser
flex|flex|1|kconfig lexer
gperf|gperf|1|build NuttX tools
genromfs|genromfs|1|ROMFS images (several configs use them)
xxd|xxd|0|some configs embed binaries
kconfig-conf|kconfig-frontends|1|configure/build generate .config (required)
kconfig-mconf|kconfig-frontends|0|make menuconfig (graphical, for NuttX and the SDK)
picocom|picocom|0|serial monitor (board console)
qemu-system-riscv32|qemu-system-misc|0|run NuttX on QEMU without hardware"

doctor() {
  step "1/4 Checking host prerequisites"
  local missing_req=() missing_opt=() line cmd pkg req desc
  while IFS='|' read -r cmd pkg req desc; do
    if command -v "$cmd" >/dev/null 2>&1; then
      continue
    fi
    if [ "$req" = 1 ]; then missing_req+=("$pkg"); warn "missing $cmd ($desc)"
    else missing_opt+=("$pkg"); info "optional missing: $cmd ($desc)"; fi
  done <<< "$DOCTOR_TABLE"

  # python3-venv (the ensurepip module disappears when the package is not installed)
  if command -v python3 >/dev/null 2>&1 && ! python3 -c 'import ensurepip' >/dev/null 2>&1; then
    missing_req+=("python3-venv"); warn "missing python's venv module (python3-venv)"
  fi
  # ncurses header (to compile kconfig-frontends from the 'kconfig' group)
  if ! echo '#include <ncurses.h>' | gcc -E - >/dev/null 2>&1; then
    missing_opt+=("libncurses-dev"); info "optional missing: ncurses.h (to compile kconfig-frontends)"
  fi

  if [ ${#missing_req[@]} -gt 0 ]; then
    printf '\nInstall the prerequisites and run again:\n\n'
    printf '  sudo apt install %s\n\n' "${missing_req[*]} ${missing_opt[*]}"
    return 1
  fi
  if [ ${#missing_opt[@]} -gt 0 ]; then
    printf '\nOptional (recommended):  sudo apt install %s\n' "${missing_opt[*]}"
  fi
  ok "host ready"
}

# --- 2. SDK Python venv --------------------------------------------------------
# pip tools that the NuttX build/flash uses. Versions follow the python_tools()
# function from nuttx/tools/ci/platforms/ubuntu.sh (a dev subset, the CI also
# installs pytest/CodeChecker, which do not make sense here).
PIP_PKGS=(esptool==5.2.0 kconfiglib imgtool pyelftools "pyserial==3.5")

setup_venv() {
  step "2/4 SDK Python venv (isolated pip tools)"
  if [ -x "$VENV_DIR/bin/python3" ]; then
    ok "venv already exists: $VENV_DIR"
  else
    info "creating venv at $VENV_DIR"
    python3 -m venv "$VENV_DIR"
  fi
  local need=()
  local pkg name
  for pkg in "${PIP_PKGS[@]}"; do
    name="${pkg%%=*}"; name="${name%%<*}"; name="${name%%>*}"
    "$VENV_DIR/bin/python3" -m pip show "$name" >/dev/null 2>&1 || need+=("$pkg")
  done
  if [ ${#need[@]} -gt 0 ]; then
    info "installing: ${need[*]}"
    "$VENV_DIR/bin/python3" -m pip install --quiet --upgrade pip
    "$VENV_DIR/bin/python3" -m pip install --quiet "${need[@]}"
    ok "pip tools installed in the venv"
  else
    ok "pip tools already installed (nothing to do)"
  fi
}

# --- 3. Repositories ------------------------------------------------------------
clone_or_update() {
  local url="$1" dest="$2"
  if [ ! -d "$dest/.git" ]; then
    info "cloning $url"
    if [ "$SHALLOW" = 1 ]; then
      git clone --depth 1 "$url" "$dest"
    else
      git clone "$url" "$dest"
    fi
    return
  fi
  # Already exists: only update if it is clean and on the default branch,
  # never run over work in progress (port branches, WIP...).
  local branch default
  branch="$(git -C "$dest" branch --show-current)"
  default="$(git -C "$dest" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||')"
  if [ -n "$(git -C "$dest" status --porcelain)" ]; then
    warn "$dest has local changes, will not git pull (update it manually)"
  elif [ -n "$default" ] && [ "$branch" != "$default" ]; then
    warn "$dest is on branch '$branch' (not '$default'), will not git pull"
  else
    info "updating $dest (git pull)"
    git -C "$dest" pull --ff-only || warn "git pull failed, resolve it manually"
  fi
}

setup_repos() {
  step "3/4 NuttX workspace at $WORKSPACE"
  mkdir -p "$WORKSPACE"
  clone_or_update https://github.com/apache/nuttx.git      "$WORKSPACE/nuttx"
  clone_or_update https://github.com/apache/nuttx-apps.git "$WORKSPACE/apps"
  ok "workspace ready: $WORKSPACE/nuttx + $WORKSPACE/apps"
}

# --- 4. Toolchains ---------------------------------------------------------------
check_toolchains() {
  step "4/4 SDK toolchains"
  local have=()
  local d
  for d in "$SDK_ROOT"/toolchains/*/; do
    [ -d "$d" ] && have+=("$(basename "$d")")
  done
  if [ ${#have[@]} -gt 0 ]; then
    ok "installed: ${have[*]}"
    info "to add/remove:  make -C $SDK_ROOT menuconfig"
    return
  fi
  if [ -t 0 ] && [ -t 1 ]; then
    info "no toolchain installed, opening the SDK menuconfig..."
    make -C "$SDK_ROOT" menuconfig
  else
    warn "no toolchain installed. Run:  make -C $SDK_ROOT menuconfig"
  fi
}

# --- main ---------------------------------------------------------------------
if [ "$CHECK_ONLY" = 1 ]; then
  doctor
  exit $?
fi

doctor || exit 1
setup_venv
setup_repos
check_toolchains

cat <<EOF

$(ok "Installation complete!")

Activate the environment in THIS terminal (and in every terminal where you use NuttX):

  get_nuttx        # activates the toolchains only in this terminal (like 'get_idf')

If you have not set up the command yet, add it to ~/.bashrc (once):
  echo "source $SDK_ROOT/get_nuttx.sh" >> ~/.bashrc
  # then:  get_nuttx | get_nuttx menuconfig | get_nuttx help

Once activated, try it out (no board needed at all):
  cd $WORKSPACE/nuttx
  ./tools/configure.sh sim:nsh     # configures the NuttX simulator
  make -j\$(nproc)                  # builds
  ./nuttx                          # runs NuttX on your PC, nsh> prompt

With a board (examples):
  ./tools/configure.sh esp32-devkitc:nsh        # ESP32 (xtensa group)
  ./tools/configure.sh gd32vw553k-start:nsh     # GD32VW553 (riscv group)
  ./tools/configure.sh -L | less                # list all the options

Running 'nuttx-install' again only updates what changed, nothing is reinstalled.
EOF
