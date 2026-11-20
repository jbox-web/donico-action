#!/usr/bin/env bats
# scripts/matrix.sh: asks donico for the matrix of the project and writes it
# in the form of `strategy.matrix.include`, one object per row with the
# distro, the version and the task prefix, plus the image builder.

load test_helper

setup() {
  setup_job
  use_stub donico
}

@test "writes the rows of a bake project, with their task prefix" {
  export DONICO_STUB_MATRIX="$BATS_TEST_DIRNAME/fixtures/matrix-bake.json" DONICO_STUB_BUILDER=bake
  run_script matrix.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_OUTPUT")" = 'matrix=[{"distro":"bookworm","version":"1.0","task":"bookworm:1.0"},{"distro":"trixie","version":"2.0","task":"trixie:2.0"}]
image-builder=bake' ]
  [ "$output" = "donico-action: 2 matrix rows, image builder bake" ]
}

@test "writes the rows of a debuerreotype project" {
  export DONICO_STUB_MATRIX="$BATS_TEST_DIRNAME/fixtures/matrix-debuerreotype.json" DONICO_STUB_BUILDER=debuerreotype
  run_script matrix.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_OUTPUT")" = 'matrix=[{"distro":"trixie","version":"13","task":"trixie:13"},{"distro":"bookworm","version":"12","task":"bookworm:12"}]
image-builder=debuerreotype' ]
}

@test "asks donico in the working directory" {
  mkdir -p "$WORK/image"
  export INPUT_WORKING_DIRECTORY="$WORK/image"
  export DONICO_STUB_MATRIX="$BATS_TEST_DIRNAME/fixtures/matrix-bake.json"
  run_script matrix.sh
  [ "$status" -eq 0 ]
  [ "$(stub_calls donico)" = "$WORK/image matrix
$WORK/image image-builder" ]
}

@test "stops with donico's own message when donico refuses the project" {
  export DONICO_STUB_ERROR="version must be a quoted string"
  run_script matrix.sh
  [ "$status" -eq 1 ]
  [ "$output" = "donico: version must be a quoted string
::error::donico-action: donico refused the project in $WORK" ]
  [ ! -s "$GITHUB_OUTPUT" ]
}

@test "refuses an empty matrix" {
  printf '[]\n' > "$JOB_DIR/empty.json"
  export DONICO_STUB_MATRIX="$JOB_DIR/empty.json"
  run_script matrix.sh
  [ "$status" -eq 1 ]
  [ "$output" = "::error::donico-action: the matrix of $WORK has no row" ]
  [ ! -s "$GITHUB_OUTPUT" ]
}
