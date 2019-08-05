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

DEFAULT_FEATURES="+core +graphical +gcloud"

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

debbie::prestage::install() {
  sudo apt-get update
  sudo apt-get upgrade
}
PREPARE[prestage]=util::noop
INSTALL[prestage]=debbie::prestage::install
BUILD[prestage]=util::noop

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

debbie::graphical::install() {
  util::install_packages \
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

debbie::gcloud::prepare() {
  if ! grep -q "packages.cloud.google.com" /etc/apt/sources.list.d/* /etc/apt/sources.list
  then
    CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)"
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

main "$@"
