#!/bin/bash
#
# Sets the CFBundleVersion of a system extension built in the Debug or Review
# configuration to "<CURRENT_PROJECT_VERSION>.<content number>", where the
# content number changes whenever the extension's content changes.
#
# Run it as the last build phase of a system extension target, before code
# signing. Other configurations keep CURRENT_PROJECT_VERSION.
#
# Mach-O files contribute their linker UUIDs instead of their bytes, so the
# code signature embedded in them doesn't change the number. The Info.plist
# contributes everything except CFBundleVersion, and the entitlements file in
# CODE_SIGN_ENTITLEMENTS contributes its content.

set -euo pipefail

case "${CONFIGURATION}" in
    Debug|Review) ;;
    *) exit 0 ;;
esac

bundle_path="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
info_plist_path="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"

content_fingerprint() {
    cd "${bundle_path}"
    find . -type f ! -path '*/_CodeSignature/*' ! -path './Contents/Info.plist' -print0 \
        | LC_ALL=C sort -z \
        | while IFS= read -r -d '' file; do
            if file -b "${file}" | grep -q 'Mach-O'; then
                printf '%s ' "${file}"
                dwarfdump --uuid "${file}" | awk '{ print $2, $3 }' | LC_ALL=C sort | tr '\n' ' '
                printf '\n'
            else
                shasum -a 256 "${file}"
            fi
        done

    plutil -remove CFBundleVersion -o - "${info_plist_path}" | shasum -a 256

    if [ -n "${CODE_SIGN_ENTITLEMENTS:-}" ]; then
        shasum -a 256 < "${SRCROOT}/${CODE_SIGN_ENTITLEMENTS}"
    fi
}

content_number=$((16#$(content_fingerprint | shasum -a 256 | cut -c1-7)))
bundle_version="${CURRENT_PROJECT_VERSION}.${content_number}"

current_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${info_plist_path}")
if [ "${current_version}" != "${bundle_version}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${bundle_version}" "${info_plist_path}"
fi

echo "CFBundleVersion of ${WRAPPER_NAME}: ${bundle_version}"
