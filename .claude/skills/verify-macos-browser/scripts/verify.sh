#!/bin/bash
# Single entry point for verify-macos-browser, so one permission rule covers every step.
#
# Usage: verify.sh <command> <topic> [args...]
#   vm      <topic> [vm-1|vm-2|auto]    run this topic in a VM (see VM-SETUP.md): reserve a free one, wipe the
#                                       app's data there; first, before flag/set-default/build
#   build   <topic> [worktree] [--automation] [--language <l> --locale <l>] [--keep-onboarding]
#                                       build, record source fingerprint + hashes, launch (en-US, internal user),
#                                       wait until ready, start the PixelKit stream; in a VM, copy the app there
#                                       and skip onboarding unless --keep-onboarding
#   doctor  <topic>                     fail if the source, the binaries or the process don't match the build
#   ax      <topic> <ax-args...>        drive the app through the accessibility tree (see ax.swift)
#   shot    <topic> <name>              screenshot of the app's window only, if the app is frontmost
#   wait    <topic> <seconds>           sleep, for scripted deadlines
#   flag    <topic> <caseName> on|off   pin a FeatureFlag (validated against FeatureFlag.swift); before build
#   set-default <topic> <key> <type> <value>   other defaults, remembered for cleanup; before build
#   mark    <topic>                     telemetry counts from here: right before the action under test
#   expect-pixel <topic> <name> [key=value...] [--timeout 10]
#   expect-no-pixel <topic> <name> [--within 3]
#   expect-wide-event <topic> <feature> [--status SUCCESS] [--timeout 10]
#   web     <topic> url | eval '<js>' | navigate <url>   read, or set up, through the AutomationServer (needs --automation)
#   logs    <topic>                     write [VERIFY] lines to log.txt and the app's full log to app.log
#   cleanup <topic>                     app.log + manifest.json, stop the streams, kill the build, delete defaults,
#                                       release the VM, fail while [VERIFY] lines are left
#
# Exit codes: 0 ok · 1 a check failed · 2 error / can't tell (stale build, not ready, dead stream).
# Evidence: ~/.ddg-verify-macos/<topic>/ ($VERIFY_MACOS_HOME overrides the root, locks included; $VERIFY_RUN_DIR the folder)
set -euo pipefail

BUNDLE_ID="com.duckduckgo.macos.browser.debug"
VERIFY_HOME="${VERIFY_MACOS_HOME:-$HOME/.ddg-verify-macos}"
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
AX_BIN="$SCRIPTS_DIR/../.bin/ax"
VM_LOCKS="$VERIFY_HOME/.vm-locks"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=15)

usage() { sed -n '4,28p' "$0" | sed 's/^# \{0,1\}//'; exit 64; }

command=${1:-}
topic=${2:-}
[[ -n "$command" && "$topic" =~ ^[a-z0-9-]+$ ]] || usage
# shortcut: the app is named "DuckDuckGo - verify-<topic>", and a Debug app named over 35 characters quits at
# launch (callingSymbol() misreads stack lines whose module column is cut at 35); drop the cap once #8345 is in.
if (( ${#topic} > 14 )); then
    echo "topic '$topic' is ${#topic} characters; use 14 at most (a longer app name quits at launch)" >&2; exit 64
fi
shift 2

RUN_DIR="${VERIFY_RUN_DIR:-$VERIFY_HOME/$topic}"
APP_NAME="DuckDuckGo - verify-$topic"
mkdir -p "$RUN_DIR"
VM=$(cat "$RUN_DIR/vm" 2>/dev/null || true)

helper() {
    if [[ -n "$VM" ]]; then VERIFY_WIDE_LOG="$RUN_DIR/vm-wide.jsonl" python3 -I "$SCRIPTS_DIR/vhelp.py" "$@"
    else python3 -I "$SCRIPTS_DIR/vhelp.py" "$@"; fi
}
json_get() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2], {"json": json}, {"d": d}))' "$@"; }

