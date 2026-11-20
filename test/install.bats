#!/usr/bin/env bats
# scripts/install.sh: puts the wanted donico on the PATH of the job's next
# steps. Nothing is downloaded when the donico already there is the wanted
# one (the donico image); otherwise the release archive of the runner's
# platform is downloaded, checked against checksums.txt and unpacked.

load test_helper

RELEASE_URL="https://github.com/jbox-web/donico/releases/download/v3.2.0"

setup() {
  setup_job
  use_stub curl uname
  export WANTED_VERSION=3.2.0 UNAME_STUB_S=Linux UNAME_STUB_M=x86_64
  export CURL_STUB_FILES="$JOB_DIR/release"
  INSTALL_DIR="$RUNNER_TEMP/donico-action/donico-3.2.0"
}

# Publish a fake release in $CURL_STUB_FILES: the archive of one platform,
# holding a donico that reports $2 and, unless $3 is "no-manager" (releases
# before 3.2.0), its donico-manager link; and a checksums.txt listing it among
# the other artefacts of a real release.
make_release() {
  local platform="$1" reports="$2" manager="${3:-}"
  local archive="donico_3.2.0_$platform.tar.gz"
  local content="$JOB_DIR/archive-content"
  mkdir -p "$CURL_STUB_FILES" "$content"
  # shellcheck disable=SC2016 # $1 belongs to the fake donico, not to this shell
  printf '#!/usr/bin/env bash\n[ "$1" = version ] && echo %s\n' "$reports" > "$content/donico"
  chmod +x "$content/donico"
  [ "$manager" = no-manager ] || ln -s donico "$content/donico-manager"
  printf 'MIT\n' > "$content/LICENSE"
  # Members named without "./", as in the archives of a real release.
  (cd "$content" && tar -czf "$CURL_STUB_FILES/$archive" -- *)
  {
    printf '%s  donico_3.2.0_amd64.deb\n' "558baf8c7b9d63dda50ca47f9d998ae34ecc633d14e2f5831d29219f14d673db"
    printf '%s  %s\n' "$(sha256sum "$CURL_STUB_FILES/$archive" | cut -d' ' -f1)" "$archive"
  } > "$CURL_STUB_FILES/checksums.txt"
}

@test "installs nothing when the donico on the PATH is the wanted version" {
  use_stub donico
  export DONICO_STUB_VERSION=3.2.0
  run_script install.sh
  [ "$status" -eq 0 ]
  [ "$output" = "donico-action: donico 3.2.0 is already installed" ]
  [ -z "$(stub_calls curl)" ]
  [ ! -s "$GITHUB_PATH" ]
  [ "$(cat "$GITHUB_OUTPUT")" = "version=3.2.0" ]
}

@test "downloads, checks and unpacks the archive of a linux amd64 runner" {
  make_release linux_amd64 3.2.0
  run_script install.sh
  [ "$status" -eq 0 ]
  [ "$output" = "donico-action: installed donico 3.2.0 (linux/amd64) in $INSTALL_DIR" ]
  [ "$(stub_calls curl)" = "--silent --show-error --fail --location --retry 3 --output $RUNNER_TEMP/donico-action/download/checksums.txt $RELEASE_URL/checksums.txt
--silent --show-error --fail --location --retry 3 --output $RUNNER_TEMP/donico-action/download/donico_3.2.0_linux_amd64.tar.gz $RELEASE_URL/donico_3.2.0_linux_amd64.tar.gz" ]
  [ "$(cat "$GITHUB_PATH")" = "$INSTALL_DIR" ]
  [ "$("$INSTALL_DIR/donico" version)" = "3.2.0" ]
  [ "$(readlink "$INSTALL_DIR/donico-manager")" = "donico" ]
  [ "$(cat "$GITHUB_OUTPUT")" = "version=3.2.0" ]
}

@test "installs a release without donico-manager, as before 3.2.0" {
  make_release linux_amd64 3.2.0 no-manager
  run_script install.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_PATH")" = "$INSTALL_DIR" ]
  [ "$("$INSTALL_DIR/donico" version)" = "3.2.0" ]
  [ ! -e "$INSTALL_DIR/donico-manager" ]
}

@test "stops on an archive it cannot unpack" {
  make_release linux_amd64 3.2.0
  printf 'not a tarball' > "$CURL_STUB_FILES/donico_3.2.0_linux_amd64.tar.gz"
  sed -i -E "s/^[0-9a-f]{64}  (donico_3\.2\.0_linux_amd64\.tar\.gz)$/$(sha256sum "$CURL_STUB_FILES/donico_3.2.0_linux_amd64.tar.gz" | cut -d' ' -f1)  \1/" "$CURL_STUB_FILES/checksums.txt"
  run_script install.sh
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "::error::donico-action: cannot unpack donico_3.2.0_linux_amd64.tar.gz" ]
  [ ! -s "$GITHUB_PATH" ]
}

