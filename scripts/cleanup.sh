#!/usr/bin/env bash
# Remove what the action created and the job does not take away with it: the
# buildx builder (a buildkit container on the daemon) and the Docker
# configuration that holds the registry credentials. Needed when the daemon or
# the disk outlive the job; harmless otherwise.
#
# It never fails the job: it runs last, often with `if: always()`, and a
# failure there would hide the result of the build. It only removes the one
# configuration directory the action writes, whatever the environment says.
#
# Inputs (environment): DONICO_ACTION_BUILDER, DONICO_ACTION_DOCKER_CONFIG,
# both set by scripts/docker.sh for the rest of the job.
set -o errexit -o nounset -o pipefail
# shellcheck source=scripts/lib.sh
source "${BASH_SOURCE[0]%/*}/lib.sh"

builder="${DONICO_ACTION_BUILDER:-}"
config_dir="${DONICO_ACTION_DOCKER_CONFIG:-}"

if [ -z "$builder" ] && [ -z "$config_dir" ]; then
  info "nothing to clean up"
  exit 0
fi

if [ -n "$builder" ]; then
  if docker buildx rm "$builder" > /dev/null 2>&1; then
    info "buildx builder $builder removed"
  else
    warn "cannot remove the buildx builder $builder"
  fi
fi

if [ -n "$config_dir" ]; then
  if [ "$config_dir" != "${RUNNER_TEMP:-}/donico-action/docker-config" ]; then
    warn "not removing $config_dir: it is not a directory of this action"
  else
    rm -rf "$config_dir"
    info "Docker configuration $config_dir removed"
  fi
fi
