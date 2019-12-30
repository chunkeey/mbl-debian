#!/bin/bash

INPUT="${1:-/boot/boot/boot-source.txt}"

# The u-boot is looking for a file "/boot/boot.scr" on the first
# partition. This partition has to be a special ext2 format.
# This is all hardcoded.

/usr/bin/mkimage -A powerpc -T script -C none -n "MyBook Live Boot Script" \
		-d "$INPUT" "/boot/boot/boot.scr"
