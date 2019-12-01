#! /bin/bash -eu
# Set up a Debian / Ubuntu machine to my liking.
# Put it all in a single file, so that it can be curl'd.


## OUTLINE
# debbie defines a set of "features" that we may / may not want to run.
# Each "feature" ties in to "stages", which are:
# - Install dependencies (including Apt repositories)
# - Install & update pre-built binaries
# - Test and/or build pinned software (i.e. stuff that's built from source)
#
# All the available functions go into stage tables,
#   PREPARE[$feature], INSTALL[$feature], and BUILD[$feature].
# Usually the function in the table will be something like debbie::${feature}::${stage},
# but some share implementations (e.g. util::noop).
#
# Features can be toggled on and off by +feature -feature on the command line.

declare -A PREPARE
declare -A INSTALL
declare -A BUILD
export PREPARE INSTALL BUILD

DEFAULT_FEATURES="+core +home +tmux +tldr +graphical +redo"

util::all_features() {
  for feature in "${!PREPARE[@]}"
  do
    if test "$feature" == "prestage"
    then
      continue
    fi
    echo -n "${feature} "
  done
}

util::help() {
  cat <<EOF
$1: bootstrap a system to cceckman's liking

  debbie.sh is a (Bash) shell script that configures a Debian system with stuff
  @cceckman finds useful.

  It contains a number of "features", which can be toggled on or off with
  arguments like "+feature" or "-feature". The default options are given below;
  feature names are (mostly) self-describing.

Default features:
  $DEFAULT_FEATURES

Available features:
  $(util::all_features)
EOF
  exit -1
}

main() {
  local INPUT_FEATURES="$DEFAULT_FEATURES $*"
  declare -a FEATURES
  FEATURES=(prestage)

  local ERR="false"
  for flag in $INPUT_FEATURES
  do
    local tag="${flag:0:1}"
    local feature="${flag:1}"

    # Special cases first:
    case "$flag" in
      '+all')
        for feature in $(util::all_features);
        do
          for existing_feature in "${FEATURES[@]}"
          do
            if test "$existing_feature" = "$feature"
            then
              continue 2
            fi
          done
          FEATURES+=("$feature")
        done
        continue
        ;;
      '-all') FEATURES=(prestage); continue;;
      *help) util::help "$0";;
    esac

    case "$tag" in
      '+') for existing_feature in "${FEATURES[@]}"
           do
             if test "$existing_feature" = "$feature"
             then
               continue 2
             fi
           done
           FEATURES+=("$feature")
           ;;
      '-') declare -a newFeatures
           for existing_feature in "${FEATURES[@]}"
           do
             if test "$existing_feature" != "$feature"
             then
               newFeatures+=("$existing_feature")
             fi
           done
           FEATURES=("${newFeatures[@]}")
           ;;
        *) echo >&2 "Unrecognized operation $tag in $flag; must be '+' or '-'"
           ERR="true"
           ;;
    esac
  done

  for feature in "${FEATURES[@]}"
  do
    # We can't loop through here because treating it like a nested array goes poorly.
    if ! test "$(type -t "${PREPARE[$feature]}")" == "function"
    then
      ERR="true"
      echo >&2 "Unknown stage/feature combination: 'PREPARE ${feature}'"
    fi
    if ! test "$(type -t "${INSTALL[$feature]}")" == "function"
    then
      ERR="true"
      echo >&2 "Unknown stage/feature combination: 'INSTALL ${feature}'"
    fi
    if ! test "$(type -t "${BUILD[$feature]}")" == "function"
    then
      ERR="true"
      echo >&2 "Unknown stage/feature combination: 'BUILD ${feature}'"
    fi
  done
  if "$ERR"; then exit 1; fi

  # Some features have interdependencies, e.g. bazel depends on go.
  # TODO: Remove the interdependencies, or enforce them.

  # We've validated that each feature & stage exists.
  # Do some general checking:
  util::preflight
  # and run each stage.
  for feature in "${FEATURES[@]}"
  do
    echo "Preparing $feature..."
    "${PREPARE[$feature]}"
  done
  for feature in "${FEATURES[@]}"
  do
    echo "Installing $feature..."
    "${INSTALL[$feature]}"
  done
  for feature in "${FEATURES[@]}"
  do
    echo "Building $feature..."
    "${BUILD[$feature]}"
  done
  echo "All done!"
}

