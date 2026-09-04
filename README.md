# README

This project reimplements in Ada the functionality of the
`convert-startup-to-vectors.mjs` script used to convert
Cortex-M CMSIS `startup-<device>.s` assembly files into µOS++
`vectors-<device>.c`.

The conversion requires the `templates/vectors-liquid.c` file, a
Shopify Liquid template.

The Ada code implements only a subset of the Liquid template engine
functionality.

The conversion was performed by Claude Sonnet 5.
