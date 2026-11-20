#!/usr/bin/env bash
# Put the wanted donico on the PATH of the job's next steps.
#
# When the donico already on the PATH reports the wanted version (a job that
# runs in the donico image), nothing is downloaded. Otherwise the release
# archive of the runner's platform is downloaded with the checksums.txt of the
# same release, checked, unpacked into RUNNER_TEMP, and its donico asked for
# its version before the directory is added to the PATH: a wrong checksum or
# a wrong binary leaves the PATH as it was.
#
# Inputs (environment): WANTED_VERSION, from scripts/version.sh.
set -o errexit -o nounset -o pipefail
# shellcheck source=scripts/lib.sh
source "${BASH_SOURCE[0]%/*}/lib.sh"

version="$WANTED_VERSION"

if command -v donico > /dev/null && [ "$(donico version 2> /dev/null)" = "$version" ]; then
  set_output version "$version"
  info "donico $version is already installed"
  exit 0
fi

kernel="$(uname -s)"
machine="$(uname -m)"
case "$kernel" in
  Linux) os=linux ;;
  Darwin) os=darwin ;;
  *) os="" ;;
esac
case "$machine" in
  x86_64 | amd64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) arch="" ;;
esac
if [ -z "$os" ] || [ -z "$arch" ]; then
  fail "donico is not released for this runner: $kernel $machine"
fi

archive="donico_${version}_${os}_${arch}.tar.gz"
base_url="$DONICO_RELEASES/download/v$version"
work="$RUNNER_TEMP/donico-action"
download="$work/download"
install_dir="$work/donico-$version"
rm -rf "$download"
mkdir -p "$download/unpacked"

for file in checksums.txt "$archive"; do
  curl --silent --show-error --fail --location --retry 3 \
    --output "$download/$file" "$base_url/$file" ||
    fail "cannot download $base_url/$file"
done

expected="$(awk -v name="$archive" '$2 == name { print $1 }' "$download/checksums.txt")"
[ -n "$expected" ] || fail "$archive is not listed in checksums.txt"
actual="$(sha256sum "$download/$archive" | cut -d' ' -f1)"
[ "$actual" = "$expected" ] || fail "the checksum of $archive does not match checksums.txt"

# The whole archive: donico-manager only ships from 3.2.0 on.
tar -xzf "$download/$archive" -C "$download/unpacked" || fail "cannot unpack $archive"
[ -x "$download/unpacked/donico" ] || fail "$archive holds no donico"
reported="$("$download/unpacked/donico" version)"
[ "$reported" = "$version" ] ||
  fail "the donico of $archive reports version $reported, not $version"

rm -rf "$install_dir"
mv "$download/unpacked" "$install_dir"
rm -rf "$download"

add_path "$install_dir"
set_output version "$version"
info "installed donico $version ($os/$arch) in $install_dir"
