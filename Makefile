# Portable build wrapper around gprbuild.
#
# On macOS, the linker needs an explicit SDK path (see vectors_gen.gpr
# for why); on Linux (and everywhere else) this adds no extra flags, so
# `make` behaves identically on both.
#
# gnat/gprbuild are also located automatically if installed via Alire
# (https://alire.ada.dev) but not on PATH -- `alr toolchain --select`
# installs them under ~/.local/share/alire/toolchains on every platform,
# without touching the shell's rc files.
#
# Every recipe line below ends in "; exit $$?" purely to force make to
# run it through a real shell instead of exec'ing it directly: some
# make builds (e.g. the GNU Make 3.81 that ships with Xcode's Command
# Line Tools) skip the shell for a plain command with no shell
# metacharacters, and in that fast path don't see the PATH exported by
# this file, so plain "gprbuild ..." isn't found even though it is on
# the PATH make itself computed.

GPR := vectors_gen.gpr

UNAME_S := $(shell uname -s)

empty :=
space := $(empty) $(empty)

ALIRE_TOOLCHAINS := $(HOME)/.local/share/alire/toolchains
ALIRE_BIN_DIRS := $(wildcard $(ALIRE_TOOLCHAINS)/gnat_native_*/bin) \
                   $(wildcard $(ALIRE_TOOLCHAINS)/gprbuild_*/bin)
ifneq ($(strip $(ALIRE_BIN_DIRS)),)
export PATH := $(subst $(space),:,$(strip $(ALIRE_BIN_DIRS))):$(PATH)
endif

ifeq ($(UNAME_S),Darwin)
GPRBUILD_XFLAGS := -XVECTORS_GEN_HOST=macos \
                    -XVECTORS_GEN_SDKROOT=$(shell xcrun --show-sdk-path)
endif

.PHONY: all build clean

all: build

build:
	@command -v gprbuild >/dev/null 2>&1 || { \
	  echo "error: gprbuild not found on PATH and no Alire toolchain" \
	       "detected under $(ALIRE_TOOLCHAINS)."; \
	  echo "       Install one, e.g.: alr toolchain --select"; \
	  exit 1; \
	}
	@echo gprbuild -P $(GPR) $(GPRBUILD_XFLAGS)
	@gprbuild -P $(GPR) $(GPRBUILD_XFLAGS) ; exit $$?

clean:
	@gprclean -P $(GPR) ; exit $$?
