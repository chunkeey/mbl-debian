# Debian SID/Unstable Image Generator for the MyBook Live Series

## Introduction

This project's build.sh generates an adapted Debian Sid/Unstable (As it still has the powerpc target today) image for the Western Digital MyBook Live Series devices.

Big parts of this generator code has been adapted from the [npn2-debian](https://github.com/riptidewave93/npn2-debian) project.

## Requirements
That you have a working and up-to-date Debian Sid/Unstable build (virtual) machine with 20GiB+ of free space and root access.
If this requirement have been met, you need to add the powerpc architecture with:

`# dpkg --add-architecture powerpc`

Then make sure to install the keyring for the debian ports subproject:

`# apt install debian-ports-archive-keyring`

And add the sid/unstable powerpc debian ports (sadly, that's the only one left) to apt and update:

`# echo "deb [arch=powerpc] http://deb.debian.org/debian-ports/ sid main contrib non-free non-free-firmware" > "/etc/apt/sources.list.d/powerpc-ports.list"`

Then you have to make sure your package index is up to date `# apt update` before installing the following packages on your Debian build host:

`# apt install bc binfmt-support build-essential debootstrap device-tree-compiler dosfstools fakeroot git kpartx lvm2 parted python3-dev qemu-system qemu-user-static swig wget u-boot-tools gdisk fdisk kernel-package uuid-runtime gcc-powerpc-linux-gnu binutils-powerpc-linux-gnu libssl-dev:powerpc rsync zerofree ca-certificates `

Because the image generation process relies on losetup+kpartx+friends making a docker/podman image proved to be tricky.
Let me know if you know a solution.

## Build
- Just run `sudo ./build.sh`.
- Due to reasons beyond my control, press and hold "Enter" during the kernel build process.
- Completed builds output to the project root directory as `Debian-powerpc-unstable-YYYYMMDD-HHMM-GPT.img.gz`

## Installing
There are multiple ways to get the image onto the device.

### Write the image onto the HDD by disassembling
This is the prefered method for the MyBook Live Duo. As it's as easy as opening the drive lid and pulling the HDD out of the enclosure. On the MyBook Live Single, this requires to fully disassemble the device in order to extract the HDD.

Once you have the HDD extracted, connect it to a PC and make a backup of it. After the backup was successfully completed and verified, you should zap out the existing GPT+MBR structures `gfdisk /dev/sdX` on that disk (look there in the expert option menu) and then you can uncompress the image onto the HDD. For example: `# gunzip -d -c Debian-powerpc-*-GPT.img.gz > /dev/sdX`... followed up by a `sync` to make sure everything is written to the HDD.

### Over the SSH-Console
For this method, you have to gain root access to the MyBook Live via SSH by any means necessary.
This is by no means ideal, since this can lead to a soft-bricked device, in case something went wrong.
So be prepared to disassemble the device.

To write the image onto the MyBook Live's drive, you can do it over the same network by executing:

`# cat Debian-powerpc-*-GPT.img.gz | ssh root@$MYBOOKLIVEADDRESS 'gunzip -d -c > /dev/sda'`

`zcat > /dev/sda` could be used in place of `gunzip -d -c > /dev/sda`

It's also possible (but it's discouraged because you can end up even more so with a bricked
device) to simply copy the image onto the HDD (via the provided standard access in the vendor
NAS firmware) and execute `# gunzip -c /path/to/Debian*.img.gz > /dev/sda` on the ssh shell of
the MyBook Live in order to write it directly onto /dev/sda.

After the image has been written, remove and reinsert the powerplug to do a instant reset.
The MyBook Live should then boot into a vanilla Debian Sid/Unstable.

## Boot from USB (exclusive for the My Book Live DUO)

Please note that, booting from USB is really slow (6-10 Minutes)! Please be patient and give
the device some additional minutes to load the DTB, kernel and Initrd image. You'll get a
confirmation that the process itself is working since the DTB is just 32KiB so it loads
within seconds. So once you see "32768 bytes read", just let it do its thing peacefully.

To do that: Extract the image to a compatible USB-Stick (anything that works with U-Boot).
Then attach a UART (DO NOT US a RS232/TTL without a CMOS/3.3V-Level converter), while the
device is off.

The power on the device, it boots up and enter the U-Boots prompt (The device tells you to
"Hit any key to stop autoboot", you have to be quick to press a key there, otherwise you
have to try again!). Next, once you managed to get to the PROMPT ("=>"), then copy&paste
the following commands line by line (to the letter! The quote (') get easily lost...).
If you get weird errors like: 'unknown command setenv', then write everything by hand.

    setenv usb_load_dtb 'ext2load usb 0:1 ${fdt_addr_r} /apollo3g.dtb'
    setenv usb_load_uImage 'ext2load usb 0:1 ${kernel_addr_r} /uImage'
    setenv usb_load_uInitrd 'ext2load usb 0:1 \${ramdisk_addr_r} /uInitrd'
    setenv usb_load 'run usb_load_dtb usb_load_uImage usb_load_uInitrd'
    setenv usb_env 'setenv bootargs '\$bootargs root=PARTLABEL=mblroot''
    setenv usb_boot 'bootm ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}'
    setenv usb 'usb start; run usb_load usb_env usb_boot'

When you are done, please verify handy-work with `printenv` / `echo $usb` first before
issuing the following command that writes these scripts to the u-boot-env.

    saveenv

now you can give this a one-time try... by entering:

    run addtty usb

This allows you to test and confirm that it is working. 

So if it doesn't work: you can leave this all "as-is", you don't need to 
revert/restore anything.

But if it worked and you are happy with the boottimes, then you can make 
the usb-boot permanent by entering the following commands when you reboot
and reenter u-boot.

    setenv bootcmd 'run usb || run boot_sata_script_ap2nc'
    saveenv

This will cause the MBL Duo to boot from an attached usb-stick first and if it fails,
it then tries to boot from the harddrives as before.

Note: you can still rollback at any time to factory default, by running the following
commands in the U-boot prompt:

    setenv usb_load_dtb
    setenv usb_load_uImage
    setenv usb_load_uInitrd
    setenv usb_load
    setenv usb_env
    setenv usb_boot
    setenv bootcmd 'run boot_sata_script_ap2nc'
    saveenv

This removes all usb boot scripts/commands and restores the previous boot-order.

## Usage

For access and administration, the image comes preinstalled with the [cockpit](https://cockpit-project.org/) web interface at [https://mbl-debian](https://mbl-debian).
SSH access is also available. Though, caution should be exercised. Because to make the first login possible when no serial cable has been attached, SSH will allow
password login for root, when no authorized_keys file is placed in `/root/.ssh/`.

## Notes
- The default root password is "debian" (see ROOT_PASSWORD variable in the build.sh script).
- The default hostname is "mbl-debian".
- This image will initialize the swap on the first boot and resize the GPT to fit the HDD.
- All Debian packages are directly pulled from the debian server. This is great since, the programs are up-to-date, but they can also be problems because of this. Be prepared to handle/fix or work-around your own problems. 
