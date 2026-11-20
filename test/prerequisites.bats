#!/usr/bin/env bats
# scripts/prerequisites.sh: the action checks the tools it needs before doing
# anything, and names the one that is missing. It never installs them.

load test_helper

setup() {
  setup_job
  use_stub curl
  export INPUT_SETUP_DOCKER=false
}

@test "passes when every tool is there and Docker is not set up" {
  run_script prerequisites.sh
  [ "$status" -eq 0 ]
  [ "$output" = "donico-action: found jq, curl, tar, gzip, sha256sum, git" ]
}

assert_missing() {
  remove_tool "$1"
  run_script prerequisites.sh
  [ "$status" -eq 1 ]
  [ "$output" = "::error::donico-action: $1 is required and was not found in PATH" ]
}

@test "names jq when it is missing" {
  assert_missing jq
}

@test "names tar when it is missing" {
  assert_missing tar
}

@test "names gzip when it is missing" {
  assert_missing gzip
}

@test "names sha256sum when it is missing" {
  assert_missing sha256sum
}

@test "names git when it is missing" {
  assert_missing git
}

@test "names curl when it is missing" {
  rm "$STUB_BIN/curl"
  run_script prerequisites.sh
  [ "$status" -eq 1 ]
  [ "$output" = "::error::donico-action: curl is required and was not found in PATH" ]
}

@test "does not look for docker when Docker is not set up" {
  use_stub docker
  run_script prerequisites.sh
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls docker)" ]
}

@test "names docker when Docker is set up and docker is missing" {
  export INPUT_SETUP_DOCKER=true
  run_script prerequisites.sh
  [ "$status" -eq 1 ]
  [ "$output" = "::error::donico-action: docker is required and was not found in PATH" ]
}

@test "names the buildx plugin when Docker is set up and buildx is missing" {
  export INPUT_SETUP_DOCKER=true DOCKER_STUB_NO_BUILDX=1
  use_stub docker
  run_script prerequisites.sh
  [ "$status" -eq 1 ]
  [ "$output" = "::error::donico-action: the docker buildx plugin is required and \`docker buildx version\` failed" ]
}

@test "passes with docker and buildx when Docker is set up" {
  export INPUT_SETUP_DOCKER=true
  use_stub docker
  run_script prerequisites.sh
  [ "$status" -eq 0 ]
  [ "$output" = "donico-action: found jq, curl, tar, gzip, sha256sum, git, docker, docker buildx" ]
}

@test "refuses a setup-docker that is neither true nor false" {
  export INPUT_SETUP_DOCKER=yes
  run_script prerequisites.sh
  [ "$status" -eq 1 ]
  [ "$output" = "::error::donico-action: setup-docker must be true or false, got: yes" ]
}
