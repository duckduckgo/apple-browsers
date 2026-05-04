# Per-Tab Unified Input State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each iOS tab remembers its own unified-input state (text, toggle, attachments, model id, reasoning mode, tool selection) across tab switches; new tabs seed from last-used choices.

**Architecture:** A new `UnifiedInputStateStore` (behind `UnifiedInputStateStoring`) holds `[TabUID: TabInputState]` in memory, observes `TabsModel` for tab inserts/removes, and exposes `LastUsedInputDefaults` reading through to `ToggleModeStorage` + `AIChatPreferencesPersisting`. The coordinator hydrates from the store on tab activation and flushes back on deactivation; mutation publishers also push to the store. `Tab.preferredTextEntryMode` continues to be the only NSCoding-persisted slice (toggle).

**Tech Stack:** Swift 5.9+, UIKit, Combine, XCTest. iOS 16+. The implementation lives in `iOS/DuckDuckGo/UnifiedToggleInput/`.

---

## Spec reference

`docs/superpowers/specs/2026-05-04-per-tab-unified-input-state-design.md`

## File structure

**New** (`iOS/DuckDuckGo/UnifiedToggleInput/`):
- `TabInputState.swift` — value struct + `TabUID` typealias.
- `UnifiedInputStateStoring.swift` — protocol + `LastUsedInputDefaults` value type.
- `UnifiedInputStateStore.swift` — concrete store; `TabsModel` observation; mutation API.

**New** (`iOS/DuckDuckGoTests/UnifiedToggleInput/`):
- `TabInputStateTests.swift`
- `UnifiedInputStateStoreTests.swift`

**Modified:**
- `UnifiedToggleInputCoordinator.swift` — new `currentTabUID`, `activateForTab(_:)`, narrowed `resetSessionState`, mutation hooks pushing to store.
- `MainViewController+UnifiedToggleInput.swift` — construct store, wire to `TabsModel`, pass through to coordinator init, call `coordinator.activateForTab(tab.uid)` in refresh paths.
- `iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedToggleInputCoordinatorTests.swift` — extend with hydrate / flush / mutation propagation tests.
- `iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj` — add the three new source files and two new test files (Xcode usually auto-prompts when files are dropped; can also be added manually).

## How to run tests

These tests are XCTest-based and run in Xcode. Simulator startup is slow; the most efficient cycle is:

- **Per-task TDD loop**: in Xcode, open the test file, hit ⌘U with only the new test class targeted (Product → Test → individual class). For pure value-type tests this is < 5 s.
- **Final integration run**: `xcodebuild test -workspace DuckDuckGo.xcworkspace -scheme "DuckDuckGo" -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:DuckDuckGoTests/UnifiedInputStateStoreTests -only-testing:DuckDuckGoTests/TabInputStateTests` from the repo root for CI parity.

After each task: `git status` should be clean and a single commit lands.

---

## Task 1: `TabInputState` value struct + `TabUID` typealias

**Files:**
- Create: `iOS/DuckDuckGo/UnifiedToggleInput/TabInputState.swift`
- Create: `iOS/DuckDuckGoTests/UnifiedToggleInput/TabInputStateTests.swift`

- [ ] **Step 1: Write the failing test**

Create `TabInputStateTests.swift`:

```swift
//
//  TabInputStateTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//

import AIChat
import XCTest
@testable import DuckDuckGo

final class TabInputStateTests: XCTestCase {

    func test_default_isEmpty() {
        let sut = TabInputState()
        XCTAssertEqual(sut.text, "")
        XCTAssertEqual(sut.toggleMode, .search)
        XCTAssertTrue(sut.attachments.isEmpty)
        XCTAssertNil(sut.selectedModelID)
        XCTAssertNil(sut.selectedReasoningMode)
        XCTAssertNil(sut.selectedTool)
    }

    func test_equatable_sameValues_areEqual() {
        let a = TabInputState(text: "hi", toggleMode: .aiChat)
        let b = TabInputState(text: "hi", toggleMode: .aiChat)
        XCTAssertEqual(a, b)
    }

    func test_equatable_differingText_areNotEqual() {
        let a = TabInputState(text: "a")
        let b = TabInputState(text: "b")
        XCTAssertNotEqual(a, b)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

In Xcode, ⌘U on `TabInputStateTests`. Expected: compile error — `TabInputState` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `TabInputState.swift`:

```swift
//
//  TabInputState.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//

