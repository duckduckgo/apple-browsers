#!/usr/bin/env bash
set -euxo pipefail

# Bitrise Build Cache CLI release to install. To update, change the version and copy the
# darwin checksums from bitrise-build-cache_<version>_checksums.txt of that release.
version="3.19.5"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "::error::Unsupported OS: $(uname -s)"
  exit 1
fi

case "$(uname -m)" in
  arm64)
    arch="arm64"
    expected_sha256="95f1c36a64b30f37d7d7527c9840d3c7ccea772e014b617a9f6b5c994558595a"
    ;;
  x86_64)
    arch="amd64"
    expected_sha256="d9e44e31504752f368b086d2f1ba2e2a1612b0a122850e1da64f2345ee2a803b"
    ;;
  *)
    echo "::error::Unsupported architecture: $(uname -m)"
    exit 1
    ;;
esac

# download Bitrise Build Cache CLI and verify it before installing
archive="bitrise-build-cache_${version}_darwin_${arch}.tar.gz"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
curl --retry 5 -sSfL -o "${tmp_dir}/${archive}" "https://github.com/bitrise-io/bitrise-build-cache-cli/releases/download/v${version}/${archive}"
echo "${expected_sha256}  ${tmp_dir}/${archive}" | shasum -a 256 -c -
tar -xzf "${tmp_dir}/${archive}" -C "$tmp_dir" bitrise-build-cache
mkdir -p /tmp/bin
install "${tmp_dir}/bitrise-build-cache" /tmp/bin/

# run the CLI to enable Bitrise build cache for Xcode
/tmp/bin/bitrise-build-cache activate xcode --cache --cache-push