# Some preflight checks that should run before any module.
util::preflight() {
  for tool in sudo apt-get
  do
    if ! command -v "$tool" >/dev/null
    then
      echo >&2 "Could not find required tool $tool"
      exit 1
    fi
  done

  if [ "$USER" = "root" ]
  then
    echo >&2 "Don't run this as root!"
    echo >&2 "Just run as yourself; debbie will ask for sudo permission when needed."
    exit 1
  else
    echo "Prompting for sudo mode..."
    sudo true
  fi
}
util::getver() {
  echo -n "$@" | grep -o '[0-9][0-9a-z]*\.[0-9][0-9a-z]*\(\.[0-9][0-9a-z]*\)\?'
}

util::vergte() {
  lesser="$(echo -e "$(util::getver "$1")\\n$(util::getver "$2")" | sort -V | head -n1)"
  [ "$1" = "$lesser" ]
}
util::noop() {
  return
}

util::install_packages() {
  sudo \
    DEBIAN_FRONTEND=noninteractive \
    apt-get -yq --no-install-recommends \
    install "$@"
}

## prestage
debbie::prestage::prepare() {
  # "prepare" steps are usually installing new repositories.
  # Make sure there's a directory to install into.
  if ! test -d /etc/apt/sources.list.d
  then
    mkdir -m 0755 /etc/apt/sources.list.d
  fi
  # And make sure they can get the right release & keys when adding
  # the repositories.
  # They can rely on https://pubs.opengroup.org/onlinepubs/9699919799/idx/utilities.html
  # (e.g. `tee`, `grep`), `apt` (assume Debian), and `sudo` (assume it's installed),
  # but these are still needed.
  sudo apt-get install -y lsb-release curl gnupg2
}
debbie::prestage::install() {
  sudo apt-get update
  sudo apt-get upgrade -y
}
PREPARE[prestage]=debbie::prestage::prepare
INSTALL[prestage]=debbie::prestage::install
BUILD[prestage]=util::noop

## core
debbie::core::install() {
  util::install_packages \
    locales \
    git \
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
    fping \
    gdb \
    graphviz \
    ipcalc \
    jq \
    libnotify-bin \
    lldb \
    llvm \
    make \
    mlocate \
    mtr \
    net-tools \
    netcat \
    ntfs-3g \
    parallel \
    parted \
    pcscd \
    pkg-config \
    psmisc \
    python \
    python-gflags \
    python3 \
    python3-pip \
    rsync \
    socat \
    ssh \
    tcpdump \
    traceroute \
    vim \
    whois \
    zip \
    zsh

  # PIP packages as well
  python3 -m pip install --user wheel setuptools
  python3 -m pip install --user pyyaml pathspec yamllint
}

debbie::core::build() {
  # Set locale to US
  if ! locale | grep -q 'LANG=en_US.UTF-8'
  then
    # Set locale to US.
    sudo sed -i -e 's/^[^#]/# \0/' -e 's/^.*\(en_US.UTF-8\)/\1/' /etc/locale.gen
    sudo /usr/sbin/locale-gen
  fi
}
PREPARE[core]=util::noop
INSTALL[core]=debbie::core::install
BUILD[core]=debbie::core::build

## graphical
debbie::graphical::install() {
  util::install_packages \
    chromium \
    feh \
    fonts-powerline \
    i3 \
    i3status \
    konsole \
    libanyevent-i3-perl \
    redshift \
    scdaemon \
    vim-gtk \
    wireshark \
    xbacklight \
    xclip \
    xorg \
    xscreensaver \
    xscreensaver-data-extra \
    xss-lock \
    xterm \
    yubikey-personalization

  debbie::graphical::install::firacode
}

