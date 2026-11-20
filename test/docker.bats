#!/usr/bin/env bats
# scripts/docker.sh: prepares the Docker of the job for donico: the daemon to
# talk to, the registry credentials in a configuration of the job's own, the
# binfmt handlers of a multi-platform build, and a buildx builder.

load test_helper

BINFMT="tonistiigi/binfmt@sha256:400a4873b838d1b89194d982c45e5fb3cda4593fbfd7e08a02e76b03b21166f0"
TOKEN='{"auths":{"registry.example.com":{"auth":"c2VjcmV0LXZhbHVlCg=="}}}'

setup() {
  setup_job
  use_stub docker donico
  export INPUT_SETUP_DOCKER=true INPUT_SETUP_QEMU=true INPUT_SETUP_BUILDX=true
  export INPUT_REGISTRY_AUTH="" INPUT_DOCKER_HOST=""
  export GITHUB_RUN_ID=4242 GITHUB_RUN_ATTEMPT=1 GITHUB_JOB=images
  export DONICO_STUB_MATRIX="$BATS_TEST_DIRNAME/fixtures/matrix-bake.json" DONICO_STUB_BUILDER=bake
  export DOCKER_STUB_DRIVER_STATUS='[["driver-type","io.containerd.snapshotter.v1"]]'
  CONFIG_DIR="$RUNNER_TEMP/donico-action/docker-config"
}

builder_re='donico-4242-1-images-[0-9a-f]{8}'

@test "sets nothing up and never calls docker when setup-docker is false" {
  export INPUT_SETUP_DOCKER=false INPUT_DOCKER_HOST=tcp://docker:2375 INPUT_REGISTRY_AUTH="$TOKEN"
  run_script docker.sh
  [ "$status" -eq 0 ]
  [ "$output" = "donico-action: Docker setup skipped" ]
  [ -z "$(stub_calls docker)" ]
  [ ! -s "$GITHUB_ENV" ]
  [ ! -e "$CONFIG_DIR" ]
}

