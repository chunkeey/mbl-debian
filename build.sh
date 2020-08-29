#!/bin/bash

# set -xe

die() {
	(>&2 echo "$@")
	exit 1
}

to_k()
{
	echo $(($1 / 1024))"k"
}

OURPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

ARCH=powerpc
RELEASE=unstable
TARGET=mbl-debian
DISTRIBUTION=Debian
PARTITION=GPT
SOURCE=http://ftp.ports.debian.org/debian-ports

QEMU_STATIC=/usr/bin/qemu-ppc-static
MKIMAGE=/usr/bin/mkimage
DTC=/usr/bin/dtc
KPARTX=/sbin/kpartx
PARTPROBE=/sbin/partprobe
DEBOOTSTRAP=/usr/sbin/debootstrap
ROOT_PASSWORD=debian
DATE=$(date +%Y%m%d-%H%M)

IMAGE="$DISTRIBUTION-$ARCH-$RELEASE-$DATE-$PARTITION.img"

echo "Building Image '$IMAGE'"

# Test if all the required tool are installed
declare -a NEEDED=("/usr/bin/uuidgen uuid-runtime" "$QEMU_STATIC qemu-user-static" "$MKIMAGE u-boot-tools"
	"$DTC device-tree-compiler" "$KPARTX kpartx" "$PARTPROBE parted"
	"$DEBOOTSTRAP debootstrap" "/usr/bin/git git" "/bin/mount mount" "/usr/bin/rsync rsync"
	"/sbin/gdisk gdisk" "/sbin/fdisk fdisk" "/usr/sbin/chroot coreutils"
	"/sbin/mkswap util-linux"
	"/usr/bin/powerpc-linux-gnu-gcc gcc-powerpc-linux-gnu"
	"/usr/bin/powerpc-linux-gnu-ld binutils-powerpc-linux-gnu")

for packaged in "${NEEDED[@]}"; do
	set -- $packaged

	[ -r "$1" ] || {
		die "Can't find '$1'. Please install '$2'"
	}
done

EXTRA_PACKAGES="u-boot-tools,device-tree-compiler,xz-utils,gzip,hdparm,smartmontools,net-tools,fdisk,parted,ethtool,less,vim,net-tools,openssh-server,locales,console-common,binutils,ca-certificates,e2fsprogs,mdadm,dmsetup,cryptsetup,parted,gdisk,curl,vim,nano,aptitude,file,bzip2,debian-ports-archive-keyring,wget,iperf3,htop,telnet,screen,netcat,initramfs-tools"

DTS_DIR=dts
LINUX_DIR=linux

# Cleanup

[ -d "$TARGET" ] && {
	/bin/umount -f -l "$TARGET" || echo "Image was already mounted - unmounting"
}
[ -r "$IMAGE" ] && {
	$KPARTX -d "$IMAGE" || echo "Image was already loaded - cleaning"
}
/sbin/losetup -D
rm -rf "$TARGET" "$IMAGE"

DO_COMPRESS=1

# HDD Image

BOOTSIZE=134217728   # 128 MiB
SWAPSIZE=939524096   # 768 MiB
ROOTSIZE=3212836864  # ~ 3GiB
ROOTPARTUUID=$(uuidgen)
ROOTUUID=$(uuidgen)
IMAGESIZE=$(("$BOOTSIZE" + "$SWAPSIZE" + "$ROOTSIZE" + (4 * 1024 * 1024 )))

fallocate -l "$IMAGESIZE" "$IMAGE"

trap "/bin/umount -A -R -l $TARGET || echo unmounted; $KPARTX -d $IMAGE || echo ''; /sbin/losetup -D; rm -rf $TARGET linux-*.deb" EXIT

case "$PARTITION" in
GPT)
	/sbin/gdisk "$IMAGE" <<-GPTEOF
		o
		y
		n
		p
		1

		+$(to_k $BOOTSIZE)

		n
		p
		2

		+$(to_k $SWAPSIZE)
		8200
		n
		p
		3

		+$(to_k $ROOTSIZE)

		x
		c
		3
		$ROOTPARTUUID
		m
		w
		y
	GPTEOF
	;;

MBR)
	die "Broken due do UUID-boot"
	/sbin/fdisk "$IMAGE" <<-MBREOF
		o
		n
		p
		1

		+$(to_k $BOOTSIZE)
		n
		p
		2

		+$(to_k $SWAPSIZE)
		t
		2
		82
		n
		p
		3

		+$(to_k $ROOTSIZE)
		w
	MBREOF
	;;
*)
	die "Unsupported Partition Format $PARTITION"
	;;
esac


DEVICE=$(/sbin/losetup -f --show "$IMAGE")

$PARTPROBE

DEVICE=$($KPARTX -vas "$IMAGE" | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1)
sleep 1

DEVICE="/dev/mapper/${DEVICE}"
BOOTP=${DEVICE}p1
SWAPP=${DEVICE}p2
ROOTP=${DEVICE}p3

# Kernel build
./build-kernel.sh

# Make filesystems

# revision 1 - needed for u-boot ext2load
/sbin/mkfs.ext2 "$BOOTP" -O filetype -L BOOT -m 0

/sbin/mkfs.ext4 "$ROOTP" -L root -U $ROOTUUID
mkdir -p "$TARGET"

/bin/mount "$ROOTP" "$TARGET" -t ext4

#prepare boot
mkdir -p "$TARGET/boot"
/bin/mount "$BOOTP" "$TARGET/boot" -t ext2
mkdir -p "$TARGET/boot/boot"
cp dts/wd-mybooklive.dtb "$TARGET/boot/apollo3g.dtb"
cp dts/wd-mybooklive.dtb.tmp "$TARGET/boot/apollo3g.dts"

