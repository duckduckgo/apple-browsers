# List all schemes
xcodebuild -list -workspace DuckDuckGo.xcworkspace

# List all simulators
xcrun simctl list devices

# Clean everything
rm -rf ~/Library/Developer/Xcode/DerivedData/

# Open workspace in Xcode
open DuckDuckGo.xcworkspace

