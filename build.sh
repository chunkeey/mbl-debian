#!/bin/bash

# set -xe

OURPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

MBLBRANCH=unstable
RELEASE=unstable
ROOT_PASSWORD=debian
DISTRIBUTION=Debian
DATE=$(date +%Y%m%d-%H%M)

ARCH=powerpc
TARGET=mbl-debian
SOURCE=http://ftp.ports.debian.org/debian-ports
SOURCE_SRC=http://ftp.debian.org/debian

QEMU_STATIC=/usr/bin/qemu-ppc-static
MKIMAGE=/usr/bin/mkimage
DTC=/usr/bin/dtc
KPARTX=/sbin/kpartx
PARTPROBE=/sbin/partprobe
DEBOOTSTRAP=/usr/sbin/debootstrap

DO_COMPRESS=1

# HDD Image
BOOTSIZE=285212672   # 272 MiB
ROOTSIZE=4152360960  # ~ 4GiB
SWAPFILESIZE=768     # in MiB
BOOTUUID=$(uuidgen)
ROOTPARTUUID=$(uuidgen)
ROOTUUID=$(uuidgen)
BOOTPARTNAME="BOOT"
BOOTPARTNO=1	     # UBoot scripts rely on this being 1
ROOTPARTNAME="mblroot"
ROOTPARTNO=2
IMAGESIZE=$(("$BOOTSIZE" + "$ROOTSIZE" + (4 * 1024 * 1024 )))

IMAGE="$DISTRIBUTION-$ARCH-$RELEASE-$MBLBRANCH-$DATE.img"

# Problem here is that the kernel md-autodetect code needs
# a 0.90 SuperBlock for the rootfs to boot off. The 0.90
# superblock unfortunatley uses the ARCH's (powerpc =
# big endian) encoding....
# But we are building on x86/ARM with little endian so we,
# can't use the established mdadm to make the RAID.
MAKE_RAID=

die() {
	(>&2 echo "$@")
	exit 1
}

to_k()
{
	echo $(($1 / 1024))"k"
}

echo "Building Image '$IMAGE'"

# Test if all the required tool are installed
declare -a NEEDED=("/usr/bin/uuidgen uuid-runtime" "$QEMU_STATIC qemu-user-static" "$MKIMAGE u-boot-tools"
	"$DTC device-tree-compiler" "$KPARTX kpartx" "$PARTPROBE parted"
	"$DEBOOTSTRAP debootstrap" "/usr/bin/git git" "/bin/mount mount" "/usr/bin/rsync rsync"
	"/sbin/gdisk gdisk" "/sbin/fdisk fdisk" "/usr/sbin/chroot coreutils"
	"/sbin/mkswap util-linux" "/usr/sbin/zerofree zerofree"
	"/usr/bin/powerpc-linux-gnu-gcc gcc-powerpc-linux-gnu"
	"/usr/bin/powerpc-linux-gnu-ld binutils-powerpc-linux-gnu")

for packaged in "${NEEDED[@]}"; do
	set -- $packaged

	[ -r "$1" ] || {
		die "Can't find '$1'. Please install '$2'"
	}
done

# Packages that are installed by debbootstrap - please note that
# debootstrap package dependency isn't great...
# Don't use tabs to align the entries! Debootstrap will choke and
# complain about missing "strange number" dependencies.
#
# Some of these packages could be moved to INSTALL_PACKAGES,
# others like binutils,gzip,u-boot-tools are necessary for
# scripts that run before we can apt install packages...
#
DEBOOTSTRAP_INCLUDE_PACKAGES="gzip,u-boot-tools,device-tree-compiler,binutils,\
        bzip2,locales,aptitude,file,xz-utils,initramfs-tools,fdisk,gdisk,\
        console-common,console-setup,console-setup-linux,parted,e2fsprogs,\
        dropbear,dropbear-initramfs,keyboard-configuration,ca-certificates,\
        debian-archive-keyring,debian-ports-archive-keyring,mdadm,dmsetup,\
        bsdextrautils,zstd,libubootenv-tool"

