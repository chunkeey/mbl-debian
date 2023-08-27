#!/bin/bash

DIR="/run/.root-ro/ro/"
FLAGFILE="$DIR/disable-root-ro"

if [[ -d "$DIR" ]]; then
	echo "Killing flag file..."
	mount "$DIR" -o remount,rw && touch "$FLAGFILE" && mount "$DIR" -o remount,ro && reboot
fi
