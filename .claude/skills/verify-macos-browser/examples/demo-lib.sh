# Shared by the demo-*.sh examples: narrated steps, checks recorded as they run, a summary at the end.
# Source it after setting TOPIC; scenarios call demo_start, then say / run / check / expect, then demo_end.
# Not a harness: the checks are recorded by hand here. A proof file and `prove` will do this for real.

V="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/verify.sh"
checkout=.; vm=auto; pause=0
passed=(); failed=(); step=0

demo_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vm) vm=$2; shift ;;
            --topic) TOPIC=$2; shift ;;
            --pause) pause=1 ;;
            -*) echo "unknown option $1"; exit 64 ;;
            *) checkout=$1 ;;
        esac
        shift
    done
}

say() {
    step=$((step + 1))
    printf '\n\033[1m%d. %s\033[0m\n   %s\n' "$step" "$1" "$2"
    (( pause )) && read -r -p "   [Return] " _
    return 0
}
run() { printf '   $ verify.sh %s\n' "$*"; "$V" "$@"; }
check() {  # check <label> <0 = pass>
    if [[ $2 == 0 ]]; then passed+=("$1"); echo "   PASS  $1"; else failed+=("$1"); echo "   FAIL  $1"; fi
}
expect() {  # expect <label> <wanted exit code> <verify.sh args...>
    local label=$1 want=$2; shift 2
    run "$@"; local got=$?
    [[ $got == "$want" ]] && check "$label" 0 || check "$label (exit $got, wanted $want)" 1
}
tabs() { "$V" ax "$TOPIC" dump 8 | grep -c 'id=TabBarViewItem title='; }

demo_start() {  # demo_start [--automation]: reserve a VM, build, launch, doctor
    trap '"$V" cleanup "$TOPIC" >/dev/null 2>&1 || true' EXIT
    say "Reserve a VM" "Picks a free VM, wipes the app's data there and copies the ax driver. Nothing touches this Mac's screen."
    run vm "$TOPIC" "$vm" || exit 2
    say "Build and launch" "Builds the checkout here, copies the app to the VM, checks its hashes, launches it in English as an internal user and skips onboarding."
    run build "$TOPIC" "$checkout" "$@" || exit 2
    say "Doctor" "Refuses to go on if the source, the binaries or the process don't match the build."
    run doctor "$TOPIC" || exit 2
}

demo_end() {
    say "Logs and cleanup" "Keeps the app's log, writes manifest.json, quits the app, removes the defaults it wrote, releases the VM."
    run logs "$TOPIC" | grep -m1 "VERIFY lines"
    trap - EXIT
    run cleanup "$TOPIC" | tail -2
    printf '\n\033[1mResult: %s\033[0m\n' "$TOPIC"
    for p in ${passed[@]+"${passed[@]}"}; do echo "   PASS  $p"; done
    for f in ${failed[@]+"${failed[@]}"}; do echo "   FAIL  $f"; done
    echo "   evidence: ${VERIFY_MACOS_HOME:-$HOME/.ddg-verify-macos}/$TOPIC/"
    (( ${#failed[@]} == 0 && ${#passed[@]} > 0 ))
}
