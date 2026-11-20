# Helpers shared by the scripts of the action. Sourced, never run.
#
# Every message is prefixed with "donico-action:" so that it can be told apart
# from what donico and docker print in the same step. Errors and warnings use
# the workflow commands of GitHub Actions, which annotate the run.

info() {
  printf 'donico-action: %s\n' "$*"
}

warn() {
  printf '::warning::donico-action: %s\n' "$*"
}

fail() {
  printf '::error::donico-action: %s\n' "$*"
  exit 1
}

# Value of a boolean input; only "true" and "false" are accepted, so that a
# typo never silently means "off".
input_true() {
  local name="$1" value="$2"
  case "$value" in
    true) return 0 ;;
    false) return 1 ;;
    *) fail "$name must be true or false, got: $value" ;;
  esac
}

set_output() {
  printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
}

set_env() {
  printf '%s=%s\n' "$1" "$2" >> "$GITHUB_ENV"
}

add_path() {
  printf '%s\n' "$1" >> "$GITHUB_PATH"
}

# The two constants below are used by the scripts that source this file.

# Where donico is released. The archives and checksums.txt of a release are
# under $DONICO_RELEASES/download/v<version>/.
# shellcheck disable=SC2034
DONICO_RELEASES="https://github.com/jbox-web/donico/releases"

# A donico version number, without the leading "v" of its tag.
# shellcheck disable=SC2034
VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$'
