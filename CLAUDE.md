# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

The GitHub Action of [donico](https://github.com/jbox-web/donico), a composite
action written in bash. It gives a job everything it needs before it runs
`donico <distro>:<version>:<task>`: it installs donico, gives the matrix of
`donico.yml` in the form of `strategy.matrix.include`, dates the build the way
donico expects under GitLab CI, and prepares Docker. A second action,
`cleanup/`, removes what the first one created.

The action never runs a donico task: those stay plain `run: donico ...` steps
of the workflow. It never changes donico either; everything it knows about a
project it asks donico (`donico matrix`, `donico image-builder`).

The README is the contract of the action (inputs, outputs, environment,
prerequisites). A behaviour change means updating it in the same change.

## Commands

Always go through `mise`: the tasks carry a timeout and put the pinned tools
(bats, shellcheck, jq, action-validator, actionlint) on the PATH.

```sh
mise run dev:test   # bats tests of the scripts
mise run dev:lint   # shellcheck, action-validator, actionlint
```

One test file, or one test by name:

```sh
mise exec -- bats test/docker.bats
mise exec -- bats test/docker.bats --filter "never prints"
```

CI (`.github/workflows/ci.yml`) runs both tasks, then the action for real: in
a bare Debian container on amd64 and arm64 (`matrix`), then on the runner
itself, where it builds the two-platform project of `example/` and calls the
cleanup action (`build`).

## Architecture

- `action.yml` is a list of steps, one script of `scripts/` each, in this
  order: `prerequisites.sh`, `version.sh`, `install.sh`, `matrix.sh`,
  `timestamp.sh`, `docker.sh`. `cleanup/action.yml` calls `cleanup.sh`.
- The inputs reach the scripts as `INPUT_*` environment variables. Nothing is
  interpolated into a `run:` line, so no input value is ever parsed as shell.
  A script passes a value to the next steps through `GITHUB_OUTPUT`,
  `GITHUB_ENV` or `GITHUB_PATH`, with the helpers of `scripts/lib.sh`
  (`set_output`, `set_env`, `add_path`).
- `scripts/lib.sh` also holds `info`, `warn` and `fail`. Every message starts
  with `donico-action:`; `fail` prints a `::error::` annotation and exits 1.
- `version.sh` picks the version: the `version` input, then the donico pin of
  `mise.toml` or `.mise.toml`, then the latest release (read from the redirect
  of `/releases/latest`, no API call). `install.sh` downloads nothing when the
  donico on the PATH already reports that version.
- `docker.sh` writes `registry-auth` to a Docker configuration of the job's
  own under `RUNNER_TEMP` and exports it as `DOCKER_CONFIG`; it records what it
  created in `DONICO_ACTION_BUILDER` and `DONICO_ACTION_DOCKER_CONFIG`, which
  is all `cleanup.sh` removes.
- `example/` is a real donico project (its generated files are committed, as
  in any image repository). The end-to-end job builds it; nothing pushes it.

### Tests

`test/test_helper.bash` runs a script the way a job step would, in a throwaway
directory, with a `PATH` of two directories only: `$STUB_BIN`, the stand-ins a
test asked for with `use_stub` (`test/stubs/`: docker, curl, donico, uname,
date), and `$TOOLS_BIN`, links to the real tools listed in `JOB_TOOLS`. The
stand-ins log their arguments under `$STUB_LOG` and answer what the test set
in their environment variables.

## Constraints that are easy to break

- **A test before the code.** Every script behaviour has a bats test, written
  and seen failing first. The expected values are literals written from the
  README and the design, never copied from what a run printed.
- **A tool a script calls must be in `JOB_TOOLS`** (`test/test_helper.bash`)
  and, when a bare runner may lack it, in the checks of `prerequisites.sh` and
  the "Prerequisites" section of the README. The action checks its
  prerequisites and never installs them.
- **Nothing specific to one fleet.** No registry host, secret name or daemon
  address in the action: whatever varies from one runner to another is an
  input.
- **No heuristic on `donico.yml`.** The action never reads it nor the files
  generated from it.
- **The registry credentials are never printed**, and their file exists with
  mode 0600 before they are written to it. `cleanup.sh` only removes the one
  directory the action writes, whatever the environment says.
- **binfmt runs privileged**, so its image is pinned by digest, the same one
  as the GitLab template of the jbox fleet. Change both together.
- **`cleanup.sh` never fails the job**: it runs last, with `if: always()`.
- **Tags are annotated, signed and never moved**: there is no floating `v1`
  tag. The README examples reference an exact tag.
- **Workflow invariants**: `permissions: {}` at the top of the workflow and
  `persist-credentials: false` on every `actions/checkout`. Check the latest
  published version of an action before pinning or bumping it.
