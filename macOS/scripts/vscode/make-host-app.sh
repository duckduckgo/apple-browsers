#!/usr/bin/env bash
#
# Builds the host app used to run the browser from VSCode/Cursor.
#
# The host app is a minimal Xcode app target generated into macOS/.build/vscode-host: it uses the
# DuckDuckGo Privacy Browser target's xcconfig, Info.plist, entitlements and app bundle resources, and
# its executable is macOS/scripts/vscode/launcher/launcher.c, which loads the DuckDuckGoBrowserDynamic library built
# by `swift build`. The project has no package dependencies, so building it doesn't resolve the package
# graph. Swift code changes only need `swift build`; the host app is rebuilt when its inputs change.
#
# Not included: the VPN and Personal Information Removal login items.

set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") [--force]

Builds macOS/.build/vscode-host/DuckDuckGo.app for running the browser from VSCode/Cursor.

Options:
  --force        Rebuild the host app even if its inputs didn't change
  -h, --help     Show this help message
EOF
}

script_dir="$(cd "$(dirname "$0")" && pwd)"
macos_dir="$(cd "${script_dir}/../.." && pwd)"
# Build output lives outside the package folder: Xcode scans the package folder it has open.
work_dir="${macos_dir}/.build/vscode-host"
project="${work_dir}/DuckDuckGoHost.xcodeproj"
host_app="${work_dir}/DuckDuckGo.app"
stamp_file="${work_dir}/inputs.sha"
force=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) force=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
    shift
done

# Bundle resources of the DuckDuckGo Privacy Browser target, relative to macOS/:
# the app bundle's string catalogs (without the App Store ones) and the resources shared with the helper targets.
cd "$macos_dir"
resources=(DuckDuckGo/AppIcons/*.icon DuckDuckGo/ContentBlocker/Resources/macos-config.json)
for path in DuckDuckGoAppBundle/*.xcstrings DuckDuckGoAppBundle/*/*.xcstrings; do
    [[ "$path" == *AppStore* ]] || resources+=("$path")
done

inputs_hash() {
    local paths=(Configuration DuckDuckGoAppBundle "${resources[@]}")
    {
        git ls-files -s -- "${paths[@]}"
        git diff HEAD -- "${paths[@]}"
        cat "${script_dir}/launcher/launcher.c" "${script_dir}/$(basename "$0")"
    } | shasum | cut -d' ' -f1
}

mkdir -p "$work_dir"
hash="$(inputs_hash)"
if [[ $force -eq 0 && -d "$host_app" && -f "$stamp_file" && "$(cat "$stamp_file")" == "$hash" ]]; then
    echo "Host app is up to date: ${host_app}"
    exit 0
fi

file_type() {
    case "$1" in
        *.c) echo sourcecode.c.c ;;
        *.icon) echo folder.iconcomposer.icon ;;
        *.xcconfig) echo text.xcconfig ;;
        *.xcstrings) echo text.json.xcstrings ;;
        *.json) echo text.json ;;
    esac
}

