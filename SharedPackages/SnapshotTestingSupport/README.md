# SnapshotTestingSupport

DuckDuckGo wrapper around [Point-Free's `swift-snapshot-testing`](https://github.com/pointfreeco/swift-snapshot-testing) with conventions for iOS / macOS image snapshots and SwiftUI preview reuse.

## Products

| Product | Link from | Purpose |
|---|---|---|
| `PreviewSnapshots` | App target (only when the view file exposes states) | Defines `PreviewSnapshots<State>` so a `PreviewProvider` and a test can share the same configuration list. |
| `SnapshotTestingSupport` | Test target | Re-exports `SnapshotTesting` + `InlineSnapshotTesting`, adds DDG image snapshot helpers, environment validation, and naming. |

Keep `SnapshotTestingSupport` linked only to test targets.

## Quick start

### Direct view snapshots

```swift
import SnapshotTestingSupport
import Testing

@MainActor
@Suite("My View Tests")
final class MyViewTests {

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testMyViewSnapshot() {
        assertImageSnapshot(
            matching: MyView().withBackground,
            size: .intrinsicContentSize
        )
    }
}
```

### Preview-backed snapshots

In the view file:

```swift
struct MyView_Previews: PreviewProvider {
    typealias State = MyViewModel

    static var previews: some View {
        snapshots.previews
    }

    static let snapshots = PreviewSnapshots<State>(
        configurations: [
            .init(name: "Empty", state: .empty),
            .init(name: "Loaded", state: .loaded)
        ],
        configure: { MyView(viewModel: $0) }
    )
}
```

In the test:

```swift
@Test(.timeLimit(.minutes(1)))
func testMyViewSnapshots() {
    assertImageSnapshots(MyView_Previews.snapshots, size: .screen)
}
```

If preview states need mocks, put them in a sibling `MyView_PreviewMocks.swift` under `#if DEBUG` so the view file stays focused.

### Existing Point-Free APIs

Re-exported transitively, so JSON / inline / AppKit `NSImage` snapshots keep working:

```swift
assertSnapshot(of: value, as: .json)
```

## Size modes

`SnapshotImageSize` controls layout. Each mode resolves to one or more configurations (light + dark, sometimes phone + pad).

| Mode | Use when | Devices |
|---|---|---|
| `.intrinsicContentSize` | Compact view sized by its content | none |
| `.constrainedWidth` | Content-driven height, default iPhone width (390) | none |
| `.screen` | Full-screen layout | iPhone + iPad on iOS |
| `.sheet` | Sheet presentation; iPhone bottom-aligned, iPad centered with padding | iPhone + iPad on iOS |
| `.fixed(CGSize)` | Explicit size (typical for macOS windows/panels) | none |

Only `.sheet` adds a backdrop automatically (it simulates the sheet chrome). For every other mode the snapshot reflects the view as-is — call `.withBackground` on your view if you want `systemBackground` / `windowBackgroundColor` behind it.

On macOS, device variants don't apply — `.screen`/`.sheet`/`.fixed` all resolve to the configuration's size (default `800x600` if unspecified).

Default appearance strategy is `.allAppearances` (light + dark). Use `.single(.light)` or `.single(.dark)` to scope, or `.custom([...])` for full control.

## Environment requirements

Snapshots are pixel-strict, so the test environment is validated before each assertion:

- **iOS**: must run on **iOS 26.4** at **@3x**.
- **macOS**: must run on **macOS 26.x**.

Wrong OS or scale → the helper calls `XCTFail` with an explanatory message and skips the comparison. Make sure your simulator / runner matches before recording.

When the OS rolls forward, bump `SnapshotEnvironment.expectedMajorVersion` and `expectedMinorVersion` and re-record affected references.

## Recording

- Missing references are recorded automatically (`.missing` mode).
- `record: true` on a specific call records that assertion.
- `GENERATE_SNAPSHOTS=1` in the test scheme's env records everything.

After re-recording, inspect every diff and commit only the intentional ones.

## Conventions

- Snapshot tests use Swift Testing with `@MainActor`, `@Suite`, and `@Test(.timeLimit(.minutes(1)))`.
- Function names that start with `test` keep `#function`-derived snapshot paths consistent with the legacy XCTest convention.
- One `@Suite` per view test file; one `@Test` per view configuration.
- `*_PreviewMocks.swift` under `#if DEBUG` for preview-only mocks.

## Examples in the repo

Real test sites you can crib from:

### iOS — preview-backed compact view (`.constrainedWidth`)
- View: `iOS/DuckDuckGo/AIChat/InputBox/SwitchBar/Suggestions/AIChatSyncPromoView.swift`
- Test: `iOS/DuckDuckGoTests/AIChat/InputBox/SwitchBar/Suggestions/AIChatSyncPromoViewTests.swift`
- Snapshots: same folder under `__Snapshots__/AIChatSyncPromoViewTests`
- Shows a small SwiftUI view whose `PreviewProvider` lives in the same file as the view and is reused directly by the test.

### iOS — direct SwiftUI sheet (`.sheet`)
- Test: `iOS/DuckDuckGoTests/AIChat/InputBox/SwitchBar/Suggestions/AIChatSyncIntroSheetViewTests.swift`
- Shows `assertImageSnapshot(matching:size:)` against a constructed view (no `PreviewProvider`), exercising iPhone + iPad sheet sizing automatically.

### iOS — preview-backed screen with mocks (`.screen`)
- View: `iOS/DuckDuckGo/VoiceSearchFeedbackView.swift`
- Preview mocks: `iOS/DuckDuckGo/VoiceSearchFeedbackView_PreviewMocks.swift`
- Test: `iOS/DuckDuckGoTests/VoiceSearchFeedbackViewTests.swift`
- Shows the preferred structure when preview states need mocks: keep `PreviewProvider`, `typealias State`, and `static let snapshots` in the view file; move mocks to the sibling `_PreviewMocks.swift` under `#if DEBUG`.

### macOS — preview-backed fixed-size view (`.fixed`)
- View: `macOS/DuckDuckGo/DefaultBrowserAndAddToDockPrompts/DefaultBrowserAndDockPromptInactiveUserView.swift`
- Preview mocks: `macOS/DuckDuckGo/DefaultBrowserAndAddToDockPrompts/DefaultBrowserAndDockPromptInactiveUserView_PreviewMocks.swift`
- Test: `macOS/UnitTests/DefaultBrowserAndAddToDockPrompts/DefaultBrowserAndDockPromptInactiveUserViewTests.swift`
- Same `_PreviewMocks` pattern on macOS, with explicit `CGSize` for views that have a fixed canvas.

### macOS — direct SwiftUI intrinsic size (`.intrinsicContentSize`)
- Test: `macOS/UnitTests/InfoViews/InfoViewTests.swift`
- Smallest possible direct snapshot — combine with `.withBackground` to make the surface explicit.

### macOS — existing Point-Free AppKit image snapshots
- Test: `macOS/UnitTests/URLDragPreviewProvider/URLDragPreviewProviderTests.swift`
- Older style that still works through the re-exports — manual `NSAppearance.Name.aqua` / `.darkAqua` loop with a custom snapshot window. Useful when you need full control of the host window.

### macOS — JSON / data snapshots
- Test: `macOS/UnitTests/DataImport/BookmarksHTMLReaderTests.swift`
- Demonstrates that non-UI Point-Free strategies (`as: .json`) still work via the re-exports.

## Package layout

```
SharedPackages/SnapshotTestingSupport/
├── Package.swift                       # PreviewSnapshots library + test-only helpers
├── Sources/
│   ├── PreviewSnapshots/               # SwiftUI-only product safe to link from app targets
│   └── SnapshotTestingSupport/         # Test-only helpers + Point-Free re-exports
└── Tests/SnapshotTestingSupportTests/  # Pure-logic Swift Testing suites
```
