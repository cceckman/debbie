#! /bin/sh -x
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

  # Skip (default to 'no') if non-interactive.
  if ! [ -t 0 ]
  then
    echo "fd 0 is not a TTY ∴ assuming 'No' by default"
    return 1
  fi

  read result
  echo -n "$result" | grep -q '[yY]'
  return $?
}
# Version greater-than-or-equal-to:
# https://stackoverflow.com/questions/4023830/how-compare-two-strings-in-dot-separated-version-format-in-bash
vergte() {
  vA="$(echo $1 | grep -o '[0-9]\+\.[0-9]\+\(\.[0-9]\+\)\?')"
  vB="$(echo $2 | grep -o '[0-9]\+\.[0-9]\+\(\.[0-9]\+\)\?')"
  lesser="$(echo -e "${vA}\n${vB}" | sort -V | head -n1)"
  [ "$1" = "$lesser" ]
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

sudo apt-get install locales

# Set locale to US.
sudo sed -i -e 's/^[^#]/# \0/' -e 's/^.*\(en_US.UTF-8\)/\1/' /etc/locale.gen
sudo /usr/sbin/locale-gen
sudo apt-get update
# Bring everything up to date from the base image.
sudo apt-get -y upgrade

# Want a more recent kernel?
# Great- upgrade from Jessie!
# if { uname -r | grep -q '^[^4]'; } && yesno "Would you like to update to a 4.X kernel?"
# then
#   {
#   sudo apt-get -y install -t jessie-backports \
#     linux-image-amd64 \
#     linux-headers-amd64 \
#     linux-image-extra \
#     dkms \
#     virtualbox-guest-dkms \
#     broadcom-sta-dkms
#   }
# fi


# Get git
sudo apt-get -y install git

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
  sleep 10 # error budget for Github to catch new keys.
else
  echo "OK, skipping new SSH credentials..."
fi

# Github now, presumably, has whatever keys we're using.
# Set defaults:
git config --global user.email "$(echo 'puneyrf@pprpxzna.pbz' | tr '[A-Za-z]' '[N-ZA-Mn-za-m]')"
git config --global user.name "Charles Eckman"
git config --global push.default simple
git config --global status.showUntrackedFiles no
# From https://stackoverflow.com/questions/4611512/is-there-a-way-to-make-git-pull-automatically-update-submodules
# Automatically recurse into submodules when pulling.
# Makes some of the stuff in update-repos redundant, but that's okay.
git config --global alias.pullall '!f(){ git pull "$@" && git submodule update --init --recursive; }; f'
git config --global diff.tool vimdiff
git config --global merge.tool vimdiff
git config --global --add difftool.prompt false

# Set Github public key.
mkdir ~/.ssh
echo "github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ=="  >> $HOME/.ssh/known_hosts


# Clone Tilde.
ETCLONEHOME='yes'
if test -d $HOME/.git
then
  ETCLONEHOME='no'
  if yesno "Found $HOME/.git. Clone Tilde anyway?"
  then
    ETCLONEHOME='yes'
  fi
fi

if test "$ETCLONEHOME" = 'yes'
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
else
  echo "Skipping cloning Tilde..."
  touch $HOME/clone-skipped
fi

# Load any other "default" repositories.
# Include this one- hey, if I'm using it, I probably want it cloned.
$HOME/scripts/update-repos cceckman/debbie

# Need this to use the other repositories...
sudo apt-get -y install apt-transport-https

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
echo "deb https://apt.dockerproject.org/repo debian-stretch main" | sudo tee /etc/apt/sources.list.d/docker.list

# Docker group setup
sudo groupadd docker
sudo gpasswd -a ${USER} docker

sudo apt-get update

# Packages that are different on Debian vs. Ubuntu.

more_pkgs=''
case "$(uname -v)" in
  *Ubuntu*)
    more_pkgs='chromium-browser'
    ;;
  *Debian*)
    mork_pkgs='chromium'
    ;;
esac
# Missing:
# - bd not available in Ubuntu 16.04, so don't include it anywhere.

