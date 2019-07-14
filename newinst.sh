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

NEWUSER="${NEWUSER:-${USER}}"

sudo echo "entered sudo mode!"

echo -n "Confirming debootstrap..."
if ! sudo which debootstrap
then
  err "could not find debootstrap as root!"
fi
echo "done."

echo "Candidate drive $DEVICE looks OK."
echo "Confirming: "
echo "  New hostname: $NEWHOST"
echo "  On device:    $DEVICE"
echo "  Superuser:    $NEWUSER"
echo -n "(y/N)> "
read -r CONFIRM
case "$CONFIRM" in
  y*|Y*)
    ;;
  *)
    exit 1
    ;;
esac


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


echo "Running debootstrap..."
sudo debootstrap \
  --include=linux-image-amd64 \
  --merged-usr \
  buster "$MOUNT"
echo "debootstrap done!"

echo "Generating fstab..."
cat <<FSTAB | sudo tee "$MOUNT/etc/fstab"
# /etc/fstab: static file system information. See fstab(5)
#
# Use 'blkid' to print the UUID for a device where applicable.
#
# <volume/device>              <mount point>   <fs type>  <options>          <dump>   <pass>
/dev/mapper/$NEWHOST--vg-root  /               ext4       errors=remount-ro 0 1
UUID=$(lsblk --noheadings --output UUID "$EFI") /boot vfat umask=0077 0 2
/dev/mapper/$NEWHOST--vg-var   /var            ext4       defaults 0 2
/dev/mapper/$NEWHOST--vg-home  /home           ext4       defaults 0 2
/dev/mapper/$NEWHOST--vg-swap  none            swap       sw 0 2
tmpfs                          /tmp            tmpfs      size=10g 0 0
FSTAB
echo "done generating fstab."

NEWLOCALE="en_US.UTF-8"
echo "Configuring locales for $NEWLOCALE..."
sudo chroot "$MOUNT" \
  apt install -y locales                        # Add locales package
# TODO: install locales with debootstrap?
sudo chroot "$MOUNT" \
  sed -i "/$NEWLOCALE/s/^# //" /etc/locale.gen  # Configure locales-gen
sudo chroot "$MOUNT" \
  dpkg-reconfigure -f noninteractive locales    # Run locales-gen
sudo chroot "$MOUNT" \
  update-locale "LANG=$NEWLOCALE"               # Set /etc/default/locale
echo "done."

NEWTZ="America/Los_Angeles"
echo "Configuring timezone to $NEWTZ..."
sudo chroot "$MOUNT" \
  ln -fs "/usr/share/zoneinfo/$NEWTZ" /etc/localtime # Set system timezone
sudo dpkg-reconfigure -f noninteractive tzdata       # Reconfigure tzdata accordingly
# TODO: do something with hwclock or /etc/adjtime?
echo "done."

sudo systemd-nspawn --directory "$MOUNT" \
  systemctl enable systemd-networkd systemd-resolved
cat <<NET | sudo tee "$MOUNT/etc/systemd/network/99-default.network"
[Match]
# Any not yet matched.

[Network]
Description=Default DHCP networking
DHCP=yes

NET

# TODO: Install graphical system

echo "Adding mounts to chroot for grub install..."
sudo chroot "$MOUNT" mount none -t proc /proc
sudo mount -obind /dev "$MOUNT/dev"
sudo mount -obind /sys "$MOUNT/sys"
echo "done."

# TODO: Move to grub-efi-amd64-signed, and install with --uefi-secure-boot
echo "Installing bootloader..."
sudo chroot "$MOUNT" \
  apt install -y \
  grub-efi

# Some info at https://wiki.debian.org/GrubEFIReinstall
sudo chroot "$MOUNT" \
  grub-install \
  --target=x86_64-efi \
  --efi-directory=/boot \
  --bootloader-id=GRUB-SSD

cat <<TUNE | sudo tee -a "$MOUNT/etc/default/grub"
# Super Mario boot tune, per https://forum.manjaro.org/t/grub-tunes-collection-fun-sound-startup-grub/62229
GRUB_INIT_TUNE="1000 334 1 334 1 0 1 334 1 0 1 261 1 334 1 0 1 392 2 0 4 196 2"
TUNE
sudo chroot "$MOUNT" \
  update-grub

# Don't use MAKEDEV; we don't need all those spare ones (can use systemd)

echo "Setting up admin user $NEWUSER..."
sudo chroot "$MOUNT" \
  adduser "$NEWUSER" \
  --gecos '' \
  --disabled-password

echo "Granting sudo permissions..."
sudo chroot "$MOUNT" \
  adduser "$NEWUSER" sudo
echo "done."

NEWPW=$(
  grep -v "'" /usr/share/dict/words \
    | grep '....' \
    | shuf -n 4 \
    | sed 's/.\+/\L\u&/g' \
    | tr -d '\n'
)

PWBACKUP="$HOME/${NEWHOST}-pass"

echo "Setting temporary password for $NEWUSER..."
# Use `chroot` rather than `--root` for chpasswd; appears to be something to do
# with blocked PAM syscalls.
echo "$NEWUSER":"$NEWPW" \
  | tee "$PWBACKUP" \
  | sudo chroot "$MOUNT" chpasswd
echo "Password for $NEWUSER is stored at $PWBACKUP."

# Likewise, don't use the builtin `-R`; causes a load error. :-(
sudo chroot "$MOUNT" passwd --expire "$NEWUSER"
echo "You'll be prompted to change it at first login."

echo "Press enter to confirm and continue..."
read -r

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
