#!/bin/bash
#
# Copies llama.cpp's framework into the app without linking it. LlamaRuntime opens it at runtime,
# and only on iOS 16.4 or later: a linked framework would load at launch on every device, including
# iOS 15, which this build of llama.cpp doesn't support.
#
# The headers in SharedPackages/LlamaRuntime/Sources/CLlama/include, and LICENSE and
# THIRD-PARTY-NOTICES next to them, come from the same release. Update them together, and keep the
# tag and checksum the same as in macOS/scripts/embed_llama_framework.sh.
#
# Temporary, for the internal release and evals. Downloading llama.cpp's prebuilt release at build
# time, the hand-copied headers and opening the framework at runtime will be refactored before an
# external release.

set -euo pipefail

readonly LLAMA_TAG="b12262"
readonly LLAMA_ZIP_SHA256="704a9ede82cfa161dfcb4971394ffcf61e4c4d0f3ca7ad17355a93a0f9d7718b"
readonly LLAMA_ZIP_URL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_TAG}/llama-${LLAMA_TAG}-xcframework.zip"

# The release has no simulator build, so simulators go without it and report llama.cpp as unsupported.
if [[ "${ENABLE_PREVIEWS:-NO}" == "YES" || "${PLATFORM_NAME}" != "iphoneos" ]]; then
	exit 0
fi

cache_dir="${OBJROOT}/LlamaCpp/${LLAMA_TAG}"
source_framework="${cache_dir}/build-apple/llama.xcframework/ios-arm64/llama.framework"
frameworks_dir="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
destination="${frameworks_dir}/llama.framework"

if [[ ! -d "${source_framework}" ]]; then
	# Several builds can run this at once; each unpacks on its own and the first move wins.
	staging="${cache_dir}.$$"
	rm -rf "${staging}"
	mkdir -p "${staging}"
	zip_path="${staging}/llama.zip"
	echo "Downloading llama.cpp ${LLAMA_TAG}"
	curl --fail --location --silent --show-error --retry 3 --output "${zip_path}" "${LLAMA_ZIP_URL}"
	if ! echo "${LLAMA_ZIP_SHA256}  ${zip_path}" | shasum -a 256 --check --status; then
		echo "error: llama.cpp ${LLAMA_TAG} doesn't match its pinned SHA-256"
		rm -rf "${staging}"
		exit 1
	fi
	unzip -q "${zip_path}" -d "${staging}"
	rm -f "${zip_path}"
	mkdir -p "$(dirname "${cache_dir}")"
	mv "${staging}" "${cache_dir}" 2>/dev/null || true
	# When another build got there first, mv doesn't fail: it moves this copy inside the winner's folder.
	rm -rf "${staging}" "${cache_dir:?}/$(basename "${staging}")"
fi

rm -rf "${destination}"
mkdir -p "${frameworks_dir}"
ditto "${source_framework}" "${destination}"

# Headers and the module map are for linking, which nothing does.
rm -rf "${destination}/Headers" "${destination}/Modules"

# App Store Connect can reject a nested framework whose minimum is above the app's, or whose Info.plist claims
# a lower minimum than its binary (ITMS-90208). Both now claim the app's minimum, which is safe because only
# iOS 16.4 and later ever open this framework.
binary="${destination}/llama"
sdk_version="$(xcrun vtool -show-build "${binary}" | awk '$1 == "sdk" { print $2; exit }')"
xcrun vtool -set-build-version ios "${IPHONEOS_DEPLOYMENT_TARGET}" "${sdk_version}" -replace -output "${binary}.min" "${binary}"
mv "${binary}.min" "${binary}"
/usr/libexec/PlistBuddy -c "Set :MinimumOSVersion ${IPHONEOS_DEPLOYMENT_TARGET}" "${destination}/Info.plist"

# The release has no license files. Copied before signing, so the signature covers them.
license_dir="${SRCROOT}/../SharedPackages/LlamaRuntime/Sources/CLlama"
cp "${license_dir}/LICENSE" "${license_dir}/THIRD-PARTY-NOTICES" "${destination}/"

# iOS only opens code signed by the app's team. Exporting an archive signs it again for distribution.
if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
	codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${destination}"
fi
