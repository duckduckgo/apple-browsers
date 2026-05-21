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
    BUNDLE_ID="com.duckduckgo.mobile.ios.alpha"
    TITLE="DuckDuckGo Alpha"
    ;;
  Release)
    BUNDLE_ID="com.duckduckgo.mobile.ios"
    TITLE="DuckDuckGo"
    ;;
  Experimental)
    BUNDLE_ID="com.duckduckgo.mobile.ios.experimental"
    TITLE="DuckDuckGo Experimental"
    ;;
  *)
    echo "Unknown build type: ${BUILD_TYPE}" >&2
    exit 1
    ;;
esac

COMMIT_SHORT_SHA="$(git rev-parse --short HEAD)"
BUILD_TIMESTAMP="$(date -u +'%Y-%m-%d %H:%M UTC')"

# Place manifest + install page in the same <sha>/ directory as the IPA, named
# after the IPA output name so re-runs on the same SHA with different suffixes
# do not overwrite each other.
ipa_dir_url="${IPA_URL%/*}"
ipa_dir_s3="${IPA_S3_PATH%/*}"
install_filename="${OUTPUT_NAME}.install.html"
manifest_filename="${OUTPUT_NAME}.manifest.plist"

manifest_url="${ipa_dir_url}/${manifest_filename}"
install_url="${ipa_dir_url}/${install_filename}"

# URL-encode the manifest URL for embedding in the itms-services link.
manifest_url_encoded="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "${manifest_url}")"

manifest_template_vars=(
  "IPA_URL=${IPA_URL}"
  "BUNDLE_ID=${BUNDLE_ID}"
  "BUNDLE_VERSION=${BUNDLE_VERSION}"
  "TITLE=${TITLE}"
)

install_template_vars=(
  "TITLE=${TITLE}"
  "BUNDLE_VERSION=${BUNDLE_VERSION}"
  "BUILD_NUMBER=${BUILD_NUMBER}"
  "BUILD_TYPE=${BUILD_TYPE}"
  "BUNDLE_ID=${BUNDLE_ID}"
  "COMMIT_SHORT_SHA=${COMMIT_SHORT_SHA}"
  "BUILD_TIMESTAMP=${BUILD_TIMESTAMP}"
  "MANIFEST_URL_ENCODED=${manifest_url_encoded}"
)

python3 "${action_dir}/render.py" "${action_dir}/ios_adhoc_manifest.plist" "${manifest_filename}" "${manifest_template_vars[@]}"
python3 "${action_dir}/render.py" "${action_dir}/ios_adhoc_install.html" "${install_filename}" "${install_template_vars[@]}"

aws s3 cp "${manifest_filename}" "${ipa_dir_s3}/${manifest_filename}" \
  --acl public-read --content-type "application/x-plist"
aws s3 cp "${install_filename}" "${ipa_dir_s3}/${install_filename}" \
  --acl public-read --content-type "text/html; charset=utf-8"

echo "install-url=${install_url}" >> "${GITHUB_OUTPUT}"
echo "title=${TITLE}" >> "${GITHUB_OUTPUT}"
