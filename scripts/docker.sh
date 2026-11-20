#!/usr/bin/env bash
# Prepare the Docker of the job for donico, the way a donico CI job always
# had to: the daemon to talk to, the registry credentials, the binfmt handlers
# that let one daemon build every platform, and a buildx builder.
#
# Everything that depends on the runner is an input: the action knows no
# registry, no secret name and no daemon address.
#
# - docker-host becomes the current context of a Docker configuration of the
#   job's own, exported as DOCKER_CONFIG. Never as DOCKER_HOST: in a job
#   container, the runner hands the environment of a step to its own
#   `docker exec` on the host, which would then call docker-host and fail.
# - registry-auth, the content of a Docker config.json, is written to a
#   directory of the job's own, exported as DOCKER_CONFIG. The runner's
#   ~/.docker is neither read nor changed, and the file is created 0600
#   before the credentials are written to it. They are never printed.
#   The CLI plugins of the configuration it replaces are linked into it.
# - binfmt runs privileged, so its image is pinned by digest: a mutable tag
#   would let an upstream re-tag run privileged code on the runner. The digest
#   is the one of the GitLab template of the jbox fleet. A runner that refuses
#   privileged containers only gets a warning: it can still build the platform
#   of its own daemon.
# - The builder gets a name of its own, recorded in DONICO_ACTION_BUILDER for
#   the cleanup action: jobs that share a daemon must not share a builder.
# - A bake build loads a multi-platform image into the daemon, which needs
#   the containerd image store. The action does not change the daemon; it
#   warns when a row builds several platforms and the store is missing.
#
# Inputs (environment): INPUT_SETUP_DOCKER, INPUT_DOCKER_HOST,
# INPUT_REGISTRY_AUTH, INPUT_SETUP_QEMU, INPUT_SETUP_BUILDX,
# INPUT_WORKING_DIRECTORY; GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT, GITHUB_JOB.
set -o errexit -o nounset -o pipefail
# shellcheck source=scripts/lib.sh
source "${BASH_SOURCE[0]%/*}/lib.sh"

BINFMT_IMAGE="tonistiigi/binfmt@sha256:400a4873b838d1b89194d982c45e5fb3cda4593fbfd7e08a02e76b03b21166f0"

if ! input_true setup-docker "${INPUT_SETUP_DOCKER:-true}"; then
  info "Docker setup skipped"
  exit 0
fi
setup_qemu=false setup_buildx=false
input_true setup-qemu "${INPUT_SETUP_QEMU:-true}" && setup_qemu=true
input_true setup-buildx "${INPUT_SETUP_BUILDX:-true}" && setup_buildx=true
working_directory="${INPUT_WORKING_DIRECTORY:-.}"

config_dir="$RUNNER_TEMP/donico-action/docker-config"

# The Docker configuration of the job, created once, 0600 before anything is
# written to it. The CLI plugins (buildx among them) of the configuration it
# replaces stay reachable through a link; nothing is written there.
own_docker_config() {
  [ "${DOCKER_CONFIG:-}" = "$config_dir" ] && return 0
  (
    umask 077
    mkdir -p "$config_dir"
    : > "$config_dir/config.json"
  )
  chmod 600 "$config_dir/config.json"
  printf '{}' > "$config_dir/config.json"
  local user_plugins="${DOCKER_CONFIG:-$HOME/.docker}/cli-plugins"
  if [ -d "$user_plugins" ] && [ ! -e "$config_dir/cli-plugins" ]; then
    ln -s "$user_plugins" "$config_dir/cli-plugins"
  fi
  export DOCKER_CONFIG="$config_dir"
  set_env DOCKER_CONFIG "$config_dir"
  set_env DONICO_ACTION_DOCKER_CONFIG "$config_dir"
}

if [ -n "${INPUT_REGISTRY_AUTH:-}" ]; then
  jq --exit-status 'type == "object"' <<< "$INPUT_REGISTRY_AUTH" > /dev/null 2>&1 ||
    fail "registry-auth is not a JSON document: it must hold the content of a Docker config.json"
  own_docker_config
  printf '%s' "$INPUT_REGISTRY_AUTH" > "$config_dir/config.json"
  info "registry credentials written to $config_dir/config.json"
fi

# After the credentials: `docker context use` writes its choice into the
# config.json they live in.
if [ -n "${INPUT_DOCKER_HOST:-}" ]; then
  own_docker_config
  { docker context create donico-action --docker "host=$INPUT_DOCKER_HOST" > /dev/null &&
    docker context use donico-action > /dev/null; } ||
    fail "cannot point docker at $INPUT_DOCKER_HOST (docker context create)"
  info "docker talks to $INPUT_DOCKER_HOST (context donico-action)"
fi

if [ "$setup_qemu" = true ]; then
  if docker run --rm --privileged "$BINFMT_IMAGE" --install all > /dev/null 2>&1; then
    info "binfmt handlers installed"
  else
    warn "cannot install the binfmt handlers (does the runner refuse privileged containers?): only the platform of the daemon will build"
  fi
fi

if [ "$setup_buildx" = true ]; then
  suffix="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  builder="donico-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-${GITHUB_JOB:-job}-$suffix"
  docker buildx create --use --bootstrap --name "$builder" ||
    fail "cannot create the buildx builder $builder"
  set_env DONICO_ACTION_BUILDER "$builder"
  info "buildx builder $builder created and selected"
fi

# The image store only matters to a bake build that loads several platforms.
cd "$working_directory"
if [ "$(donico image-builder)" = bake ]; then
  platforms="$(donico matrix | jq '[.[].archs | length] | max // 0')"
  if [ "$platforms" -gt 1 ]; then
    driver_status="$(docker info --format '{{json .DriverStatus}}')"
    if [[ "$driver_status" != *io.containerd.snapshotter* ]]; then
      warn "the Docker daemon does not use the containerd image store, which the build task needs to load a multi-platform image (the default from Docker 29 on)"
    fi
  fi
fi
