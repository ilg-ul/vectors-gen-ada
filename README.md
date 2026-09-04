# README

This project reimplements in Ada the functionality of the
`convert-startup-to-vectors.mjs` script used to convert
Cortex-M CMSIS `startup_<device>.s` assembly files into µOS++
`vectors-<device>.c`.

The conversion requires the `templates/vectors-liquid.c` file, a
Shopify Liquid template.

The Ada code implements only a subset of the Liquid template engine
functionality.

The conversion was performed by Claude Sonnet 5.

## Building

Requires an Ada toolchain (`gnat` + `gprbuild`), e.g. installed via
[Alire](https://alire.ada.dev):

```console
alr toolchain --select
```

Then, from the project root:

```console
make
```

builds `main` and the `*_selftest` executables into `obj/`; `make clean`
removes them. `make` works unmodified on Linux and macOS: on macOS it
also points the linker at the Xcode/Command Line Tools SDK, which the
Alire-distributed GNAT toolchain doesn't locate on its own (see
`vectors_gen.gpr` and `Makefile` for details).
