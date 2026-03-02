# Suspend Tab - Implementation Plan

## Context

The goal is to allow users to manually suspend background tabs to free web content process memory. A PoC commit (`a31f039ac7`) demonstrates the approach. This plan refines the PoC into an implementable, production-ready feature covering only the **manual suspend/resume** flow (triggered via tab context menu).

**How it works:** Suspending replaces the Tab instance with a lightweight placeholder that holds the URL, title, and favicon but never spawns a WKWebView process. Resuming (clicking the tab or using the context menu) reloads the URL.

---

## Step 1: Feature Flag

Add a feature flag to gate the feature during development and rollout.

**Files:**
- `macOS/LocalPackages/FeatureFlags/Sources/FeatureFlags/FeatureFlag.swift` - add `case tabSuspension`

**Where checked:**
- `TabBarViewItem.addSuspendResumeMenuItem(to:)` - skip menu item if flag is off
- `TabCollectionViewModel.suspendTab(at:)` - early return (defense in depth)
- `Tab+NSSecureCoding.encode(with:)` - skip encoding `isSuspended` if flag is off

---

## Step 2: Tab Model

**File:** `macOS/DuckDuckGo/Tab/Model/Tab.swift`

Add:
- `@Published private(set) var isSuspended: Bool = false`
- `restoreIsSuspended(_ value: Bool)` - sets flag without side effects (used during decode)
- `suspend()` - sets `isSuspended = true`; actual memory release happens in TabCollectionViewModel
- `resume()` - sets `isSuspended = false`, calls `reloadIfNeeded(source: .contentUpdated)`

---

## Step 3: TabViewModel Bridge

**File:** `macOS/DuckDuckGo/Tab/ViewModel/TabViewModel.swift`

Add:
- `@Published private(set) var isSuspended: Bool = false`
- Subscribe via `tab.$isSuspended.assign(to: \.isSuspended, onWeaklyHeld: self)` (matches existing pattern for `canGoBack`, `canReload`, etc.)

---

## Step 4: TabBarViewItem - Protocol, Visual, Context Menu

**File:** `macOS/DuckDuckGo/TabBar/View/TabBarViewItem.swift`

### Protocol (`TabBarViewModel`)
- Add `var isSuspended: Bool { get }` and `var isSuspendedPublisher: AnyPublisher<Bool, Never> { get }`
- Add conformance on `TabViewModel`: `var isSuspendedPublisher` returns `$isSuspended.eraseToAnyPublisher()`

### Delegate (`TabBarViewItemDelegate`)
- Add `@MainActor func tabBarViewItemSuspendAction(_: TabBarViewItem)`

### Visual dimming
In `subscribe(to:)`, subscribe to `isSuspendedPublisher` and set `faviconView.alphaValue` / `titleView.alphaValue` to 0.5 when suspended, 1.0 otherwise.

