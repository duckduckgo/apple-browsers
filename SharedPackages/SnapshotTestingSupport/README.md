# SnapshotTestingSupport

DuckDuckGo wrapper around [Point-Free's `swift-snapshot-testing`](https://github.com/pointfreeco/swift-snapshot-testing) with conventions for iOS / macOS image snapshots and SwiftUI preview reuse.

This package gives shared UI snapshot tests one consistent home for rendering SwiftUI views, validating the simulator or host environment, naming generated images, and keeping preview states reusable between Xcode previews and automated tests. It keeps the app-facing preview helpers separate from the test-only assertion helpers, so production targets can share preview configuration without taking a dependency on snapshot testing libraries.

## Why snapshot testing?

Snapshot testing records the rendered output of a view, data structure, or other value as a reference artifact, then compares future test runs against that reference. For UI work, this is useful because many regressions are visual rather than purely behavioral: spacing changes, missing states, clipped text, incorrect colors, light / dark appearance differences, or unexpected layout shifts can all be caught by comparing the final rendered image.

Use snapshot tests as a focused regression safety net for stable UI states. They are especially valuable when a view has several meaningful configurations that can be represented by previews, because the same list of states can document the component, power Xcode previews, and verify the rendered output in tests. Snapshot tests complement unit and interaction tests; they prove that a known state still looks the way reviewers approved, while other tests should continue to cover logic, accessibility behavior, navigation, and user flows.

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
            matching: MyView().snapshotBackground(),
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

Only `.sheet` adds a backdrop automatically (it simulates the sheet chrome). For every other mode the snapshot reflects the view as-is — call `.snapshotBackground()` on your view if you want `systemBackground` / `windowBackgroundColor` behind it.

On macOS, device variants don't apply — `.screen`/`.sheet`/`.fixed` all resolve to the configuration's size (default `800x600` if unspecified).

Default appearance strategy is `.allAppearances` (light + dark). Use `.single(.light)` or `.single(.dark)` to scope, `.iPhoneAllAppearances` or `.iPhoneSingle(.dark)` to skip the iPad variants of `.screen` / `.sheet` (iPhone device on iOS regardless of size mode; plain appearances on macOS), or `.custom([...])` for full control.

## Limitations: `List`, effects, and the host-application requirement

### `List` needs a fixed-size mode

A SwiftUI `List` has no intrinsic content size, so it needs a fixed size to render: snapshot it with `.screen` or `.fixed(CGSize)`.

### Effects and iPad navigation

By default the helpers render off-screen (`drawHierarchyInKeyWindow: false`), so on iOS:

- **`UIAppearance`** is not applied.
- **Untinted glass and materials** (`.buttonStyle(.glass)`, `.glassEffect()`, `.ultraThinMaterial`) are silently left out.
- **Tinted glass** (`.buttonStyle(.glassProminent)`, `.glassEffect(.regular.tint(…))`) blanks the whole snapshot, and the blank image is recorded as the reference. Snapshot these screens through the key-window path ([below](#if-you-must-snapshot-an-effect-heavy-screen)).
- **`NavigationView` on iPad** renders as a split view — use `NavigationStack` / `.navigationViewStyle(.stack)`, or snapshot iPhone only.

### macOS: glass is never rendered

macOS renders into an off-screen window with no key-window option, and an app host doesn't change that. Glass is left out (`.glass`, `.glassProminent`, `.glassEffect()`), and tinted `.glassEffect(.regular.tint(…))` blanks the whole snapshot. Snapshots of macOS screens with glass will look different from the app, so review them with that in mind and keep tinted-glass screens out of image snapshots.

### If you must snapshot an effect-heavy screen

iOS only. You need **both** `drawHierarchyInKeyWindow: true` (renders through the real key window) **and** an app-hosted test target such as `iOS/DuckDuckGoTests`: package test targets have no key window, and a hosted target without the flag renders exactly like a package target. Reach the view's `PreviewSnapshots` with `@testable import <Module>`.

```swift
assertImageSnapshots(
    SyncSuccessView_Previews.snapshots,
    strategy: .iPhoneAllAppearances,
    size: .screen,
    drawHierarchyInKeyWindow: true
)
```

Example: `iOS/DuckDuckGoTests/SyncUI/SyncSuccessViewTests.swift`.

## Environment requirements

Snapshots are pixel-strict, so the test environment is validated before each assertion:

- **iOS**: must run on **iOS 27.0** at **@3x** (simulator runtime).
- **macOS**: must run on **macOS 27** — major version only; minor and patch are ignored.

iOS renders in a pinnable simulator runtime, so it validates major.minor. macOS renders on the uncontrolled host and CI can't guarantee an exact point release, so the macOS guard only checks the major version — we accept the small flakiness risk from minor/patch rendering differences rather than fail every time CI rolls forward. A mismatch → the helper records a failure (`XCTFail` / `Issue.record`) with an explanatory message and skips the comparison — the same in CI and locally; a developer on a different OS opts out by not running the snapshot suite.

When the OS rolls forward, bump `SnapshotEnvironment.expectedIOSVersion` / `expectedMacOSVersion` and re-record affected references.

## Reference storage

Reference images live in the `SnapshotReferences` git submodule at the repo root, mirroring each test's repo-relative path (`<platform>/…/__Snapshots__/<TestClass>/`). The wrapper redirects the library's `snapshotDirectory` there automatically, so references stay out of the app trees.

Each image name carries the recording environment as a suffix so references are unambiguous across OSes: iOS uses `…_iOS-27-0` (major.minor), macOS uses `…_macOS-27` (major only, matching the guard granularity).

## Recording

- Missing references are recorded automatically (`.missing` mode).
- `record: true` on a specific call records that assertion.
- `GENERATE_SNAPSHOTS=1` in the test scheme's env records everything.

After re-recording, inspect every diff and commit only the intentional ones.

## Skipping

`SKIP_SNAPSHOT_TESTS=1` in the test scheme's env (or on the command line, same place as `GENERATE_SNAPSHOTS`) turns off **every** image-snapshot assertion. Skipped assertions return silently and go **green** — no `XCTFail` / `Issue.record` — so the suites still run but stop comparing images. Use it as a global kill switch when a rendering or environment change would otherwise turn snapshot suites red across the board, while you investigate. Accepts `1` / `true` / `yes` (case-insensitive) and takes precedence over `GENERATE_SNAPSHOTS`.

```bash
xcodebuild test ... SKIP_SNAPSHOT_TESTS=1
```

**Currently pinned on.** The variable is hardcoded to `1` in the test-action environment of the app schemes (`iOS Browser`, `macOS Browser`, `macOS Browser App Store`, `macOS Unit Tests`), so image snapshots are skipped for everyone — locally and in CI — while snapshot references and CI runners stabilise. To re-enable snapshots, set the value back to `$(SKIP_SNAPSHOT_TESTS)` (or disable the entry) in those schemes.

## Conventions

- Snapshot tests use Swift Testing with `@MainActor`, `@Suite`, and `@Test(.timeLimit(.minutes(1)))`.
- Function names that start with `test` keep `#function`-derived snapshot paths consistent with the legacy XCTest convention.
- One `@Suite` per view test file; one `@Test` per view configuration.
- `*_PreviewMocks.swift` under `#if DEBUG` for preview-only mocks.
- Snapshots and `PreviewSnapshots` previews always render the **rebranded** design (iOS and macOS): every image assertion and `PreviewSnapshots.previews` force the rebrand flags (plus the rebranded palette on iOS), so previews don't need a `RebrandedPreview` wrapper.

## Examples in the repo

Real test sites you can crib from. References mirror each test's path inside the `SnapshotReferences` submodule.

### iOS — preview-backed compact view (`.constrainedWidth`)
- View: `iOS/DuckDuckGo/AIChat/InputBox/SwitchBar/Suggestions/AIChatSyncPromoView.swift`
- Test: `iOS/DuckDuckGoTests/AIChat/InputBox/SwitchBar/Suggestions/AIChatSyncPromoViewTests.swift`
- `PreviewProvider` in the same file as the view, reused directly by the test.

### iOS — preview-backed screen with mocks (`.screen`)
- View: `iOS/DuckDuckGo/VoiceSearchFeedbackView.swift`
- Preview mocks: `iOS/DuckDuckGo/VoiceSearchFeedbackView_PreviewMocks.swift`
- Test: `iOS/DuckDuckGoTests/VoiceSearchFeedbackViewTests.swift`
- Keep `PreviewProvider`, `typealias State`, and `static let snapshots` in the view file; move mocks to the sibling `_PreviewMocks.swift` under `#if DEBUG`.

### iOS — package test target, several states per view (`.screen`)
- Views: `iOS/LocalPackages/SyncUI-iOS/Sources/SyncUI-iOS/Views/SimplifiedSyncSettingsView.swift`, `SimplifiedConnectingSheetView.swift`
- Shared preview mocks: `iOS/LocalPackages/SyncUI-iOS/Sources/SyncUI-iOS/Views/Internal/SyncSettingsViewModel_PreviewMocks.swift`
- Tests: `iOS/LocalPackages/SyncUI-iOS/Tests/SyncUI-iOSTests/`
- Hostless package tests. Uses `scope: .previews` to keep states in Xcode previews but out of snapshots, and `.iPhoneAllAppearances` / `.iPhoneSingle(.dark)` to skip iPad. `List`-based settings screens use `.screen`.

### iOS — app-hosted key-window snapshot (glass effect)
- View: `iOS/LocalPackages/SyncUI-iOS/Sources/SyncUI-iOS/Views/SyncSuccessView.swift`
- Test: `iOS/DuckDuckGoTests/SyncUI/SyncSuccessViewTests.swift`
- `drawHierarchyInKeyWindow: true` from an app-hosted target, for a screen whose toolbar button uses `.glassProminent`.

### macOS — preview-backed fixed-size view (`.fixed`)
- View: `macOS/DuckDuckGo/DefaultBrowserAndAddToDockPrompts/DefaultBrowserAndDockPromptInactiveUserView.swift`
- Preview mocks: `macOS/DuckDuckGo/DefaultBrowserAndAddToDockPrompts/DefaultBrowserAndDockPromptInactiveUserView_PreviewMocks.swift`
- Test: `macOS/UnitTests/DefaultBrowserAndAddToDockPrompts/DefaultBrowserAndDockPromptInactiveUserViewTests.swift`
- Same `_PreviewMocks` pattern on macOS, with an explicit `CGSize` for a fixed canvas.

### macOS — package test target (`.intrinsicContentSize`)
- Tests: `macOS/LocalPackages/SyncUI-macOS/Tests/SyncUI-macOSTests/`
- Preview-backed snapshots from a hostless package test target.

### macOS — direct SwiftUI view (`.intrinsicContentSize`)
- Tests: `macOS/UnitTests/InfoViews/InfoViewTests.swift`, `macOS/UnitTests/URLDragPreviewProvider/URLDragPreviewProviderTests.swift`
- Direct `assertImageSnapshot(matching:)` without previews — combine with `.snapshotBackground()` to make the surface explicit.

### macOS — JSON / data snapshots
- Test: `macOS/UnitTests/DataImport/BookmarksHTMLReaderTests.swift`
- Non-UI Point-Free strategies (`as: .json`) still work via the re-exports.

## Package layout

```
SharedPackages/SnapshotTestingSupport/
├── Package.swift                       # PreviewSnapshots library + test-only helpers
├── Sources/
│   ├── PreviewSnapshots/               # SwiftUI-only product safe to link from app targets
│   └── SnapshotTestingSupport/         # Test-only helpers + Point-Free re-exports
└── Tests/SnapshotTestingSupportTests/  # Pure-logic Swift Testing suites
```
