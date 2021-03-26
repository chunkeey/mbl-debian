#!/bin/bash

MDADM=/usr/sbin/mdadm
SFDISK=/usr/sbin/sfdisk

cat << EOF

This script will help you adding a secondary HDD for RAID-1 for both the /boot and main file system.
Be aware: the procedure will re-partition and overwrite your secondary drive.

This is not a migration tool from the Western Digital MyBook Live installations.

EOF

msg() {
	(1>&2 echo "$@")
}

die() {
	msg "$@"
	exit 1
}

[[ -x "$MDADM" ]] || die "necessary component: 'mdadm' was not found."
[[ -x "$SFDISK" ]] || die "necessary component: 'sfdisk' was not found."

[[ -r "/dev/md0" ]] || die "Did not find boot-RAID1 (md0)? Maybe this isn't the RAID1-Image of the MBL-Debian? Anyway... Aborting."

#"$MDADM" --misc /dev/md0 --test
#[[ "$?" = "0" ]] && die "RAID seems to be already initialized on boot-RAID1 (md0)... Aborting."

OUR_SIZE="$(cat /sys/block/sda/size)"

[[ "$?" = "0" ]] || die "Failure querying the size of our main HDD (sda)... Aborting."

msg "Size of our main drive (sda):$OUR_SIZE"

while (true); do
	COMPARE_SIZE="$(cat /sys/block/sdb/size 2>/dev/null)"
	[ "0" = "$?" ] && {
		msg "Size of our secondary drive (sdb):$COMPARE_SIZE"

		[[ "$OUR_SIZE" -ge "$COMPARE" ]] && {
			msg "Everything seems good to go... Secondary disk is equal or bigger in size."
			break
		}

		msg "Secondary HDD is smaller than the main HDD. Either switch them around or get a different HDD."
		read -p "(Hit <Enter> to try again, Press <CTRL>-<C> to exit)" tmp
		continue
	}
	msg "Please insert the second HDD into the empty tray and wait a bit for it to be initialized..."
	read -p "(Hit <Enter> to try again, Press <CTRL>-<C> to exit)" tmp
done

msg "The next steps involves repartitioning and overwriting the secondary HDD. Is this OK?"
read -p "Enter YES<enter>(in uppercase letters!), anything else will quit the program: " prompt

[[ "YES" = "$prompt" ]] || die "Exiting on user request."

msg "Copying partition layout from main HDD to secondary HDD."

"$SFDISK" -d /dev/sda | "$SFDISK" /dev/sdb
[[ "$?" = "0" ]] || die "Unfortunately, this failed. Exiting..."

MDS=$(find /sys/block/md* -printf '%f\n')

for MD in $MDS; do
	SDP=sdb$((${MD##md}+1))
	msg "Adding secondary HDD Partition $SDP to RAID1 for $MD."
	"$MDADM" --manage "/dev/$MD" --add "/dev/$SDP"
done

msg "Updating /etc/mdadm/mdadm.conf"
"$MDADM" --detail --scan >> /etc/mdadm/mdadm.conf

msg "Do you wish to follow through re-configuring the mdadm package to enable periodic drive checks and more?"
read -p "Enter Yes<enter>: " prompt
[[ "YES" = "${prompt^^}" ]] && dpkg-reconfigure -plow mdadm