import AIChat

typealias TabUID = String

struct TabInputState: Equatable {
    var text: String
    var toggleMode: TextEntryMode
    var attachments: [AIChatImageAttachment]
    var selectedModelID: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?

    init(
        text: String = "",
        toggleMode: TextEntryMode = .search,
        attachments: [AIChatImageAttachment] = [],
        selectedModelID: String? = nil,
        selectedReasoningMode: AIChatReasoningMode? = nil,
        selectedTool: AIChatRAGTool? = nil
    ) {
        self.text = text
        self.toggleMode = toggleMode
        self.attachments = attachments
        self.selectedModelID = selectedModelID
        self.selectedReasoningMode = selectedReasoningMode
        self.selectedTool = selectedTool
    }
}
```

Add the file to the `DuckDuckGo` (iOS) target via Xcode (or by editing the `.pbxproj`). Add the test file to the `DuckDuckGoTests` target.

- [ ] **Step 4: Run test to verify it passes**

⌘U on `TabInputStateTests`. Expected: 3/3 PASS.

- [ ] **Step 5: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/TabInputState.swift \
        iOS/DuckDuckGoTests/UnifiedToggleInput/TabInputStateTests.swift \
        iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj
git commit -m "Add TabInputState value struct for per-tab unified input state"
```

---

## Task 2: `UnifiedInputStateStoring` protocol + `LastUsedInputDefaults`

**Files:**
- Create: `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputStateStoring.swift`

- [ ] **Step 1: Create the protocol file**

```swift
//
//  UnifiedInputStateStoring.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//

import AIChat

struct LastUsedInputDefaults: Equatable {
    var toggleMode: TextEntryMode
    var selectedModelID: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
}

@MainActor
protocol UnifiedInputStateStoring: AnyObject {
    /// Returns the current state for `uid`. If no entry exists, returns a fresh state seeded from `lastUsed`.
    func state(for uid: TabUID) -> TabInputState

    /// Replaces the entry for `uid` and updates `lastUsed` for the seedable fields.
    func update(_ state: TabInputState, for uid: TabUID)

    /// Removes the entry for `uid`. No-op if absent.
    func remove(for uid: TabUID)

    /// The seedable defaults used for new tabs. Read-through to global preferences where one exists.
    var lastUsed: LastUsedInputDefaults { get }
}
```

- [ ] **Step 2: Build to verify compilation**

⌘B in Xcode. Expected: Build Succeeded. (No tests yet — exercised in Task 3.)

- [ ] **Step 3: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputStateStoring.swift \
        iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj
git commit -m "Add UnifiedInputStateStoring protocol and LastUsedInputDefaults"
```

---

## Task 3: `UnifiedInputStateStore` — basic get/set/remove (TDD)

**Files:**
- Create: `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputStateStore.swift`
- Create: `iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedInputStateStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Create `UnifiedInputStateStoreTests.swift`:

```swift
//
//  UnifiedInputStateStoreTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//

import AIChat
import XCTest
@testable import DuckDuckGo

@MainActor
final class UnifiedInputStateStoreTests: XCTestCase {

    private var preferences: StubPreferences!
    private var toggleStorage: StubToggleModeStorage!
    private var sut: UnifiedInputStateStore!

    override func setUp() {
        super.setUp()
        preferences = StubPreferences()
        toggleStorage = StubToggleModeStorage()
        sut = UnifiedInputStateStore(
            preferences: preferences,
            toggleModeStorage: toggleStorage
        )
    }

    override func tearDown() {
        sut = nil
        toggleStorage = nil
        preferences = nil
        super.tearDown()
    }

    // MARK: - get/set/remove

    func test_state_forUnknownUID_returnsSeededFromLastUsed() {
        toggleStorage.stored = .aiChat
        preferences.selectedModelId = "gpt-5"
        let state = sut.state(for: "tab-1")
        XCTAssertEqual(state.toggleMode, .aiChat)
        XCTAssertEqual(state.selectedModelID, "gpt-5")
        XCTAssertEqual(state.text, "")
        XCTAssertTrue(state.attachments.isEmpty)
    }

    func test_update_thenState_returnsSameValue() {
        var state = TabInputState()
        state.text = "hello"
        state.toggleMode = .aiChat
        sut.update(state, for: "tab-1")
        XCTAssertEqual(sut.state(for: "tab-1"), state)
    }

    func test_remove_clearsEntry() {
        var state = TabInputState()
        state.text = "hello"
        sut.update(state, for: "tab-1")
        sut.remove(for: "tab-1")
        // After remove, state(for:) should re-seed from lastUsed (empty text).
        XCTAssertEqual(sut.state(for: "tab-1").text, "")
    }
}

// MARK: - Test Stubs

final class StubPreferences: AIChatPreferencesPersisting {
    var selectedModelId: String?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedModelShortName: String?
    var selectedReasoningEffort: String?
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningMode: AIChatReasoningMode?
}

final class StubToggleModeStorage: ToggleModeStoring {
    var stored: TextEntryMode = .search
    func save(_ mode: TextEntryMode) { stored = mode }
    func restore() -> TextEntryMode { stored }
}
```

