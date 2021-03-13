# Debian SID/Unstable Image Generator for the MyBook Live Series

## Introduction

This project's build.sh generates an adapted Debian Sid/Unstable (As it still has the powerpc target today) image for the Western Digital MyBook Live Series devices.

Big parts of this generator code has been adapted from the [npn2-debian](https://github.com/riptidewave93/npn2-debian) project.

## Requirements
That you have a working and up-to-date Debian build (virtual) machine with 20GiB+ of free space and root access.
If this requirement have been met, you need to add the powerpc architecture with:

`# dpkg --add-architecture powerpc`

Then you have to make sure your package index is up to date `# apt update` before installing the following packages on your Debian build host:

`# apt install bc binfmt-support build-essential debootstrap device-tree-compiler dosfstools fakeroot git kpartx lvm2 parted python-dev python3-dev qemu qemu-user-static swig wget u-boot-tools gdisk fdisk kernel-package uuid-runtime c-compiler-powerpc-linux-gnu binutils-powerpc-linux-gnu`

## Build
- Just run `sudo ./build.sh`.
- Due to reasons beyond my control, press and hold "Enter" during the kernel build process.
- Completed builds output to the project root directory as `Debian-powerpc-unstable-YYYYMMDD-HHMM-GPT.img.gz`

## Installing
There are multiple ways to get the image onto the device.

### Write the image onto the HDD by disassembling
This is the prefered method for the MyBook Live Duo. As it's as easy as opening the drive lid and pulling the HDD out of the enclosure. On the MyBook Live Single, this requires to fully disassemble the device in order to extract the HDD.

Once you have the HDD extracted, connect it to a PC and make a backup of it. After the backup was successfully completed and verified, you can uncompress the image onto the HDD. For example: `# gunzip Debian-powerpc-*-GPT.img.gz -c > /dev/sdX`.

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

## Usage

For access and administration, the image comes preinstalled with the [cockpit](https://cockpit-project.org/) web interface at [https://mbl-debian](https://mbl-debian).
SSH access is also available. Though, caution should be exercised. Because to make the first login possible when no serial cable has been attached, SSH will allow
password login for root, when no authorized_keys file is placed in `/root/.ssh/`.

## Notes
- The default root password is "debian" (see ROOT_PASSWORD variable in the build.sh script).
- The default hostname is "mbl-debian".
- This image will initialize the swap on the first boot and resize the GPT to fit the HDD.
- All Debian packages are directly pulled from the debian server. This is great since, the programs are up-to-date, but they can also be problems because of this. Be prepared to handle/fix or work-around your own problems. 
