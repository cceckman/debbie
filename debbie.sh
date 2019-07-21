#! /bin/bash -x
# Set up a Debian / Ubuntu machine to my liking.
# Put it all in a single file, so that it can be curl'd.

# Header: pinned versions.
GO_VERSION="1.12.6"
TMUX_VNO="2.9a"
WEECHAT_VNO="2.5"
IBAZEL_VNO="0.10.2"
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

  read -r result
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

pushd "$HOME"

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
  if ! which "$tool"
  then
    echo "Could not find $tool! Aborting."
    exit 1
  fi
done

# Ask all questions up-front.
# Set up SSH credentials, incl. for Github.
NEWKEYS="false"
if yesno "Generate new SSH credentials?"
then
  NEWKEYS="true"
fi

# Clone Tilde.
ETCLONEHOME="true"
if test -d "$HOME/.git"
then
  ETCLONEHOME="false"
  if yesno "Found $HOME/.git. Clone Tilde anyway?"
  then
    ETCLONEHOME="true"
  fi
fi

# Always ask - we aren't checking for upgrades yet
if yesno "Install Docker?"
then
  GETDOCKER="true"
fi

# Indirect dependencies
sudo apt-get install -y locales git apt-transport-https

if ! locale | grep 'LANG=en_US.UTF-8'
then
  # Set locale to US.
  sudo sed -i -e 's/^[^#]/# \0/' -e 's/^.*\(en_US.UTF-8\)/\1/' /etc/locale.gen
  sudo /usr/sbin/locale-gen
fi

if "$NEWKEYS"
then
  echo "Generating new SSH credentials..."
  ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -C "$USER $(hostname)" -o -a 100
  ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -C "$USER $(hostname)" -o -a 100

  # Attempt to POST to github.
  keyreq='/tmp/keyreq'
  cat - << HRD > $keyreq
{
  "title": "$USER@$(hostname)",
  "key": "$(cat "$HOME/.ssh/id_rsa.pub")"
}
HRD
  while true
  do
    prompt "Enter a Github authentication token for ${USER}:"
    read -r token

    {
      curl --fail \
        -X POST \
        --data-binary @"$keyreq" \
        -u "${USER}:${token}" \
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
if grep -v "^github.com" "$HOME/.ssh/known_hosts"
then
  echo "github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ=="  >> "$HOME/.ssh/known_hosts"
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
  touch "$HOME/clone-skipped"
fi

# Add some custom repositories
# Bazel
echo "deb [arch=amd64] https://storage.googleapis.com/bazel-apt stable jdk1.8" | sudo tee /etc/apt/sources.list.d/bazel.list

curl https://storage.googleapis.com/bazel-apt/doc/apt-key.pub.gpg | sudo apt-key add  -

# GCloud
if ! test -e /etc/apt/sources.list.d/google-cloud*.list
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
	sudo gpasswd -a "$USER" docker
fi

# Update && upgrade now that we've added repositories
sudo apt-get update
sudo apt-get upgrade

# Packages that are different on Debian vs. Ubuntu.
more_pkgs=''
case "$(uname -v)" in
  *Ubuntu*)
    more_pkgs='chromium-browser'
    ;;
  *Debian*)
    more_pkgs='chromium'
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
sudo chsh -s "$(which zsh)" "$USER"

# Manually install tmux, since the mainline repos aren't up-to-date.
if ! which tmux || ! vergte "$TMUX_VNO" "$(tmux -V)"
then
  echo "Building & installing tmux $TMUX_VNO"
  pushd /tmp
  sudo apt-get install libncurses5-dev automake
  TMUXTAR=/tmp/tmux.tar.gz
  sudo apt-get -y install libevent-dev \
    && curl -Lo $TMUXTAR https://github.com/tmux/tmux/archive/${TMUX_VNO}.tar.gz \
    && tar -xvf $TMUXTAR \
    && cd tmux-$TMUX_VNO \
    && sh autogen.sh \
    && ./configure \
    && make \
    && sudo make install \
    && sudo apt-get -y remove tmux \
    && rm -rf /tmp/tmux*
  set +e
  popd
fi

# Manually install weechat, likewise.
if ! which weechat || ! vergte "$WEECHAT_VNO" "$(weechat --version)"
then
  echo "Building & installing weechat $WEECHAT_VNO"
  pushd /tmp/
  set -e
  WCTAR=/tmp/weechat.tar.gz
  sudo apt-get remove weechat
  rm -rf /tmp/build /tmp/weechat-*
  sudo apt-get build-dep -y weechat \
    && curl -Lo $WCTAR "https://github.com/weechat/weechat/archive/v${WEECHAT_VNO}.tar.gz" \
    && tar -xvf $WCTAR \
    && cd weechat-${WEECHAT_VNO}* \
    && mkdir build \
    && cd build \
    && cmake .. \
    && make \
    && sudo make install
  set +e
  popd
fi

# Manually install Go, since the mainline repos aren't usually up-to-date.
if ! which go || ! vergte "$GO_VERSION" "$(go version)"
then
  {
    echo "updating Go from $(getver "$(go version)") to $GO_VERSION"
    GOTAR=/tmp/golang.tar.gz
    curl -o "$GOTAR" https://storage.googleapis.com/golang/go${GO_VERSION}.linux-amd64.tar.gz \
    && sudo rm -rf /usr/local/go \
    && sudo tar -C /usr/local -xzf $GOTAR \
    && rm $GOTAR
  } || {
    x=$?
    echo "Go tools install failed with exit code: $x"
    exit $x
  }

  if ! vergte "$GO_VERSION" "$(go version)"
  then
    echo >&2 "Unexpected Go version: $(go version) from $(which go)"
    echo >&2 "Check install path, and maybe uninstall the Golang package"
    exit 1
  fi
else
  echo "Go appears to be up to date."
fi

# Go get go tools
go get -u github.com/alecthomas/gometalinter
go get -u github.com/bazelbuild/buildtools/buildifier
go get -u github.com/derekparker/delve/cmd/dlv
go get -u github.com/github/hub

# shellcheck disable=SC2046
if ! which ibazel || ! vergte "$IBAZEL_VNO" "$(ibazel 2>&1 | head -1 grep -o '[^v]*$')"
then
  # Manually install ibazel
  mkdir -p "$HOME/bin"
  pushd /tmp
  set -e
  rm -rf ibazel
  git clone git://github.com/bazelbuild/bazel-watcher ibazel
  cd ibazel
  bazel build //ibazel
  cp bazel-bin/ibazel/*_pure_stripped/ibazel "$HOME/bin"
  set +e
  popd
fi

if ! which ctags
then
  pushd /tmp
  # Manually install universal ctags. This is a little sketchy- they don't
  # actually build releases. TODO(cceckman): Move to LSP at some point(s).
  cd /tmp/
  rm -rf ctags
  { git clone git://github.com/universal-ctags/ctags \
    && cd ctags \
    && ./autogen.sh\
    && ./configure \
    && make \
    && sudo make install \
    && rm -rf /tmp/ctags
  } || {
    x=$?
    echo "Failed to install universal ctags!" 1>&2
    echo $x
  }
  set +e
  popd
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
popd