# Load packages. This eats a little more than 1GB, all told.
sudo apt-get -y install \
  acpi \
  arping \
  autoconf \
  bash \
  bc \
  cgmanager \
  clang \
  cmatrix \
  devscripts \
  dnsutils \
  dosfstools \
  feh \
  fping \
  gdb \
  google-cloud-sdk \
  graphviz \
  haskell-platform \
  i3 \
  imagemagick \
  ipcalc \
  irssi \
  jq \
  kubectl \
  libanyevent-i3-perl \
  libnotify-bin \
  lldb \
  llvm \
  make \
  mlocate \
  mtr \
  net-tools \
  network-manager \
  ninja-build \
  ntfs-3g \
  open-vm-tools-dkms \
  parallel \
  parted \
  pkg-config \
  python \
  python-gflags \
  redshift \
  rsync \
  rxvt-unicode \
  screen \
  ssh \
  tcpdump \
  tmux \
  traceroute \
  vim \
  vim-gtk \
  vlc \
  wireshark \
  whois \
  xbacklight \
  xclip \
  xorg \
  xscreensaver \
  xscreensaver-data-extra \
  xterm \
  zip \
  zsh \
  ${more_pkgs} \
 || {
  x=$?
  echo "Package install failed with exit code: $x"
  exit $x
}

# Packages to soft-fail on
sudo apt-get -y install \
  bazel \
 || {
  echo "Package install failed with exit code: $?"
  echo "Continuing regardless..."
  sleep 5
}

sudo apt-get -y install \
  docker-engine \
  || {
  echo "Docker install exited with code $?"
  echo "Using less safe method..."
  curl -sSL https://get.docker.com | sh
  sleep 5
}

# Set default shell.
sudo chsh -s $(which zsh) $USER

# Manually install tmux, since the mainline repos aren't up-to-date.
TMUX_VNO="2.4"
if ! which tmux || ! vergte "$TMUX_VNO" "$(tmux -V)"
then
  sudo apt-get install libncurses5-dev
  LDIR="$(pwd)"
  TMUXTAR=/tmp/tmux.tar.gz
  sudo apt-get -y install libevent-dev \
    && curl -Lo $TMUXTAR https://github.com/tmux/tmux/archive/${TMUX_VNO}.tar.gz \
    && cd /tmp \
    && tar -xvf $TMUXTAR \
    && cd tmux-$TMUX_VNO \
    && sh autogen.sh \
    && ./configure \
    && make \
    && sudo make install \
    && sudo apt-get -y remove tmux \
    && rm -rf /tmp/tmux*
  cd $LDIR
fi

# Manually install Go, since the mainline repos aren't up-to-date.
GO_VERSION="1.9.2"
if (! which go && ! test -x /usr/local/go/bin/go) || \
  ! vergte "$GO_VERSION" "$(go version)"
then
  {
    GOTAR=/tmp/golang.tar.gz
    curl -o $GOTAR https://storage.googleapis.com/golang/go${GO_VERSION}.linux-amd64.tar.gz \
    && sudo apt-get remove golang-1.9 golang-1.8 golang-1.7 \
    && sudo rm -rf /usr/local/go \
    && sudo tar -C /usr/local -xzf $GOTAR \
    && rm $GOTAR
  } || {
    x=$?
    echo "Go tools install failed with exit code: $x"
    exit $x
  }
else
  echo "Go appears to be up to date."
fi

# Manually install Helm, since there aren't repositoried packages.
HELM_VERSION="2.7.2"
if ! which helm || ! vergte "$HELM_VERSION" "$(helm version -c --short)"
then
  {
    HELMTAR="/tmp/helm.tar.gz"
    curl -o "$HELMTAR" https://storage.googleapis.com/kubernetes-helm/helm-v${HELM_VERSION}-linux-amd64.tar.gz \
    && tar -C /tmp -zxvf $HELMTAR linux-amd64/helm \
    && sudo mv /tmp/linux-amd64/helm /usr/local/bin/helm \
    && helm init -c 
  } || {
    x=$?
    echo >&2 "Helm install failed with exit code: $x"
    exit $x
  }
fi

if ! which ctags
then
  # Manually install universal ctags
  LPUSHD="$(pwd)"
  cd /tmp/
  rm -rf ctags
  git clone git://github.com/universal-ctags/ctags \
    && cd ctags \
    && ./autogen.sh\
    && ./configure \
    && make \
    && sudo make install \
    && rm -rf /tmp/ctags \
    || {
    x=$?
    echo "Failed to install universal ctags!" 1>&2
    echo $x
  }

  cd "$LPUSHD"
fi

# Manually install rust via rustup.
# curl https://sh.rustup.sh -sSf | sh

# TODO: remote GUI tools

# One-time setup scripts... don't always run.
# $HOME/scripts/install-wallpapertab.sh

# echo "If you're going to use this with a Macbook, you probably want to look at:"
# echo "http://askubuntu.com/questions/530325/tilde-key-on-mac-air-with-ubuntu"

echo "All done! Reboot to finish up."

cd $PUSHD