# on_target <bash script> [args...]: run the script on this Mac, or in the topic's VM over ssh. Same $1.. either way.
on_target() {
    local script=$1; shift
    if [[ -z "$VM" ]]; then bash -c "$script" verify "$@"; return; fi
    local quoted=""
    (( $# )) && quoted=$(printf '%q ' "$@")
    ssh "${SSH_OPTS[@]}" "$VM" "bash -s -- $quoted" <<< "$script"
}

app_pid() { on_target 'pgrep -f "$1.app/Contents/MacOS" | head -1 || true' "$APP_NAME"; }
epoch_of_pid() { on_target 'date -j -f "%a %b %d %T %Y" "$(ps -o lstart= -p "$1" | sed "s/^ *//; s/ *$//")" +%s' "$1"; }

# On-screen main windows of a pid; needs neither Accessibility nor Screen Recording.
WINDOW_JS='function run(argv) { ObjC.import("CoreGraphics"); var l = ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly, 0)); var n = 0; for (var i = 0; i < l.count; i++) { var w = l.objectAtIndex(i); if (w.objectForKey("kCGWindowOwnerPID").intValue == parseInt(argv[0]) && w.objectForKey("kCGWindowLayer").intValue == 0) n++; } return n; }'
window_count() { on_target 'osascript -l JavaScript -e "$1" "$2" 2>/dev/null || echo 0' "$WINDOW_JS" "$1"; }

# DerivedData for a checkout: Xcode's folder for its workspace (newest if several), else the runner's
# <checkout>/.build/DerivedData if it exists. Prints nothing when neither exists.
derived_data_of() {
    local workspace="$1/DuckDuckGo.xcworkspace" d best="" newest=0 mtime
    for d in "$HOME"/Library/Developer/Xcode/DerivedData/*/; do
        [[ "$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$d/info.plist" 2>/dev/null)" == "$workspace" ]] || continue
        mtime=$(stat -f %m "$d")
        (( mtime > newest )) && { newest=$mtime; best=${d%/}; }
    done
    [[ -z "$best" && -d "$1/.build/DerivedData" ]] && best="$1/.build/DerivedData"
    printf '%s' "$best"
}

# Which DerivedData to build into, and why: $VERIFY_DERIVED_DATA, this checkout's, the main checkout's
# (a worktree shares it, so its first build is incremental), else a new one where the runner puts it.
resolve_derived_data() {
    local worktree=$1 main dd
    if [[ -n "${VERIFY_DERIVED_DATA:-}" ]]; then echo "$VERIFY_DERIVED_DATA	VERIFY_DERIVED_DATA"; return; fi
    dd=$(derived_data_of "$worktree")
    if [[ -n "$dd" ]]; then echo "$dd	this checkout"; return; fi
    main=$(git -C "$worktree" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
    if [[ -n "$main" && "$main" != "$worktree" ]]; then
        dd=$(derived_data_of "$main")
        if [[ -n "$dd" ]]; then echo "$dd	main checkout $main"; return; fi
    fi
    echo "$worktree/.build/DerivedData	new (first build is a full build)"
}

build_ax() {
    if [[ ! -x "$AX_BIN" || "$SCRIPTS_DIR/ax.swift" -nt "$AX_BIN" ]]; then
        mkdir -p "$(dirname "$AX_BIN")"
        swiftc -O "$SCRIPTS_DIR/ax.swift" -o "$AX_BIN"
    fi
}

# Copy ax into the VM when it differs from this Mac's build.
sync_ax() {
    build_ax
    local want have
    want=$(shasum -a 256 "$AX_BIN" | cut -d' ' -f1)
    have=$(on_target 'mkdir -p ~/verify; shasum -a 256 ~/verify/ax 2>/dev/null | cut -d" " -f1')
    [[ "$want" == "$have" ]] || scp -q "${SSH_OPTS[@]}" "$AX_BIN" "$VM:verify/ax"
}

ax() {
    build_ax
    on_target 'cd ~/verify 2>/dev/null || true; t=$1; shift; VERIFY_APP="verify-$t" "${AX:-./ax}" "$@"' "$topic" "$@"
}
[[ -z "$VM" ]] && ax() {
    build_ax
    VERIFY_APP="verify-$topic" "$AX_BIN" "$@"
}

# sha256 of the binary and its .debug.dylib, as vhelp hash prints them.
target_hashes() {
    if [[ -z "$VM" ]]; then helper hash "$1" "$1.debug.dylib"; return; fi
    on_target 'cd ~/verify/"$1"/"$2.app"/Contents/MacOS && for f in "$2" "$2.debug.dylib"; do printf "%s\t%s\n" "$f" "$(shasum -a 256 "$f" | cut -d" " -f1)"; done' "$topic" "$APP_NAME" \
        | python3 -I -c 'import json,sys; print(json.dumps(dict(l.rstrip("\n").split("\t") for l in sys.stdin if l.strip())))'
}

kill_pidfile() {
    if [[ -f "$RUN_DIR/$1" ]]; then
        kill "$(cat "$RUN_DIR/$1")" 2>/dev/null || true
        rm -f "$RUN_DIR/$1"
    fi
}
stop_stream() { kill_pidfile pixel_stream.pid; kill_pidfile wide_stream.pid; kill_pidfile tunnel.pid; }

write_app_log() {
    [[ -f "$RUN_DIR/launch.json" ]] || return 0
    local launched size
    launched=$(json_get "$RUN_DIR/launch.json" 'd["launched"]')
    # By process name, not processImagePath: the log keeps the first path it saw for a binary's UUID, and the
    # Debug stub executable keeps its UUID across builds, so a copy at a new path logs under the old one.
    on_target '/usr/bin/log show --start "$(date -r "$1" "+%Y-%m-%d %H:%M:%S")" --style compact --predicate "process == \"$2\""' \
        "$launched" "$APP_NAME" > "$RUN_DIR/app.log.tmp" 2>&1 || true
    size=$(stat -f %z "$RUN_DIR/app.log.tmp")
    if (( size > 5000000 )); then
        { echo "# truncated: kept the last 5 MB of $size bytes"; tail -c 5000000 "$RUN_DIR/app.log.tmp"; } > "$RUN_DIR/app.log"
        rm "$RUN_DIR/app.log.tmp"
    else
        mv "$RUN_DIR/app.log.tmp" "$RUN_DIR/app.log"
    fi
}

write_default() {  # key type value
    on_target 'defaults write "$1" "$2" "-$3" "$4"' "$BUNDLE_ID" "$1" "$2" "$3"
    grep -qxF "$1" "$RUN_DIR/defaults_written" 2>/dev/null || echo "$1" >> "$RUN_DIR/defaults_written"
}

# Wipes the debug app's data in the VM; the keychain is kept. bash, so an unmatched glob is just skipped.
VM_RESET='shopt -s nullglob
pkill -f "DuckDuckGo - verify-.*\.app/Contents/MacOS" && sleep 2
cd ~/Library
rm -rf "Application Support/$1" "Caches/$1" "Containers/$1" "WebKit/$1" "HTTPStorages/$1" \
       "Saved Application State/$1.savedState" "Group Containers/"HKE973VLUW.* Caches/wide-event-validation-log.jsonl
defaults delete "$1" >/dev/null 2>&1; defaults delete com.duckduckgo.wide-pixel.storage >/dev/null 2>&1
rm -f "Preferences/$1.plist" Preferences/com.duckduckgo.wide-pixel.storage.plist
killall -u "$USER" cfprefsd 2>/dev/null; sleep 1
mkdir -p ~/verify; for d in ~/verify/*/; do rm -rf "$d"; done
printf "%s\t%s\n" "$(sw_vers -productVersion)" "$(system_profiler SPHardwareDataType | awk -F": " "/Provisioning UDID/{print \$2}")"'

case "$command" in
vm)
    want=${1:-auto}
    if [[ -n "$VM" ]]; then echo "vm=$VM (already reserved for $topic)"; exit 0; fi
    if [[ "$want" == auto ]]; then read -ra candidates <<< "${VERIFY_VMS:-vm-1 vm-2}"; else candidates=("$want"); fi
    mkdir -p "$VM_LOCKS"
    for host in "${candidates[@]}"; do
        lock="$VM_LOCKS/$host"
        if mkdir "$lock" 2>/dev/null; then
            echo "$topic" > "$lock/topic"
            if ssh "${SSH_OPTS[@]}" "$host" true 2>/dev/null; then VM=$host; break; fi
            rm -rf "$lock"
        elif [[ "$(cat "$lock/topic" 2>/dev/null)" == "$topic" ]]; then
            VM=$host; break
        fi
    done
    if [[ -z "$VM" ]]; then
        echo "NO VM FREE: ${candidates[*]} busy or unreachable"
        for host in "${candidates[@]}"; do
            [[ -f "$VM_LOCKS/$host/topic" ]] && echo "  $host: reserved by $(cat "$VM_LOCKS/$host/topic") (stale? cleanup that topic, or remove $VM_LOCKS/$host)"
        done
        exit 2
    fi
    echo "$VM" > "$RUN_DIR/vm"
    info=$(on_target "$VM_RESET" "$BUNDLE_ID")
    printf '{"host": "%s", "macos": "%s", "provisioning_udid": "%s"}\n' "$VM" "${info%%$'\t'*}" "${info##*$'\t'}" > "$RUN_DIR/vm.json"
    sync_ax
    echo "vm=$VM macOS ${info%%$'\t'*} (app data wiped)"
    ;;
build)
    worktree="."; automation=0; language="en"; locale="en_US"; skip_onboarding=1
    if [[ $# -gt 0 && "$1" != --* ]]; then worktree=$1; shift; fi
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --automation) automation=1 ;;
            --language) language=$2; shift ;;
            --locale) locale=$2; shift ;;
            --keep-onboarding) skip_onboarding=0 ;;
            *) echo "build: unknown option $1"; exit 64 ;;
        esac
        shift
    done
    worktree=$(cd "$worktree" && pwd)
    resolved=$(resolve_derived_data "$worktree")
    DERIVED_DATA=${resolved%%	*}
    echo "DerivedData: $DERIVED_DATA (${resolved#*	})"
    pid=$(app_pid); if [[ -n "$pid" ]]; then on_target 'kill "$1"' "$pid"; sleep 1; fi
    stop_stream
    rm -f "$RUN_DIR"/{launch.json,mark.json,pixels.ndjson,pixels.json,vm-wide.jsonl,wide-events.json,pixel_stream.err}
    # One build at a time: parallel topics share DerivedData. Only the drive in the VMs runs in parallel.
    build_lock="$VERIFY_HOME/.build-lock"
    for i in $(seq 1800); do
        mkdir "$build_lock" 2>/dev/null && break
        holder=$(cat "$build_lock/pid" 2>/dev/null || true)
        [[ -n "$holder" ]] && ! kill -0 "$holder" 2>/dev/null && rm -rf "$build_lock" && continue
        (( i == 1 )) && echo "waiting for another verify build ($(cat "$build_lock/topic" 2>/dev/null || echo ?))"
        sleep 1
    done
    echo $$ > "$build_lock/pid"; echo "$topic" > "$build_lock/topic"
    build_start=$(date +%s)
    if ! (cd "$worktree" && xcodebuild -workspace DuckDuckGo.xcworkspace -scheme "macOS Browser" -configuration Debug \
            -destination "platform=macOS" -derivedDataPath "$DERIVED_DATA" -skipPackagePluginValidation \
            -skipMacroValidation -skipPackageUpdates "PRODUCT_NAME_PREFIX=$APP_NAME" build) > "$RUN_DIR/build.log" 2>&1; then
        rm -rf "$build_lock"
        grep -m1 -E "error:" "$RUN_DIR/build.log" || tail -20 "$RUN_DIR/build.log"
        exit 1
    fi
    build_end=$(date +%s)
    rm -rf "$build_lock"
    app="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
    exe="$app/Contents/MacOS/$APP_NAME"
    [[ -x "$exe" ]] || { echo "BUILD PRODUCT MISSING: $exe"; exit 2; }
    # A build stopped halfway can leave an empty compiled asset catalog that later incremental builds reuse;
    # the app then traps at launch looking up a color (ThemeStyle). Seen at 512 bytes; a real one is MBs.
    car_size=$(stat -f %z "$app/Contents/Resources/Assets.car" 2>/dev/null || echo 0)
    if (( car_size < 1000000 )); then
        echo "BROKEN BUILD PRODUCT: Assets.car is $car_size bytes (a build stopped halfway?)."
        echo "  Remove the app target's assetcatalog_output under $DERIVED_DATA/Build/Intermediates.noindex and build again."
        exit 2
    fi
    source_json=$(helper fingerprint "$worktree")
    hashes_json=$(helper hash "$exe" "$exe.debug.dylib")
    printf '{"worktree": "%s", "build_start": %s, "build_end": %s, "derived_data": "%s", "app": "%s", "source": %s, "hashes": %s}\n' \
        "$worktree" "$build_start" "$build_end" "$DERIVED_DATA" "$app" "$source_json" "$hashes_json" > "$RUN_DIR/build.json"

    target_app="$app"
    if [[ -n "$VM" ]]; then
        # tar, not scp -r: scp follows the frameworks' symlinks and breaks the signature.
        on_target 'rm -rf ~/verify/"$1"; mkdir -p ~/verify/"$1"' "$topic"
        (cd "$(dirname "$app")" && tar -cf - "$APP_NAME.app") | ssh "${SSH_OPTS[@]}" "$VM" "cd ~/verify/$topic && tar -xf -" \
            || { echo "COPY FAILED: $VM"; exit 2; }
        copied=$(target_hashes | python3 -I -c 'import json,sys; print(json.dumps(json.load(sys.stdin), sort_keys=True))')
        built=$(python3 -I -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1]), sort_keys=True))' "$hashes_json")
        [[ "$copied" == "$built" ]] || { echo "COPY MISMATCH: the app in $VM differs from the build"; exit 2; }
        target_app="~/verify/$topic/$APP_NAME.app"
        sync_ax
    fi

    launch_args=(-NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints YES -SUEnableAutomaticChecks NO
                 -com.apple.CoreData.ConcurrencyDebug 1
                 -AppleLanguages "($language)" -AppleLocale "$locale" -isInternalUser true)
    open_env=()
    port=null
    if (( automation )); then
        port=$(( 20000 + $(printf '%s' "$topic" | cksum | cut -d' ' -f1) % 1000 ))
        (umask 077; openssl rand -hex 16 > "$RUN_DIR/automation_token")
        launch_args+=(-automationPort "$port")
        open_env=(--env "AUTOMATION_TOKEN=$(cat "$RUN_DIR/automation_token")")
    fi
    # Prints the launch time on the target's clock (logs and doctor compare against it).
    launched=$(on_target 'app=$1; shift; app=${app/#\~/$HOME}; date +%s; open -a "$app" "$@" >&2 || true' \
        "$target_app" ${open_env[@]+"${open_env[@]}"} --args "${launch_args[@]}")
    pid=""
    for _ in $(seq 60); do pid=$(app_pid); [[ -n "$pid" ]] && break; sleep 1; done
    [[ -n "$pid" ]] || { echo "NOT LAUNCHED: no $APP_NAME process after 60 s${VM:+ in $VM (AMFI? is its Provisioning UDID in the profile?)}"; exit 2; }
    printf '{"pid": %s, "launched": %s, "language": "%s", "locale": "%s", "internal_user": true, "automation_port": %s, "vm": %s}\n' \
        "$pid" "$launched" "$language" "$locale" "$port" "$([[ -n "$VM" ]] && echo "\"$VM\"" || echo null)" > "$RUN_DIR/launch.json"

    predicate="subsystem == \"PixelKit\" AND processID == $pid"
    if [[ -n "$VM" ]]; then
        nohup ssh "${SSH_OPTS[@]}" "$VM" "/usr/bin/log stream --level debug --style ndjson --predicate $(printf '%q' "$predicate")" \
            > "$RUN_DIR/pixels.ndjson" 2>"$RUN_DIR/pixel_stream.err" &
        echo $! > "$RUN_DIR/pixel_stream.pid"
        nohup ssh "${SSH_OPTS[@]}" "$VM" "tail -n +1 -F ~/Library/Caches/wide-event-validation-log.jsonl" \
            > "$RUN_DIR/vm-wide.jsonl" 2>/dev/null &
        echo $! > "$RUN_DIR/wide_stream.pid"
        if (( automation )); then
            nohup ssh "${SSH_OPTS[@]}" -N -o ExitOnForwardFailure=yes -L "$port:localhost:$port" "$VM" >/dev/null 2>&1 &
            echo $! > "$RUN_DIR/tunnel.pid"
        fi
    else
        nohup /usr/bin/log stream --level debug --style ndjson \
            --predicate "$predicate" > "$RUN_DIR/pixels.ndjson" 2>"$RUN_DIR/pixel_stream.err" &
        echo $! > "$RUN_DIR/pixel_stream.pid"
    fi

    if (( automation )); then
        helper ready "$RUN_DIR" 60
    else
        ready=0
        for _ in $(seq 60); do
            # Both reads: right after launch System Events can list a window the AX tree doesn't have yet (seen on a Mac).
            if (( $(window_count "$pid") > 0 )) && ax winrect > /dev/null 2>&1; then ready=1; break; fi
            sleep 1
        done
        if (( ! ready )); then   # a prompt (keychain, notifications) in front of the app blocks its first window
            front=$(on_target 'lsappinfo info -only name "$(lsappinfo front)" | sed -n "1s/^\"\([^\"]*\)\".*/\1/p"')
            echo "NOT READY: no window after 60 s${front:+; $front is in front: answer its prompt (keychain, notifications), then rerun}${VM:+ (see VM-SETUP.md)}"
            exit 2
        fi
        echo "READY window"
    fi
    kill -0 "$(cat "$RUN_DIR/pixel_stream.pid")" 2>/dev/null || { echo "PIXEL STREAM FAILED: $(head -3 "$RUN_DIR/pixel_stream.err")"; exit 2; }
    if [[ -n "$VM" ]] && (( skip_onboarding )); then
        # A press right after launch can land too early, and a background app gets no key events: bring the app
        # to the front, press, and confirm a regular tab replaced the onboarding one before going on.
        skipped=0
        for _ in 1 2 3 4 5; do
            ax activate >/dev/null 2>&1 || true
            ax press MainMenu.skipOnboarding >/dev/null 2>&1 || true
            sleep 2
            tabs=$(ax dump 8 | grep 'id=TabBarViewItem title=' || true)
            if [[ -n "$tabs" && "$tabs" != *'title="Welcome"'* && "$(ax front)" == yes ]]; then skipped=1; break; fi
        done
        (( skipped )) || { echo "ONBOARDING NOT SKIPPED: no regular tab, a Welcome tab left, or the app isn't frontmost"; exit 2; }
        echo "onboarding skipped"
    fi
    echo "pid=$pid language=$language locale=$locale automation=$automation${VM:+ vm=$VM}"
    ;;
