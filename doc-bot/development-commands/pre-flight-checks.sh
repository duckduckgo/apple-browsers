# 1. Verify you're in the project directory
ls -la | grep DuckDuckGo.xcworkspace
# Expected: DuckDuckGo.xcworkspace directory exists

# 2. Check Xcode command line tools
xcodebuild -version
# Expected: Xcode version output (e.g., "Xcode 15.0")

# 3. Verify xcbeautify is installed
which xcbeautify
# Expected: Path to xcbeautify (e.g., "/opt/homebrew/bin/xcbeautify")
# If missing: brew install xcbeautify

