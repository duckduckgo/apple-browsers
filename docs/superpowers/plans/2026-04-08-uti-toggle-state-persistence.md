# UTI Toggle State Persistence — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move toggle state commit/revert logic from MainViewController into the UTI coordinator, so the coordinator owns the committed-vs-uncommitted distinction and persistence, following the existing UTI architecture patterns.

**Architecture:** The coordinator gains a `ToggleModeStoring` dependency and a new `committedInputMode` property. On submission it saves to storage; on dismiss it reverts to `committedInputMode`. MainVC still writes to `tab.preferredTextEntryMode` via the existing delegate but no longer orchestrates the storage or revert logic. A new `UnifiedToggleInputDelegate` method notifies MainVC of commits so it can update the tab.

**Tech Stack:** Swift, XCTest, Combine

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputCoordinator.swift` | Modify | Add `toggleModeStorage`, `committedInputMode`; commit on submit; revert on dismiss |
| `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputDelegate.swift` | Modify | Add `unifiedToggleInputDidCommitMode(_ mode:)` |
| `iOS/DuckDuckGo/UnifiedToggleInput/MainViewController+UnifiedToggleInput.swift` | Modify | Implement new delegate method; remove manual commit calls |
| `iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedToggleInputCoordinatorTests.swift` | Modify | Add toggle state persistence tests |

---

### Task 1: Add toggle state persistence tests to the coordinator

**Files:**
- Modify: `iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedToggleInputCoordinatorTests.swift`

These tests define the desired behavior. They will fail until Task 2 is complete.

- [ ] **Step 1: Add `MockToggleModeStorage` and update `setUp` to inject it**

In the test file, add the mock class near the other mocks at the bottom:

```swift
private final class MockToggleModeStorage: ToggleModeStoring {
    private var storedMode: TextEntryMode?
    func save(_ mode: TextEntryMode) { storedMode = mode }
    func restore() -> TextEntryMode? { storedMode }
}
```

Add the property to the test class:

```swift
private var mockToggleModeStorage: MockToggleModeStorage!
```

Update `setUp` to create and inject it:

```swift
mockToggleModeStorage = MockToggleModeStorage()
sut = UnifiedToggleInputCoordinator(
    isToggleEnabled: true,
    preferences: mockPreferences,
    toggleModeStorage: mockToggleModeStorage
)
```

Update `tearDown` to nil it:

```swift
mockToggleModeStorage = nil
```

- [ ] **Step 2: Add tests for commit on submission**

Add a new `// MARK: - Toggle State Persistence` section:

```swift
// MARK: - Toggle State Persistence

func test_submitSearch_commitsInputModeToStorage() {
    sut.activateFromOmnibar(inputMode: .search)
    sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "query", mode: .search)
    XCTAssertEqual(mockToggleModeStorage.restore(), .search)
}

func test_submitAIChat_commitsInputModeToStorage() {
    sut.activateFromOmnibar(inputMode: .aiChat)
    sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "prompt", mode: .aiChat)
    XCTAssertEqual(mockToggleModeStorage.restore(), .aiChat)
}

func test_submitSearch_notifiesDelegateOfCommit() {
    sut.activateFromOmnibar(inputMode: .search)
    sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "query", mode: .search)
    XCTAssertEqual(mockDelegate.committedMode, .search)
}

func test_submitAIChat_notifiesDelegateOfCommit() {
    sut.activateFromOmnibar(inputMode: .aiChat)
    sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "prompt", mode: .aiChat)
    XCTAssertEqual(mockDelegate.committedMode, .aiChat)
}
```

Add `committedMode` to `MockUnifiedToggleInputDelegate`:

```swift
var committedMode: TextEntryMode?

func unifiedToggleInputDidCommitMode(_ mode: TextEntryMode) {
    committedMode = mode
}
```

- [ ] **Step 3: Add tests for revert on dismiss (omnibar session)**

```swift
func test_activateFromOmnibar_setsCommittedInputMode() {
    sut.activateFromOmnibar(inputMode: .aiChat)
    XCTAssertEqual(sut.committedInputMode, .aiChat)
}

func test_toggleWithoutSubmit_doesNotCommit() {
    sut.activateFromOmnibar(inputMode: .search)
    sut.updateInputMode(.aiChat, animated: false)
    XCTAssertNil(mockToggleModeStorage.restore(), "Toggling without submitting should not persist")
    XCTAssertEqual(sut.committedInputMode, .search, "Committed mode should not change on toggle")
}

func test_deactivateToOmnibar_revertsToCommittedMode() {
    sut.activateFromOmnibar(inputMode: .search)
    sut.updateInputMode(.aiChat, animated: false)
    sut.deactivateToOmnibar()
    XCTAssertEqual(sut.inputMode, .search)
}
```

- [ ] **Step 4: Add test for external submission commit**