doctor)
    [[ -f "$RUN_DIR/build.json" ]] || { echo "NO BUILD: run verify.sh build first"; exit 2; }
    pid=$(app_pid)
    [[ -n "$pid" ]] || { echo "NOT RUNNING: $APP_NAME${VM:+ in $VM}"; exit 2; }
    worktree=$(json_get "$RUN_DIR/build.json" 'd["worktree"]')
    exe="$(json_get "$RUN_DIR/build.json" 'd["app"]')/Contents/MacOS/$APP_NAME"
    [[ -z "$VM" ]] && exe=$(ps -o comm= -p "$pid")
    want_source=$(json_get "$RUN_DIR/build.json" 'd["source"]["stamp"]')
    have_source=$(helper fingerprint "$worktree" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["stamp"])')
    want_hashes=$(json_get "$RUN_DIR/build.json" 'json.dumps(d["hashes"], sort_keys=True)')
    have_hashes=$(target_hashes "$exe" | python3 -I -c 'import json,sys; print(json.dumps(json.load(sys.stdin), sort_keys=True))')
    # The process must have started after the build (on this Mac) or after this build's launch (VM clock).
    if [[ -n "$VM" ]]; then since=$(json_get "$RUN_DIR/launch.json" 'd["launched"]'); else since=$(json_get "$RUN_DIR/build.json" 'd["build_end"]'); fi
    started=$(epoch_of_pid "$pid")
    verify_lines=$(grep -a -c "\[VERIFY\]" "$exe.debug.dylib" || true)
    echo "pid=$pid started=$started since=$since verify_strings=$verify_lines${VM:+ vm=$VM}"
    echo "running_hashes=$have_hashes"
    [[ "$have_source" == "$want_source" ]] || { echo "STALE SOURCE: the worktree changed since the build; rebuild"; exit 2; }
    [[ "$have_hashes" == "$want_hashes" && "$have_hashes" != *null* ]] || { echo "REBUILT: the binaries changed since this build (Xcode?); rebuild"; exit 2; }
    (( started >= since - 1 )) || { echo "OLD PROCESS: started before this build's launch; rebuild"; exit 2; }
    echo "OK"
    ;;
