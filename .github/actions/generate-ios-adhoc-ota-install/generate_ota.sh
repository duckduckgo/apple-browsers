#!/usr/bin/env bash
set -euo pipefail

: "${BUILD_TYPE:?Missing BUILD_TYPE}"
: "${IPA_URL:?Missing IPA_URL}"
: "${IPA_S3_PATH:?Missing IPA_S3_PATH}"
: "${BUNDLE_VERSION:?Missing BUNDLE_VERSION}"
: "${BUILD_NUMBER:?Missing BUILD_NUMBER}"
: "${OUTPUT_NAME:?Missing OUTPUT_NAME}"

action_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Bundle ID and display title per build type. These must match the IPA's actual
# bundle ID exactly or iOS will fail OTA install with a generic error.
case "${BUILD_TYPE}" in
  Alpha)
    export BUNDLE_ID="com.duckduckgo.mobile.ios.alpha"
    export TITLE="DuckDuckGo Alpha"
    ;;
  Release)
    export BUNDLE_ID="com.duckduckgo.mobile.ios"
    export TITLE="DuckDuckGo"
    ;;
  Experimental)
    export BUNDLE_ID="com.duckduckgo.mobile.ios.experimental"
    export TITLE="DuckDuckGo Experimental"
    ;;
  *)
    echo "Unknown build type: ${BUILD_TYPE}" >&2
    exit 1
    ;;
esac

export BUILD_TYPE
export IPA_URL
export BUNDLE_VERSION
export BUILD_NUMBER
export COMMIT_SHORT_SHA="$(git rev-parse --short HEAD)"
export BUILD_TIMESTAMP="$(date -u +'%Y-%m-%d %H:%M UTC')"

# Place manifest + install page in the same <sha>/ directory as the IPA, named
# after the IPA output name so re-runs on the same SHA with different suffixes
# do not overwrite each other.
ipa_dir_url="${IPA_URL%/*}"
ipa_dir_s3="${IPA_S3_PATH%/*}"
manifest_filename="${OUTPUT_NAME}.manifest.plist"
install_filename="${OUTPUT_NAME}.install.html"

export MANIFEST_URL="${ipa_dir_url}/${manifest_filename}"
install_url="${ipa_dir_url}/${install_filename}"

# URL-encode the manifest URL for embedding in the itms-services link.
export MANIFEST_URL_ENCODED="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "${MANIFEST_URL}")"

python3 "${action_dir}/render.py" "${action_dir}/ios_adhoc_manifest.plist" "${manifest_filename}"
python3 "${action_dir}/render.py" "${action_dir}/ios_adhoc_install.html" "${install_filename}"

aws s3 cp "${manifest_filename}" "${ipa_dir_s3}/${manifest_filename}" \
  --acl public-read --content-type "application/x-plist"
aws s3 cp "${install_filename}" "${ipa_dir_s3}/${install_filename}" \
  --acl public-read --content-type "text/html; charset=utf-8"

echo "install-url=${install_url}" >> "${GITHUB_OUTPUT}"
echo "title=${TITLE}" >> "${GITHUB_OUTPUT}"