# Writes the host project as a JSON pbxproj; paths are relative to macOS/ (projectDirPath).
write_project() {
    local refs=() file_refs="" resource_files=""
    local index=0 path
    for path in "${resources[@]}"; do
        file_refs+="\"R${index}\":{\"isa\":\"PBXFileReference\",\"lastKnownFileType\":\"$(file_type "$path")\",\"path\":\"${path}\",\"sourceTree\":\"SOURCE_ROOT\"},"
        resource_files+="\"RB${index}\":{\"isa\":\"PBXBuildFile\",\"fileRef\":\"R${index}\"},"
        refs+=("\"R${index}\"")
        index=$((index + 1))
    done
    local ref_list resource_list
    ref_list="$(IFS=,; echo "${refs[*]}")"
    resource_list="$(IFS=,; echo "${refs[*]//\"R/\"RB}")"

    mkdir -p "$project"
    cat > "${project}/project.pbxproj" <<EOF
{"archiveVersion":"1","classes":{},"objectVersion":"56","rootObject":"PROJECT","objects":{
"PROJECT":{"isa":"PBXProject","attributes":{},"buildConfigurationList":"PROJECT_CONFIGS","compatibilityVersion":"Xcode 14.0","developmentRegion":"en","knownRegions":["en","Base"],"mainGroup":"MAIN_GROUP","productRefGroup":"PRODUCTS","projectDirPath":"../..","projectRoot":"","targets":["HOST"]},
"PROJECT_CONFIGS":{"isa":"XCConfigurationList","buildConfigurations":["PROJECT_DEBUG"],"defaultConfigurationName":"Debug"},
"PROJECT_DEBUG":{"isa":"XCBuildConfiguration","baseConfigurationReference":"GLOBAL_XCCONFIG","buildSettings":{},"name":"Debug"},
"MAIN_GROUP":{"isa":"PBXGroup","children":["LAUNCHER","GLOBAL_XCCONFIG","APP_XCCONFIG",${ref_list},"PRODUCTS"],"sourceTree":"<group>"},
"PRODUCTS":{"isa":"PBXGroup","children":["HOST_APP"],"name":"Products","sourceTree":"<group>"},
"LAUNCHER":{"isa":"PBXFileReference","lastKnownFileType":"sourcecode.c.c","path":"scripts/vscode/launcher/launcher.c","sourceTree":"SOURCE_ROOT"},
"GLOBAL_XCCONFIG":{"isa":"PBXFileReference","lastKnownFileType":"text.xcconfig","path":"Configuration/Global.xcconfig","sourceTree":"SOURCE_ROOT"},
"APP_XCCONFIG":{"isa":"PBXFileReference","lastKnownFileType":"text.xcconfig","path":"Configuration/App/DuckDuckGo.xcconfig","sourceTree":"SOURCE_ROOT"},
${file_refs}
"HOST_APP":{"isa":"PBXFileReference","explicitFileType":"wrapper.application","includeInIndex":"0","path":"DuckDuckGo.app","sourceTree":"BUILT_PRODUCTS_DIR"},
"LAUNCHER_BUILD":{"isa":"PBXBuildFile","fileRef":"LAUNCHER"},
${resource_files}
"SOURCES":{"isa":"PBXSourcesBuildPhase","buildActionMask":"2147483647","files":["LAUNCHER_BUILD"],"runOnlyForDeploymentPostprocessing":"0"},
"RESOURCES":{"isa":"PBXResourcesBuildPhase","buildActionMask":"2147483647","files":[${resource_list}],"runOnlyForDeploymentPostprocessing":"0"},
"HOST":{"isa":"PBXNativeTarget","buildConfigurationList":"HOST_CONFIGS","buildPhases":["SOURCES","RESOURCES"],"buildRules":[],"dependencies":[],"name":"DuckDuckGo","productName":"DuckDuckGo","productReference":"HOST_APP","productType":"com.apple.product-type.application"},
"HOST_CONFIGS":{"isa":"XCConfigurationList","buildConfigurations":["HOST_DEBUG"],"defaultConfigurationName":"Debug"},
"HOST_DEBUG":{"isa":"XCBuildConfiguration","baseConfigurationReference":"APP_XCCONFIG","buildSettings":{},"name":"Debug"}
}}
EOF
}

# Shows build progress; the full log is kept in xcodebuild.log.
show_progress() {
    if command -v xcbeautify > /dev/null; then
        xcbeautify --disable-logging
        return
    fi
    # Without xcbeautify: one short line per build step ("CompileC [DuckDuckGo]"), errors and the result.
    sed -l -n -E \
        -e "s/^([A-Za-z]+) .* \(in target '([^']+)' from project .*/\1 [\2]/p" \
        -e "/error:|\*\* BUILD/p" | uniq
}

write_project
# A clean bundle: Xcode only adds to an existing one.
rm -rf "$host_app"
build_log="${work_dir}/xcodebuild.log"
echo "Building the host app with Xcode (full log: ${build_log})…"
set +e
xcodebuild -project "$project" \
    -target DuckDuckGo \
    -arch "$(uname -m)" \
    -configuration Debug \
    SYMROOT="${work_dir}/build" \
    CONFIGURATION_BUILD_DIR="$work_dir" \
    build 2>&1 | tee "$build_log" | show_progress
build_status=${PIPESTATUS[0]}
set -e
if [[ $build_status -ne 0 ]]; then
    echo "Xcode build failed, see ${build_log}"
    exit 1
fi

# The app has system extension entitlements, so the hardened runtime doesn't allow disable-library-validation:
# sign-dylib.sh signs the swift build output with the same identity instead, so library validation passes.
identity="$(codesign -dvv "$host_app" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
echo "${identity:--}" > "${work_dir}/identity"

echo "$hash" > "$stamp_file"
echo "Host app is ready: ${host_app} (signed with: ${identity:--})"