@test "replaces a donico of another version" {
  use_stub donico
  export DONICO_STUB_VERSION=3.1.0
  make_release linux_amd64 3.2.0
  run_script install.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_PATH")" = "$INSTALL_DIR" ]
}

@test "takes the arm64 archive on an aarch64 linux runner" {
  export UNAME_STUB_M=aarch64
  make_release linux_arm64 3.2.0
  run_script install.sh
  [ "$status" -eq 0 ]
  [ "$output" = "donico-action: installed donico 3.2.0 (linux/arm64) in $INSTALL_DIR" ]
}

@test "takes the darwin archive on a macOS runner" {
  export UNAME_STUB_S=Darwin UNAME_STUB_M=arm64
  make_release darwin_arm64 3.2.0
  run_script install.sh
  [ "$status" -eq 0 ]
  [ "$output" = "donico-action: installed donico 3.2.0 (darwin/arm64) in $INSTALL_DIR" ]
}

@test "refuses a platform donico is not released for" {
  export UNAME_STUB_S=MINGW64_NT-10.0
  run_script install.sh
  [ "$status" -eq 1 ]
  [ "$output" = "::error::donico-action: donico is not released for this runner: MINGW64_NT-10.0 x86_64" ]
  [ -z "$(stub_calls curl)" ]
}

@test "refuses an archive whose checksum does not match, and adds nothing to the PATH" {
  make_release linux_amd64 3.2.0
  sed -i -E 's/^[0-9a-f]{64}  (donico_3\.2\.0_linux_amd64\.tar\.gz)$/0000000000000000000000000000000000000000000000000000000000000000  \1/' "$CURL_STUB_FILES/checksums.txt"
  run_script install.sh
  [ "$status" -eq 1 ]
  [ "$output" = "::error::donico-action: the checksum of donico_3.2.0_linux_amd64.tar.gz does not match checksums.txt" ]
  [ ! -s "$GITHUB_PATH" ]
  [ ! -e "$INSTALL_DIR" ]
  [ ! -s "$GITHUB_OUTPUT" ]
}

@test "refuses an archive that checksums.txt does not list" {
  make_release linux_amd64 3.2.0
  sed -i '/linux_amd64/d' "$CURL_STUB_FILES/checksums.txt"
  run_script install.sh
  [ "$status" -eq 1 ]
  [ "$output" = "::error::donico-action: donico_3.2.0_linux_amd64.tar.gz is not listed in checksums.txt" ]
  [ ! -s "$GITHUB_PATH" ]
}

@test "fails when the release cannot be downloaded, after curl's own message" {
  run_script install.sh
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "curl: (22) The requested URL returned error: 404" ]
  [ "${lines[1]}" = "::error::donico-action: cannot download $RELEASE_URL/checksums.txt" ]
  [ "${#lines[@]}" -eq 2 ]
  [ ! -s "$GITHUB_PATH" ]
}

@test "refuses an archive whose donico reports another version" {
  make_release linux_amd64 3.1.0
  run_script install.sh
  [ "$status" -eq 1 ]
  [ "$output" = "::error::donico-action: the donico of donico_3.2.0_linux_amd64.tar.gz reports version 3.1.0, not 3.2.0" ]
  [ ! -s "$GITHUB_PATH" ]
}

@test "refuses an archive that holds no donico" {
  make_release linux_amd64 3.2.0
  mkdir -p "$JOB_DIR/empty-archive"
  printf 'MIT\n' > "$JOB_DIR/empty-archive/LICENSE"
  (cd "$JOB_DIR/empty-archive" && tar -czf "$CURL_STUB_FILES/donico_3.2.0_linux_amd64.tar.gz" LICENSE)
  sed -i -E "s/^[0-9a-f]{64}  (donico_3\.2\.0_linux_amd64\.tar\.gz)$/$(sha256sum "$CURL_STUB_FILES/donico_3.2.0_linux_amd64.tar.gz" | cut -d' ' -f1)  \1/" "$CURL_STUB_FILES/checksums.txt"
  run_script install.sh
  [ "$status" -eq 1 ]
  [ "$output" = "::error::donico-action: donico_3.2.0_linux_amd64.tar.gz holds no donico" ]
  [ ! -s "$GITHUB_PATH" ]
}