@test "installs binfmt, creates and selects a builder of its own, checks the image store" {
  run_script docker.sh
  [ "$status" -eq 0 ]
  [[ "$(stub_calls docker)" =~ ^"run --rm --privileged $BINFMT --install all
buildx create --use --bootstrap --name "($builder_re)"
info --format {{json .DriverStatus}}"$ ]]
  builder="${BASH_REMATCH[1]}"
  [ "$(cat "$GITHUB_ENV")" = "DONICO_ACTION_BUILDER=$builder" ]
  [ "$output" = "donico-action: binfmt handlers installed
donico-action: buildx builder $builder created and selected" ]
}

@test "gives each job a builder of its own" {
  run_script docker.sh
  first="$(cat "$GITHUB_ENV")"
  : > "$GITHUB_ENV"
  run_script docker.sh
  [ "$(cat "$GITHUB_ENV")" != "$first" ]
}

@test "talks to the daemon of docker-host, and passes it on to the next steps" {
  export INPUT_DOCKER_HOST=tcp://docker:2375
  run_script docker.sh
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "$GITHUB_ENV")" = "DOCKER_HOST=tcp://docker:2375" ]
  [ "$(sort -u "$STUB_LOG/docker.env")" = "tcp://docker:2375 -" ]
}

@test "writes registry-auth into a configuration of the job's own, readable by the job's user only" {
  export INPUT_REGISTRY_AUTH="$TOKEN"
  run_script docker.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$CONFIG_DIR/config.json")" = "$TOKEN" ]
  [ "$(stat -c %a "$CONFIG_DIR/config.json")" = "600" ]
  [ "$(head -n 2 "$GITHUB_ENV")" = "DOCKER_CONFIG=$CONFIG_DIR
DONICO_ACTION_DOCKER_CONFIG=$CONFIG_DIR" ]
  [ "$(sort -u "$STUB_LOG/docker.env")" = "- $CONFIG_DIR" ]
  [ ! -e "$HOME/.docker" ]
}

@test "keeps the CLI plugins of the user's Docker configuration reachable" {
  mkdir -p "$HOME/.docker/cli-plugins"
  : > "$HOME/.docker/cli-plugins/docker-buildx"
  export INPUT_REGISTRY_AUTH="$TOKEN"
  run_script docker.sh
  [ "$status" -eq 0 ]
  [ "$(readlink "$CONFIG_DIR/cli-plugins")" = "$HOME/.docker/cli-plugins" ]
  [ "$(ls "$HOME/.docker")" = "cli-plugins" ]
}

@test "links no CLI plugins when the user's Docker configuration has none" {
  export INPUT_REGISTRY_AUTH="$TOKEN"
  run_script docker.sh
  [ "$status" -eq 0 ]
  [ ! -e "$CONFIG_DIR/cli-plugins" ]
}

@test "never prints the registry credentials" {
  export INPUT_REGISTRY_AUTH="$TOKEN"
  run_script docker.sh
  [ "$status" -eq 0 ]
  [[ "$output" != *c2VjcmV0* ]]
  [[ "$output" == *"donico-action: registry credentials written to $CONFIG_DIR/config.json"* ]]
  run grep -q c2VjcmV0 "$GITHUB_ENV" "$GITHUB_OUTPUT"
  [ "$status" -eq 1 ]
}

@test "refuses a registry-auth that is not a Docker config.json, without printing it" {
  export INPUT_REGISTRY_AUTH='user:c2VjcmV0'
  run_script docker.sh
  [ "$status" -eq 1 ]
  [ "$output" = "::error::donico-action: registry-auth is not a JSON document: it must hold the content of a Docker config.json" ]
  [ ! -e "$CONFIG_DIR" ]
  [ -z "$(stub_calls docker)" ]
}

@test "only warns when binfmt cannot be installed" {
  export DOCKER_STUB_FAIL='^run '
  run_script docker.sh
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "::warning::donico-action: cannot install the binfmt handlers (does the runner refuse privileged containers?): only the platform of the daemon will build" ]
}

@test "stops when the builder cannot be created" {
  export DOCKER_STUB_FAIL='^buildx create '
  run_script docker.sh
  [ "$status" -eq 1 ]
  [[ "${lines[-1]}" =~ ^"::error::donico-action: cannot create the buildx builder "$builder_re$ ]]
  [ ! -s "$GITHUB_ENV" ]
}

@test "skips binfmt when setup-qemu is false" {
  export INPUT_SETUP_QEMU=false
  run_script docker.sh
  [ "$status" -eq 0 ]
  [[ "$(stub_calls docker)" != *binfmt* ]]
}

@test "skips the builder when setup-buildx is false" {
  export INPUT_SETUP_BUILDX=false
  run_script docker.sh
  [ "$status" -eq 0 ]
  [[ "$(stub_calls docker)" != *"buildx create"* ]]
  [ ! -s "$GITHUB_ENV" ]
}

@test "warns when a multi-platform bake build meets a daemon without the containerd image store" {
  export DOCKER_STUB_DRIVER_STATUS='[["Backing Filesystem","extfs"],["Supports d_type","true"]]'
  run_script docker.sh
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "::warning::donico-action: the Docker daemon does not use the containerd image store, which the build task needs to load a multi-platform image (the default from Docker 29 on)" ]
}

@test "does not warn about the image store when every row builds one platform" {
  jq '[.[1]]' "$BATS_TEST_DIRNAME/fixtures/matrix-bake.json" > "$JOB_DIR/one-platform.json"
  export DONICO_STUB_MATRIX="$JOB_DIR/one-platform.json"
  export DOCKER_STUB_DRIVER_STATUS='[["Backing Filesystem","extfs"]]'
  run_script docker.sh
  [ "$status" -eq 0 ]
  [[ "$output" != *"containerd image store"* ]]
  [[ "$(stub_calls docker)" != *"info"* ]]
}

@test "does not check the image store of a debuerreotype project, which loads no image" {
  export DONICO_STUB_MATRIX="$BATS_TEST_DIRNAME/fixtures/matrix-debuerreotype.json" DONICO_STUB_BUILDER=debuerreotype
  export DOCKER_STUB_DRIVER_STATUS='[["Backing Filesystem","extfs"]]'
  run_script docker.sh
  [ "$status" -eq 0 ]
  [[ "$(stub_calls docker)" != *"info"* ]]
}

@test "refuses a setup-qemu that is neither true nor false" {
  export INPUT_SETUP_QEMU=1
  run_script docker.sh
  [ "$status" -eq 1 ]
  [ "$output" = "::error::donico-action: setup-qemu must be true or false, got: 1" ]
}