```swift
func test_externalSubmission_commitsCurrentMode() {
    sut.activateFromOmnibar(inputMode: .aiChat)
    mockDelegate.committedMode = nil
    sut.commitCurrentToggleState()
    XCTAssertEqual(mockToggleModeStorage.restore(), .aiChat)
    XCTAssertEqual(mockDelegate.committedMode, .aiChat)
}
```

- [ ] **Step 5: Run tests to verify they fail**

Run: `mcp__xcode__RunSomeTests` with test class `UnifiedToggleInputCoordinatorTests`
Expected: Compilation errors — `toggleModeStorage` parameter doesn't exist on coordinator init yet, `committedInputMode` not found, `commitCurrentToggleState()` not found, `committedMode` not found on delegate.

- [ ] **Step 6: Commit**

```
git add iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedToggleInputCoordinatorTests.swift
git commit -m "Add failing tests for UTI toggle state persistence"
```

---

### Task 2: Add `committedInputMode` and `ToggleModeStoring` to the coordinator

**Files:**
- Modify: `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputDelegate.swift`
- Modify: `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputCoordinator.swift`

- [ ] **Step 1: Add delegate method for mode commit**

In `UnifiedToggleInputDelegate.swift`, add:

```swift
func unifiedToggleInputDidCommitMode(_ mode: TextEntryMode)
```

- [ ] **Step 2: Add `toggleModeStorage` and `committedInputMode` to the coordinator**

In `UnifiedToggleInputCoordinator.swift`, add the storage property near the other properties (around line 111-116):

```swift
private let toggleModeStorage: ToggleModeStoring
private(set) var committedInputMode: TextEntryMode = .search
```

Update the `init` to accept and store it:

```swift
init(
    isToggleEnabled: Bool,
    modelsService: AIChatModelsProviding = AIChatModelsService(),
    preferences: AIChatPreferencesPersisting = AIChatPreferencesPersistor(),
    subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager,
    toggleModeStorage: ToggleModeStoring = ToggleModeStorage()
) {
    self.isToggleEnabled = isToggleEnabled
    self.toggleModeStorage = toggleModeStorage
    // ... rest unchanged
}
```

- [ ] **Step 3: Add `commitCurrentToggleState()` method**

Add a new `// MARK: - Toggle State Persistence` section after the "External Submissions" section (around line 530):

```swift
// MARK: - Toggle State Persistence

func commitCurrentToggleState() {
    committedInputMode = inputMode
    toggleModeStorage.save(inputMode)
    delegate?.unifiedToggleInputDidCommitMode(inputMode)
}
```

- [ ] **Step 4: Set `committedInputMode` on activation**

In `activateFromOmnibar(prefilledText:inputMode:cardPosition:)`, after `self.inputMode = effectiveInputMode` (line 310), add:

```swift
self.committedInputMode = effectiveInputMode
```

In `showExpanded(prefilledText:inputMode:)`, after `self.inputMode = inputMode` (line 263), add:

```swift
self.committedInputMode = inputMode
```

In `showCollapsed()`, after `inputMode = .aiChat` (line 250), add:

```swift
self.committedInputMode = .aiChat
```

- [ ] **Step 5: Commit on submission**

In `unifiedToggleInputVC(_:didSubmitText:mode:)` (around line 866), add `commitCurrentToggleState()` as the first line of the method, before `setText("")`:

```swift
func unifiedToggleInputVC(_ vc: UnifiedToggleInputViewController, didSubmitText text: String, mode: TextEntryMode) {
    commitCurrentToggleState()
    setText("")
    // ... rest unchanged
}
```

- [ ] **Step 6: Revert on deactivation**

In `deactivateToOmnibar(resetView:)` (around line 356), add the revert after `guard isOmnibarSession else { return }`:

```swift
func deactivateToOmnibar(resetView: Bool = true) {
    guard isOmnibarSession else { return }
    inputMode = committedInputMode
    // ... rest unchanged
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `mcp__xcode__RunSomeTests` with test class `UnifiedToggleInputCoordinatorTests`
Expected: All tests pass, including the new toggle state persistence tests.

- [ ] **Step 8: Commit**

```
git add iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputCoordinator.swift
git add iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputDelegate.swift
git commit -m "Move toggle state persistence into UTI coordinator"
```

---

### Task 3: Update MainViewController to use coordinator-driven persistence

**Files:**
- Modify: `iOS/DuckDuckGo/UnifiedToggleInput/MainViewController+UnifiedToggleInput.swift`

- [ ] **Step 1: Implement the new delegate method**

In the `UnifiedToggleInputDelegate` extension (around line 523), add:

```swift
func unifiedToggleInputDidCommitMode(_ mode: TextEntryMode) {
    tabManager.currentTabsModel.currentTab?.preferredTextEntryMode = mode
}
```

- [ ] **Step 2: Remove manual commit calls from submission delegates**

Remove the `commitUnifiedToggleStateToCurrentTab()` calls from `unifiedToggleInputDidSubmitPrompt` and `unifiedToggleInputDidSubmitQuery`:

```swift
func unifiedToggleInputDidSubmitPrompt(_ prompt: String, modelId: String?, images: [AIChatNativePrompt.NativePromptImage]?) {
    openAIChat(prompt, autoSend: true, modelId: modelId, images: images)
}