Note: also add `import Combine` at the top with the other imports.

- [ ] **Step 2: Run test to verify it fails**

⌘U on `UnifiedInputStateStoreTests`. Expected: compile error — `UnifiedInputStateStore` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `UnifiedInputStateStore.swift`:

```swift
//
//  UnifiedInputStateStore.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//

import AIChat
import Combine

@MainActor
final class UnifiedInputStateStore: UnifiedInputStateStoring {

    private var states: [TabUID: TabInputState] = [:]
    private let preferences: AIChatPreferencesPersisting
    private let toggleModeStorage: ToggleModeStoring
    private var lastUsedTool: AIChatRAGTool?

    init(
        preferences: AIChatPreferencesPersisting,
        toggleModeStorage: ToggleModeStoring
    ) {
        self.preferences = preferences
        self.toggleModeStorage = toggleModeStorage
    }

    var lastUsed: LastUsedInputDefaults {
        LastUsedInputDefaults(
            toggleMode: toggleModeStorage.restore(),
            selectedModelID: preferences.selectedModelId,
            selectedReasoningMode: preferences.selectedReasoningMode,
            selectedTool: lastUsedTool
        )
    }

    func state(for uid: TabUID) -> TabInputState {
        if let existing = states[uid] {
            return existing
        }
        return seededState()
    }

    func update(_ state: TabInputState, for uid: TabUID) {
        states[uid] = state
        lastUsedTool = state.selectedTool
    }

    func remove(for uid: TabUID) {
        states.removeValue(forKey: uid)
    }

    private func seededState() -> TabInputState {
        let defaults = lastUsed
        return TabInputState(
            text: "",
            toggleMode: defaults.toggleMode,
            attachments: [],
            selectedModelID: defaults.selectedModelID,
            selectedReasoningMode: defaults.selectedReasoningMode,
            selectedTool: defaults.selectedTool
        )
    }
}
```

Add to `DuckDuckGo` and `DuckDuckGoTests` targets.

- [ ] **Step 4: Run tests to verify they pass**

⌘U on `UnifiedInputStateStoreTests`. Expected: 3/3 PASS.

- [ ] **Step 5: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputStateStore.swift \
        iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedInputStateStoreTests.swift \
        iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj
git commit -m "Add UnifiedInputStateStore with get/set/remove and lastUsed read-through"
```

---

## Task 4: `lastUsed` updates from per-tab mutation

**Files:**
- Modify: `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputStateStore.swift`
- Modify: `iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedInputStateStoreTests.swift`

The store needs to write through seedable fields to canonical homes when `update(_:for:)` runs. This keeps the global "last used" preferences in sync with the active tab.

- [ ] **Step 1: Add failing tests**

Append to `UnifiedInputStateStoreTests.swift`:

```swift
    func test_update_writesThroughToggleModeToStorage() {
        var state = TabInputState()
        state.toggleMode = .aiChat
        sut.update(state, for: "tab-1")
        XCTAssertEqual(toggleStorage.stored, .aiChat)
    }

    func test_update_writesThroughSelectedModelIDToPreferences() {
        var state = TabInputState()
        state.selectedModelID = "claude-opus"
        sut.update(state, for: "tab-1")
        XCTAssertEqual(preferences.selectedModelId, "claude-opus")
    }

    func test_update_writesThroughReasoningModeToPreferences() {
        var state = TabInputState()
        state.selectedReasoningMode = .think
        sut.update(state, for: "tab-1")
        XCTAssertEqual(preferences.selectedReasoningMode, .think)
    }

    func test_update_setsLastUsedTool() {
        var state = TabInputState()
        state.selectedTool = .webSearch
        sut.update(state, for: "tab-1")
        XCTAssertEqual(sut.lastUsed.selectedTool, .webSearch)
    }
