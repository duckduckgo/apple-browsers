# Step 1: Get workspace path
WORKSPACE_DIR=$(pwd)
WORKSPACE_FILE=$(find . -name "DuckDuckGo.xcworkspace" | head -1)
WORKSPACE_PATH="${WORKSPACE_DIR}/${WORKSPACE_FILE#./}"
echo "Workspace: ${WORKSPACE_PATH}"

# Step 2: Get architecture (for macOS builds)
ARCHITECTURE=$(uname -m)
echo "Architecture: ${ARCHITECTURE}"

# Step 3: Find iOS simulator (for iOS builds)
SIMULATOR_ID=$(xcrun simctl list devices | grep -E "iPhone.*\([A-F0-9-]{36}\)" | head -1 | grep -oE "[A-F0-9-]{36}")
echo "Simulator ID: ${SIMULATOR_ID}"