### Context menu
- Add `addSuspendResumeMenuItem(to:)` after `addMuteUnmuteMenuItem` in `menuNeedsUpdate(_:)`
- Shows "Suspend Tab" or "Resume Tab" based on `isSuspended`
- Disabled for the currently selected tab (can't suspend the active tab)
- Gated behind feature flag

### Mock updates
- Update `PreviewViewController` delegate stub: `func tabBarViewItemSuspendAction(_:) {}`
- Update `TabBarViewModelMock`: add `@Published var isSuspended: Bool = false` and `isSuspendedPublisher`

---

## Step 5: TabCollectionViewModel - Core Logic

**File:** `macOS/DuckDuckGo/TabBar/ViewModel/TabCollectionViewModel.swift`

### `suspendTab(at: TabIndex)`
1. Guard: `changesEnabled`, tab exists, not selected, content is `.url`
2. Create a new `Tab(content: .url(url, source: .pendingStateRestoration), title:, favicon:, shouldLoadInBackground: false, lastSelectedAt:)`
3. Call `restoreIsSuspended(true)` on the new tab
4. Save `selectionIndex`, call `remove(at:)` + `insert(_:at:selected: false)`, restore selection

> **Why remove+insert instead of replaceTab?** `replaceTab` has no delegate notification, so TabBarViewController never refreshes the cell. The old TabViewModel keeps referencing the old Tab, preventing its WKWebView from being deallocated. Remove+insert fires proper delegate callbacks.

### `resumeTab(at: TabIndex)`
- Get tab at index, call `tab.resume()`

### Auto-resume on selection
Modify `select(at:forceChange:)`: after successful selection, check if the tab `isSuspended` and call `tab.resume()`.

---

## Step 6: TabBarViewController - Delegate Wiring

**File:** `macOS/DuckDuckGo/TabBar/View/TabBarViewController.swift`

Implement `tabBarViewItemSuspendAction(_:)`:
- Resolve `TabIndex` from collection view index path (handles both pinned and unpinned)
- Dispatch to `tabCollectionViewModel.suspendTab(at:)` or `.resumeTab(at:)` based on `isSuspended`

Follows the same pattern as `tabBarViewItemMuteUnmuteSite` and `tabBarViewItemFireproofSite`.

---

## Step 7: State Restoration

**File:** `macOS/DuckDuckGo/StateRestoration/Tab+NSSecureCoding.swift`

- Add coding key `static let isSuspended = "isSuspended"`
- **Decode:** `decoder.decodeBool(forKey:)` (returns `false` for missing keys). If true, call `restoreIsSuspended(true)` after init.
- **Encode:** Only encode when `isSuspended == true` (and feature flag is on) to avoid unnecessary data.

Suspended tabs restore naturally because URL tabs already decode with `.pendingStateRestoration` source, so they won't load until explicitly triggered.

---

## Step 8: Localization

**Files:**
- `macOS/DuckDuckGo/Common/Localizables/UserText.swift` - add `suspendTab` and `resumeTab` strings
- `macOS/DuckDuckGo/Localization/Localizable.xcstrings` - add `suspend.tab` and `resume.tab` entries

---

## Step 9: Unit Tests

**New file:** `macOS/UnitTests/TabBar/ViewModel/TabCollectionViewModelSuspendTests.swift`

Key test cases:
- `suspend()` sets `isSuspended = true`; `resume()` resets it
- `suspendTab(at:)` replaces Tab with a lightweight unloaded placeholder preserving title/favicon
- Suspending the selected tab is rejected
- Suspending a non-URL tab (`.newtab`, `.settings`) is rejected
- Selection index is preserved correctly after suspend
- Selecting a suspended tab auto-resumes it
- Encode/decode round-trip preserves `isSuspended` flag

Use existing `aTabCollectionViewModel()` factory from the test helpers.

---

## Edge Cases & Known Limitations

| Issue | Status |
|-------|--------|
| **Pinned tabs** - Disabled for pinned tabs (shared across windows via `PinnedTabsManager`, suspension wouldn't sync) | Guard in `suspendTab(at:)`: reject `.pinned` indexes. Hide/disable menu item for pinned tabs. |
| **Page state loss** - Scroll position, form data, JS state are lost on suspend (no `interactionStateData` saved) | Accept for v1; consider saving interaction state in a follow-up |
| **`select(tab:)` bypass** - This method doesn't go through `select(at:)`, so auto-resume won't trigger | Low risk: programmatic callers unlikely to target suspended tabs |
| **Exclude from PoC** - `WKWebViewExtension.swift` has an extraneous blank line addition | Do not include |

---

## Existing Utilities to Reuse

- `Logger.tabLazyLoading` (`macOS/DuckDuckGo/Common/Logger+Multiple.swift:29`) - for logging
- `Tab.reloadIfNeeded(source:)` (`Tab.swift:1024`) - for resume reload
- `TabCollectionViewModel.remove(at:)` / `insert(_:at:selected:)` - for tab replacement
- `TabCollectionViewModel.selectWithoutResettingState(at:forceChange:)` - for selection restore

---

## Verification

1. **Build** the project and confirm no compiler errors
2. **Manual test:** Open 3+ tabs, right-click a background tab, choose "Suspend Tab":
   - Tab should dim (alpha 0.5) but keep its title and favicon
   - Context menu should now show "Resume Tab"
   - Click the suspended tab - it should reload and un-dim
3. **Persistence:** Suspend a tab, quit and relaunch - suspended tab should restore as suspended
4. **Guard rails:** Verify "Suspend Tab" is disabled for the active tab; verify non-URL tabs don't show the option
5. **Run unit tests** for TabCollectionViewModel suspend/resume logic
