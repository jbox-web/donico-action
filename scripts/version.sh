#!/usr/bin/env bash
# Decide which version of donico the job gets, and write it to the step
# output `version`. In this order:
#   1. the `version` input;
#   2. the donico pin of mise.toml, then of .mise.toml, in the working
#      directory: an image repository already pins donico there, and one
#      source of truth is better than two;
#   3. the latest release, read from the redirect of /releases/latest, which
#      needs neither the API, nor its quota, nor a token.
# A pin that is there but cannot be read stops the action: falling back on the
# latest release would silently build with a version nobody chose.
#
# Inputs (environment): INPUT_VERSION, INPUT_WORKING_DIRECTORY.
set -o errexit -o nounset -o pipefail
# shellcheck source=scripts/lib.sh
source "${BASH_SOURCE[0]%/*}/lib.sh"

# A line that sets the donico tool of mise, readable or not, and the one form
# this action reads: a quoted key, then a quoted version number.
pin_key_re="^[[:space:]]*[\"'](github|aqua):jbox-web/donico[\"'][[:space:]]*="
pin_re="${pin_key_re}[[:space:]]*[\"']v?([0-9][^\"']*)[\"'][[:space:]]*(#.*)?$"

# Set `pin` to the version pinned in a mise configuration file, to nothing
# when the file pins no donico; stop the action on a pin it cannot read. Not
# meant for a command substitution: `fail` must end the script, not a subshell.
read_pin() {
  local file="$1" line candidate
  pin=""
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ $pin_key_re ]] || continue
    candidate=""
    if [[ "$line" =~ $pin_re ]]; then
      candidate="${BASH_REMATCH[2]}"
    fi
    if [[ "$candidate" =~ $VERSION_RE ]]; then
      pin="$candidate"
      return 0
    fi
    line="${line#"${line%%[![:space:]]*}"}"
    fail "cannot read the donico pin of ${file##*/}: $line; write it as \"github:jbox-web/donico\" = \"<version>\", or set the version input"
  done < "$file"
}

working_directory="${INPUT_WORKING_DIRECTORY:-.}"
version="${INPUT_VERSION:-}"
source="version input"

if [ -n "$version" ]; then
  version="${version#v}"
  [[ "$version" =~ $VERSION_RE ]] || fail "version is not a donico version number: ${INPUT_VERSION}"
else
  for file in mise.toml .mise.toml; do
    read_pin "$working_directory/$file"
    version="$pin"
    if [ -n "$version" ]; then
      source="pin of $file"
      break
    fi
  done
fi

if [ -z "$version" ]; then
  latest="$DONICO_RELEASES/latest"
  redirect="$(curl --silent --show-error --fail --retry 3 --output /dev/null \
    --write-out '%{redirect_url}' "$latest")" || redirect=""
  version="${redirect##*/tag/v}"
  if [[ "$redirect" != */tag/v* ]] || ! [[ "$version" =~ $VERSION_RE ]]; then
    fail "cannot resolve the latest donico release from $latest; set the version input"
  fi
  source="latest release"
fi

set_output version "$version"
info "donico $version ($source)"
