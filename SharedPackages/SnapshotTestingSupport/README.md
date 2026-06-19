# SnapshotTestingSupport Demo References

Handy index for showing the current snapshot testing setup on iOS and macOS.

## Package Layout

`SnapshotTestingSupport` lives at `SharedPackages/SnapshotTestingSupport`.

Products:
- `PreviewSnapshots`: lightweight product for app targets that want Xcode previews reusable by snapshot tests.
- `SnapshotTestingSupport`: test-only product that re-exports Point-Free `SnapshotTesting`, `InlineSnapshotTesting`, and `PreviewSnapshots`, plus DuckDuckGo image snapshot helpers.

Keep `SnapshotTestingSupport` linked only to test targets. App targets can link `PreviewSnapshots` when a view exposes preview configurations for tests.

## Main APIs

Direct view snapshots:

```swift
assertImageSnapshot(
    matching: view.withBackground,
    size: .intrinsicContentSize
)
```

Preview-backed snapshots:

```swift
assertImageSnapshots(
    SomeView_Previews.snapshots,
    size: .screen
)
```

Point-Free APIs are available through `SnapshotTestingSupport` for existing data snapshots:

```swift
assertSnapshot(of: value, as: .json)
```

## Size Modes

- `.intrinsicContentSize`: content-driven size. Good for compact SwiftUI/AppKit/UIKit views.
- `.constrainedWidth`: content-driven height with the default iPhone width, currently `390`.
- `.screen`: full-screen layout. On iOS this expands across the default iPhone and iPad devices.
- `.sheet`: iOS sheet layout. iPhone is bottom-aligned; iPad is centered with sheet padding.
- `.fixed(CGSize)`: explicit size. Useful for macOS windows, panels, and fixed-format views.

Default strategy is `.allAppearances`.

On iOS:
- `.screen` and `.sheet` generate light/dark snapshots for `iPhoneDefault` (`390x844`) and `iPadDefault` (`820x1180`).
- Other sizes generate light/dark snapshots without device suffixes.

On macOS:
- Light/dark snapshots are generated with AppKit appearances.
- `.screen` and `.sheet` currently resolve to the macOS default size (`800x600`) unless a custom or fixed size is supplied.

Environment validation is strict:
- iOS snapshots require iOS 26 and `@3x`.
- macOS snapshots require macOS 26.

Recording:
- Missing references record automatically.
- Use `record: true` on a specific assertion when needed.
- Use `GENERATE_SNAPSHOTS=1` to force recording from the environment.

## Current iOS UI Image Examples

### Preview-Backed Compact View

- Test: `iOS/DuckDuckGoTests/AIChat/InputBox/SwitchBar/Suggestions/AIChatSyncPromoViewTests.swift`
- View preview: `iOS/DuckDuckGo/AIChat/InputBox/SwitchBar/Suggestions/AIChatSyncPromoView.swift`
- Snapshot directory: `iOS/DuckDuckGoTests/AIChat/InputBox/SwitchBar/Suggestions/__Snapshots__/AIChatSyncPromoViewTests`
- Pattern: `assertImageSnapshots(AIChatSyncPromoView_Previews.snapshots, size: .constrainedWidth)`

Use this to demo a small SwiftUI view that exposes `PreviewSnapshots` directly from the view file.

### Direct SwiftUI Sheet

- Test: `iOS/DuckDuckGoTests/AIChat/InputBox/SwitchBar/Suggestions/AIChatSyncIntroSheetViewTests.swift`
- Snapshot directory: `iOS/DuckDuckGoTests/AIChat/InputBox/SwitchBar/Suggestions/__Snapshots__/AIChatSyncIntroSheetViewTests`
- Pattern: `assertImageSnapshot(matching: AIChatSyncIntroSheetView(...), size: .sheet)`

Use this to demo direct view snapshots without a `PreviewProvider`, plus iPhone/iPad sheet sizing.

### Preview-Backed Screen With Mocks

- Test: `iOS/DuckDuckGoTests/VoiceSearchFeedbackViewTests.swift`
- View preview: `iOS/DuckDuckGo/VoiceSearchFeedbackView.swift`
- Preview mocks: `iOS/DuckDuckGo/VoiceSearchFeedbackView_PreviewMocks.swift`
- Snapshot directory: `iOS/DuckDuckGoTests/__Snapshots__/VoiceSearchFeedbackViewTests`
- Pattern: `assertImageSnapshots(VoiceSearchFeedbackView_Previews.snapshots, size: .screen)`

Use this to demo the preferred structure when preview states need mock dependencies:
- `PreviewProvider`, `typealias State`, and `static let snapshots` stay in the view file.
- Mocks and preview factories live in a sibling `_PreviewMocks.swift` file under `#if DEBUG`.

