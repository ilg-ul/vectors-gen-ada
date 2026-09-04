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

# The selftest executables (everything in vectors_gen.gpr's "Main" list
# except "main"). They read fixtures via paths relative to the project
# root (e.g. "tests/golden/..."), so they must be run from here, not
# from obj/.
TEST_BINS := parser_selftest lexer_selftest liquid_parser_selftest \
             evaluator_selftest renderer_selftest

# Same golden fixtures the renderer_selftest checks in-process; "convert"
# instead exercises the real CLI end to end, by actually running "main".
#
# main stamps the output's header comment with whatever input path it's
# given, and the golden file was generated from the device tree's real
# path, not from tests/golden/ -- so the input is staged at that same
# relative path under obj/ first, to get a byte-identical comparison
# (matching what renderer_selftest already checks in-process).
GOLDEN_INPUT  := tests/golden/startup_stm32h533xx.s
GOLDEN_OUTPUT := tests/golden/vectors-stm32h533xx.c
CONVERT_STAGE_DIR := obj/convert-input
CONVERT_INPUT_REL := platforms/nucleo-h533re/device/stm32cubemx/startup_stm32h533xx.s
CONVERT_OUTPUT := obj/vectors-stm32h533xx.c

.PHONY: all build test convert clean

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

test: build
	@fail=0; \
	for t in $(TEST_BINS); do \
	  echo "=== $$t ==="; \
	  ./obj/$$t || fail=1; \
	done; \
	exit $$fail

convert: build
	@mkdir -p $(CONVERT_STAGE_DIR)/$(dir $(CONVERT_INPUT_REL)); \
	cp $(GOLDEN_INPUT) $(CONVERT_STAGE_DIR)/$(CONVERT_INPUT_REL); \
	( cd $(CONVERT_STAGE_DIR) \
	  && $(CURDIR)/obj/main $(CONVERT_INPUT_REL) $(CURDIR)/$(CONVERT_OUTPUT) \
	       $(CURDIR)/templates/vectors-liquid.c ); \
	diff -u $(GOLDEN_OUTPUT) $(CONVERT_OUTPUT) \
	  && echo "OK: $(CONVERT_OUTPUT) matches $(GOLDEN_OUTPUT) byte-for-byte"

clean:
	@gprclean -P $(GPR) ; exit $$?
