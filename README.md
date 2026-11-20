# donico-action

[![CI](https://github.com/jbox-web/donico-action/actions/workflows/ci.yml/badge.svg)](https://github.com/jbox-web/donico-action/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/tag/jbox-web/donico-action?sort=semver&label=release)](https://github.com/jbox-web/donico-action/tags)
[![License: MIT](https://img.shields.io/github/license/jbox-web/donico-action)](LICENSE)

The GitHub Action of [donico](https://github.com/jbox-web/donico): everything a
job needs before it runs `donico <distro>:<version>:<task>`.

- **Installs donico**, at the version the project pins in its `mise.toml`, the
  archive checked against the `checksums.txt` of its release. A job that already
  runs in an image with the right donico downloads nothing.
- **Gives the matrix** of `donico.yml` in the form of `strategy.matrix.include`,
  one entry per row, with the prefix of its task names.
- **Dates the build** the way donico expects under GitLab CI, so that `build`,
  `test` and `push` of a job agree on the tags.
- **Prepares Docker**: the daemon to talk to, the registry credentials, the
  binfmt handlers of a multi-platform build, and a buildx builder of the job's
  own.

The tasks themselves are plain `run: donico ...` steps.

## Usage

Two jobs: one reads the matrix, the other builds, tests and pushes each row.

```yaml
jobs:
  matrix:
    runs-on: ubuntu-24.04
    outputs:
      include: ${{ steps.donico.outputs.matrix }}
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: jbox-web/donico-action@v1.0.0
        id: donico
        with:
          setup-docker: false

  images:
    needs: matrix
    runs-on: ubuntu-24.04
    strategy:
      fail-fast: false
      matrix:
        include: ${{ fromJSON(needs.matrix.outputs.include) }}
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: jbox-web/donico-action@v1.0.0
        id: donico
        with:
          registry-auth: ${{ secrets.REGISTRY_DOCKER_CONFIG }}
      - run: donico ${{ matrix.task }}:build
      - run: donico ${{ matrix.task }}:test
        if: steps.donico.outputs.image-builder == 'bake'
      - run: donico ${{ matrix.task }}:push
        if: github.ref_name == 'master'
```

`test` is skipped for a Debian root filesystem (`image_builder: debuerreotype`),
whose rows have no such task.

### In a job container, with a docker-in-docker service

A self-hosted runner that runs the job in a container and gives it a daemon as a
service passes the address of that daemon:

```yaml
  images:
    runs-on: [self-hosted, dind]
    container: registry.example.com/base/donico:3.2.0
    services:
      docker:
        image: docker:29-dind
        options: --privileged
        env:
          DOCKER_TLS_CERTDIR: ""
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: jbox-web/donico-action@v1.0.0
        with:
          registry-auth: ${{ secrets.REGISTRY_DOCKER_CONFIG }}
          docker-host: tcp://docker:2375
      - run: donico ${{ matrix.task }}:build
```

When the image of the job container already holds the wanted donico, the action
uses it and downloads nothing.

## Inputs

| Input | Default | What it does |
|---|---|---|
| `version` | the pin of `mise.toml`, else the latest release | Version of donico to install, with or without its leading `v`. |
| `working-directory` | `.` | Directory that holds `donico.yml`. |
| `setup-docker` | `true` | Prepare Docker. `false` in a job that only reads the matrix: no `docker` command is run. |
| `registry-auth` | none | Content of a Docker `config.json` holding the registry credentials. Pass it from a secret. |
| `docker-host` | none | Address of the Docker daemon, exported as `DOCKER_HOST`. |
| `setup-qemu` | `true` | Install the binfmt handlers that let the daemon build every platform. |
| `setup-buildx` | `true` | Create and select a buildx builder of the job's own. |

The three booleans take `true` or `false` and nothing else: a typo stops the
action instead of switching a step off.

### The version of donico

In this order:

1. the `version` input;
2. the pin of `mise.toml`, then of `.mise.toml`, in `working-directory`, written
   `"github:jbox-web/donico" = "3.2.0"` or `"aqua:jbox-web/donico" = "3.2.0"`
   (single quotes and a trailing comment are fine);
3. the latest release, read from the redirect of
   `https://github.com/jbox-web/donico/releases/latest`: no API call, no token.

A pin the action cannot read, such as `= "latest"` or a table
`= { version = "3.2.0" }`, stops it with the line it found: it never falls back
on the latest release behind your back.

## Outputs

| Output | Content |
|---|---|
| `version` | Version of donico on the `PATH`. |
| `matrix` | The rows of `donico.yml` as a JSON array for `strategy.matrix.include`: `distro`, `version`, and `task`, the prefix of their task names (`"bookworm:1.0"`). |
| `image-builder` | `bake` or `debuerreotype`. |

For a `donico.yml` with two rows:

```json
[{"distro":"bookworm","version":"1.0","task":"bookworm:1.0"},{"distro":"trixie","version":"2.0","task":"trixie:2.0"}]
```

The matrix comes from `donico matrix`: the action never reads `donico.yml` nor
the files generated from it, and a `donico.yml` that donico refuses stops it
with donico's own message.

## What it sets for the rest of the job

| Variable | Value |
|---|---|
| `PATH` | Prepended with the directory of the downloaded donico, when one is downloaded. |
| `CI_COMMIT_TIMESTAMP` | The date of the commit being built (`git log -1 --format=%cI`). donico derives the build tag and `BUILD_DATE` from it: the same 14 digits as under GitLab CI, the same for every task of the job and for every build of one commit. |
| `CI_PIPELINE_CREATED_AT` | The time the action ran. A Debian root filesystem is dated from the day before it, so `build` and `push` of one job agree. |
| `DOCKER_HOST` | `docker-host`, when given. |
| `DOCKER_CONFIG` | The Docker configuration written from `registry-auth`, when given. The CLI plugins of the configuration it replaces (`~/.docker/cli-plugins`) are linked into it. |
| `DONICO_ACTION_BUILDER`, `DONICO_ACTION_DOCKER_CONFIG` | What the cleanup action removes. |

`CI_COMMIT_TIMESTAMP` and `CI_PIPELINE_CREATED_AT` are left alone when the job
already set them. Without them donico would fall back on the day of the clock,
computed again by each command: a job across midnight would build under one tag
and test under another.

## Docker

- **Credentials**: `registry-auth` is written to a directory of the job's own
  under `RUNNER_TEMP`, in a file created `0600` before the credentials go in.
  The runner's `~/.docker` is neither read nor changed, and the value is never
  printed.
- **binfmt** runs privileged, so its image is pinned by digest. A runner that
  refuses privileged containers gets a warning, not an error: it can still build
  the platform of its own daemon.
- **The builder** is named after the run, the job and a random suffix, so that
  jobs sharing a daemon never share a builder.
- **The containerd image store**: the `build` task of a bake project loads its
  image into the daemon, and a multi-platform image needs the containerd image
  store, the default from Docker 29 on. The action does not change the daemon:
  it warns when a row builds several platforms and the store is not there.

## Cleanup

On a daemon or a disk that outlive the job (a self-hosted runner without an
ephemeral daemon), end the job with the cleanup action. It removes the builder
and the Docker configuration, and never fails the job:

```yaml
      - uses: jbox-web/donico-action/cleanup@v1.0.0
        if: always()
```

It is not needed when the daemon is a service of the job, or on a runner hosted
by GitHub.

## Prerequisites

Its steps run with `bash`. It checks the other tools first and names the one
that is missing; it never installs them.

- `jq`, `curl`, `tar`, `gzip`, `sha256sum` and `git`;
- with `setup-docker: true`, the `docker` CLI and its buildx plugin;
- a checkout of the repository: the commit date comes from it.

The runners hosted by GitHub have all of them. A Debian job container needs
`apt-get install ca-certificates curl git jq`.

## Versions

Releases are tagged `vX.Y.Z`, annotated and signed, and a tag is never moved:
there is no `v1` tag following the latest `v1.x.y`. Reference an exact tag.

## Development

```sh
mise run dev:test   # bats tests of the scripts, with stand-ins for docker, curl and donico
mise run dev:lint   # shellcheck, action-validator, actionlint
```

Each step of `action.yml` is one script of `scripts/`, tested on its own in
`test/`. The workflow of this repository also runs the action for real: in a
Debian container on amd64 and arm64, then on the runner itself, where it builds
the two-platform project of `example/`.

## License

MIT, see [LICENSE](LICENSE).