```

(Use whichever case the codebase uses for `AIChatReasoningMode`; if `.think` doesn't exist, replace with the first case from the enum — see `AIChatReasoningMode.swift`.)

- [ ] **Step 2: Run tests to verify they fail**

⌘U on the new tests. Expected: 4 failures.

- [ ] **Step 3: Update `update(_:for:)`**

Replace the existing `update(_:for:)` body in `UnifiedInputStateStore.swift`:

```swift
    func update(_ state: TabInputState, for uid: TabUID) {
        states[uid] = state
        toggleModeStorage.save(state.toggleMode)
        preferences.selectedModelId = state.selectedModelID
        preferences.selectedReasoningMode = state.selectedReasoningMode
        lastUsedTool = state.selectedTool
    }
```

- [ ] **Step 4: Run tests to verify they pass**

⌘U. Expected: all 7 tests in the file PASS.

- [ ] **Step 5: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputStateStore.swift \
        iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedInputStateStoreTests.swift
git commit -m "Write through seedable fields to global preferences on update"
```

---

## Task 5: Eager seeding on tab insert

**Files:**
- Modify: `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputStateStore.swift`
- Modify: `iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedInputStateStoreTests.swift`

The store should observe `TabsModel.tabsPublisher` to detect new tabs and call `state(for: uid)` so they're materialized eagerly. It should also use the tab's `preferredTextEntryMode` for the toggle slice.

- [ ] **Step 1: Add failing test**

Append to `UnifiedInputStateStoreTests.swift`:

```swift
    func test_observingTabsModel_seedsNewTabs() {
        let tabsModel = TabsModel(desktop: false)
        let tab = Tab(uid: "tab-eager", fireTab: false, preferredTextEntryMode: .aiChat)
        sut.observeTabsModel(tabsModel)
        tabsModel.insert(tab: tab, placement: .atEnd, selectNewTab: true)
        // After insert, the store should hold an entry whose toggle came from the tab.
        XCTAssertEqual(sut.state(for: "tab-eager").toggleMode, .aiChat)
    }
```

- [ ] **Step 2: Run test to verify it fails**

⌘U. Expected: compile error — `observeTabsModel` not defined.

- [ ] **Step 3: Implement**

Add to `UnifiedInputStateStore.swift`:

```swift
    private var tabsCancellable: AnyCancellable?
    private var knownUIDs: Set<TabUID> = []

    func observeTabsModel(_ tabsModel: TabsModel) {
        tabsCancellable = tabsModel.tabsPublisher
            .sink { [weak self] tabs in
                self?.reconcile(with: tabs)
            }
    }

    private func reconcile(with tabs: [Tab]) {
        let currentUIDs = Set(tabs.map { $0.uid })
        // Insertions: seed from tab.preferredTextEntryMode + lastUsed for the rest.
        for tab in tabs where !knownUIDs.contains(tab.uid) {
            states[tab.uid] = seededState(forTab: tab)
        }
        // Removals: evict entries for vanished tabs.
        for uid in knownUIDs.subtracting(currentUIDs) {
            states.removeValue(forKey: uid)
        }
        knownUIDs = currentUIDs
    }

    private func seededState(forTab tab: Tab) -> TabInputState {
        let defaults = lastUsed
        return TabInputState(
            text: "",
            toggleMode: tab.preferredTextEntryMode,
            attachments: [],
            selectedModelID: defaults.selectedModelID,
            selectedReasoningMode: defaults.selectedReasoningMode,
            selectedTool: defaults.selectedTool
        )
    }
```

- [ ] **Step 4: Run test to verify it passes**

⌘U. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputStateStore.swift \
        iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedInputStateStoreTests.swift
git commit -m "Seed per-tab input state eagerly on TabsModel insert"
```

---

## Task 6: Eviction on tab remove

**Files:**
- Modify: `iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedInputStateStoreTests.swift`

The previous task already implements eviction in `reconcile`. Add a test to lock it in.

- [ ] **Step 1: Add failing test**

Append:

```swift
    func test_observingTabsModel_evictsRemovedTabs() {
        let tabsModel = TabsModel(desktop: false)
        let tab = Tab(uid: "tab-evict", fireTab: false)
        tabsModel.insert(tab: tab, placement: .atEnd, selectNewTab: true)
        sut.observeTabsModel(tabsModel)
        sut.update(TabInputState(text: "kept"), for: "tab-evict")

        tabsModel.remove(tab: tab)
        // After removal, state(for:) re-seeds from lastUsed → empty text.
        XCTAssertEqual(sut.state(for: "tab-evict").text, "")
    }
