#!/bin/bash

SRC=/.
CHD=/.root-ro/ro

binddir='dev dev/pts dev/shm var/run var/lock tmp'

mount_chroot()
{
        for dir in $binddir; do
                mount --bind "$SRC/$dir" "$CHD/$dir"
        done

        mount -t proc none "$CHD/proc"
        mount -t sysfs none "$CHD/sys"
}

umount_chroot()
{
        umount "$CHD/proc"
        umount "$CHD/sys"

        revbind=$(echo $binddir | rev)

        for revdir in $revbind; do
                dir=$(echo $revdir | rev)
                sleep 0.1
                umount "$CHD/$dir"
        done
}

mount /.root-ro/ro -o remount,rw

mount_chroot
>&2 echo "Chrooting... - enter 'exit' to return."
pushd "$CHD"
debian_chroot='-- MAINTAIN --' /usr/sbin/chroot .
popd

>&2 echo "Exiting Chroot."
umount_chroot

mount /.root-ro/ro -o remount,ro || echo "Could not change back to read-only. Please reboot."
