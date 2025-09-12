# NetworkQualityMonitor Integration Instructions

## Current Status
✅ Package created and tested successfully
✅ Debug menu file created (DuckDuckGo/Debug/NetworkQualityDebugMenu.swift)
✅ MainMenu.swift updated to include NetworkQuality menu item

## To Complete Integration in Xcode:

1. **Add Package Dependency**
   - Open `DuckDuckGo-macOS.xcodeproj` in Xcode
   - Select the project in the navigator
   - Select "DuckDuckGo Privacy Browser" target
   - Go to "Build Phases" → "Dependencies"
   - Click "+" and add "NetworkQualityMonitor" from LocalPackages

2. **Add to Linked Frameworks**
   - In the same target, go to "General" tab
   - Under "Frameworks, Libraries, and Embedded Content"
   - Click "+" and add "NetworkQualityMonitor"

3. **Add Debug Menu File to Target**
   - In Xcode, navigate to `DuckDuckGo/Debug/`
   - Right-click and select "Add Files to DuckDuckGo..."
   - Select `NetworkQualityDebugMenu.swift`
   - Make sure "DuckDuckGo Privacy Browser" target is checked

4. **Build and Run**
   - Build the project (⌘B)
   - Run the app
   - Go to Debug menu → Network Quality
   - Test the network quality features

## Files Created/Modified:

- `LocalPackages/NetworkQualityMonitor/` - Complete Swift Package
- `DuckDuckGo/Debug/NetworkQualityDebugMenu.swift` - Debug menu integration
- `macOS/DuckDuckGo/Menus/MainMenu.swift` - Added menu item at line 697-698

## Testing the Package Standalone:

```bash
cd LocalPackages/NetworkQualityMonitor
swift test  # Run tests
swift run network-quality-test  # Run CLI tool
```