```

- [ ] **Step 2: Run test**

⌘U. Expected: PASS (logic was already added in Task 5).

- [ ] **Step 3: Commit**

```bash
git add iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedInputStateStoreTests.swift
git commit -m "Add eviction test for tab removal"
```

---

## Task 7: Coordinator hydrate / flush methods

The coordinator gains:
- `currentTabUID: TabUID?`
- `applyState(_ state: TabInputState)` — pushes state into the input view, switch handler, `UTIModelStore`, `UTIToolsController`.
- `snapshotCurrentState() -> TabInputState` — reads back the same fields.
- `activateForTab(_ uid: TabUID)` — flush previous → `store.update(snapshot, for: previousUID)` → load new → `applyState(store.state(for: uid))`.

A new initializer accepts a `UnifiedInputStateStoring`. The existing initializer adds it as a parameter (no overload — fewer surfaces).

**Files:**
- Modify: `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputCoordinator.swift`
- Modify: `iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedToggleInputCoordinatorTests.swift`

- [ ] **Step 1: Add failing test**

In `UnifiedToggleInputCoordinatorTests.swift`, add a fake store and a test (locate the existing test fixture; after the existing tests, append):

```swift
// MARK: - Per-tab state

@MainActor
final class FakeInputStateStore: UnifiedInputStateStoring {
    var states: [TabUID: TabInputState] = [:]
    var lastUsed = LastUsedInputDefaults(
        toggleMode: .search,
        selectedModelID: nil,
        selectedReasoningMode: nil,
        selectedTool: nil
    )

    func state(for uid: TabUID) -> TabInputState {
        states[uid] ?? TabInputState(toggleMode: lastUsed.toggleMode)
    }

    func update(_ state: TabInputState, for uid: TabUID) {
        states[uid] = state
    }

    func remove(for uid: TabUID) {
        states.removeValue(forKey: uid)
    }
}

extension UnifiedToggleInputCoordinatorTests {

    func test_activateForTab_appliesStoredText() {
        let store = FakeInputStateStore()
        store.states["tab-A"] = TabInputState(text: "remembered")
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        XCTAssertEqual(sut.currentText, "remembered")
    }

