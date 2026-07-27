#!/bin/bash
#
# Works around an Xcode Previews bug that breaks every preview in the macOS app.
#
# Any target that uses the Swift WebKit overlay gets a strong load command for
# "/usr/lib/swift/libswiftWebKit.dylib". WebKit now ships that overlay only as a
# Cryptex-layout symlink to WebKit.framework, so in the macOS SDK the stub exists
# solely at:
#
#     $SDKROOT/System/Cryptexes/OS/usr/lib/swift/libswiftWebKit.tbd
#
# ld resolves the Cryptex layout implicitly, so normal builds and archives are
# fine. Xcode Previews runs its own linker-parse over the built target
# description, and that step only looks in the legacy "$SDKROOT/usr/lib/swift",
# so it fails before rendering anything:
#
#     CouldNotFindLibrary: Could not find library with name
#     ”/usr/lib/swift/libswiftWebKit.dylib“
#     phase: output load commands, strong
#
# Adding the path to LIBRARY_SEARCH_PATHS does NOT help: the dependency is an
# absolute path, and search paths only apply to -lfoo style references.
#
# The fix mirrors what WebKit itself did for the simulator (bug 293831): create
# the missing symlink in the legacy location. Upstream references:
#   https://bugs.webkit.org/show_bug.cgi?id=293831
#   https://github.com/WebKit/WebKit/pull/46146
#
# Xcode updates and reinstalls replace the SDK, so re-run this afterwards.
# To undo: rm the symlink this script reports.
#
# REQUIREMENT: since macOS Sonoma, writing inside another app's bundle needs App
# Management permission, even though the SDK is owned by your user and mode 755.
# Without it the symlink fails with "Operation not permitted". Grant it to the
# terminal you run this from under:
#
#     System Settings > Privacy & Security > App Management
#
# You may need to quit and reopen the terminal for the change to take effect.

set -eo pipefail

sdk_path=$(xcrun --sdk macosx --show-sdk-path)
legacy_dir="${sdk_path}/usr/lib/swift"
legacy_stub="${legacy_dir}/libswiftWebKit.tbd"
# Relative so the link keeps working if the SDK is moved or renamed.
relative_target="../../../System/Library/Frameworks/WebKit.framework/Versions/A/WebKit.tbd"

if [[ ! -d "${legacy_dir}" ]]; then
	echo "error: Swift stub directory not found in SDK: ${legacy_dir}"
	exit 1
fi

if [[ -e "${legacy_stub}" ]] && [[ ! -L "${legacy_stub}" ]]; then
	echo "A real file already exists at ${legacy_stub} — refusing to overwrite it."
	echo "Apple may have shipped a proper stub, in which case this workaround is obsolete."
	exit 0
fi

if [[ -L "${legacy_stub}" ]]; then
	if [[ -e "${legacy_stub}" ]]; then
		echo "Already fixed: ${legacy_stub}"
		exit 0
	fi
	echo "Replacing dangling symlink at ${legacy_stub}"
	rm "${legacy_stub}"
fi

if [[ ! -e "${legacy_dir}/${relative_target}" ]]; then
	echo "error: WebKit.tbd not found at expected location:"
	echo "       ${legacy_dir}/${relative_target}"
	echo "       The SDK layout changed; this workaround needs updating."
	exit 1
fi

# Deliberately no up-front writability test: inside an app bundle, access(2)
# reports the App Management verdict rather than the POSIX mode, so a pre-check
# just produces misleading "fix your permissions" advice. Let ln report instead.
if ! ln -s "${relative_target}" "${legacy_stub}" 2>/dev/null; then
	echo "error: Could not create the symlink at:"
	echo "       ${legacy_stub}"
	echo
	echo "This is usually macOS App Management blocking writes into Xcode.app."
	echo "Grant App Management to the terminal you are running from under"
	echo "System Settings > Privacy & Security > App Management, quit and reopen it,"
	echo "then re-run this script."
	exit 1
fi

echo "Created ${legacy_stub}"
echo "     -> $(readlink -f "${legacy_stub}")"
echo
echo "Xcode Previews should now build. Re-run this after any Xcode update."
