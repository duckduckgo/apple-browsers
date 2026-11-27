#!/bin/bash
#
# Copies llama.cpp's framework into the app without linking it. LlamaRuntime opens it at runtime,
# and only on Apple silicon with macOS 13.3 or later: a linked framework would load at launch on
# every Mac, including macOS 12, which this build of llama.cpp doesn't support.
#
# The headers in SharedPackages/LlamaRuntime/Sources/CLlama/include, and LICENSE and
# THIRD-PARTY-NOTICES next to them, come from the same release. Update them together.
#
# Temporary, for the internal release and evals. Downloading llama.cpp's prebuilt release at build
# time, the hand-copied headers and opening the framework at runtime will be refactored before an
# external release.

set -euo pipefail

readonly LLAMA_TAG="b12262"
readonly LLAMA_ZIP_SHA256="704a9ede82cfa161dfcb4971394ffcf61e4c4d0f3ca7ad17355a93a0f9d7718b"
readonly LLAMA_ZIP_URL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_TAG}/llama-${LLAMA_TAG}-xcframework.zip"

if [[ "${ENABLE_PREVIEWS:-NO}" == "YES" ]]; then
	exit 0
fi

cache_dir="${OBJROOT}/LlamaCpp/${LLAMA_TAG}"
source_framework="${cache_dir}/build-apple/llama.xcframework/macos-arm64_x86_64/llama.framework"
frameworks_dir="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
destination="${frameworks_dir}/llama.framework"

if [[ ! -d "${source_framework}" ]]; then
	# Several targets can run this at once; each unpacks on its own and the first move wins.
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
	# When another target got there first, mv doesn't fail: it moves this copy inside the winner's folder.
	rm -rf "${staging}" "${cache_dir:?}/$(basename "${staging}")"
fi

rm -rf "${destination}"
mkdir -p "${frameworks_dir}"
ditto "${source_framework}" "${destination}"

# Only Apple silicon ever loads it, so the Intel half would be dead weight in every download.
binary="${destination}/Versions/A/llama"
lipo "${binary}" -thin arm64 -output "${binary}.arm64"
mv "${binary}.arm64" "${binary}"

# Headers and the module map are for linking, which nothing does.
rm -rf "${destination}/Headers" "${destination}/Modules" \
	"${destination}/Versions/A/Headers" "${destination}/Versions/A/Modules"

# The release has no license files. Copied before signing, so the signature covers them.
license_dir="${SRCROOT}/../SharedPackages/LlamaRuntime/Sources/CLlama"
cp "${license_dir}/LICENSE" "${license_dir}/THIRD-PARTY-NOTICES" "${destination}/Versions/A/Resources/"

# The app's own signature covers nested code, so the framework is signed with the same identity.
# Exporting an archive signs it again for distribution.
if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
	timestamp="--timestamp"
	if [[ "${CONFIGURATION}" == "Debug" ]]; then
		timestamp="--timestamp=none"
	fi
	codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --options runtime "${timestamp}" "${destination}/Versions/A"
fi
