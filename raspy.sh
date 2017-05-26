#! /bin/sh
# Raspberry Pi setup tool; runs on the host.

# Sources:
# https://gist.github.com/jkullick/9b02c2061fbdf4a6c4e8a78f1312a689
# https://wiki.debian.org/RaspberryPi/qemu-user-static

set -e

DEVICE="$1"

# install dependecies
apt-get install qemu qemu-user-static binfmt-support

DL_TGT=/tmp/raspbian_latest.zip
if ! test -e $DL_TGT
then
  # download raspbian image
  curl -L -o $DL_TGT https://downloads.raspberrypi.org/raspbian_latest

  echo "Download complete!"
fi

# extract raspbian image
IMG="$(unzip -l $DL_TGT)"

if (( $(unzip -l $DL_TGT | wc -l) != 1 ))
then
  echo "Unexpected files in archive: $(unzip -l $DL_TGT)"
  exit 1
fi

unzip $DL_TGT

# extend raspbian image by 1gb
dd if=/dev/zero bs=1M count=1024 >> $IMG

# set up image as loop device
losetup /dev/loop0 $IMG

# check file system
e2fsck -f /dev/loop0p2

#expand partition
resize2fs /dev/loop0p2

# mount partition
mount -o rw /dev/loop0p2  /mnt
mount -o rw /dev/loop0p1 /mnt/boot

# mount binds
mount --bind /dev /mnt/dev/
mount --bind /sys /mnt/sys/
mount --bind /proc /mnt/proc/
mount --bind /dev/pts /mnt/dev/pts

# ld.so.preload fix
sed -i 's/^/#/g' /mnt/etc/ld.so.preload

# copy qemu binary
cp /usr/bin/qemu-arm-static /mnt/usr/bin/
cp dessert.sh /mnt/usr/bin

# chroot to raspbian & run setup script
chroot /mnt /bin/bash -c dessert.sh

# revert ld.so.preload fix
sed -i 's/^#//g' /mnt/etc/ld.so.preload

# unmount everything
umount /mnt/{dev/pts,dev,sys,proc,boot,}

# unmount loop device
losetup -d /dev/loop0


# Now that we have the image working, copy it to the device
if mount | greq -q "$DEVICE"
then
  echo >&2 "$DEVICE appears to be mounted; aborting"
  exit 1
fi

echo "Copying $IMG to $DEVICE, y/n?"
read RESP
case $RESP in
  y*) true;;
  *) echo "cancelled"; exit;;
esac

dd bs=4M if="$IMG" of="$DEVICE" status=progress
sync

# Check correctness...
TESTABLE=/tmp/from-sd-card.img
dd bs=4M if="$DEVICE" of="$TESTABLE"
truncate --reference "$IMG" "$TESTABLE"
diff -s "$IMG" "$TESTABLE"

