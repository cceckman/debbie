#! /bin/sh -e
# Raspberry Pi setup tool; runs on the host.

# Sources:
# https://gist.github.com/jkullick/9b02c2061fbdf4a6c4e8a78f1312a689
# https://wiki.debian.org/RaspberryPi/qemu-user-static

set -e

DEVICE="$1"
TMPDIR="$HOME/tmp/"
mkdir -p $TMPDIR

if test "$#" -ne 1
then
  echo >&2 "Specify one argument: the device to write to, e.g. /dev/sdc"
  exit 1
fi

# Now that we have the image working, copy it to the device
if mount | grep -q "$DEVICE"
then
  echo >&2 "$DEVICE appears to be mounted; aborting"
  exit 1
fi

# install dependecies
apt-get install qemu qemu-user-static binfmt-support

DL_TGT=$TMPDIR/raspbian_latest.zip
if ! test -e $DL_TGT
then
  echo "No existing image found: $(ls $DL_TGT)"
  # download raspbian image
  curl -L -o $DL_TGT https://downloads.raspberrypi.org/raspbian_latest

  echo "Download complete!"
fi

IMG="$TMPDIR/$(zipinfo -1 $DL_TGT)"

if test $(zipinfo -1 $DL_TGT | wc -l) -ne 1
then
  echo >&2 "Unexpected files in archive: \n $(zipinfo -1 $DL_TGT)"
  exit 1
fi

# extract raspbian image
echo "unzipping to $IMG..."
unzip -b $DL_TGT -d $TMPDIR
echo "Done!"

# extend raspbian image by 1gb
dd if=/dev/zero bs=1M count=1024 >> $IMG

# set up image as loop device
sudo losetup /dev/loop0 $IMG

# check file system
sudo e2fsck -f /dev/loop0p2

# expand partition
sudo resize2fs /dev/loop0p2

# mount partition
sudo mount -o rw /dev/loop0p2  /mnt
sudo mount -o rw /dev/loop0p1 /mnt/boot

# mount binds
sudo mount --bind /dev /mnt/dev/
sudo mount --bind /sys /mnt/sys/
sudo mount --bind /proc /mnt/proc/
sudo mount --bind /dev/pts /mnt/dev/pts

# ld.so.preload fix
sudo sed -i 's/^/#/g' /mnt/etc/ld.so.preload

# copy qemu binary
sudo cp /usr/bin/qemu-arm-static /mnt/usr/bin/
sudo cp dessert.sh /mnt/usr/bin

# chroot to raspbian & run setup script
sudo chroot /mnt /bin/bash -c dessert.sh

# revert ld.so.preload fix
sudo sed -i 's/^#//g' /mnt/etc/ld.so.preload

# unmount everything
sudo umount /mnt/{dev/pts,dev,sys,proc,boot,}

# unmount loop device
sudo losetup -d /dev/loop0


# Now that we have the image working, copy it to the device
if mount | grep -q "$DEVICE"
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
TESTABLE=$TMPDIR/from-sd-card.img
dd bs=4M if="$DEVICE" of="$TESTABLE"
truncate --reference "$IMG" "$TESTABLE"
diff -s "$IMG" "$TESTABLE"

