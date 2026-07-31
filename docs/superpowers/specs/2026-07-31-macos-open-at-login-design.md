# macOS "Open at login" setting

**Date:** 2026-07-31
**Platform:** macOS only

## Goal

Let the user make DuckDuckGo launch automatically when they log in to macOS,
via a checkbox in Settings. This is the standard macOS app affordance, backed
by `SMAppService.mainApp`.

## Placement

Settings → General → **On Startup**, as a new sub-section above the existing
window-type radio group.

```
On Startup
┌──────────────────────────────────────────────┐
│ ☑ Open DuckDuckGo at login                   │
│   Allow DuckDuckGo in System Settings to     │  ← only when
│   finish turning this on.                    │     requiresApproval
│   Open System Settings…                      │
│                                              │
│ ◉ Open a new [Window ▾]                      │
│ ○ Reopen all windows from last session       │
└──────────────────────────────────────────────┘
```

## Components

### 1. `MainAppLoginItem` — the service

New file: `macOS/DuckDuckGo/LoginItems/MainAppLoginItem.swift`

```swift
/// Registers the browser itself to launch when the user logs in to macOS.
/// Distinct from `LoginItemsManager`, which manages the VPN/DBP helper agents.
protocol MainAppLoginItemManaging {
    /// False below macOS 13, where `SMAppService.mainApp` is unavailable.
    var isSupported: Bool { get }
    func status() async -> MainAppLoginItemStatus
    func enable() async throws
    func disable() async throws
}

enum MainAppLoginItemStatus {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}
```

The concrete `MainAppLoginItem` wraps `SMAppService.mainApp`:

- `enable()` → `register()`, `disable()` → `unregister()`, `status()` → `.status`
- All three dispatch onto a detached `Task`. These do synchronous XPC to the
  Service Management daemon; `LoginItems/Sources/LoginItems/LoginItem.swift`
  already documents that as the reason to keep them off the calling thread.
- `isSupported` is `if #available(macOS 13, *)`. Below 13, `status()` returns
  `.notFound` and `enable()`/`disable()` are no-ops.
- `MainAppLoginItemStatus` is initialised from `SMAppService.Status` under an
  `@available(macOS 13.0, *)` initialiser, mirroring `LoginItem.Status`.

### 2. `OpenAtLoginModel` — the view model

New file: `macOS/DuckDuckGo/Preferences/Model/OpenAtLoginModel.swift`

```swift
@MainActor
final class OpenAtLoginModel: ObservableObject {
    @Published private(set) var status: MainAppLoginItemStatus = .notRegistered

    var isSupported: Bool { loginItem.isSupported }
    var isOn: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    init(loginItem: MainAppLoginItemManaging = MainAppLoginItem())

    func refresh() async
    func setOpenAtLogin(_ enabled: Bool) async
    func openSystemSettings()
}
```

`setOpenAtLogin` optimistically publishes the requested state, awaits
`enable()`/`disable()`, then re-reads the real status and publishes that. Errors
are logged via `Logger` and not surfaced in the UI.

`openSystemSettings()` calls `SMAppService.openSystemSettingsLoginItems()` on
macOS 13+, falling back to opening
`x-apple.systempreferences:com.apple.LoginItems-Settings.extension` — the same
pair `NetworkProtectionStatusViewModel.openLoginItemSettings()` already uses.

### 3. View changes

`macOS/DuckDuckGo/Preferences/View/PreferencesGeneralView.swift`

- New `@ObservedObject var openAtLoginModel: OpenAtLoginModel` property.
- Inside the existing `PreferencePaneSection(UserText.onStartup)`, a new
  `PreferencePaneSubSection` placed **before** the window-type
  `PreferencePaneSubSection`, wrapped in `if openAtLoginModel.isSupported`.
- The control is a `ToggleMenuItem` (checkbox style) bound to a computed
  `Binding<Bool>` whose getter is `openAtLoginModel.isOn` and whose setter
  spawns `Task { await openAtLoginModel.setOpenAtLogin(newValue) }`.
