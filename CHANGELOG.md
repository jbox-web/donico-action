# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-20

### Added

- The donico action: installs donico (version input, then the pin of
  `mise.toml`, then the latest release; archive checked against
  `checksums.txt`), gives the matrix of `donico.yml` for
  `strategy.matrix.include` and the image builder, sets `CI_COMMIT_TIMESTAMP`
  and `CI_PIPELINE_CREATED_AT`, and prepares Docker (`docker-host`,
  `registry-auth` in a Docker configuration of the job's own, binfmt pinned by
  digest, a buildx builder of the job's own).
- The cleanup action, which removes the builder and the Docker configuration.
