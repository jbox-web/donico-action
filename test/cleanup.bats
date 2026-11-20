#!/usr/bin/env bats
# scripts/cleanup.sh: removes what the action created on a daemon or a disk
# that outlive the job: its buildx builder and its Docker configuration. It
# never fails the job: it runs last, often with `if: always()`.

load test_helper

setup() {
  setup_job
  use_stub docker
  CONFIG_DIR="$RUNNER_TEMP/donico-action/docker-config"
}

@test "removes the builder and the Docker configuration of the job" {
  mkdir -p "$CONFIG_DIR"
  printf '{}' > "$CONFIG_DIR/config.json"
  export DONICO_ACTION_BUILDER=donico-4242-1-images-0a1b2c3d DONICO_ACTION_DOCKER_CONFIG="$CONFIG_DIR"
  export DOCKER_CONFIG="$CONFIG_DIR"
  run_script cleanup.sh
  [ "$status" -eq 0 ]
  [ "$(stub_calls docker)" = "buildx rm donico-4242-1-images-0a1b2c3d" ]
  [ "$(cat "$STUB_LOG/docker.env")" = "- $CONFIG_DIR" ]
  [ ! -e "$CONFIG_DIR" ]
  [ "$output" = "donico-action: buildx builder donico-4242-1-images-0a1b2c3d removed
donico-action: Docker configuration $CONFIG_DIR removed" ]
}

@test "does nothing when the action created nothing" {
  run_script cleanup.sh
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls docker)" ]
  [ "$output" = "donico-action: nothing to clean up" ]
}

@test "only warns when the builder cannot be removed, and still removes the configuration" {
  mkdir -p "$CONFIG_DIR"
  export DONICO_ACTION_BUILDER=donico-4242-1-images-0a1b2c3d DONICO_ACTION_DOCKER_CONFIG="$CONFIG_DIR"
  export DOCKER_STUB_FAIL='^buildx rm '
  run_script cleanup.sh
  [ "$status" -eq 0 ]
  [ "${lines[-2]}" = "::warning::donico-action: cannot remove the buildx builder donico-4242-1-images-0a1b2c3d" ]
  [ ! -e "$CONFIG_DIR" ]
}

@test "removes only a configuration directory of the action" {
  mkdir -p "$JOB_DIR/elsewhere"
  export DONICO_ACTION_DOCKER_CONFIG="$JOB_DIR/elsewhere"
  run_script cleanup.sh
  [ "$status" -eq 0 ]
  [ -d "$JOB_DIR/elsewhere" ]
  [ "$output" = "::warning::donico-action: not removing $JOB_DIR/elsewhere: it is not a directory of this action" ]
}