## Current macOS UI Image Examples

### Preview-Backed Fixed-Size View

- Test: `macOS/UnitTests/DefaultBrowserAndAddToDockPrompts/DefaultBrowserAndDockPromptInactiveUserViewTests.swift`
- View preview: `macOS/DuckDuckGo/DefaultBrowserAndAddToDockPrompts/DefaultBrowserAndDockPromptInactiveUserView.swift`
- Preview mocks: `macOS/DuckDuckGo/DefaultBrowserAndAddToDockPrompts/DefaultBrowserAndDockPromptInactiveUserView_PreviewMocks.swift`
- Snapshot directory: `macOS/UnitTests/DefaultBrowserAndAddToDockPrompts/__Snapshots__/DefaultBrowserAndDockPromptInactiveUserViewTests`
- Pattern: `assertImageSnapshots(DefaultBrowserAndDockPromptInactiveUserView_Previews.snapshots, size: .fixed(CGSize(width: 868, height: 508)))`

Use this to demo macOS `PreviewSnapshots` with `DefaultBrowserAndDockPromptInactiveUserViewModel` as the preview state.

### Direct SwiftUI Intrinsic Size

- Test: `macOS/UnitTests/InfoViews/InfoViewTests.swift`
- Snapshot directory: `macOS/UnitTests/InfoViews/__Snapshots__/InfoViewTests`
- Pattern: `assertImageSnapshot(matching: InfoView(...).withBackground, size: .intrinsicContentSize)`

Use this to demo the smallest direct SwiftUI snapshot.

### Existing Point-Free AppKit Image Snapshots

- Test: `macOS/UnitTests/URLDragPreviewProvider/URLDragPreviewProviderTests.swift`
- Snapshot directory: `macOS/UnitTests/URLDragPreviewProvider/__Snapshots__/URLDragPreviewProviderTests`
- Pattern: direct `assertSnapshot(of: preview, as: .image(...))`

Use this to show the older style that still works through `SnapshotTestingSupport` re-exports. It manually loops through `NSAppearance.Name.aqua` and `.darkAqua` and controls a custom snapshot window.

## Current Data Snapshot Examples

### macOS JSON Snapshots

- Test: `macOS/UnitTests/DataImport/BookmarksHTMLReaderTests.swift`
- Snapshot directory: `macOS/UnitTests/DataImport/__Snapshots__/BookmarksHTMLReaderTests`
- Pattern: `assertSnapshot(of: importResult.bookmarks, as: .json, named: fileNameWithoutExtension, testName: "snapshot")`

Use this to demo that the wrapper still allows non-UI Point-Free snapshot strategies for existing data snapshots.

## Package-Level Tests

Package tests live in `SharedPackages/SnapshotTestingSupport/Tests/SnapshotTestingSupportTests`.

Useful references:
- `PreviewSnapshotsTests.swift`: preview configuration filtering and named state support.
- `SnapshotImageSizeTests.swift`: size mode behavior.
- `SnapshotImageStrategyTests.swift`: strategy expansion for iOS/macOS and devices.
- `SnapshotNameGeneratorTests.swift`: generated snapshot names.
- `SnapshotRecordModeTests.swift`: `record` and `GENERATE_SNAPSHOTS`.
- `SnapshotEnvironmentTests.swift`: strict OS/display-scale validation.

## Demo Flow

1. Start with `SharedPackages/SnapshotTestingSupport/Sources/SnapshotTestingSupport`.
2. Show `SnapshotImageSize.swift`, `SnapshotImageStrategy.swift`, and `XCTestCase+PreviewSnapshots.swift`.
3. Show an iOS direct snapshot: `AIChatSyncIntroSheetViewTests.swift`.
4. Show an iOS preview-backed snapshot with mocks: `VoiceSearchFeedbackViewTests.swift`.
5. Show a macOS preview-backed snapshot: `DefaultBrowserAndDockPromptInactiveUserViewTests.swift`.
6. Show a macOS intrinsic snapshot: `InfoViewTests.swift`.
7. Show the older Point-Free examples: `URLDragPreviewProviderTests.swift` and `BookmarksHTMLReaderTests.swift`.

Useful test commands for reference only:

```sh
swift test --package-path SharedPackages/SnapshotTestingSupport
xcodebuild -project iOS/DuckDuckGo-iOS.xcodeproj -scheme "Unit Tests" test
xcodebuild -project macOS/DuckDuckGo-macOS.xcodeproj -scheme "macOS Unit Tests" test
```

Do not run tests unless explicitly requested.
