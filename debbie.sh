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
  local INPUT_FEATURES="+core +home +tmux $*"
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

  declare -A STAGES
  STAGES[0]="prepare"
  STAGES[1]="prebuilt"
  STAGES[2]="built"

  for feature in "${!FEATURES[@]}"
  do
    for stage in "${STAGES[@]}"
    do
      myType=""
      if ! test "$(type -t "debbie::${feature}::${stage}")" == "function"
      then
        ERR="true"
        echo >&2 "Unknown feature/stage combination ${feature}::${stage}: type '$myType'"
      fi
    done
  done
  if "$ERR"; then exit 1; fi

  # We've validated that each feature & stage exists. Run them.
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

main "$@"
