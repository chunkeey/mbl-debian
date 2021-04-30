#!/bin/bash

set -e

ARCH=powerpc
RELEASE=unstable
TARGET=mbl-debian
DISTRIBUTION=Debian
PARALLEL=$(getconf _NPROCESSORS_ONLN)
REV=1.00

DTS_DIR=dts
DTS_MBL=dts/wd-mybooklive.dts
DTB_MBL=dts/wd-mybooklive.dtb
LINUX_DIR=linux
LINUX_VER=v5.12

# This "cached-linux" serves as a local cache for a unmodified linux.git
LINUX_LOCAL="cached-linux"
LINUX_GIT=https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git

OURPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

rm -rf "$LINUX_DIR"

if [[ -d "$LINUX_LOCAL" ]]; then
	git clone --local "$LINUX_LOCAL" "$LINUX_DIR"
else
	git clone "$LINUX_GIT" "$LINUX_DIR"
fi

if [[ "$LINUX_VER" ]]; then
	(cd "$LINUX_DIR"; git checkout -b dev "$LINUX_VER")
fi

if [[ -d "$OURPATH/overlay/kernel/" ]]; then
	echo "Applying kernel overlay"
	cp -vr "$OURPATH/overlay/kernel/.config" "$OURPATH/overlay/kernel/*" "$LINUX_DIR" || echo bad
fi

if [[ -d "$OURPATH/patches/kernel/" ]]; then
	for file in $OURPATH/patches/kernel/*.patch; do
		echo "Applying kernel patch $file"
		( cd $LINUX_DIR; git am $file )
	done
fi

cpp -nostdinc -x assembler-with-cpp \
		-I "$DTS_DIR" \
		-I "$LINUX_DIR/include/" \
		-undef -D__DTS__ "$DTS_MBL" -o "$DTB_MBL.tmp"

# The DTB needs to be enlarged as u-boot needs the extra size for adding ranges and frequency properties
dtc -O dtb -i "$DTS_DIR" -S 32768 -o "$DTB_MBL" "$DTB_MBL.tmp"

#(cd $LINUX_DIR; make ARCH="$ARCH" syncconfig;
#make-kpkg kernel-source kernel-headers kernel-image kernel-debug --revision 1.00 --arch=powerpc --cross-compile powerpc-linux-gnu- )
#make-kpkg kernel-image --revision 1.00 --arch=powerpc --cross-compile powerpc-linux-gnu- )
#make deb-pkg ARCH=powerpc CROSS_COMPILE=powerpc-linux-gnu- -j8
#
(cd $LINUX_DIR; make deb-pkg ARCH="$ARCH" CROSS_COMPILE=powerpc-linux-gnu- -j$PARALLEL )
