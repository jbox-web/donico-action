#!/usr/bin/env bash
# Check the tools the action needs, before it changes anything. The action
# never installs them: a runner or a job container that lacks one is told
# which, and the job stops.
#
# Inputs (environment): INPUT_SETUP_DOCKER.
set -o errexit -o nounset -o pipefail
# shellcheck source=scripts/lib.sh
source "${BASH_SOURCE[0]%/*}/lib.sh"

# jq shapes the matrix, curl and sha256sum fetch and verify the release, tar
# and gzip unpack it, git dates the commit.
tools=(jq curl tar gzip sha256sum git)
setup_docker=false
if input_true setup-docker "${INPUT_SETUP_DOCKER:-true}"; then
  setup_docker=true
fi

for tool in "${tools[@]}"; do
  command -v "$tool" > /dev/null || fail "$tool is required and was not found in PATH"
done

found="${tools[*]}"
if [ "$setup_docker" = true ]; then
  command -v docker > /dev/null || fail "docker is required and was not found in PATH"
  docker buildx version > /dev/null 2>&1 ||
    fail "the docker buildx plugin is required and \`docker buildx version\` failed"
  found="$found docker docker-buildx"
fi

found="${found// /, }"
info "found ${found/docker-buildx/docker buildx}"
