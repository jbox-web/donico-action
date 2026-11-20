#!/usr/bin/env bats
# scripts/timestamp.sh: donico dates its builds from two GitLab variables.
# The action sets them for the rest of the job, unless they are already set:
# CI_COMMIT_TIMESTAMP to the date of the commit being built (the build tag and
# BUILD_DATE of a bake image), CI_PIPELINE_CREATED_AT to the time the action
# runs (the day of a Debian root filesystem, shared by build and push).

load test_helper

setup() {
  setup_job
  use_stub date
  export DATE_STUB=2026-11-20T10:15:00Z
  git -C "$WORK" init --quiet
  GIT_COMMITTER_DATE="2026-11-17T09:30:00+01:00" GIT_AUTHOR_DATE="2026-11-01T08:00:00+01:00" \
    git -C "$WORK" -c user.name=test -c user.email=test@example.org \
    commit --quiet --allow-empty --message "the commit being built"
}

@test "sets both variables, from the commit date and from the clock" {
  run_script timestamp.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_ENV")" = "CI_COMMIT_TIMESTAMP=2026-11-17T09:30:00+01:00
CI_PIPELINE_CREATED_AT=2026-11-20T10:15:00Z" ]
  [ "$output" = "donico-action: CI_COMMIT_TIMESTAMP=2026-11-17T09:30:00+01:00 (date of the commit)
donico-action: CI_PIPELINE_CREATED_AT=2026-11-20T10:15:00Z (now)" ]
  [ "$(stub_calls date)" = "-u +%Y-%m-%dT%H:%M:%SZ" ]
}

@test "keeps the variables the job already set" {
  export CI_COMMIT_TIMESTAMP=2026-01-02T03:04:05+00:00 CI_PIPELINE_CREATED_AT=2026-01-02T00:00:00+00:00
  run_script timestamp.sh
  [ "$status" -eq 0 ]
  [ ! -s "$GITHUB_ENV" ]
  [ "$output" = "donico-action: CI_COMMIT_TIMESTAMP already set, kept
donico-action: CI_PIPELINE_CREATED_AT already set, kept" ]
}

@test "counts an empty variable as unset, as donico does" {
  export CI_COMMIT_TIMESTAMP="" CI_PIPELINE_CREATED_AT=""
  run_script timestamp.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_ENV")" = "CI_COMMIT_TIMESTAMP=2026-11-17T09:30:00+01:00
CI_PIPELINE_CREATED_AT=2026-11-20T10:15:00Z" ]
}

@test "dates the commit of the working directory" {
  mkdir -p "$JOB_DIR/other"
  git -C "$JOB_DIR/other" init --quiet
  GIT_COMMITTER_DATE="2025-05-05T05:05:05+02:00" \
    git -C "$JOB_DIR/other" -c user.name=test -c user.email=test@example.org \
    commit --quiet --allow-empty --message "another repository"
  export INPUT_WORKING_DIRECTORY="$JOB_DIR/other"
  run_script timestamp.sh
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "$GITHUB_ENV")" = "CI_COMMIT_TIMESTAMP=2025-05-05T05:05:05+02:00" ]
}

@test "stops when the working directory is not a git checkout" {
  mkdir -p "$JOB_DIR/plain"
  export INPUT_WORKING_DIRECTORY="$JOB_DIR/plain" GIT_CEILING_DIRECTORIES="$JOB_DIR"
  run_script timestamp.sh
  [ "$status" -eq 1 ]
  [ "$output" = "::error::donico-action: cannot date the commit: $JOB_DIR/plain is not a git checkout; check the repository out first, or set CI_COMMIT_TIMESTAMP" ]
  [ ! -s "$GITHUB_ENV" ]
}

@test "needs no git checkout when the commit date is already set" {
  mkdir -p "$JOB_DIR/plain"
  export INPUT_WORKING_DIRECTORY="$JOB_DIR/plain" GIT_CEILING_DIRECTORIES="$JOB_DIR"
  export CI_COMMIT_TIMESTAMP=2026-01-02T03:04:05+00:00
  run_script timestamp.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_ENV")" = "CI_PIPELINE_CREATED_AT=2026-11-20T10:15:00Z" ]
}
