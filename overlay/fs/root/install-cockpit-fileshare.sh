#!/bin/bash

FILESHAREVER="4.2.5"
FILESHARESUB="-2focal"
FILESHAREURL="https://github.com/45Drives/cockpit-file-sharing/releases/download/v${FILESHAREVER}/cockpit-file-sharing_${FILESHAREVER}${FILESHARESUB}_all.deb"

SMBIDENTVER="0.1.12"
SMBIDENTSUB="-1focal"
SMBIDENTURL="https://github.com/45Drives/cockpit-identities/releases/download/v${SMBIDENTVER}/cockpit-identities_${SMBIDENTVER}${SMBIDENTSUB}_all.deb"

wget "${FILESHAREURL}" -O /tmp/cockpit-file-sharing.deb || exit 1
wget "${SMBIDENTURL}" -O /tmp/cockpit-identities.deb || exit 1

# apt update

echo "include = registry" >> /etc/samba/smb.conf
apt -fy install  /tmp/cockpit-file-sharing.deb /tmp/cockpit-identities.deb
rm -f /tmp/cockpit-file-sharing.deb /tmp/cockpit-identities.deb
smbcontrol smbd reload-config
systemctl restart cockpit
rm -f "$0"