ax)
    ax "$@"
    ;;
shot)
    name=${1:?shot needs a name}
    [[ "$(ax front)" == "yes" ]] || { echo "NOT FRONTMOST: no screenshot taken (it could capture another app)"; exit 1; }
    rect=$(ax winrect)
    if [[ -n "$VM" ]]; then
        on_target 'screencapture -x -R"$1" ~/verify/shot.png' "$rect"
        scp -q "${SSH_OPTS[@]}" "$VM:verify/shot.png" "$RUN_DIR/$name.png"
    else
        screencapture -x -R"$rect" "$RUN_DIR/$name.png"
    fi
    echo "$RUN_DIR/$name.png"
    ;;
wait)
    sleep "${1:?wait needs seconds}"
    ;;
flag)
    name=${1:?flag needs a FeatureFlag case name}; state=${2:?on or off}
    [[ "$state" == on || "$state" == off ]] || { echo "flag: on or off"; exit 64; }
    worktree=$(cd "${VERIFY_WORKTREE:-.}" && pwd)
    if ! key=$(helper flag "$worktree" "$name"); then echo "$key"; exit 2; fi
    [[ "$state" == on ]] && value=true || value=false
    write_default "$key" bool "$value"
    { grep -v "^$name=" "$RUN_DIR/flags" 2>/dev/null || true; echo "$name=$state"; } > "$RUN_DIR/flags.tmp"
    mv "$RUN_DIR/flags.tmp" "$RUN_DIR/flags"
    echo "pinned $name $state ($key)${VM:+ in $VM}"
    ;;