### Firacode helper for graphical target;
### Once de6dde848269fdd6360e5e7dce4874ce62fbed7f makes it into the prebuilt changes
### we can do a much lighter-weight install.
debbie::graphical::install::firacode() {
  if fc-list | grep -q 'Fira Code'
  then
    echo "Fira code already installed, skipping build..."
    return
  fi

  fonts_dir="${HOME}/.local/share/fonts"
  mkdir -p "$fonts_dir"
  pushd "$fonts_dir"
  for type in Bold Light Medium Regular Retina; do
    curl -LO "https://github.com/cceckman/FiraCode/raw/master/distr/ttf/FiraCode-${type}.ttf"
  done
  popd
  fc-cache -f
}

PREPARE[graphical]=util::noop
INSTALL[graphical]=debbie::graphical::install
BUILD[graphical]=util::noop

## home
debbie::home::install() {
  pushd "$HOME"
  {
    if ! test -d ".git"
    then
      git clone https://github.com/cceckman/Tilde.git
      mv Tilde/.git .
      rm -rf Tilde
      git reset --hard
      git submodule update --recursive --init
    fi

    if test "$(git remote get-url origin)" = "https://github.com/cceckman/Tilde.git"
    then
      git remote set-url origin git@github.com:cceckman/Tilde.git
    fi
  }
  popd
}

debbie::home::build() {
  # Use `sudo` so it doesn't prompt to enter $USER's password againa
  sudo chsh -s "$(command -v zsh)" "$USER"
  # Get public key used for signing.
  curl -Lo- \
    https://raw.githubusercontent.com/cceckman/debbie/master/pubkeys.pgp \
    | gpg --import
  # Create undo & swap Vim directories, to keep tem out of the working dirs
  mkdir -p "$HOME/.vim/swap" "$HOME/.vim/undo"
}

PREPARE[home]=util::noop
INSTALL[home]=debbie::home::install
BUILD[home]=debbie::home::build

## gcloud
debbie::gcloud::prepare() {
  if ! grep -Rq "packages.cloud.google.com" /etc/apt/sources.list /etc/apt/sources.list.d
  then
    CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -cs)"
    echo "deb https://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
  fi
}

debbie::gcloud::install() {
  util::install_packages google-cloud-sdk kubectl google-cloud-sdk-app-engine-go
}

PREPARE[gcloud]=debbie::gcloud::prepare
INSTALL[gcloud]=debbie::gcloud::install
BUILD[gcloud]=util::noop

## docker
debbie::docker::prepare() {
  if ! grep -Rq "download.docker.com" /etc/apt/sources.list /etc/apt/sources.list.d
  then
    curl -fsSL https://download.docker.com/linux/debian/gpg \
    | sudo apt-key add -v - 2>&1 \
    | grep 8D81803C0EBFCD88 \
    || {
      echo >&2 "Bad key for Docker!"
      exit 1
    }
    echo "deb https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list
  fi
}

debbie::docker::install() {
  util::install_packages docker-ce docker-ce-cli containerd.io
}

debbie::docker::build() {
  sudo groupadd -f docker
  sudo gpasswd -a "$USER" docker
}

PREPARE[docker]=debbie::docker::prepare
INSTALL[docker]=debbie::docker::install
BUILD[docker]=debbie::docker::build

