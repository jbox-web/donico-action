#!/usr/bin/env bash
# Give donico the dates it reads under GitLab CI, for the rest of the job.
#
# donico dates a bake build from CI_COMMIT_TIMESTAMP, and falls back on the
# day of the clock, computed again by every command: under GitHub Actions a
# job across midnight would build under one tag and test under another, and
# the tag would carry the day only. The action sets it to the date of the
# commit being built: 14 digits, the same value for build, test and push, and
# the same for every build of one commit. (Under GitLab CI, donico dates the
# tag from CI_PIPELINE_CREATED_AT instead, so that two pipelines of one commit
# on a shared Docker daemon do not share it; it does not read that variable
# here, where the action sets it to the time each job starts.)
#
# A Debian root filesystem (image_builder: debuerreotype) is dated from the
# day before CI_PIPELINE_CREATED_AT: it names a state of the Debian archive,
# not a commit. The action sets it to the time it runs, so that build and push
# of one job agree.
#
# A variable the job already set, to a non-empty value, is left alone (donico
# counts an empty one as unset).
#
# Inputs (environment): INPUT_WORKING_DIRECTORY, CI_COMMIT_TIMESTAMP,
# CI_PIPELINE_CREATED_AT.
set -o errexit -o nounset -o pipefail
# shellcheck source=scripts/lib.sh
source "${BASH_SOURCE[0]%/*}/lib.sh"

working_directory="${INPUT_WORKING_DIRECTORY:-.}"

if [ -n "${CI_COMMIT_TIMESTAMP:-}" ]; then
  info "CI_COMMIT_TIMESTAMP already set, kept"
else
  # safe.directory: in a job container the checkout belongs to another uid
  # than the job's user, and git refuses a repository it does not own.
  commit_date="$(git -c safe.directory='*' -C "$working_directory" log -1 --format=%cI 2> /dev/null)" ||
    fail "cannot date the commit: $working_directory is not a git checkout; check the repository out first, or set CI_COMMIT_TIMESTAMP"
  set_env CI_COMMIT_TIMESTAMP "$commit_date"
  info "CI_COMMIT_TIMESTAMP=$commit_date (date of the commit)"
fi

if [ -n "${CI_PIPELINE_CREATED_AT:-}" ]; then
  info "CI_PIPELINE_CREATED_AT already set, kept"
else
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  set_env CI_PIPELINE_CREATED_AT "$now"
  info "CI_PIPELINE_CREATED_AT=$now (now)"
fi
