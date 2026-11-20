#!/usr/bin/env bash
# Write the matrix of the project in the form of `strategy.matrix.include`:
# one object per row of donico.yml, with its distro, its version and `task`,
# the prefix of its task names (`<distro>:<version>`), so that a workflow runs
# `donico ${{ matrix.task }}:build` without assembling anything. The image
# builder goes with it: a debuerreotype row has no `test` task.
#
# Everything comes from donico itself (`donico matrix`, `donico image-builder`):
# the action never reads donico.yml nor the files generated from it.
#
# Inputs (environment): INPUT_WORKING_DIRECTORY.
set -o errexit -o nounset -o pipefail
# shellcheck source=scripts/lib.sh
source "${BASH_SOURCE[0]%/*}/lib.sh"

working_directory="${INPUT_WORKING_DIRECTORY:-.}"
cd "$working_directory"

resolved="$(donico matrix)" || fail "donico refused the project in $working_directory"
builder="$(donico image-builder)" || fail "donico refused the project in $working_directory"

matrix="$(jq --compact-output '[.[] | {distro, version, task: "\(.distro):\(.version)"}]' <<< "$resolved")"
rows="$(jq length <<< "$matrix")"
[ "$rows" -gt 0 ] || fail "the matrix of $working_directory has no row"

set_output matrix "$matrix"
set_output image-builder "$builder"
info "$rows matrix rows, image builder $builder"