    func test_activateForTab_flushesPreviousTab() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        sut.setText("typed")
        sut.activateForTab("tab-B")
        XCTAssertEqual(store.states["tab-A"]?.text, "typed")
    }
}
```

`makeSUT(stateStore:)` should mirror the existing factory in this test file with the new dependency. Find the existing `makeSUT(...)` and add `stateStore: UnifiedInputStateStoring = FakeInputStateStore()` as a parameter, then thread it into the coordinator init.

- [ ] **Step 2: Run tests to verify they fail**

⌘U on the two new tests. Expected: compile errors — `activateForTab` and `stateStore:` parameter missing.

- [ ] **Step 3: Add the dependency to the coordinator initializer**

In `UnifiedToggleInputCoordinator.swift`, find the `init(...)` (around line 208) and add a parameter:

```swift
    private let stateStore: UnifiedInputStateStoring
    private(set) var currentTabUID: TabUID?

    init(
        isToggleEnabled: Bool,
        isFireTab: Bool = false,
        duckAiNativeStorageHandler: DuckAiNativeStorageHandling? = nil,
        modelsService: AIChatModelsProviding = AIChatModelsService(),
        preferences: AIChatPreferencesPersisting = AIChatPreferencesPersistor(),
        subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager,
        toggleModeStorage: ToggleModeStoring = ToggleModeStorage(),
        stateStore: UnifiedInputStateStoring
    ) {
        self.isToggleEnabled = isToggleEnabled
        self.toggleModeStorage = toggleModeStorage
        self.stateStore = stateStore
        // ... rest unchanged
```

- [ ] **Step 4: Add `applyState`, `snapshotCurrentState`, `activateForTab`**

Add a new section near the existing "Tab Binding" MARK in `UnifiedToggleInputCoordinator.swift`:

```swift
    // MARK: - Per-Tab State

    func activateForTab(_ uid: TabUID) {
        if let previous = currentTabUID, previous != uid {
            stateStore.update(snapshotCurrentState(), for: previous)
        }
        currentTabUID = uid
        applyState(stateStore.state(for: uid))
    }

    func applyState(_ state: TabInputState) {
        setText(state.text)
        viewController.handler.setToggleState(state.toggleMode)
        inputMode = state.toggleMode

        viewController.removeAllAttachments()
        for attachment in state.attachments {
            viewController.addAttachment(attachment)
        }

        if let modelID = state.selectedModelID {
            modelStore.updateSelectedModel(modelID)
        }
        if let reasoning = state.selectedReasoningMode {
            modelStore.updateSelectedReasoningMode(reasoning)
        }

        if let tool = state.selectedTool {
            toolsController.select(tool, for: modelStore)
        } else {
            toolsController.clearSelection()
        }
    }

    func snapshotCurrentState() -> TabInputState {
        TabInputState(
            text: currentText,
            toggleMode: inputMode,
            attachments: viewController.currentAttachments,
            selectedModelID: modelStore.persistedModelId,
            selectedReasoningMode: modelStore.selectedReasoningMode,
            selectedTool: toolsController.selectedTool
        )
    }
```

(Note: `viewController.handler.setToggleState(_:)` already exists on `SwitchBarHandling`. `viewController.addAttachment(_:)` and `removeAllAttachments()` exist on `UnifiedToggleInputView` and forward through; verify with the existing files in `UnifiedToggleInput/`.)

- [ ] **Step 5: Run tests**

⌘U. Expected: 2/2 PASS.

- [ ] **Step 6: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputCoordinator.swift \
        iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedToggleInputCoordinatorTests.swift
git commit -m "Add coordinator activateForTab/applyState/snapshotCurrentState"
```

---

## Task 8: Narrow `resetSessionState`

`resetSessionState` currently clears per-tab fields (text, attachments, tools). The hydrate path now sets these explicitly, so reset should drop those clears and keep only chat-binding-related resets.

**Files:**
- Modify: `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputCoordinator.swift`
- Modify: `iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedToggleInputCoordinatorTests.swift`

- [ ] **Step 1: Add failing test**

Append:

```swift
    func test_bindToTabDifferentScript_doesNotClearText() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        sut.setText("draft")
        // Simulate switching to a different AI user-script binding (same tab uid).
        let scriptA = makeUserScript()
        let scriptB = makeUserScript()
        sut.bindToTab(scriptA)
        sut.bindToTab(scriptB)
        XCTAssertEqual(sut.currentText, "draft")
    }
```

(`makeUserScript()` is whatever helper the existing test file uses to mint a fake `AIChatUserScript`. Reuse the existing helper.)

- [ ] **Step 2: Run test to verify it fails**

⌘U. Expected: FAIL — `resetSessionState` wipes the text.

- [ ] **Step 3: Edit `resetSessionState`**

In `UnifiedToggleInputCoordinator.swift` line ~1025, replace the body:

```swift
    func resetSessionState() {
        isNewChatPending = false
        aiChatStatus = .unknown
        aiChatInputBoxVisibility = .unknown
        attachmentUsage = nil
        hasSubmittedPrompt = false
        updateModelChipVisibility()
        syncHasSubmittedPromptToHandler()
    }
```

(Removed: `if isActive { setText("") }`, `resetToolsSelection()`, `clearAttachments()`. These are now driven by `applyState`/`activateForTab`.)

- [ ] **Step 4: Run test**

⌘U. Expected: PASS. Also run the full test class to catch regressions in existing tests; some existing tests may have implicitly relied on the old reset behavior — fix them by calling `applyState(TabInputState())` (an empty state) where they previously expected reset to clear.

- [ ] **Step 5: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputCoordinator.swift \
        iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedToggleInputCoordinatorTests.swift
git commit -m "Narrow resetSessionState; per-tab fields now driven by applyState"
```

---

## Task 9: Mutation propagation to the store

Each user mutation in the active tab should also push into the store so that switching away preserves the change.

**Files:**
- Modify: `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputCoordinator.swift`
- Modify: `iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedToggleInputCoordinatorTests.swift`

- [ ] **Step 1: Add failing tests**

Append:

```swift
    func test_textChange_propagatesToStore() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        sut.setText("typing")
        XCTAssertEqual(store.states["tab-A"]?.text, "typing")
    }

    func test_modeChange_propagatesToStore() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        sut.updateInputMode(.aiChat, animated: false)
        XCTAssertEqual(store.states["tab-A"]?.toggleMode, .aiChat)
    }

    func test_attachmentAdded_propagatesToStore() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        sut.addImageAttachment(image: UIImage(), fileName: "x.jpg")
        XCTAssertEqual(store.states["tab-A"]?.attachments.count, 1)
    }

    func test_toolSelected_propagatesToStore() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        sut.selectTool(.webSearch)
        XCTAssertEqual(store.states["tab-A"]?.selectedTool, .webSearch)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

