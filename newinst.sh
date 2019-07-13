#! /bin/bash
#
# Set up a new (Debian) machine on a target disk.

err() {
  echo >&2 "$@"
  exit 1
}

set -e

DEVICE="$1"
if test -z "$DEVICE"
then
  echo -n "Target device: "
  read -r DEVICE
fi

if ! test -b "$DEVICE"
then
  err "$DEVICE does not appear to be a block device!"
fi

# Intentionally use 'grep', so we include subdevices (e.g. partitions)
if mount | grep "$DEVICE"
then
  err "$DEVICE seems to be in use!"
fi

NEWHOST="$2"
if test -z "$NEWHOST"
then
  echo -n "New host name: "
  read -r NEWHOST
fi
MOUNT="/mnt/${NEWHOST}"
if mount | grep "$MOUNT"
then
  err "There appears to already be a mount at $MOUNT!"
fi

echo -n "Confirming debootstrap..."
if ! sudo which debootstrap
then
  err "could not find debootstrap as root!"
fi
echo "done."


echo "Candidate drive $DEVICE looks OK."
echo "Confirming: can I make changes to $DEVICE?"
echo -n "(y/N)> "
read -r CONFIRM
case "$CONFIRM" in
  y*|Y*)
    ;;
  *)
    exit 1
    ;;
esac

sudo echo "entered sudo mode!"


# Partition the device for EFI booting w/ encrypted LVM and swap.
# Our threat model here is "the drive isn't wiped before being sold / stolen",
# i.e. passive collection after it's left the owner's possession.
# We aren't (yet) attempting to protect against an active attacker, e.g. someone
# tampering with the bootloader / installing a keylogger.
EFI="${DEVICE}p1"  # /boot - ESP
LUKS="${DEVICE}p2" # LUKS-encrypted LVM

echo -n "Creating partition table..."
sudo parted --script "$DEVICE" \
  mktable gpt \
  unit MiB \
  mkpart primary fat32 1 512 \
  name 1 efi \
  set 1 boot on \
  set 1 esp on \
  mkpart primary 512 100%
  print
echo "done."

# Mountpoint for the new system:
sudo mkdir -p "$MOUNT" || true
# We'll mount partitions there once we've made them.

# Encrypt a partition w/ LUKS
# https://wiki.archlinux.org/index.php/Dm-crypt/Encrypting_an_entire_system#LVM_on_LUKS
echo "Creating encrypted partition..."
echo "Choose your passphrase carefully!"
sudo cryptsetup luksFormat "$LUKS"
echo "Encrypted partition created.."

CRYPTNAME="${NEWHOST}-crypt"
echo "Decrypting partition for LVM use..."
sudo cryptsetup open "$LUKS" "$CRYPTNAME"
CRYPTPART="/dev/mapper/$CRYPTNAME"
echo "Partition $LUKS open at $CRYPTPART; to detach, run:"
echo "  sudo cryptsetup close $CRYPTNAME"

echo -n "Initializing decrypted volume for LVM..."
sudo pvcreate "$CRYPTPART"
echo "done."
VGNAME="${NEWHOST}-vg"
echo -n "Creating LVM volume group..."
sudo vgcreate "$VGNAME" "$CRYPTPART"
echo "done."
echo "To deactivate the volume group, run:"
echo "  sudo lvchange --activate -n $VGNAME"

echo "Creating logical volumes..."
# Create logical volumes in the encrypted storage.
# - swap - a bit of it
# - var  - limit size taken up by e.g. docker
# - home - generous allowance for e.g. source repos & temp files, but don't
#          compete with the main system
# - root - everything else
#
# Don't bother with logical volumes for:
# - tmp  - use tmpfs
# We're assuming a 512GB disk here.
echo -n "  swap:  " && sudo lvcreate -L  10G       "$VGNAME" -n "swap" && echo "done."
echo -n "  root:  " && sudo lvcreate -L 100G       "$VGNAME" -n "root" && echo "done. (System size limited.)"
echo -n "  /var:  " && sudo lvcreate -L 100G       "$VGNAME" -n "var"  && echo "done. (App size limited.)"
echo -n "  /home: " && sudo lvcreate -l '100%FREE' "$VGNAME" -n "home" && echo "done. (Home size maximized.)"
echo "Logical volumes done."

echo "Creating filesystems..."
## Swap:
echo -n "  swap:" && sudo mkswap "/dev/$VGNAME/swap" && echo "done."
## ext4:
for part in var root home
do
  echo -n "  $part:" && sudo mkfs.ext4 "/dev/$VGNAME/$part" && echo "done."
done
## fat32, for UEFI compatibility:
echo -n "  boot:" && sudo mkfs.fat -F32 "$EFI" && echo "done."

echo "Mounting filesystems at $MOUNT..."
## /
sudo mount "/dev/$VGNAME/root" "$MOUNT"
echo "Mounted /dev/$VGNAME/root at $MOUNT; to undo, run:"
echo "  sudo umount --recursive $MOUNT"
sudo mkdir -p "$MOUNT/boot" "$MOUNT/home" "$MOUNT/var"

## /boot
sudo mount "$EFI" "$MOUNT/boot"
echo "Mounted $EFI at $MOUNT/boot; to undo, run:"
echo "  sudo umount --recursive $MOUNT/boot"

## /var
sudo mount "/dev/$VGNAME/var" "$MOUNT/var"
echo "Mounted /dev/$VGNAME/var at $MOUNT/var; to undo, run:"
echo "  sudo umount --recursive $MOUNT/var"

## /home
sudo mount "/dev/$VGNAME/home" "$MOUNT/home"
echo "Mounted /dev/$VGNAME/home at $MOUNT/home; to undo, run:"
echo "  sudo umount --recursive $MOUNT/home"

## swap (not quite a mount)
sudo swapon "/dev/$VGNAME/swap"

sync
echo "Mounted filesystems."

# TODO: Install OS, EFI bootloader, etc.

echo "Cleaning up..."

sync
echo -n "Unmounting decrypted filesystems..." \
  && sudo umount --recursive "$MOUNT" \
  && sudo swapoff "/dev/$VGNAME/swap" \
  && echo "done."

sync
echo -n "Deactivating volume group..." \
  && sudo vgchange -a n "$VGNAME" \
  && echo "done."

sync
echo -n "Closing decrypted volume..." \
  && sudo cryptsetup close "$CRYPTNAME" \
  && echo "done"

sync
echo "All done!"

# https://wiki.debian.org/UEFI#Disk_partitioning:_MS-DOS_and_GPT -
# need grub-efi; efibootmgr; efivar