set-default)
    key=${1:?key}; type=${2:?type, e.g. bool}; value=${3:?value}
    write_default "$key" "$type" "$value"
    echo "wrote $key${VM:+ in $VM}"
    ;;
mark)
    helper mark "$RUN_DIR"
    ;;
expect-pixel)
    helper expect-pixel "$RUN_DIR" "$@"
    ;;
expect-no-pixel)
    helper expect-no-pixel "$RUN_DIR" "$@"
    ;;
expect-wide-event)
    helper expect-wide-event "$RUN_DIR" "$@"
    ;;
web)
    helper web "$RUN_DIR" "$@"
    ;;
logs)
    [[ -f "$RUN_DIR/launch.json" ]] || { echo "NO LAUNCH: run verify.sh build first"; exit 2; }
    # A run launched in a VM keeps its logs there: after cleanup released the VM, reading here would overwrite them.
    if [[ -z "$VM" && "$(json_get "$RUN_DIR/launch.json" 'd.get("vm")')" != None ]]; then
        echo "VM RELEASED: this run's logs were written by cleanup; run logs before cleanup"; exit 2
    fi
    launched=$(json_get "$RUN_DIR/launch.json" 'd["launched"]')
    on_target '/usr/bin/log show --start "$(date -r "$1" "+%Y-%m-%d %H:%M:%S")" --predicate "process == \"$2\" AND eventMessage CONTAINS \"[VERIFY]\"" --style compact' \
        "$launched" "$APP_NAME" > "$RUN_DIR/log.txt" 2>&1
    write_app_log
    echo "VERIFY lines: $(grep -c "\[VERIFY\]" "$RUN_DIR/log.txt" || true) · app.log: $(wc -l < "$RUN_DIR/app.log" | tr -d ' ') lines"
    tail -20 "$RUN_DIR/log.txt"
    ;;
