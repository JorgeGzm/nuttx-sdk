# NuttX SDK - make front-end, in the spirit of NuttX:
#
#   make menuconfig   kconfig interface (same as NuttX) to install toolchains
#   make list         lists the available groups and versions
#   make env          shows how to activate the environment

SDK_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

.PHONY: menuconfig list env help

help:
	@echo "NuttX SDK"
	@echo ""
	@echo "  ./scripts/nuttx-install.sh   install/update the environment (once, like ESP-IDF's install.sh)"
	@echo "  get_nuttx (alias)            activate the environment in THIS terminal (like get_idf)"
	@echo "  make menuconfig              select/install toolchains (NuttX interface)"
	@echo "  make list                    list available groups"
	@echo "  make env                     print the activation alias for ~/.bashrc"

menuconfig:
	@bash $(SDK_ROOT)/scripts/sdk-menuconfig.sh

list:
	@bash $(SDK_ROOT)/scripts/setup.sh --list

env:
	@echo "alias get_nuttx='. $(SDK_ROOT)/nuttx-env.sh'"
