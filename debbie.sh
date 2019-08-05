#! /bin/bash -e
# Set up a Debian / Ubuntu machine to my liking.
# Put it all in a single file, so that it can be curl'd.


## OUTLINE
# debbie defines a set of "features" that we may / may not want to run.
# Each "feature" ties in to "stages", which are:
# - Install dependencies (including Apt repositories)
# - Install & update prebuilts
# - Test and/or build pinned software (i.e. stuff that's built from source)
# Each (feature,stage) is defined as a namespaced function: debbie::${feature}::${stage}.
# Features can be toggled on and off by +feature -feature on the command line.

main() {
  local INPUT_FEATURES="+prestage +core +home +tmux $*"
  declare -A FEATURES
  local ERR="false"
  for flag in $INPUT_FEATURES
  do
    local tag="${flag:0:1}"
    local feature="${flag:1}"
    case "$tag" in
      '+') FEATURES["$feature"]="true";;
      '-') unset FEATURES["$feature"];;
        *) echo >&2 "Unrecognized operation $tag in $flag; must be '+' or '-'"
           ERR="true"
    esac
  done

  declare -a STAGES
  STAGES=(prepare prebuilt build)

  for feature in "${!FEATURES[@]}"
  do
    for stage in "${STAGES[@]}"
    do
      myType=""
      if ! test "$(type -t "debbie::${feature}::${stage}")" == "function"
      then
        ERR="true"
        echo >&2 "Unknown feature/stage combination: 'debbie::${feature}::${stage}' has type '$myType'"
      fi
    done
  done
  if "$ERR"; then exit 1; fi

  # We've validated that each feature & stage exists.
  # Do some general checking:
  util::preflight
  # and run each stage.
  # Note this means there's no guaranteed order between different features.
  for stage in "${STAGES[@]}"
  do
    for feature in "${!FEATURES[@]}"
    do
      "debbie::${feature}::${stage}"
    done
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

debbie::prestage::prepare() {
  # Nothing to be done before e.g. updating repositories
  return
}
debbie::prestage::prebuilt() {
  # Before installing prebuilt packages...
  sudo apt-get update
  sudo apt-get upgrade
}
debbie::prestage::build() {
  return
}

debbie::core::prepare() {
  # Nothing to do before installing locales, git, etc.
  return
}
debbie::core::prebuilt() {
  sudo \
    DEBIAN_FRONTEND=noninteractive \
    apt-get -yq --no-install-recommends \
    install \
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

main "$@"