- When `openAtLoginModel.needsApproval`, a `VStack` containing a
  `TextMenuItemCaption` and a `TextButton` appears below the toggle, indented
  with `.padding(.leading, 19)` to align under the checkbox label — matching the
  existing `disableAutoDeleteToEnableSessionRestore` treatment in the same pane.
- `.task { await openAtLoginModel.refresh() }` on the section so re-opening
  Settings always reflects the real system state.
- Accessibility identifier `PreferencesGeneralView.openAtLogin` on the toggle,
  consistent with neighbouring controls.

`macOS/DuckDuckGo/Preferences/View/PreferencesRootView.swift`

- Construct the model and pass it into the existing `GeneralView(...)` call
  (around line 153), alongside `dockModel`.

### 4. Strings

Three new entries in `macOS/DuckDuckGo/Common/Localizables/UserText.swift`, plus
matching insertions into the `.xcstrings` catalogue:

| Key | Value |
|---|---|
| `preferences.open-at-login` | Open DuckDuckGo at login |
| `preferences.open-at-login.requires-approval` | Allow DuckDuckGo in System Settings to finish turning this on. |
| `preferences.open-at-login.open-system-settings` | Open System Settings… |

### 5. Project file

Both new `.swift` files need adding to the `DuckDuckGo` (macOS) target in
`macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj`. Edit the pbxproj surgically
by hand — do not use the `xcodeproj` gem, which re-serialises the whole file
destructively.

## Design decisions

**The system is the source of truth.** No mirrored `UserDefaults` key. The user
can remove the app from System Settings → Login Items at any time; a cached bool
would silently drift. Every pane appearance re-reads `SMAppService.mainApp.status`.

**`requiresApproval` renders as on.** Registration succeeded — macOS is only
waiting on the user to allow it. Rendering the checkbox as off would read as
"the click didn't work". The inline caption explains the remaining step.

**Failures revert the checkbox rather than alerting.** Re-reading the real status
after a write means a thrown `register()` snaps the checkbox back to the truth. A
modal alert is out of proportion for a settings checkbox.

**macOS 12 hides the row entirely.** `SMAppService.mainApp` is macOS 13+, and the
deployment target is 12.3. The `LSSharedFileList` fallback is deprecated since
10.11 and non-functional under the App Store sandbox, so it is not worth a second
code path. This mirrors how `DockCustomizer.supportsAddingToDock` already hides
the Dock UI where it cannot work.

**A separate service, not the existing `LoginItems` package.** `LoginItem` is
keyed on a helper-agent bundle ID and calls
`SMAppService.loginItem(identifier:)`; `LoginItemsManager` is documented as
managing "the login items for the VPN and DBP". Registering the browser itself
requires `SMAppService.mainApp`, which takes no identifier. Widening the
VPN-owned types to cover both would degrade them for both callers.

## Out of scope

- **Pixels.** Explicitly excluded from this first pass.
- **Feature flag.** Not gated remotely.
- **Unit tests.** Excluded from this pass. The `MainAppLoginItemManaging`
  protocol seam exists so a `MainAppLoginItemMock` and `OpenAtLoginModel` tests
  can be added later without restructuring.
- **"Launch hidden" option.** Neither Safari nor Chrome offers one.
- **Detecting whether the app was launched at login.** The app opens its normal
  startup window either way.

## Verification

Compile check:

```
xcodebuild -workspace DuckDuckGo.xcworkspace -scheme "macOS Browser" \
    -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Manual paths to exercise:

1. Toggle on → app appears in System Settings → General → Login Items.
2. Toggle off → app disappears from that list.
3. Deny in System Settings, reopen Settings → checkbox on, approval caption
   shown, link opens the right pane.
4. macOS 12 → the row is absent and the On Startup section is otherwise
   unchanged.
