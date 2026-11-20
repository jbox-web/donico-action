#!/usr/bin/env bats
# scripts/version.sh: the version of donico to install is, in this order, the
# `version` input, the donico pin of the project's mise.toml (or .mise.toml),
# and the latest release. It is written to the step output `version`.

load test_helper

setup() {
  setup_job
  use_stub curl
  export INPUT_VERSION=""
  export CURL_STUB_REDIRECT_URL="https://github.com/jbox-web/donico/releases/tag/v3.4.1"
}

@test "takes the version input as it is" {
  export INPUT_VERSION=3.2.0
  run_script version.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_OUTPUT")" = "version=3.2.0" ]
  [ "$output" = "donico-action: donico 3.2.0 (version input)" ]
}

@test "drops the leading v of the version input" {
  export INPUT_VERSION=v3.2.0
  run_script version.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_OUTPUT")" = "version=3.2.0" ]
}

@test "refuses a version input that is not a version" {
  export INPUT_VERSION=latest
  run_script version.sh
  [ "$status" -eq 1 ]
  [ "$output" = "::error::donico-action: version is not a donico version number: latest" ]
  [ ! -s "$GITHUB_OUTPUT" ]
}

@test "reads the github backend pin of mise.toml" {
  printf '[tools]\n"github:jbox-web/donico" = "3.2.0"\n' > "$WORK/mise.toml"
  run_script version.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_OUTPUT")" = "version=3.2.0" ]
  [ "$output" = "donico-action: donico 3.2.0 (pin of mise.toml)" ]
}

@test "reads the aqua backend pin of mise.toml" {
  printf '[tools]\n"aqua:jbox-web/donico" = "3.1.0"\n' > "$WORK/mise.toml"
  run_script version.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_OUTPUT")" = "version=3.1.0" ]
}

@test "reads a pin written with single quotes and followed by a comment" {
  printf "[tools]\n  'github:jbox-web/donico' = '3.2.0'  # the fleet's version\n" > "$WORK/mise.toml"
  run_script version.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_OUTPUT")" = "version=3.2.0" ]
}

@test "reads the pin of .mise.toml when mise.toml has none" {
  printf '[settings]\nexperimental = true\n' > "$WORK/mise.toml"
  printf '[tools]\n"github:jbox-web/donico" = "3.0.1"\n' > "$WORK/.mise.toml"
  run_script version.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_OUTPUT")" = "version=3.0.1" ]
  [ "$output" = "donico-action: donico 3.0.1 (pin of .mise.toml)" ]
}

@test "prefers the pin of mise.toml over the one of .mise.toml" {
  printf '[tools]\n"github:jbox-web/donico" = "3.2.0"\n' > "$WORK/mise.toml"
  printf '[tools]\n"github:jbox-web/donico" = "3.0.1"\n' > "$WORK/.mise.toml"
  run_script version.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_OUTPUT")" = "version=3.2.0" ]
}

@test "prefers the version input over the pin" {
  export INPUT_VERSION=3.3.0
  printf '[tools]\n"github:jbox-web/donico" = "3.2.0"\n' > "$WORK/mise.toml"
  run_script version.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_OUTPUT")" = "version=3.3.0" ]
}

@test "ignores a commented-out pin" {
  printf '[tools]\n# "github:jbox-web/donico" = "2.9.0"\n' > "$WORK/mise.toml"
  run_script version.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_OUTPUT")" = "version=3.4.1" ]
}

@test "refuses a pin written as a table instead of installing the latest release" {
  printf '[tools]\n"github:jbox-web/donico" = { version = "3.2.0" }\n' > "$WORK/mise.toml"
  run_script version.sh
  [ "$status" -eq 1 ]
  [ "$output" = "::error::donico-action: cannot read the donico pin of mise.toml: \"github:jbox-web/donico\" = { version = \"3.2.0\" }; write it as \"github:jbox-web/donico\" = \"<version>\", or set the version input" ]
  [ ! -s "$GITHUB_OUTPUT" ]
  [ -z "$(stub_calls curl)" ]
}

@test "refuses a pin on latest instead of installing the latest release" {
  printf '[tools]\n"aqua:jbox-web/donico" = "latest"\n' > "$WORK/mise.toml"
  run_script version.sh
  [ "$status" -eq 1 ]
  [ "$output" = "::error::donico-action: cannot read the donico pin of mise.toml: \"aqua:jbox-web/donico\" = \"latest\"; write it as \"github:jbox-web/donico\" = \"<version>\", or set the version input" ]
}

@test "reads the pin of the working directory, not of the current one" {
  mkdir -p "$WORK/image"
  printf '[tools]\n"github:jbox-web/donico" = "3.2.0"\n' > "$WORK/image/mise.toml"
  export INPUT_WORKING_DIRECTORY="$WORK/image"
  run_script version.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_OUTPUT")" = "version=3.2.0" ]
}

@test "falls back on the latest release, from the redirect of /releases/latest" {
  run_script version.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_OUTPUT")" = "version=3.4.1" ]
  [ "$output" = "donico-action: donico 3.4.1 (latest release)" ]
  [ "$(stub_calls curl)" = "--silent --show-error --fail --retry 3 --output /dev/null --write-out %{redirect_url} https://github.com/jbox-web/donico/releases/latest" ]
}

@test "fails when the latest release cannot be resolved" {
  export CURL_STUB_REDIRECT_URL=""
  run_script version.sh
  [ "$status" -eq 1 ]
  [ "$output" = "::error::donico-action: cannot resolve the latest donico release from https://github.com/jbox-web/donico/releases/latest; set the version input" ]
}
