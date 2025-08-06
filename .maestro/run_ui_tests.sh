#!/bin/zsh

### Run UI tests

source $(dirname $0)/common.sh

## Constants

run_log="$derived_data_path/run_log.txt"
app_bundle="com.duckduckgo.mobile.ios"

echo "run_log: $run_log"
echo "app_bundle: $app_bundle"

## Functions

log_message() {
    local run_log="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$timestamp: $message" >> $run_log
}

get_device_type() {
	local test_file=$1
	
	# Check if the test has an 'ipad' tag
	# Extract tags section and check for ipad tag
	# This approach handles any number of tags without hardcoded limits
	if awk '/^tags:/{flag=1; next} /^[^ -]/{flag=0} flag' "$test_file" | grep -q "^[[:space:]]*- ipad"; then
		echo "iPad"
	else
		echo "iPhone"
	fi
}

ensure_simulator_booted() {
	local uuid=$1
	local device_name=$2
	
	# Check if simulator is booted
	# Extract just the state from the last set of parentheses
	local state=$(xcrun simctl list devices | grep "$uuid" | sed -n 's/.*(\(.*\))$/\1/p')
	
	if [ "$state" != "Booted" ]; then
		echo "ℹ️ Booting $device_name simulator..." >&2
		xcrun simctl boot "$uuid"
		if [ $? -ne 0 ]; then
			echo "⚠️  Failed to boot $device_name simulator, it might already be booted..." >&2
		fi
		# Give it a moment to boot
		sleep 3
	fi
}

get_simulator_uuid() {
	local device_type=$1
	
	if [ "$device_type" = "iPad" ]; then
		# Read iPad UUID from file
		local ipad_uuid_path="${device_uuid_path%.txt}_ipad.txt"
		if [ -f "$ipad_uuid_path" ]; then
			local uuid=$(cat "$ipad_uuid_path")
			ensure_simulator_booted "$uuid" "iPad"
			echo "$uuid"
		else
			fail "iPad simulator not found. Please run setup_ui_tests.sh first"
		fi
	else
		# Read iPhone UUID from file
		if [ -f "$device_uuid_path" ]; then
			local uuid=$(cat "$device_uuid_path")
			ensure_simulator_booted "$uuid" "iPhone"
			echo "$uuid"
		else
			fail "iPhone simulator not found. Please run setup_ui_tests.sh first"
		fi
	fi
}

run_flow() {
	local flow=$1

	# Determine device type based on test tags
	local device_type=$(get_device_type "$flow")
	
	if [ "$device_type" = "iPad" ]; then
		echo "ℹ️ Test requires iPad simulator"
	fi
	
	# Get the appropriate simulator UUID
	local target_device_uuid=$(get_simulator_uuid "$device_type")

	echo "ℹ️ Deleting app in $device_type simulator"

	xcrun simctl uninstall $target_device_uuid $app_bundle 2>&1
	local uninstall_result=$?
	if [ $uninstall_result -ne 0 ]; then
		# App might not be installed, which is fine
		log_message $run_log "⚠️  App uninstall failed for $device_type (may not be installed)"
		echo "⚠️  Failed to uninstall app (may not be installed), continuing..."
	fi

	echo "ℹ️ Installing app in $device_type simulator"
	xcrun simctl install $target_device_uuid $app_location

	echo "⏲️ Starting flow $( basename $flow) on $device_type"

	export MAESTRO_DRIVER_STARTUP_TIMEOUT=60000
	maestro --udid=$target_device_uuid test -e ONBOARDING_COMPLETED=true $flow
	if [ $? -ne 0 ]; then
		log_message $run_log "❌ FAIL: $flow ($device_type)"
		echo "🚨 Flow failed $flow"
	else		
		log_message $run_log "✅ PASS: $flow ($device_type)"
	fi
}

show_usage() {
	echo "ℹ️ Usage: $1 /path/to/flow.yaml | /path/folder/of/flows/"
	echo
	exit 1
}

## Main Script

if [ ! -f "$device_uuid_path" ]; then
	fail "Please run setup-ui-tests.sh first"
fi

if [ -z $1 ]; then
	show_usage $0
fi

if [ ! -f $1 ] && [ ! -d $1 ]; then
	echo "‼️ $1 is not a file or directory"
	show_usage $0
fi

# Run the selected tests

echo
echo "ℹ️ Running UI tests for $1"

# Ensure Simulator app is running
if ! pgrep -x "Simulator" > /dev/null; then
    echo "ℹ️ Opening Simulator app..."
    open -a Simulator
    sleep 2
fi

# Simulators are pre-created by setup_ui_tests.sh
echo "ℹ️ Using pre-configured simulators (iPhone and iPad)"
echo "ℹ️ Device will be selected based on test tags (default: iPhone, 'ipad' tag: iPad)"

echo "ℹ️ creating run log in $run_log"
if [ -f $run_log ]; then
	rm $run_log
fi

log_message $run_log "START"

if [ -f $1 ]; then
	# Run single test file
	run_flow $1
elif [ -d $1 ]; then
	# Run all test files in directory
	for file in "$1"/*.yaml; do
		run_flow $file
	done
fi

log_message $run_log "END"

cat $run_log

echo 
echo "Log at $(realpath $run_log)"
echo

if grep -q "FAIL" $run_log; then
	fail "There were errors, please see check the log."
else
	echo "✅ Finished"
fi
