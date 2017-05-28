#! /bin/sh -ex
#
# Commands to run within a Raspberry Pi install to set it up.

# To start off with: add a non-root user, turn off 'pi', turn off 'root'.

NEWUSER="$1"


sudo adduser $NEWUSER
sudo usermod -a -G sudoers $NEWUSER
sudo userdel -r pi
sudo passwd -l root

# Allow SSH.
touch /ssh

mkdir ~$NEWUSER/.ssh
