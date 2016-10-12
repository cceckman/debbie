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
    prompt "Enter a Github authentication token for ${gh_username}:"
    read token

    {
      curl -X POST -d @$keyreq -u ${gh_username}:${token} https://api.github.com/user/keys \
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

# Clone Tilde.
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
# Load any other "default" repositories.
# Include this one- hey, if I'm using it, I probably want it cloned.
$HOME/scripts/update-repos cceckman/debbie

# Add some custom repositories
# Bazel
echo "deb [arch=amd64] http://storage.googleapis.com/bazel-apt stable jdk1.8" | sudo tee /etc/apt/sources.list.d/bazel.list

curl https://storage.googleapis.com/bazel-apt/doc/apt-key.pub.gpg | sudo apt-key add  -

# GCloud
export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)"
echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list

curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

sudo apt-get update
# Load packages. This eats a little more than 1GB, all told.
sudo apt-get install \
  arping \
  bash \
  bazel \
  bc \
  clang \
  cmatrix \
  default-jdk \
  dosfstools \
  fping \
  golang \
  google-cloud-sdk \
  i3 \
  irssi \
  libanyevent-i3-perl \
  lldb \
  llvm \
  make \
  mlocate \
  mtr \
  ninja-build \
  ntfs-3g \
  parted \
  pkg-config \
  python \
  python-gflags \
  rsync \
  screen \
  ssh \
  traceroute \
  vim \
  xclip \
  xorg \
  xscreensaver \
  xterm \
  zip \
 || {
  x=$?
  echo "Package install failed with exit code: $x"
  exit $x
}

# TODO: remote GUI tools
# TODO: installing kubectl

echo "All done! Log in again to update everything."

cd $PUSHD