cleanup)
    write_app_log
    helper manifest "$RUN_DIR" "$SKILL_DIR" "$topic" > /dev/null || echo "MANIFEST FAILED"
    stop_stream
    pid=$(app_pid); if [[ -n "$pid" ]]; then on_target 'kill "$1"' "$pid"; echo "killed $pid${VM:+ in $VM}"; fi
    if [[ -f "$RUN_DIR/defaults_written" ]]; then
        while read -r key; do
            on_target 'defaults delete "$1" "$2" 2>/dev/null' "$BUNDLE_ID" "$key" && echo "deleted default $key"
        done < "$RUN_DIR/defaults_written"
        rm "$RUN_DIR/defaults_written"
    fi
    rm -f "$RUN_DIR/automation_token" "$RUN_DIR/flags"
    if [[ -n "$VM" ]]; then
        [[ "$(cat "$VM_LOCKS/$VM/topic" 2>/dev/null)" == "$topic" ]] && rm -rf "$VM_LOCKS/$VM"
        rm -f "$RUN_DIR/vm"
        echo "released $VM"
    fi
    if [[ -f "$RUN_DIR/build.json" ]]; then
        worktree=$(json_get "$RUN_DIR/build.json" 'd["worktree"]')
        # This skill's own files mention the tag; only the app's code matters here.
        leftovers=$(git -C "$worktree" grep -n "\[VERIFY\]" -- . ':(exclude).claude' || true)
        if [[ -n "$leftovers" ]]; then echo "[VERIFY] lines left:"; echo "$leftovers"; exit 1; fi
    fi
    echo "evidence: $RUN_DIR"
    ;;
*)
    usage
    ;;
esac
