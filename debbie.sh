#! /bin/sh -x
# Set up a Debian / Ubuntu machine to my liking.
# Put it all in a single file, so that it can be curl'd.

# Header: pinned versions.
GO_VERSION="1.12.5"
TMUX_VNO="2.9a"
WEECHAT_VNO="2.4"
GETDOCKER="false"

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
getver() {
  echo -n "$@" | grep -o '[0-9][0-9a-z]*\.[0-9][0-9a-z]*\(\.[0-9][0-9a-z]*\)\?'
}

vergte() {
  lesser="$(echo -e "$(getver "$1")\n$(getver "$2")" | sort -V | head -n1)"
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

# Set Github public key.
mkdir -p ~/.ssh
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

# Always ask - we aren't checking for upgrades yet
if yesno "Install Docker?"
then
  GETDOCKER="true"
fi

if test "$ETCLONEHOME" = 'yes'
then
  echo "Cloning Tilde repository..."
  {
    git clone https://github.com/cceckman/Tilde.git 2>&1 || {
      x=$?
      echo "Failed to clone Tilde! Exiting unhappily.,"
      exit $x
    }
  } && {
    mv Tilde/.git . \
    && rm -rf Tilde \
    && git reset --hard \
    && git submodule update --recursive --init \
    && git remote set-url origin git@github.com:cceckman/Tilde.git
  } || {
    x=$?
    echo "Failed to load Tilde into \$HOME!"
    exit $x
  }
else
  echo "Skipping cloning Tilde..."
  touch $HOME/clone-skipped
fi

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
if $GETDOCKER
then
  curl -fsSL https://download.docker.com/linux/debian/gpg \
    | sudo apt-key add -v - 2>&1 \
    | grep 8D81803C0EBFCD88 \
    || {
      echo >&2 "bad key for Docker!"
      exit 1
    }
  echo "deb https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list

	# Docker group setup
	sudo groupadd docker
	sudo gpasswd -a ${USER} docker

	sudo apt-get update
fi

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
sudo apt-get \
  --no-install-recommends \
  -y install \
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
  fonts-powerline \
  fping \
  gdb \
  google-cloud-sdk \
  graphviz \
  i3 \
  i3status \
  ipcalc \
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
  ntfs-3g \
  parallel \
  parted \
  pcscd \
  pkg-config \
  python \
  python-gflags \
  python3 \
  python3-pip \
  redshift \
  rsync \
  ssh \
  scdaemon \
  tcpdump \
  traceroute \
  vim \
  vim-gtk \
  whois \
  wireshark \
  xbacklight \
  xclip \
  xorg \
  xscreensaver \
  xscreensaver-data-extra \
  xss-lock \
  xterm \
  yubikey-personalization \
  zip \
  zsh \
  ${more_pkgs} \
 || {
  x=$?
  echo "Package install failed with exit code: $x"
  exit $x
}

{
  pip3 install wheel setuptools pyyaml pathspec yamllint;
} || {
  x=$?
  echo "Could not install yamllint"
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

if $GETDOCKER
then
  sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
	sudo apt-get -y install docker-ce docker-ce-cli containerd.io
fi

# Set default shell.
sudo chsh -s $(which zsh) $USER

# Manually install tmux, since the mainline repos aren't up-to-date.
if ! which tmux || ! vergte "$TMUX_VNO" "$(tmux -V)"
then
  set -e
  sudo apt-get install libncurses5-dev automake
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
  set +e
fi

# Manually install weechat, likewise.
if ! which weechat || ! vergte "$VNO" "$(weechat --version)"
then
  set -e
  LDIR="$(pwd)"
  WCTAR=/tmp/weechat.tar.gz
  sudo apt-get remove weechat
  rm -rf /tmp/build /tmp/weechat-*
  sudo apt-get build-dep -y weechat \
    && curl -Lo $WCTAR "https://github.com/weechat/weechat/archive/v${WEECHAT_VNO}.tar.gz" \
    && cd /tmp \
    && tar -xvf $WCTAR \
    && cd weechat-${WEECAT_VNO}* \
    && mkdir build \
    && cd build \
    && cmake .. \
    && make \
    && sudo make install
  cd $LDIR
  set +e
fi

# Manually install Go, since the mainline repos aren't up-to-date.
if (! which go && ! test -x /usr/local/go/bin/go) || \
  ! vergte "$GO_VERSION" "$(go version)"
then
  {
    echo "updating Go from $(getver "$(go version)") to $GO_VERSION"
    GOTAR=/tmp/golang.tar.gz
    curl -o $GOTAR https://storage.googleapis.com/golang/go${GO_VERSION}.linux-amd64.tar.gz \
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

# Go get go tools
go get -u github.com/alecthomas/gometalinter
go get -u github.com/bazelbuild/buildtools/buildifier
go get -u github.com/derekparker/delve/cmd/dlv
go get -u github.com/github/hub

eval $(go env)
if ! which ibazel && test -n "$GOPATH"
then
  # Manually install ibazel
  LPUSHD="$(pwd)"
  cd /tmp
  rm -rf ibazel
  git clone git://github.com/bazelbuild/bazel-watcher ibazel
  cd ibazel
  bazel build //ibazel
  cp $PWD/bazel-bin/ibazel/${GOOS}_${GOARCH}_pure_stripped/ibazel $GOPATH/bin
fi

if ! which ctags
then
  set -e
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
  set +e
fi

curl -Lo- \
  https://raw.githubusercontent.com/cceckman/debbie/master/pubkeys.pgp \
  | gpg --import
# Related to GPG agent forwarding: unbind sockets when client disconnects
SLBU="StreamLocalBindUnlink yes"
if ! test -f /etc/ssh/sshd_config || ! grep "$SLBU" /etc/ssh/sshd_config
then
  echo "$SLBU" | sudo tee -a /etc/ssh/sshd_config
fi

# Manually install rust via rustup.
# curl https://sh.rustup.sh -sSf | sh

# Manually install http://tldr.sh client
# Pinning the version by content SHA, so we'll error if there's an update.
curl -Lo ~/scripts/tldr https://raw.githubusercontent.com/raylee/tldr/master/tldr
if ! test "$(sha256sum ~/scripts/tldr | cut -d' ' -f1)" = "33ff4b7c0680e85157b3020882ef8b51eabbe5adccf7059cc4df3a5e03946833"
then
  echo >&2 "Unexpected contents for ~/scripts/tldr"
  echo >&2 "Check it out, and update debbie.sh if it's OK."
  exit 1
fi
chmod +x ~/scripts/tldr

# echo "If you're going to use this with a Macbook, you probably want to look at:"
# echo "http://askubuntu.com/questions/530325/tilde-key-on-mac-air-with-ubuntu"

# Create undo, swap directories for Vim, to keep non-save changes out of the
# working directory
mkdir -p .vim/swap .vim/undo

# Trigger GoInstallBinaries in Vim
echo "nothing"  | vim -c ":GoInstallBinaries"
echo "All done! Log in or reboot to finish up."
cd $PUSHD