⌘U. Expected: 4 FAIL — store not updated by these mutations.

- [ ] **Step 3: Add a write-through helper and call it from each mutation site**

Add a private helper:

```swift
    private func persistCurrentStateToStore() {
        guard let uid = currentTabUID else { return }
        stateStore.update(snapshotCurrentState(), for: uid)
    }
```

Call it at the end of each mutation method:
- `setText(_:)` (or `textChangeSubject.send`'s subscribe site — find where `currentText` is mutated)
- `updateInputMode(_:animated:)`
- `addImageAttachment(image:fileName:)` and `removeAttachment(...)` paths
- `updateSelectedModel(_:)`
- `updateSelectedReasoningMode(_:)`
- `selectTool(_:)`, `clearSelectedTool()`

For example, in `setText(_:)`:
```swift
    func setText(_ text: String) {
        currentText = text
        // existing body...
        persistCurrentStateToStore()
    }
```

Apply analogous one-liner additions to the other five sites.

- [ ] **Step 4: Run tests**

⌘U. Expected: 4/4 PASS.

- [ ] **Step 5: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputCoordinator.swift \
        iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedToggleInputCoordinatorTests.swift
git commit -m "Propagate user mutations to UnifiedInputStateStore"
```

---

## Task 10: Wire the store into MainViewController

The store is constructed once during input setup, observes the live `TabsModel`, and is injected into the coordinator. The active tab uid is passed through `refreshUnifiedToggleInput(for:)`.

**Files:**
- Modify: `iOS/DuckDuckGo/UnifiedToggleInput/MainViewController+UnifiedToggleInput.swift`

- [ ] **Step 1: Locate `setUpUnifiedToggleInputIfNeeded` and edit**

In `MainViewController+UnifiedToggleInput.swift`, find the function (around line 30):

```swift
    func setUpUnifiedToggleInputIfNeeded() {
        guard unifiedToggleInputFeature.isAvailable else { return }

        let stateStore = UnifiedInputStateStore(
            preferences: aiChatPreferences,
            toggleModeStorage: toggleModeStorage
        )
        stateStore.observeTabsModel(tabManager.model)
        self.unifiedInputStateStore = stateStore

        let coordinator = UnifiedToggleInputCoordinator(
            isToggleEnabled: aiChatSettings.isAIChatSearchInputUserSettingsEnabled,
            isFireTab: isCurrentTabFireTab(),
            duckAiNativeStorageHandler: duckAiNativeStorageHandler,
            preferences: aiChatPreferences,
            toggleModeStorage: toggleModeStorage,
            stateStore: stateStore
        )
        // ... rest of the body unchanged
```

You'll need an `@objc dynamic` or stored property for the store on `MainViewController`; add it with the other unified input properties.

(`tabManager.model` and `aiChatPreferences` should already be on `MainViewController`. If `aiChatPreferences` doesn't exist as a single instance shared with the coordinator, follow the comment in `AIChatPreferencesPersistor.swift` — share one instance so publishers fire across components. Construct it in `MainViewController` if needed, or reuse the existing source.)

- [ ] **Step 2: Pass active tab uid through refresh**

Find `refreshUnifiedToggleInput(for: tab)` and add at the top:

```swift
    func refreshUnifiedToggleInput(for tab: TabViewController) {
        guard unifiedToggleInputFeature.isAvailable,
              let coordinator = unifiedToggleInputCoordinator else {
            return
        }

        coordinator.activateForTab(tab.tabModel.uid)

        // ... rest unchanged
```

(If `TabViewController` doesn't directly expose `Tab` as `tabModel`, find the existing accessor — search the file for `.uid` to see the pattern used by other code.)

- [ ] **Step 3: Build**

⌘B. Expected: Build Succeeded.

- [ ] **Step 4: Smoke test in simulator**

Run on iPhone 15 simulator. Manual checks:
1. Open two tabs. Type "hello" in tab 1, switch to tab 2 — input is empty. Switch back to tab 1 — "hello" is restored.
2. Flip the toggle to Duck.ai in tab 1, switch to tab 2 — toggle is whatever tab 2's preferred mode is; switch back — Duck.ai is restored.
3. In an AI tab, attach an image; switch tabs and back — image is still attached.
4. Pick a non-default model in tab 1; switch tabs and back — same model is selected.

- [ ] **Step 5: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/MainViewController+UnifiedToggleInput.swift \
        iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj
git commit -m "Wire UnifiedInputStateStore into MainViewController and refresh path"
```

---

## Task 11: End-to-end coordinator test (regression guard)

A higher-level test combining hydrate + flush + mutation, to catch future regressions.

**Files:**
- Modify: `iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedToggleInputCoordinatorTests.swift`

- [ ] **Step 1: Add the test**

```swift
    func test_endToEnd_twoTabSwitches_preserveIndependentState() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)

        sut.activateForTab("tab-A")
        sut.setText("from A")
        sut.updateInputMode(.aiChat, animated: false)

        sut.activateForTab("tab-B")
        sut.setText("from B")
        sut.updateInputMode(.search, animated: false)

        sut.activateForTab("tab-A")
        XCTAssertEqual(sut.currentText, "from A")
        XCTAssertEqual(sut.inputMode, .aiChat)

        sut.activateForTab("tab-B")
        XCTAssertEqual(sut.currentText, "from B")
        XCTAssertEqual(sut.inputMode, .search)
    }
```

- [ ] **Step 2: Run tests**

⌘U. Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedToggleInputCoordinatorTests.swift
git commit -m "Add end-to-end regression test for two-tab switch state preservation"
```

---

## Task 12: Final verification

- [ ] **Step 1: Run the full UnifiedToggleInput test suite**

```bash
xcodebuild test \
  -workspace iOS/DuckDuckGo.xcworkspace \
  -scheme "DuckDuckGo" \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:DuckDuckGoTests/TabInputStateTests \
  -only-testing:DuckDuckGoTests/UnifiedInputStateStoreTests \
  -only-testing:DuckDuckGoTests/UnifiedToggleInputCoordinatorTests
```

Expected: all tests PASS.

- [ ] **Step 2: Manual QA pass**

Re-run the four manual checks from Task 10, plus:
5. Burn a fire tab → app does not retain its state (entry evicted via `reconcile`).
6. Submit a prompt → text + attachments clear in that tab; toggle/model/reasoning/tool persist for the next prompt in the same tab.
7. Cold launch → all tabs restore with their `preferredTextEntryMode` toggles intact; text and attachments are empty.

- [ ] **Step 3: Push branch**

```bash
git push -u origin bunn/input/persist-cl
```

(Only if user authorized; otherwise stop and report to user.)

---

## Self-review

This plan covers every section of the spec:

- ✅ `TabInputState` shape — Task 1.
- ✅ `UnifiedInputStateStoring` protocol + `LastUsedInputDefaults` — Task 2.
- ✅ Concrete `UnifiedInputStateStore` with read-through to `ToggleModeStorage` + `AIChatPreferencesPersisting` — Tasks 3-4.
- ✅ Eager seeding via `TabsModel` observation; `tab.preferredTextEntryMode` for toggle slice — Task 5.
- ✅ Eviction on tab removal — Task 6.
- ✅ Coordinator hydrate/flush — Task 7.
- ✅ Narrowed `resetSessionState` — Task 8.
- ✅ Mutation propagation — Task 9.
- ✅ MainViewController integration — Task 10.
- ✅ Regression test + manual QA — Tasks 11-12.

Type consistency: `TabUID` is `String`. `selectedTool` is `AIChatRAGTool?` consistently. The coordinator's existing `currentText`, `inputMode`, `viewController.currentAttachments`, `modelStore.persistedModelId`, `modelStore.selectedReasoningMode`, `toolsController.selectedTool` accessors are reused unchanged.

Tools' `lastUsed` is in-memory only on the store (no canonical home), as the spec calls out. Memory-growth risk on attachments is acknowledged as a follow-up — not in scope.