# That's why the heavy lifting should be done by apt that will be run in the chroot
APT_INSTALL_PACKAGES="needrestart zip unzip vim screen htop ethtool iperf3 \
	openssh-server netcat-traditional net-tools curl wget systemd-timesyncd \
	smartmontools hdparm smartmontools cryptsetup psmisc \
	nfs-common nfs-kernel-server rpcbind samba rsync telnet \
	btrfs-progs xfsprogs exfatprogs ntfs-3g dosfstools \
	bcache-tools duperemove \
	udisks2 udisks2-btrfs udisks2-lvm2 unattended-upgrades \
	cockpit cockpit-packagekit cockpit-networkmanager \
	cockpit-storaged watchdog lm-sensors uuid-runtime rng-tools-debian"

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

fallocate -l "$IMAGESIZE" "$IMAGE"

trap "/bin/umount -A -R -l $TARGET || echo unmounted; $KPARTX -d $IMAGE || echo ''; /sbin/losetup -D; rm -rf $TARGET linux-*.deb" EXIT

/sbin/gdisk "$IMAGE" <<-GPTEOF
	o
	y
	n
	p
	$BOOTPARTNO

	+$(to_k $BOOTSIZE)

	c
	$BOOTPARTNAME
	n
	p
	$ROOTPARTNO

	+$(to_k $ROOTSIZE)

	c
	$ROOTPARTNO
	$ROOTPARTNAME
	x
	c
	$ROOTPARTNO
	$ROOTPARTUUID
	m
	w
	y
GPTEOF

DEVICE=$(/sbin/losetup -f --show "$IMAGE")

$PARTPROBE

DEVICE=$($KPARTX -vas "$IMAGE" | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1)
sleep 1

DEVICE="/dev/mapper/${DEVICE}"
BOOTP="${DEVICE}p${BOOTPARTNO}"
ROOTP="${DEVICE}p${ROOTPARTNO}"

# Kernel build
./build-kernel.sh

# Make filesystems

# Boot ext2 Filesystem - revision 1 is needed because of u-boot ext2load
/sbin/mkfs.ext2 "$BOOTP" -O filetype -L "$BOOTPARTNAME" -m 0 -U $BOOTUUID -b 1024
# Reserve space at the end for an mdadm RAID 0.9 or 1.0 superblock
/sbin/resize2fs "$BOOTP" $(( $BOOTSIZE / 1024 - 128 ))

# Root Filesystem - ext4 is specified in rootfstype= kernel cmdline
/sbin/mkfs.ext4 "$ROOTP" -L "$ROOTPARTNAME" -U $ROOTUUID -b 4096
# Reserve space at the end for an mdadm RAID 0.9 or 1.0 superblock
/sbin/resize2fs "$ROOTP" $(( $ROOTSIZE / 4096 - 32 ))

mkdir -p "$TARGET"

mount "$ROOTP" "$TARGET" -t ext4

# create swapfile - it's still up to debate whenever fallocate or dd is better
dd if=/dev/zero of="$TARGET/.swapfile" bs=1M count="$SWAPFILESIZE"
chmod 0600 "$TARGET/.swapfile"

#prepare boot
mkdir -p "$TARGET/boot"
mount "$BOOTP" "$TARGET/boot" -t ext2
mkdir -p "$TARGET/boot/boot"
cp dts/wd-mybooklive.dtb "$TARGET/boot/apollo3g.dtb"
cp dts/wd-mybooklive.dtb.tmp "$TARGET/boot/apollo3g.dts"

ROOTBOOT="UUID=$ROOTUUID"

echo "$ROOTBOOT" > "$TARGET/boot/boot/root-device"

# debootstrap needs chroot available in PATH. This is for "root" but not necessarily for sudo...
source /etc/profile
$DEBOOTSTRAP --no-check-gpg --foreign --include="$DEBOOTSTRAP_INCLUDE_PACKAGES" --exclude="powerpc-utils" --arch "$ARCH" "$RELEASE" "$TARGET" "$SOURCE"

