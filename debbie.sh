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

DEFAULT_FEATURES="+core +graphical +tmux"

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
           for i in "${FEATURES[@]}"
           do
             if test "${FEATURES[$i]}" != "$feature"
             then
               newFeatures+=("$feature")
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
debbie::prestage::install() {
  sudo apt-get update
  sudo apt-get upgrade
}
PREPARE[prestage]=util::noop
INSTALL[prestage]=debbie::prestage::install
BUILD[prestage]=util::noop

## core
debbie::core::install() {
  util::install_packages \
    locales \
    lsb-release \
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
    kubectl \
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
    rsync \
    ssh \
    tcpdump \
    traceroute \
    vim \
    whois \
    zip \
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

## graphical
debbie::graphical::install() {
  util::install_packages \
    chromium \
    feh \
    fonts-powerline \
    i3 \
    i3status \
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
}

PREPARE[graphical]=util::noop
INSTALL[graphical]=debbie::graphical::install
BUILD[graphical]=util::noop

## gcloud
debbie::gcloud::prepare() {
  if ! grep -q "packages.cloud.google.com" /etc/apt/sources.list.d/* /etc/apt/sources.list
  then
    CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -cs)"
    echo "deb https://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
  fi
}

debbie::gcloud::install() {
  util::install_packages google-cloud-sdk
}

PREPARE[gcloud]=debbie::gcloud::prepare
INSTALL[gcloud]=debbie::gcloud::install
BUILD[gcloud]=util::noop

## docker
debbie::docker::prepare() {
  if ! grep -q "download.docker.com" /etc/apt/sources.list.d/* /etc/apt/sources.list
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
  if ! grep -q "https://storage.googleapis.com/bazel-apt" /etc/apt/sources.list.d/* /etc/apt/sources.list
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
  GO_VNO="1.12.7"
  if command -v go >/dev/null && util::vergte "$GO_VNO" "$(go version)"
  then
    echo "Have $(go version), skipping build"
    return
  fi

  declare -A GOARCH
  GOARCH[x86_64]="amd64"
  GOTAR=/tmp/golang.tar.gz
  curl -o "$GOTAR" "https://storage.googleapis.com/golang/go${GO_VNO}.linux-${GOARCH[$(uname -m)]}.tar.gz"
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf "$GOTAR"
  rm "$GOTAR"
  export PATH="/usr/local/go/bin:$PATH"
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

main "$@"
