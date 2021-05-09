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
declare -A FEATURES
export PREPARE INSTALL BUILD FEATURES

DEFAULT_FEATURES="+update +core +build +home +tmux"

util::all_features() {
  for feature in "${!PREPARE[@]}"
  do
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
  FEATURES=()

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
      '-all') FEATURES=(); continue;;
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

## update
debbie::update::prepare() {
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
  util::install_packages lsb-release curl gnupg2
}
debbie::update::install() {
  sudo apt-get update
  sudo apt-get upgrade -y
}
PREPARE[update]=debbie::update::prepare
INSTALL[update]=debbie::update::install
BUILD[update]=util::noop

## core:
## I want these packages everywhere, including on lightweight/temp remotes.
debbie::core::install() {
  util::install_packages \
    arping \
    bash \
    bc \
    dnsutils \
    fping \
    git \
    htop \
    ipcalc \
    locales \
    mtr \
    net-tools \
    netcat \
    psmisc \
    python3 \
    rsync \
    socat \
    ssh \
    tcpdump \
    traceroute \
    vim \
    whois \
    zip unzip \
    zsh
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

## build: packages used to build / debug other things
debbie::build::prepare() {
  # Use LLVM project's repos for Clang, to stay up to date
  # https://apt.llvm.org/

  cat <<SOURCES | sudo tee /etc/apt/sources.list.d/llvm.list
# 11
deb http://apt.llvm.org/buster/ llvm-toolchain-buster-11 main
deb-src http://apt.llvm.org/buster/ llvm-toolchain-buster-11 main
# 12
deb http://apt.llvm.org/buster/ llvm-toolchain-buster-12 main
deb-src http://apt.llvm.org/buster/ llvm-toolchain-buster-12 main

SOURCES
  curl -Lo- https://apt.llvm.org/llvm-snapshot.gpg.key|sudo apt-key add -
  sudo apt-get update
}

debbie::build::install() {
  util::install_packages \
    autoconf \
    cgmanager \
    clang \
    clang \
    clang-format \
    clang-tidy \
    devscripts \
    dosfstools \
    gdb \
    graphviz \
    jq \
    libclang-dev \
    libnotify-bin \
    lld \
    llvm \
    make \
    manpages-dev \
    mlocate \
    ntfs-3g \
    parallel \
    parted \
    pcscd \
    pkg-config \
    python3-pip \
    sbuild \
    software-properties-common \

  # PIP packages as well
  python3 -m pip install --user wheel setuptools
  python3 -m pip install --user pyyaml pathspec yamllint

}

PREPARE[build]=debbie::build::prepare
INSTALL[build]=debbie::build::install
BUILD[build]=util::noop

## graphical
debbie::graphical::install() {
  util::install_packages \
    chromium \
    chromium-sandbox \
    cmatrix \
    curl \
    i3 \
    i3status \
    konsole \
    libanyevent-i3-perl \
    redshift \
    scdaemon \
    unzip \
    vim-gtk \
    wireshark \
    xbacklight \
    xclip \
    xorg \
    xss-lock \
    xterm \
    yubikey-personalization

  debbie::graphical::install::firacode
}

### Firacode helper for graphical target.
debbie::graphical::install::firacode() {
  FIRA_VNO="5.2"

  # Check presence...
  if FONT=$(fc-list | grep -o '[^ ]*FiraCode-Regular.ttf')
  then
    # Check version.
    FONTVERSION="$(fc-query -f '%{fontversion}' $FONT)"
    # Convert fixed-point to string float
    FONTVERSION="$(echo "scale=3; $FONTVERSION / 65536.0" | bc)"
    # Convert fixed-point to a string expression
    ISGTE="$(echo "scale=3; $FONTVERSION >= $FIRA_VNO" | bc)"
    if test "$ISGTE" -eq 1
    then
      echo "No update needed to Fira Code"
      echo "(version $FONTVERSION >= $FIRA_VNO)"
      return
    fi
  fi

  fonts_dir="${HOME}/.local/share/fonts"
  mkdir -p "$fonts_dir"
  TDIR="$(mktemp -d)"
  curl -Lo "$TDIR/firacode.zip" \
    "https://github.com/tonsky/FiraCode/releases/download/$FIRA_VNO/Fira_Code_v${FIRA_VNO}.zip"
  unzip "$TDIR/firacode.zip" -d "$TDIR" 'ttf/*.ttf'
  mv -f "$TDIR"/ttf/*.ttf "$fonts_dir"
  rm -rf "$TDIR"

  fc-cache -f
}

PREPARE[graphical]=util::noop
INSTALL[graphical]=debbie::graphical::install
BUILD[graphical]=util::noop

## displaymanager
## A lower-level than graphical; e.g. starting from minbase.
debbie::displaymanager::prepare() {
  cat <<SRC | sudo tee /etc/apt/sources.list.d/deb-nonfree.list
deb http://deb.debian.org/debian buster non-free contrib
deb-src http://deb.debian.org/debian buster non-free contrib
SRC

}

debbie::displaymanager::install() {
  util::install_packages \
    lightdm \
    nvidia-driver \
    linux-headers-$(uname -r)
}

PREPARE[displaymanager]=debbie::displaymanager::prepare
INSTALL[displaymanager]=debbie::displaymanager::install
BUILD[displaymanager]=util::noop

## home
debbie::home::install() {
  util::install_packages git
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

    # Leave the pull URL as http, but set the push URL to SSH.
    # This allows us to continue to pull from a host without SSH keys for the remote.
    if test "$(git remote get-url --push origin)" = "https://github.com/cceckman/Tilde.git"
    then
      git remote set-url --push origin git@github.com:cceckman/Tilde.git
    fi
  }
  popd
}

debbie::home::build() {
  # Use `sudo` so it doesn't prompt to enter $USER's password againa
  sudo chsh -s "$(command -v zsh)" "$USER"
  # Create undo & swap Vim directories, to keep tem out of the working dirs
  mkdir -p "$HOME/.vim/swap" "$HOME/.vim/undo"
}

PREPARE[home]=util::noop
INSTALL[home]=debbie::home::install
BUILD[home]=debbie::home::build

## gcloud
debbie::gcloud::prepare() {
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -

  sudo apt-get update
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
  # TODO: Add utils:: to align with docker, gcloud; verify key
  if ! grep -Rq "https://storage.googleapis.com/bazel-apt" /etc/apt/sources.list /etc/apt/sources.list.d
  then
    echo "deb https://storage.googleapis.com/bazel-apt stable jdk1.8" | sudo tee /etc/apt/sources.list.d/bazel.list
    curl https://bazel.build/bazel-release.pub.gpg | sudo apt-key add  -
  fi
  sudo apt-get update
}
debbie::bazel::install() {
  util::install_packages bazel
}
debbie::bazel::build() {
  set -x
  go get -u github.com/bazelbuild/buildtools/buildifier
  set +x

  IBAZEL_VNO="0.15.0"
  if command -v ibazel >/dev/null && util::vergte "$IBAZEL_VNO" "$(ibazel 2>&1 | head -1 | grep -o '[^v]*$')"
  then
    return
  fi
  # Manual install of ibazel
  mkdir -p "$HOME/bin"
  pushd /tmp
  {
    rm -rf ibazel
    git clone --depth=1 git://github.com/bazelbuild/bazel-watcher ibazel
    cd ibazel
    bazel build //ibazel
    cp bazel-bin/ibazel/*_stripped/ibazel "$HOME/bin/ibazel"
    chmod 0744 "$HOME/bin/ibazel" # allow later rewriting, e.g. upgrade
  }
  popd
}
PREPARE[bazel]=debbie::bazel::prepare
INSTALL[bazel]=debbie::bazel::install
BUILD[bazel]=debbie::bazel::build

## tmux
debbie::tmux::build() {
  TMUX_VNO="3.1b"
  if command -v tmux >/dev/null && util::vergte "$TMUX_VNO" "$(tmux -V)"
  then
    echo "Have tmux $(tmux -V), skipping build"
    return
  fi
  echo "Building & installing tmux $TMUX_VNO"
  pushd /tmp
  {
    # Build dependencies; should be apt-get build-dep tmux
    util::install_packages libncurses-dev automake libevent-dev bison
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

  GO_VNO="1.16.3"

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
}

PREPARE[golang]=util::noop
INSTALL[golang]=debbie::golang::install
BUILD[golang]=util::noop

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
  # Disable password authentication
  NOPA="PasswordAuthentication no"
  NOEP="PermitEmptyPasswords no"
  if ! grep -q "^$NOPA" /etc/ssh/sshd_config
  then
    echo "$NOPA" | sudo tee -a /etc/ssh/sshd_config >/dev/null
  fi
  if ! grep -q "^$NOEP" /etc/ssh/sshd_config
  then
    echo "$NOEP" | sudo tee -a /etc/ssh/sshd_config >/dev/null
  fi
  sudo systemctl restart sshd
}

PREPARE[ssh-target]=util::noop
INSTALL[ssh-target]=debbie::ssh-target::install
BUILD[ssh-target]=debbie::ssh-target::build

## rust
debbie::rust::install() {
  # There are cargo and rustc packages,
  # but we need access to nightly and src in order to xbuild.
  pushd /tmp
  {
    curl https://sh.rustup.rs -sSf -o rustup.sh
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
  FOMU_VNO="1.5.6"
  FOMU_HASH="0847802dfe7e8d0ee2f08989d5fc262f218b79bac01add717372777e64bd19b5"
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
  # {
  #   sudo groupadd plugdev || true
  #   sudo usermod -a -G plugdev "$USER" || true
  #   local UDEV="/etc/udev/rules.d/99-fomu.rules"
  #   cat >/tmp/fomu-udev-rules <<HRD
  #UBSYSTEM=="usb", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="5bf0", MODE="0664", GROUP="plugdev"
  #RD

  #   if ! { test -e "$UDEV" && test "$(cat /tmp/fomu-udev-rules)" = "$(cat "$UDEV")" ; }
  #   then
  #     # This is an OK cat! shellcheck complains about it either way!
  #     # shellcheck disable=SC2002
  #     cat /tmp/fomu-udev-rules | sudo tee  "$UDEV"
  #     sudo udevadm control --reload-rules
  #     sudo udevadm trigger
  #   fi
  # }

  popd
}
# Disabled per issue #10
# PREPARE[fomu]=util::noop
# INSTALL[fomu]=debbie::fomu::install
# BUILD[fomu]=util::noop

debbie::redo::install() {
  util::install_packages \
    python3
}
debbie::redo::build(){
  local version="0.42c"
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

debbie::powershell::prepare() {
  # Download the Microsoft repository GPG keys
  TEMP="$(mktemp)"
  VERSION="$(cut -d. -f1 /etc/debian_version)"
  curl -Lo "$TEMP" https://packages.microsoft.com/config/debian/${VERSION}/packages-microsoft-prod.deb

  # Register the Microsoft repository GPG keys
  sudo dpkg -i "$TEMP"

  # Update the list of products
  sudo apt-get update
}

debbie::powershell::install() {
  util::install_packages powershell
}

PREPARE[powershell]=debbie::powershell::prepare
INSTALL[powershell]=debbie::powershell::install
BUILD[powershell]=util::noop

## TODO: LSPs
## TODO: ctags? Removed because of the above TODO; LSPs are the new thing.
## TODO: SSH keys? I'm doing more that's rooted in one set, but there's some advice around that says I shouldn't.

main "$@"
