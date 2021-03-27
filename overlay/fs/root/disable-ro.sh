#!/bin/bash

[ -f /.root-ro/ro/disable-root-ro ] && {
	mount /.root-ro/ro -o remount,rw
	rm -f /.root-ro/ro/disable-root-ro
	mount /.root-ro/ro -o remount,ro
}