func unifiedToggleInputDidSubmitQuery(_ query: String) {
    handleUnifiedToggleInputSearchSubmission(query)
}
```

- [ ] **Step 3: Remove manual commit calls from content container delegates**

In `unifiedInputEditingStateDidSubmitQuery` and `unifiedInputEditingStateDidSubmitPrompt`, remove the `commitUnifiedToggleStateToCurrentTab()` calls:

```swift
func unifiedInputEditingStateDidSubmitQuery(_ query: String) {
    unifiedToggleInputCoordinator?.clearText()
    unifiedToggleInputCoordinator?.handleExternalSubmission(.query)
    handleUnifiedToggleInputSearchSubmission(query)
}

func unifiedInputEditingStateDidSubmitPrompt(_ query: String, tools: [AIChatRAGTool]?) {
    unifiedToggleInputCoordinator?.clearText()
    unifiedToggleInputCoordinator?.handleExternalSubmission(.prompt)
    openAIChat(query, autoSend: true, tools: tools)
}
```

- [ ] **Step 4: Commit on external submissions in the coordinator**

The external submission path (`handleExternalSubmission`) is called from the content container for suggestion/chat-history taps. These previously had `commitUnifiedToggleStateToCurrentTab()` calls in MainVC. Move the commit into the coordinator.

In `UnifiedToggleInputCoordinator.swift`, update `handleExternalSubmission(_:)` (around line 518):

```swift
func handleExternalSubmission(_ type: ExternalSubmissionType) {
    commitCurrentToggleState()
    switch displayState {
    // ... rest unchanged
    }
}
```

- [ ] **Step 6: Remove the revert logic from the dismiss closure**

In `installUnifiedInputContentViewController()` (around line 320-326), remove the manual revert:

```swift
contentVC.onDismissRequested = { [weak self] in
    guard let self, let coordinator = self.unifiedToggleInputCoordinator else { return }
    if coordinator.isOmnibarSession {
        self.dismissUnifiedToggleInputToOmnibar(coordinator: coordinator)
    } else if coordinator.isAITabExpanded {
        coordinator.showCollapsed()
    }
}
```

The revert now happens inside `deactivateToOmnibar()` in the coordinator (Task 2 Step 6).

- [ ] **Step 7: Remove the `commitUnifiedToggleStateToCurrentTab` method**

Delete the private extension method (around lines 610-613):

```swift
// DELETE:
// func commitUnifiedToggleStateToCurrentTab() {
//     guard let mode = unifiedToggleInputCoordinator?.inputMode else { return }
//     commitToggleMode(mode)
// }
```

- [ ] **Step 8: Run all tests**

Run: `mcp__xcode__RunSomeTests` with test class `UnifiedToggleInputCoordinatorTests`
Expected: All tests pass.

- [ ] **Step 9: Commit**

```
git add iOS/DuckDuckGo/UnifiedToggleInput/MainViewController+UnifiedToggleInput.swift
git add iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputCoordinator.swift
git commit -m "Wire MainVC to coordinator-driven toggle persistence"
```

---

### Task 4: Pass `toggleModeStorage` from MainViewController to coordinator

**Files:**
- Modify: `iOS/DuckDuckGo/UnifiedToggleInput/MainViewController+UnifiedToggleInput.swift`

- [ ] **Step 1: Pass the existing storage to coordinator init**

In `setUpUnifiedToggleInputIfNeeded()` (around line 36), update the coordinator creation:

```swift
let coordinator = UnifiedToggleInputCoordinator(
    isToggleEnabled: aiChatSettings.isAIChatSearchInputUserSettingsEnabled,
    toggleModeStorage: toggleModeStorage
)
```

This reuses the same `ToggleModeStoring` instance that `MainViewController` and `TabManager` already share, ensuring consistency.

- [ ] **Step 2: Build the project**

Run: `mcp__xcode__BuildProject`
Expected: Build succeeds with no errors.

- [ ] **Step 3: Run full test suite for UTI and toggle mode tests**

Run: `mcp__xcode__RunSomeTests` with test classes `UnifiedToggleInputCoordinatorTests` and `DefaultTogglePositionTests`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```
git add iOS/DuckDuckGo/UnifiedToggleInput/MainViewController+UnifiedToggleInput.swift
git commit -m "Inject shared toggleModeStorage into UTI coordinator"
```