## bazel
debbie::bazel::prepare() {
  if ! grep -Rq "https://storage.googleapis.com/bazel-apt" /etc/apt/sources.list /etc/apt/sources.list.d
  then
    echo "deb https://storage.googleapis.com/bazel-apt stable jdk1.8" | sudo tee /etc/apt/sources.list.d/bazel.list
    # TODO: Add utils:: to align with docker, gcloud; verify key
    curl https://storage.googleapis.com/bazel-apt/doc/apt-key.pub.gpg | sudo apt-key add  -
  fi
}
debbie::bazel::install() {
  util::install_packages bazel
}
debbie::bazel::build() {
  set -x
  go get -u github.com/bazelbuild/buildtools/buildifier
  set +x

  IBAZEL_VNO="0.10.2"
  if command -v ibazel >/dev/null && util::vergte "$IBAZEL_VNO" "$(ibazel 2>&1 | head -1 | grep -o '[^v]*$')"
  then
    return
  fi
  # Manual install of ibazel
  mkdir -p "$HOME/bin"
  pushd /tmp
  {
    rm -rf ibazel
    git clone git://github.com/bazelbuild/bazel-watcher ibazel
    cd ibazel
    bazel build //ibazel
    cp bazel-bin/ibazel/*_pure_stripped/ibazel "$HOME/bin/ibazel"
    chmod 0744 "$HOME/bin/ibazel" # allow later rewriting, e.g. upgrade
  }
  popd
}
PREPARE[bazel]=debbie::bazel::prepare
INSTALL[bazel]=debbie::bazel::install
BUILD[bazel]=debbie::bazel::build

## tmux
debbie::tmux::build() {
  TMUX_VNO="2.9a"
  if command -v tmux >/dev/null && util::vergte "$TMUX_VNO" "$(tmux -V)"
  then
    echo "Have tmux $(tmux -V), skipping build"
    return
  fi
  echo "Building & installing tmux $TMUX_VNO"
  pushd /tmp
  {
    # Build dependencies; should be apt-get build-dep tmux
    sudo apt-get -y install libncurses5-dev automake libevent-dev
    TMUXTAR=/tmp/tmux.tar.gz
    curl -Lo $TMUXTAR https://github.com/tmux/tmux/archive/${TMUX_VNO}.tar.gz
    tar -xvf $TMUXTAR
    cd tmux-$TMUX_VNO
    sh autogen.sh
    ./configure
    make
    sudo make install
    sudo apt-get -y remove tmux
    rm -rf /tmp/tmux*
  }
  popd
}
PREPARE[tmux]=util::noop
INSTALL[tmux]=util::noop
BUILD[tmux]=debbie::tmux::build

## golang
debbie::golang::install() {
  util::install_packages vim git

  GO_VNO="1.13.4"

  # We don't early-exit here so that we run :GoInstallBinaries at the end
  if ! (command -v go >/dev/null && util::vergte "$GO_VNO" "$(go version)")
  then
    declare -A GOARCH
    GOARCH[x86_64]="amd64"
    GOTAR=/tmp/golang.tar.gz
    curl -o "$GOTAR" "https://storage.googleapis.com/golang/go${GO_VNO}.linux-${GOARCH[$(uname -m)]}.tar.gz"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "$GOTAR"
    rm "$GOTAR"
    export PATH="/usr/local/go/bin:$PATH"
  else
    echo "Have $(go version), skipping build"
  fi

  vim "+silent GoInstallBinaries" +qall >/dev/null </dev/null
}
debbie::golang::build() {
  # Collect tools for use with Go.
  set -x
  go get -u github.com/derekparker/delve/cmd/dlv
  go get -u github.com/github/hub
  set +x
}
PREPARE[golang]=util::noop
INSTALL[golang]=debbie::golang::install
BUILD[golang]=debbie::golang::build

## ssh-target
debbie::ssh-target::install() {
  util::install_packages openssh-server
}
debbie::ssh-target::build() {
  # Important for useful GPG agent forwarding:
  # Unbind sockets when client disconnects
  SLBU="StreamLocalBindUnlink yes"
  if ! test -f /etc/ssh/sshd_config || ! grep -q "$SLBU" /etc/ssh/sshd_config
  then
    echo "$SLBU" | sudo tee -a /etc/ssh/sshd_config >/dev/null
  fi
}

PREPARE[ssh-target]=util::noop
INSTALL[ssh-target]=debbie::ssh-target::install
BUILD[ssh-target]=debbie::ssh-target::build

## tldr
debbie::tldr::install() {
  # Pinning the version by content SHA, so we'll error if there's an update we don't know of.
  curl -Lo ~/scripts/tldr https://raw.githubusercontent.com/raylee/tldr/master/tldr
  if ! test "$(sha256sum ~/scripts/tldr | cut -d' ' -f1)" = "33ff4b7c0680e85157b3020882ef8b51eabbe5adccf7059cc4df3a5e03946833"
  then
    echo >&2 "Unexpected contents for ~/scripts/tldr"
    echo >&2 "Check it out, and update debbie.sh if it's OK."
    exit 1
  fi
  chmod +x ~/scripts/tldr
}
PREPARE[tldr]=util::noop
INSTALL[tldr]=debbie::tldr::install
BUILD[tldr]=util::noop

## rust
debbie::rust::install() {
  # There are cargo and rustc packages,
  # but we need access to nightly and src in order to xbuild.
  pushd /tmp
  {
    curl https://sh.rustup.rs -sSf -o rustup.sh
    if ! test "$(sha256sum rustup.sh | cut -d' ' -f1)" = "5b4b37114fe25215224fb53b6a635b59d01a0377c5e9e4d6b553035ec695cdd3"
    then
      echo >&2 "Unexpected contents for /tmp/rustup.sh"
      echo >&2 "Check it out, and update debbie.sh if it's OK."
      exit 1
    fi
    chmod +x rustup.sh
    ./rustup.sh -y --no-modify-path
    PATH="$HOME/.cargo/bin:$PATH"
    rustup component add rustfmt
  }
  popd
}
PREPARE[rust]=util::noop
INSTALL[rust]=debbie::rust::install
BUILD[rust]=util::noop

## fomu tools
# The binaries in https://github.com/im-tomu/fomu-toolchain are gonna be
# all in the same, not-really-right place. Install / build from source instead.
debbie::fomu::install() {
  # I'd like to build "hotter", i.e. from upstream, but we'll do this for now.
  FOMU_VNO="1.4"
  FOMU_HASH="3799925468b163b9da50e531cf75549109dcbf9b8243e220497c04d9e33dd482"
  mkdir -p "$HOME/bin"
  pushd /tmp
  if ! test "$(cat "$HOME/bin/fomu-toolchain/.installed")" = "$FOMU_HASH"
  then
    local FILE="fomu-toolchain.tar.gz"
    local WORDY="fomu-toolchain-linux_x86_64-v${FOMU_VNO}"
    curl -Lo "$FILE" \
      "https://github.com/im-tomu/fomu-toolchain/releases/download/v${FOMU_VNO}/${WORDY}.tar.gz"
    test "$FOMU_HASH" = "$(sha256sum "$FILE" | cut -d' ' -f1)"
    tar -xf "$FILE"
    rm -rf "$HOME/bin/fomu-toolchain"
    mv "${WORDY}" "$HOME/bin/fomu-toolchain"
    echo "$FOMU_HASH" >"$HOME/bin/fomu-toolchain/.installed"
  fi
  # Ensure we have permissions:
  {
    sudo groupadd plugdev || true
    sudo usermod -a -G plugdev "$USER" || true
    local UDEV="/etc/udev/rules.d/99-fomu.rules"
    cat >/tmp/fomu-udev-rules <<HRD
SUBSYSTEM=="usb", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="5bf0", MODE="0664", GROUP="plugdev"
HRD

    if ! { test -e "$UDEV" && test "$(cat /tmp/fomu-udev-rules)" = "$(cat "$UDEV")" ; }
    then
      # This is an OK cat! shellcheck complains about it either way!
      # shellcheck disable=SC2002
      cat /tmp/fomu-udev-rules | sudo tee  "$UDEV"
      sudo udevadm control --reload-rules
      sudo udevadm trigger
    fi
  }

  popd
}
# Disabled per issue #10
# PREPARE[fomu]=util::noop
# INSTALL[fomu]=debbie::fomu::install
# BUILD[fomu]=util::noop

debbie::redo::install() {
  util::install_packages \
    python2.7 \
    python-setproctitle
}
debbie::redo::build(){
  local version="0.42"
  if command -v redo && test "$(redo --version)" = "$version"
  then
    return 0
  fi
  pushd /tmp
  {
    git clone https://github.com/apenwarr/redo.git \
      --branch "redo-${version}" \
      --depth=1 \
      --single-branch
    cd redo
    ./do -j"$(nproc)" test
    # Instructions don't have -E, "preserve environment",
    # but it looks like it's necessary.
    DESTDIR='' PREFIX=/usr/local sudo -E ./do install
  }
  popd
}

PREPARE[redo]=util::noop
INSTALL[redo]=debbie::redo::install
BUILD[redo]=debbie::redo::build


## TODO: LSPs
## TODO: ctags? Removed because of the above TODO; LSPs are the new thing.
## TODO: SSH keys? I'm doing more that's rooted in one set, but there's some advice around that says I shouldn't.

main "$@"
