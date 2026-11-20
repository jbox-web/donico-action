# Shared setup of the bats tests: every test runs an action script the way a
# job step would, but in a throwaway directory and with stand-ins for the
# external commands it calls.
#
# The script under test sees a PATH made of two directories only:
# - $STUB_BIN, the stand-ins a test asked for (docker, curl, donico, uname,
#   date), which log their arguments under $STUB_LOG and answer what the test
#   set in their environment variables (see test/stubs/);
# - $TOOLS_BIN, links to the real tools a job has (bash, jq, tar, git...).
#   A test removes one of these links to play a runner that lacks the tool.
# The test body itself keeps the normal PATH: bats and the assertions need it.

ACTION_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
SCRIPTS="$ACTION_ROOT/scripts"
STUBS="$ACTION_ROOT/test/stubs"

# The real tools linked into $TOOLS_BIN. The scripts may use these and no
# others: a tool missing from this list fails the test that needs it.
JOB_TOOLS=(
  bash env cat cp mv rm mkdir rmdir ls ln chmod touch mktemp dirname basename
  sed grep awk cut tr head tail sort wc printf od
  jq tar gzip sha256sum git
)

setup_job() {
  JOB_DIR="$BATS_TEST_TMPDIR/job"
  STUB_BIN="$JOB_DIR/stub-bin"
  TOOLS_BIN="$JOB_DIR/tools-bin"
  STUB_LOG="$JOB_DIR/stub-log"
  WORK="$JOB_DIR/work"
  mkdir -p "$STUB_BIN" "$TOOLS_BIN" "$STUB_LOG" "$WORK" "$JOB_DIR/temp" "$JOB_DIR/home"

  local tool path
  for tool in "${JOB_TOOLS[@]}"; do
    path="$(command -v "$tool")" || {
      echo "test setup: $tool is not installed on this machine" >&2
      return 1
    }
    ln -s "$path" "$TOOLS_BIN/$tool"
  done

  export GITHUB_ENV="$JOB_DIR/github_env"
  export GITHUB_OUTPUT="$JOB_DIR/github_output"
  export GITHUB_PATH="$JOB_DIR/github_path"
  : > "$GITHUB_ENV"
  : > "$GITHUB_OUTPUT"
  : > "$GITHUB_PATH"
  # What the machine running the tests may have set must not leak into them.
  unset DOCKER_HOST DOCKER_CONFIG CI_COMMIT_TIMESTAMP CI_PIPELINE_CREATED_AT
  unset DONICO_ACTION_BUILDER DONICO_ACTION_DOCKER_CONFIG
  export RUNNER_TEMP="$JOB_DIR/temp"
  export HOME="$JOB_DIR/home"
  export STUB_LOG
  export INPUT_WORKING_DIRECTORY="$WORK"
}

# Put the stand-in of a command in front of the real tools.
use_stub() {
  local name
  for name in "$@"; do
    cp "$STUBS/$name" "$STUB_BIN/$name"
    chmod +x "$STUB_BIN/$name"
  done
}

# Play a runner where a tool is not installed.
remove_tool() {
  rm -f "$TOOLS_BIN/$1"
}

# Run one action script with the job's restricted PATH.
run_script() {
  run env PATH="$STUB_BIN:$TOOLS_BIN" "$BASH" "$SCRIPTS/$1"
}

# What a stand-in was called with, one call per line.
stub_calls() {
  cat "$STUB_LOG/$1" 2>/dev/null || true
}
