#! /bin/sh
# Set up a Debian / Ubuntu machine to my liking.
# Put it all in a single file, so that it can be curl'd.

# Header: common functions.
prompt() {
  echo "$1"
  echo -n '> '
}
yesno() {
  echo "$1"
  echo -n "(y/N)> "
  read result
  echo -n "$result" | grep -q '^[yY]'
  return $?
}

# Header: required tools.
tools="apt-get apt-key cat curl hostname ssh-keygen sudo tee which lsb_release grep"

# Begin: start in a common base directory.
# pushd is a Bash builtin, not a POSIX-compatible command.
PUSHD="$(pwd)"
cd $HOME

# Start by entering sudo mode.
if [ "$USER" = "root" ]
then
  echo "Don't run this as root!"
  echo "Just run as yourself; debbie will ask for sudo permission when needed."
  exit 1
else
  echo "Prompting for sudo mode..."
  sudo true
fi

# Start off: make sure we have some basic tools.
echo "Looking for required tools..."
for tool in $tools
do
  if ! which $tool
  then
    echo "Could not find $tool! Aborting."
    exit 1
  fi
done

sudo apt-get update

# Want a more recent kernel?
if { uname -r | grep -q '^[^4]'; } && yesno "Would you like to update to a 4.X kernel?"
then
  {
  sudo apt-get install -t jessie-backports \
    linux-image-amd64 \
    linux-headers-amd64 \
    linux-image-extra \
    dkms \
    virtualbox-guest-dkms \
    broadcom-sta-dkms
  }
fi


# Get git
sudo apt-get install git

# Set up SSH credentials, incl. for Github.

if yesno "Generate new SSH credentials?"
then
  echo "echo OK, Generating new SSH credentials..."
  ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -C "$USER $(hostname)" -o -a 100
  ssh-keygen -t rsa -b 4096 -f $HOME/.ssh/id_rsa -C "$USER $(hostname)" -o -a 100

  # Attempt to POST to github.
  keyreq='/tmp/keyreq'
  cat - << HRD > $keyreq
{
  "title": "$USER@$(hostname)",
  "key": "$(cat $HOME/.ssh/id_rsa.pub)"
}
HRD
  while true
  do
    prompt "Enter a Github authentication token for ${USER}:"
    read token

    {
      curl --fail \
        -X POST \
        --data-binary @$keyreq \
        -u ${USER}:${token} \
        https://api.github.com/user/keys \
      && { echo "Upload successful!"; break; } 
    } || { 
      echo "Didn't upload Github key! "
      if ! yesno "Retry?"
      then
        echo "Failed to upload new Github key; aborting. :-("
        exit 2
      fi
    }
  done
else
  echo "OK, skipping new SSH credentials..."
fi

# Github now, presumably, has whatever keys we're using.
# Set defaults:
git config --global user.email "$(echo 'puneyrf@pprpxzna.pbz' | tr '[A-Za-z]' '[N-ZA-Mn-za-m]')"
git config --global user.name "Charles Eckman"
git config --global push.default simple
git config --global status.showUntrackedFiles no

# Clone Tilde.
ETCLONEHOME=''
if test -d $HOME/.git
then
  if yesno "Found $HOME/.git. Clone Tilde anyway?"
  then
    ETCLONEHOME='no'
  fi
fi

if [ "$ETCLONEHOME" == "" ]
then
  echo "Cloning Tilde repository..."
  {
    git clone git@github.com:cceckman/Tilde.git Tilde 2>&1 || {
      x=$?
      echo "Failed to clone Tilde! Exiting unhappily.,"
      exit $x
    }
  } && {
    mv Tilde/.git . \
    && rm -rf Tilde \
    && git reset --hard \
    && git submodule update --recursive --init
  } || {
    x=$?
    echo "Failed to load Tilde into \$HOME!"
    exit $x
  }
fi

# Load any other "default" repositories.
# Include this one- hey, if I'm using it, I probably want it cloned.
$HOME/scripts/update-repos cceckman/debbie

# Need this to use the other repositories...
sudo apt-get install apt-transport-https

# Add some custom repositories
# Bazel
echo "deb [arch=amd64] https://storage.googleapis.com/bazel-apt stable jdk1.8" | sudo tee /etc/apt/sources.list.d/bazel.list

curl https://storage.googleapis.com/bazel-apt/doc/apt-key.pub.gpg | sudo apt-key add  -

# GCloud
if ! ls /etc/apt/sources.list.d/ | grep -q google-cloud
then
  CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)"
  echo "deb https://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
fi

# Docker
sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 \
  --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
echo "deb https://apt.dockerproject.org/repo debian-jessie main" | sudo tee /etc/apt/sources.list.d/docker.list

# Docker group setup
sudo groupadd docker
sudo gpasswd -a ${USER} docker

sudo apt-get update
# Load packages. This eats a little more than 1GB, all told.
sudo apt-get install \
  arping \
  autoconf \
  bash \
  bazel \
  bc \
  bd \
  cgmanager \
  chromium \
  clang \
  cmatrix \
  default-jdk \
  docker-engine \
  dosfstools \
  feh \
  fping \
  gdb \
  google-cloud-sdk \
  graphviz \
  haskell-platform \
  i3 \
  imagemagick \
  irssi \
  kubectl \
  libanyevent-i3-perl \
  lldb \
  llvm \
  make \
  mlocate \
  mtr \
  network-manager \
  ninja-build \
  ntfs-3g \
  open-vm-tools \
  parted \
  pkg-config \
  python \
  python-gflags \
  rsync \
  screen \
  ssh \
  tcpdump \
  tmux \
  traceroute \
  vim \
  vim-gtk \
  xbacklight \
  xclip \
  xorg \
  xscreensaver \
  xscreensaver-data-extra \
  xss-lock \
  xterm \
  zip \
 || {
  x=$?
  echo "Package install failed with exit code: $x"
  exit $x
}

# Manually install Go, since the mainline repos aren't up-to-date.
{
  GOTAR=/tmp/golang.tar.gz
  curl -o $GOTAR https://storage.googleapis.com/golang/go1.7.4.linux-amd64.tar.gz \
  && sudo tar -C /usr/local -xzf $GOTAR
} || {
  x=$?
  echo "Go tools install failed with exit code: $x"
  exit $x
}

# Manually install rust via rustup.
# curl https://sh.rustup.sh -sSf | sh

# TODO: remote GUI tools


# One-time setup scripts
$HOME/scripts/install-wallpapertab.sh

echo "If you're going to use this with a Macbook, you probably want to look at:"
echo "http://askubuntu.com/questions/530325/tilde-key-on-mac-air-with-ubuntu"

echo -n "OK? "
read -r REPLY

echo "All done! Reboot to finish up. to update everything."

cd $PUSHD