mkdir -p "$TARGET/usr/bin"
cp "$QEMU_STATIC" "$TARGET"/usr/bin/

LANG=C.UTF-8 /usr/sbin/chroot "$TARGET" /debootstrap/debootstrap --second-stage

if [[ -d $OURPATH/overlay/fs ]]; then
	echo "Applying fs overlay"
	cp -vR $OURPATH/overlay/fs/* "$TARGET"
fi

mv linux-*.deb "$TARGET/tmp"
if [[ $(ls fix-missing-ports/*.deb 2> /dev/null) ]]; then
	mkdir -p "$TARGET/tmp/fix"
	cp fix-missing-ports/*.deb "$TARGET/tmp/fix"
fi
rm linux-upstream*

mkdir -p "$TARGET/dev/mapper"

cat <<-INSTALLEOF > "$TARGET/tmp/install-script.sh"
	#!/bin/bash -e

	export LANGUAGE=en_US.UTF-8
	export LANG=en_US.UTF-8
	export LC_ALL=en_US.UTF-8

	source /etc/profile

	#apt
	cat <<-SOURCESEOF > /etc/apt/sources.list
	deb $SOURCE $RELEASE main contrib non-free non-free-firmware
	deb-src $SOURCE_SRC $RELEASE main contrib non-free non-free-firmware
	SOURCESEOF

	# fstab
	cat <<-FSTABEOF > /etc/fstab
		# <file system>	<mount point>	<type>	<options>			<dump>	<pass>
		UUID=$ROOTUUID	/		ext4	defaults			0	1
		UUID=$BOOTUUID	/boot		ext2	defaults,sync,nosuid,noexec	0	2
		proc		/proc		proc	defaults			0	0
		none		/var/log	tmpfs	size=30M,mode=755,gid=0,uid=0	0	0
	FSTABEOF

	echo "$TARGET" > etc/hostname
	echo "127.0.1.1	$TARGET" >> /etc/host

	# Networking
	cat <<-NETOF > /etc/network/interfaces
		# This file describes the network interfaces available on your system
		# and how to activate them. For more information, see interfaces(5).

		source /etc/network/interfaces.d/*

		# The loopback network interface
		auto lo
		iface lo inet loopback
	NETOF

	cat <<-NETOF > /etc/systemd/network/20-ether.network
		[Match]
		Type=ether

		[Network]
		DHCP=yes
	NETOF

	systemctl enable systemd-networkd
	systemctl disable networking

	# Debian unattented settings
	cat <<-CONSET > /tmp/debconf.set
		console-common	console-data/keymap/policy	select	Select keymap from full list
		console-common	console-data/keymap/full	select	us
		iperf		iperf3/start_daemon		string	false
	CONSET

	( export DEBIAN_FRONTEND=noninteractive; debconf-set-selections /tmp/debconf.set )

	echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen

	/usr/sbin/locale-gen
	# Set root password...
	echo "root:$ROOT_PASSWORD" | /usr/sbin/chpasswd
	echo 'RAMTMP=yes' >> /etc/default/tmpfs
	rm -f /etc/udev/rules.d/70-persistent-net.rules

	mkdir -p /etc/systemd/system/cockpit.socket.d/
	cat <<-CPLISTEN > /etc/systemd/system/cockpit.socket.d/listen.conf
	[Socket]
	ListenStream=
	ListenStream=80
	ListenStream=443
	ListenStream=9090
	CPLISTEN

	cat <<-FWCONF > /etc/fw_env.config
	# MTD device name	Device offset	Env. size	Flash sector size	Number of sectors
	/dev/mtd1		0x0000		0x1000		0x1000			1
	/dev/mtd1		0x1000		0x1000		0x1000			1
	FWCONF

	# Delete "existing" MD arrays... These have been copied from the Host system
	# They don't belong into this image
	sed -i '/#\ definitions\ of\ existing\ MD\ arrays/,/^$/d' /etc/mdadm/mdadm.conf

	echo "overlay" >> /etc/initramfs-tools/modules
	touch /disable-root-ro

	rm -f /etc/dropbear/dropbear_*_host_key
	rm -f /etc/dropbear-initramfs/dropbear_*_host_key

	if [ -d /tmp/fix ]; then
		find /tmp/fix -name "*.deb" -exec echo '{}' \;
		find /tmp/fix -name "*.deb" -exec apt install -y '{}' \;
	fi

	# install kernel image (mostly for the modules)
	find /tmp -name "linux-*deb" -exec apt install -y '{}' \;

	# First, try to fix bad packages dependencies
	apt install -f -y

	apt install -y $APT_INSTALL_PACKAGES

	# If a root-keyfile is already in place. Don't change the SSH Default password setting for root
	[[ -f /root/.ssh/authorized_keys ]] || sed -i 's|#PermitRootLogin prohibit-password|PermitRootLogin yes|g' /etc/ssh/sshd_config

	# Make it possible to login to cockpit as root... by deleting the "root" user by overwriting that file
	echo "# List of users which are not allowed to login to Cockpit" > /etc/cockpit/disallowed-users

	# Configure first_boot
	update-rc.d first_boot defaults
	update-rc.d first_boot enable

	# ... but make it so, that root has to change it on the first login
	# (This hopefully unbreaks dnsmasq install)
	/usr/bin/passwd -e root

	# git doesn't track permission on folders, so we have to step and lock
	# the /boot and /root (since we likely created these folders with the
	# overlay.
	chmod 0770 /boot /root

	bash /root/install-cockpit-fileshare.sh || echo "Failed installing cockpit fileshare extension... Oh well..."

	# cleanup
	apt clean
	apt-get --purge -y autoremove
	rm -rf /var/lib/apt/lists/* /var/tmp/*
	rm -f /tmp/linux*deb /tmp/debconf.set
	apt-mark minimize-manual -y

	# Delete the generated ssh key - It has to go since otherwise
	# the key is shipped with the image and will not be unique
	rm -f /etc/ssh/ssh_host_*

	# Enable tmpfs on /tmp - enabled by default now
	# systemctl enable /usr/share/systemd/tmp.mount

	# Allow for better compression by NULLING all the free space on the drive
	rm /tmp/install-script.sh
INSTALLEOF

chmod a+x "$TARGET/tmp/install-script.sh"
LANG=C.UTF-8 /usr/sbin/chroot "$TARGET" /tmp/install-script.sh

sleep 2

/bin/umount -A -R -l "$TARGET"

/usr/sbin/zerofree -v "$BOOTP"
/usr/sbin/zerofree -v "$ROOTP"

[[ $MAKE_RAID ]] && {
	# super 1.0 is between 8k and 12k
	dd if=boot-md0-raid1 of="$BOOTP" bs=1K seek=$(( $BOOTSIZE / 1024 - 8 )) status=noxfer

	# super 0.9 is at 64K
	dd if=root-md1-raid1 of="$ROOTP" bs=1k seek=$(( $ROOTSIZE / 1024 - 64)) status=noxfer
}

$KPARTX -d "$IMAGE"
/sbin/losetup -D

[[ $MAKE_RAID ]] && {
	# Do this at the end. This is because if we start with the
	# FD00 partition type when we are creating the partitions above,
	# the kernel will try to automount it when partprobe and kpartx
	# gets invoced... which we don't want.

	/sbin/gdisk "$IMAGE" <<-RAIDEOF
		t
		$BOOTPARTNO
		fd00
		t
		$ROOTPARTNO
		fd00
		w
		y
	RAIDEOF
}

if [[ "$DO_COMPRESS" ]]; then
	echo "Compressing Image. This can take a while."
	if [[ "$(command -v pigz)" ]]; then
		pigz "$IMAGE"
	else
		gzip "$IMAGE"
	fi
fi
