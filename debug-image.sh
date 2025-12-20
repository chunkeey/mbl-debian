#!/bin/bash

# Utility to mount+chroot into a existing image with the help of qemu
# This will run a bash in there

IMAGE="$1"

KPARTX=/sbin/kpartx
ROOTPARTNO=2

die() {
	>&2 echo "$@"
	exit 1
}

if [[ ! -r "$IMAGE" ]]; then
	die "Usage: $(basename "$0") IMAGE-FILE"
fi


if [[ "$IMAGE" == *."gz" ]]; then
	echo "Decompressing Image. This can take a while."
        if [[ "$(command -v pigz)" ]]; then
                pigz --uncompress "$IMAGE"
        else
                gzip --uncompress "$IMAGE"
        fi
	IMAGENAME="$(basename "$IMAGE" .gz)"
else
	IMAGENAME="$IMAGE"
fi

DEVICE=$("${KPARTX}" -vas "${IMAGENAME}" | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1)
DEVICE="/dev/mapper/${DEVICE}"
ROOTP="${DEVICE}p${ROOTPARTNO}"

TARGET="$(mktemp -d)"
mount "${ROOTP}" "${TARGET}"
>&2 echo "You are now in the Image! Enter <exit> to get back to your PC."
LANG=C.UTF-8 debian_chroot='-- DEBUG --' /usr/sbin/chroot "$TARGET" /bin/bash
umount "${TARGET}"
"${KPARTX}" -d "${IMAGENAME}"

[[ "$IMAGE" != "$IMAGENAME" ]] && {
	echo "(Re-)Compressing Image. This can take a while."
        if [[ "$(command -v pigz)" ]]; then
                pigz "$IMAGENAME"
        else
                gzip "$IMAGENAME"
        fi
}