cat <<-BOOTSCRIPTEOF > "$TARGET/boot/boot/boot-source.txt"
	setenv bootargs root=PARTUUID=$ROOTPARTUUID rw
	setenv load_kernel1 'ext2load sata 0:1 \${kernel_addr_r} /uImage || ext2load sata 0:1 \${kernel_addr_r} /uImage-old;'
	setenv load_dtb1 'ext2load sata 0:1 \${fdt_addr_r} /apollo3g.dtb || ext2load sata 0:1 \${fdt_addr_r} /apollo3g.dtb-old'
	setenv load_part1 'run load_kernel1 load_dtb1'
	setenv load_kernel2 'ext2load sata 1:1 \${kernel_addr_r} /uImage || ext2load sata 1:1 \${kernel_addr_r} /uImage-old;'
	setenv load_dtb2 'ext2load sata 1:1 \${fdt_addr_r} /apollo3g.dtb || ext2load sata 1:1 \${fdt_addr_r} /apollo3g.dtb-old'
	setenv load_part2 'run load_kernel2 load_dtb2'
	setenv load_sata 'if run load_part1; then echo Loaded part 1; elif run load_part2; then echo Loaded part 2; fi'
	setenv boot_sata 'sata init; run load_sata; run addtty; bootm \${kernel_addr_r} - \${fdt_addr_r}'
	run boot_sata
BOOTSCRIPTEOF

# debootstap

$DEBOOTSTRAP --no-check-gpg --foreign --include="$EXTRA_PACKAGES" --exclude="powerpc-utils" --arch "$ARCH" "$RELEASE" "$TARGET" "$SOURCE"

mkdir -p "$TARGET/usr/bin"
/bin/cp "$QEMU_STATIC" "$TARGET"/usr/bin/

LANG=C /usr/sbin/chroot "$TARGET" /debootstrap/debootstrap --second-stage

if [ -d $OURPATH/overlay/fs ]; then
	echo "Applying fs overlay"
	cp -vR $OURPATH/overlay/fs/* "$TARGET"
fi

mv linux-*.deb $TARGET/tmp

mkdir -p $TARGET/dev/mapper

cat <<-INSTALLEOF > $TARGET/tmp/install-script.sh
	#!/bin/bash

	export LANGUAGE=en_US.UTF-8
	export LANG=en_US.UTF-8
	export LC_ALL=en_US.UTF-8

	. /etc/profile

	#apt
	echo "deb $SOURCE $RELEASE main contrib non-free
	deb-src $SOURCE $RELEASE main contrib non-free" > /etc/apt/sources.list

	# fstab
	cat <<-FSTABEOF > /etc/fstab
		# <file system>	<mount point>	<type>	<options>			<dump>	<pass>
		UUID=$ROOTUUID	/		ext4	defaults			0	1
		proc		/proc		proc	defaults			0	0
		/dev/sda2	none		swap	sw				0	0
		/dev/sda1	/boot		ext2	defaults,sync,nosuid,noexec	0	2
	FSTABEOF

	echo "$TARGET" > etc/hostname
	echo "127.0.1.1	$TARGET" >> /etc/host

	# Networking
	cat <<-NETOF > /etc/network/interfaces
		auto lo eth0

		iface lo inet loopback

		allow-hotplug eth0
		iface eth0 inet dhcp
		iface eth0 inet6 auto
	NETOF

	# Console settings
	cat <<-CONSET > /tmp/debconf.set
		console-common	console-data/keymap/policy	select	Select keymap from full list
		console-common	console-data/keymap/full	select	us
	CONSET

	( export DEBIAN_FRONTEND=noninteractive; debconf-set-selections /tmp/debconf.set )

	echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen

	/usr/sbin/locale-gen
	echo "root:$ROOT_PASSWORD" | /usr/sbin/chpasswd
	echo 'RAMTMP=yes' >> /etc/default/tmpfs
	sed -i -e 's/KERNEL\!=\"eth\*|/KERNEL\!=\"/' /lib/udev/rules.d/75-persistent-net-generator.rules
	rm -f /etc/udev/rules.d/70-persistent-net.rules
	sed -i 's|#PermitRootLogin prohibit-password|PermitRootLogin yes|g' /etc/ssh/sshd_config

	# install kernel image (mostly for the modules)
	dpkg -i /tmp/linux-image*deb /tmp/linux-headers*deb

	update-rc.d first_boot defaults
	update-rc.d first_boot enable

	# cleanup
	apt clean
	apt-get --purge -y autoremove
	rm -rf /var/lib/apt/lists/* /var/tmp/*
	rm -f /tmp/linux*deb /tmp/debconf.set

	# Delete the generated ssh key - It has to go since otherwise
	# the key is shipped with the image and will not be unique
	rm -f /etc/ssh/ssh_host_*

	# Allow for better compression by NULLING all the free space on the drive
	rm /tmp/install-script.sh
INSTALLEOF

chmod a+x "$TARGET/tmp/install-script.sh"
LANG=C /usr/sbin/chroot "$TARGET" /tmp/install-script.sh

dd if=/dev/zero of=$TARGET/tmp/file 2>/dev/null || echo ""
rm -f $TARGET/tmp/file

sleep 2

/bin/umount -A -R -l "$TARGET"
$KPARTX -d "$IMAGE"
/sbin/losetup -D

if [[ "$DO_COMPRESS" ]]; then
	echo "Compressing Image. This can take a while."
	if [[ "$(command -v pigz)" ]]; then
		pigz "$IMAGE"
	else
		gzip "$IMAGE"
	fi
fi
