#! /bin/sh -i
# Make an Ubuntu instance, and test the 'debbie' script on it.
# Use default inputs.
set -xv

NAME="ubuntu-testing"
IMG="ubuntu-1604-xenial-v20170330"
IMG_PROJECT="ubuntu-os-cloud"
ZONE="us-central1-c"

gcloud compute \
  instances create "$NAME" \
  --machine-type "g1-small" \
  --image "$IMG" \
  --image-project "$IMG_PROJECT" \
  --boot-disk-size "100" \
  --zone "$ZONE" || {
  echo "could not create VM instance, aborting."
}

# clean up the instance on exit from this script.
trap "set +x; gcloud -q compute instances delete --zone $ZONE $NAME; set -x" EXIT 

# Give the instance some time to prepare
sleep 70

# SSH in, run the script.
eval `ssh-agent`
gcloud compute ssh $NAME \
  --zone "$ZONE" \
  --command \
    'cat /dev/null | sh <(curl -L https://raw.githubusercontent.com/cceckman/debbie/master/debbie.sh)' \
  -- -A

if [ $? -ne 0 ]
then
  echo "failed!" 1>&2
else
  echo "Script succeeded!"
fi

set +xv

echo "Opening console for inspection..."

echo "Run:"
echo "gcloud compute ssh $NAME --zone $ZONE"
echo "to inspect the instance. Type 'done' to destroy this instance."

while read foo
do
  if [ "$foo" == "done" ]
  then
    break
  fi
done

echo "Exiting, including cleaning up instance..."
