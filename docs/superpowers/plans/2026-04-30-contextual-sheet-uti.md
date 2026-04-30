# Contextual Chat: Native UTI Replacement — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the duck.ai frontend-rendered composer at the bottom of `AIChatContextualWebViewController` with the native Unified Toggle Input (UTI), gated by the existing `unifiedToggleInput` feature flag, and add a page-context attach chip to the UTI for parity with the FE composer's "Attach page content" affordance.

**Architecture:** Generalize the UTI's host context (introducing `UnifiedToggleInputHost` with `.omnibar` / `.contextualChat(...)` cases) so the existing UTI view + view controller can be embedded inside the contextual chat instead of being fused to `MainViewController`. Tell the duck.ai FE to skip rendering its composer via a new `nativeInput=1` URL query param. Wire a new page-context chip into the UTI view between the text-entry surface and the image-attachments strip; chip visibility is driven by a small state machine comparing the originating tab's URL to the most-recently-attached page URL.

**Tech Stack:** Swift / UIKit / Combine. iOS app target (`iOS/DuckDuckGo/`) and `AIChat` shared package (`SharedPackages/AIChat/`). No SwiftUI in the new code (UTI is pure UIKit). Tests use XCTest. Logging via `os.Logger`.

**Spec:** `docs/superpowers/specs/2026-04-30-contextual-sheet-uti-design.md`

---

## File Structure

### New files

- `SharedPackages/AIChat/Tests/AIChatTests/AIChatURLParametersTests.swift` — tests for the new `nativeInput` query param helper (and existing helpers, since none exist today).
- `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputHost.swift` — host abstraction enum with `.omnibar` and `.contextualChat(...)` cases.
- `iOS/DuckDuckGo/UnifiedToggleInput/PageContextChip/UnifiedToggleInputPageContextChipViewModel.swift` — visibility state machine.
- `iOS/DuckDuckGo/UnifiedToggleInput/PageContextChip/UnifiedToggleInputPageContextChipView.swift` — pill view (UIKit).
- `iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedToggleInputPageContextChipViewModelTests.swift` — chip state machine tests.
- `iOS/DuckDuckGo/AIChat/ContextualMode/AIChatContextualUTIHost.swift` — installer that owns the UTI coordinator with `.contextualChat(...)` host and embeds it as a child VC of the contextual web VC.
- `iOS/DuckDuckGoTests/AIChat/AIChatContextualUTIHostTests.swift` — installer tests (smoke level).

### Modified files

- `SharedPackages/AIChat/Sources/AIChat/Shared/AIChatURLParameters.swift` — add `nativeInputName` and `nativeInputValue` constants + a `nativeInputURL(from:)` helper.
- `iOS/DuckDuckGo/AIChat/ContextualMode/AIChatContextualWebViewController.swift` — apply the `nativeInput=1` query param when the flag is on; conditionally install the UTI host.
- `iOS/DuckDuckGo/AIChat/ContextualMode/AIChatContextualSheetCoordinator.swift` — expose an originating-tab-URL publisher (re-using existing context publisher); wire it into the UTI host on construction; route prompt submission from UTI back into the existing prompt path.
- `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputCoordinator.swift` — accept `host: UnifiedToggleInputHost` at init; gate omnibar-coupled behavior on `host == .omnibar`; expose chip view-model wiring.
- `iOS/DuckDuckGo/UnifiedToggleInput/UTIRenderState.swift` — add `isToggleVisible`, `isFireVisible`, `isPageContextChipVisible`, `isSuggestionsAllowed`, `isFloatingSubmitAllowed` flags; derivation accounts for host.
- `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputView.swift` — slot the page-context chip view between the text-entry view and the attachments strip; honor the new render flags (toggle hidden, fire hidden, etc.).
- `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputToolbarView.swift` — gate fire-button visibility on a new `isFireVisible` flag.
- `iOS/DuckDuckGo/UnifiedToggleInput/MainViewController+UnifiedToggleInput.swift` — call the new init with `.omnibar` host explicitly.
- `iOS/DuckDuckGoTests/UnifiedToggleInput/UTIRenderStateTests.swift` — add cases for the new flags' derivation per host.
- `iOS/Core/Logger+ContextualUTI.swift` — new `Logger` category for this feature (or place in an existing logger-extension file if the project has one).

---

## Sequencing strategy

Implementation proceeds in six chunks of increasing complexity:

1. **A. URL param + Logger** — small, isolated, easy to verify.
2. **B. Host abstraction + render flags** — internal-only refactor; existing behavior preserved.
3. **C. Page-context chip (decoupled)** — view-model and view, no integration yet.
4. **D. Originating-tab URL stream** — expose publisher.
5. **E. Contextual host installer** — wires it all together; flag-gated installation.
6. **F. Smoke + polish** — manual run-through, log review, lint.

Each task ends with a commit. Use `Build NN — ...` reply marker after the manual smoke (per project memory).

---

# Chunk A — URL parameter + Logger

## Task 1: Add `nativeInput` URL parameter helper

**Files:**
- Modify: `SharedPackages/AIChat/Sources/AIChat/Shared/AIChatURLParameters.swift`
- Create: `SharedPackages/AIChat/Tests/AIChatTests/AIChatURLParametersTests.swift`

- [ ] **Step 1: Write failing tests**

Create `SharedPackages/AIChat/Tests/AIChatTests/AIChatURLParametersTests.swift`:

```swift
import XCTest
@testable import AIChat

final class AIChatURLParametersTests: XCTestCase {

    private let baseURL = URL(string: "https://duckduckgo.com/aichat")!

    func test_nativeInputURL_appendsParameter_whenAbsent() {
        let url = AIChatURLParameters.nativeInputURL(from: baseURL)
        XCTAssertEqual(url.absoluteString, "https://duckduckgo.com/aichat?nativeInput=1")
    }

    func test_nativeInputURL_replacesExistingParameter() {
        let withWrongValue = baseURL.appending(queryItems: [.init(name: "nativeInput", value: "0")])
        let url = AIChatURLParameters.nativeInputURL(from: withWrongValue)
        XCTAssertEqual(url.queryItems?.filter { $0.name == "nativeInput" }.count, 1)
        XCTAssertEqual(url.queryItems?.first { $0.name == "nativeInput" }?.value, "1")
    }

    func test_nativeInputURL_preservesOtherParameters() {
        let withOthers = baseURL.appending(queryItems: [
            .init(name: "placement", value: "sidebar"),
            .init(name: "q", value: "hello"),
        ])
        let url = AIChatURLParameters.nativeInputURL(from: withOthers)
        XCTAssertEqual(url.queryItems?.first { $0.name == "placement" }?.value, "sidebar")
        XCTAssertEqual(url.queryItems?.first { $0.name == "q" }?.value, "hello")
        XCTAssertEqual(url.queryItems?.first { $0.name == "nativeInput" }?.value, "1")
    }
}

private extension URL {
    func appending(queryItems items: [URLQueryItem]) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + items
        return components.url!
    }
    var queryItems: [URLQueryItem]? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run via the Xcode MCP `RunSomeTests` tool, target `AIChatTests`, test class `AIChatURLParametersTests`.
Expected: all three tests fail — symbol `nativeInputURL(from:)` not found.

- [ ] **Step 3: Add the helper**

Edit `SharedPackages/AIChat/Sources/AIChat/Shared/AIChatURLParameters.swift`:

Add after line 40 (after `sidebarOpenValue`):

```swift
    public static let nativeInputName = "nativeInput"
    public static let nativeInputEnabledValue = "1"
```

Add inside the enum, after `sidebarOpenURL(from:)` (around line 55):

```swift
    /// Appends `?nativeInput=1` to the given base URL, replacing any existing `nativeInput` value.
    public static func nativeInputURL(from baseURL: URL) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == nativeInputName }
        queryItems.append(URLQueryItem(name: nativeInputName, value: nativeInputEnabledValue))
        components.queryItems = queryItems
        return components.url ?? baseURL
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Re-run `AIChatURLParametersTests`. Expected: 3 passing.

- [ ] **Step 5: Commit**

```bash
git add SharedPackages/AIChat/Sources/AIChat/Shared/AIChatURLParameters.swift \
        SharedPackages/AIChat/Tests/AIChatTests/AIChatURLParametersTests.swift
git commit -m "Add nativeInput URL parameter for FE composer suppression"
```

---

## Task 2: Apply `nativeInput=1` in `AIChatContextualWebViewController` when flag is on

**Files:**
- Modify: `iOS/DuckDuckGo/AIChat/ContextualMode/AIChatContextualWebViewController.swift:267-273`

This is small enough that we don't write a dedicated unit test for it — the URL builder is covered in Task 1 and the conditional is one line. Manual verification in the smoke task at the end.

- [ ] **Step 1: Edit `loadAIChat()`**

Replace lines 267–273 of `AIChatContextualWebViewController.swift`:

```swift
    private func loadAIChat() {
        loadingView.startAnimating()
        var contextualURL = aiChatSettings.aiChatURL.appendingParameter(name: "placement", value: "sidebar")
        if featureFlagger.isFeatureOn(.unifiedToggleInput) {
            contextualURL = AIChatURLParameters.nativeInputURL(from: contextualURL)
            Logger.contextualUTI.info("loadAIChat - nativeInput=1 applied (flag on)")
        }
        Logger.aiChat.debug("[ContextualWebVC] loadAIChat - loading URL: \(contextualURL.absoluteString)")
        let request = URLRequest(url: contextualURL)
        webView.load(request)
    }
```

(Note: `Logger.contextualUTI` doesn't exist yet — Task 3 adds it. Build will fail; Task 3 fixes it.)

- [ ] **Step 2: Defer build verification to Task 3**

Continue to Task 3.

---

## Task 3: Add `Logger.contextualUTI` category

**Files:**
- Create: `iOS/DuckDuckGo/AIChat/ContextualMode/Logger+ContextualUTI.swift`

- [ ] **Step 1: Create the logger extension**

```swift
//
//  Logger+ContextualUTI.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  ...
//

import Foundation
import os.log

extension Logger {
    static let contextualUTI = Logger(subsystem: "com.duckduckgo.mobile.ios", category: "ContextualUTI")
}
```

- [ ] **Step 2: Add to Xcode project via MCP**

Use `mcp__xcode__XcodeWrite` with:
- path: `DuckDuckGo/AIChat/ContextualMode/Logger+ContextualUTI.swift` (Xcode project-relative)
- contents: as above

(Per project memory: never hand-edit `project.pbxproj`.)

- [ ] **Step 3: Build to verify Task 2 + 3 compile together**

Use `mcp__xcode__BuildProject`. Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add iOS/DuckDuckGo/AIChat/ContextualMode/Logger+ContextualUTI.swift \
        iOS/DuckDuckGo/AIChat/ContextualMode/AIChatContextualWebViewController.swift \
        iOS/DuckDuckGo.xcodeproj/project.pbxproj
git commit -m "Apply nativeInput query param when unifiedToggleInput flag is on"
```

---

# Chunk B — UTI host abstraction and render flags

## Task 4: Introduce `UnifiedToggleInputHost`

**Files:**
- Create: `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputHost.swift`

This task introduces the host enum without using it yet — pure scaffolding so subsequent tasks can reference it. We keep the `.contextualChat` case parameter-less for now; Task 12 adds the dependency parameters once the chip view-model exists.

- [ ] **Step 1: Create the host file**

```swift
//
//  UnifiedToggleInputHost.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  ... (Apache 2 header, mirror UTIRenderState.swift)
//

import Foundation

/// Identifies the surface that hosts a `UnifiedToggleInputCoordinator`.
///
/// The host parameterizes which UTI elements are visible (toggle, fire, suggestions overlay,
/// floating submit, page-context chip), and which couplings are active (e.g. omnibar status
/// background animations only fire for `.omnibar`).
enum UnifiedToggleInputHost: Equatable {
    /// Hosted by `MainViewController` — the omnibar / full-tab AI chat surface.
    case omnibar
    /// Hosted by `AIChatContextualWebViewController` — the post-submit contextual chat surface.
    case contextualChat
}
```

- [ ] **Step 2: Add to Xcode project via MCP**

`mcp__xcode__XcodeWrite` with path `DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputHost.swift`.

- [ ] **Step 3: Build to verify compile**

`mcp__xcode__BuildProject`. Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputHost.swift iOS/DuckDuckGo.xcodeproj/project.pbxproj
git commit -m "Add UnifiedToggleInputHost abstraction"
```

---

## Task 5: Thread `host` through `UnifiedToggleInputCoordinator` init

**Files:**
- Modify: `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputCoordinator.swift:208-252`
- Modify: `iOS/DuckDuckGo/UnifiedToggleInput/MainViewController+UnifiedToggleInput.swift` (call site)
- Modify: any other call site found via search

- [ ] **Step 1: Find all call sites**

```bash
grep -rn "UnifiedToggleInputCoordinator(" --include="*.swift" iOS/DuckDuckGo iOS/DuckDuckGoTests
```

Expected results: one production call site in `MainViewController+UnifiedToggleInput.swift` (or sibling) and tests in `UnifiedToggleInputCoordinatorTests.swift` / `UnifiedToggleInputCoordinatorAttachmentLimitsTests.swift`.

- [ ] **Step 2: Add `host` to init**

Edit `UnifiedToggleInputCoordinator.swift` lines 208–215, adding `host` as the first parameter:

```swift
    let host: UnifiedToggleInputHost

    init(
        host: UnifiedToggleInputHost,
        isToggleEnabled: Bool,
        isFireTab: Bool = false,
        duckAiNativeStorageHandler: DuckAiNativeStorageHandling? = nil,
        modelsService: AIChatModelsProviding = AIChatModelsService(),
        preferences: AIChatPreferencesPersisting = AIChatPreferencesPersistor(),
        subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager,
        toggleModeStorage: ToggleModeStoring = ToggleModeStorage()
    ) {
        self.host = host
        self.isToggleEnabled = isToggleEnabled
        // ... rest unchanged
```

- [ ] **Step 3: Update production call site**

In `MainViewController+UnifiedToggleInput.swift`, find the `UnifiedToggleInputCoordinator(...)` call and add `host: .omnibar` as the first argument.

- [ ] **Step 4: Update test call sites**

In every `UnifiedToggleInputCoordinator(...)` invocation in `iOS/DuckDuckGoTests/UnifiedToggleInput/*.swift`, add `host: .omnibar` as the first argument. (Existing tests assert omnibar-host behavior implicitly.)

- [ ] **Step 5: Build + run all UnifiedToggleInput tests**

Build via MCP. Run `UnifiedToggleInputCoordinatorTests`, `UnifiedToggleInputCoordinatorAttachmentLimitsTests`, `UnifiedToggleInputHandlerTests`, `UTIRenderStateTests`, `UTIAttachmentPolicyTests`, `UnifiedInputContentContainerViewControllerTests`, `UnifiedToggleInputModelMenuTests`, `UnifiedToggleInputReasoningTests`, `UnifiedToggleInputFeatureTests`. Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput iOS/DuckDuckGoTests/UnifiedToggleInput
git commit -m "Thread UnifiedToggleInputHost through coordinator init"
```

---

## Task 6: Extend `UTIRenderState` with host-driven visibility flags

**Files:**
- Modify: `iOS/DuckDuckGo/UnifiedToggleInput/UTIRenderState.swift`
- Modify: `iOS/DuckDuckGoTests/UnifiedToggleInput/UTIRenderStateTests.swift`

- [ ] **Step 1: Add new flags to `UTIRenderState`**

Edit `UTIRenderState.swift` adding the following stored properties after `inputMode` (line 33):

```swift
    /// Whether the Search/Duck.ai toggle row at the top of the card is visible.
    var isToggleVisible: Bool
    /// Whether the fire button on the toolbar is visible.
    var isFireVisible: Bool
    /// Whether the suggestions / history overlay below the input is allowed to render.
    var isSuggestionsAllowed: Bool
    /// Whether the floating submit (anchored to keyboard layout guide) is allowed.
    var isFloatingSubmitAllowed: Bool
    /// Whether the page-context chip row is rendered. Visibility within is governed by the chip view-model.
    var isPageContextChipVisible: Bool
```

Also update `viewConfig` if any of these flags need to thread into `UTIViewConfig` (toggle visibility almost certainly does) — see existing `UTIViewConfig` for the pattern.

- [ ] **Step 2: Write failing tests**

Append to `UTIRenderStateTests.swift`:

```swift
    func test_omnibarHost_renderState_hasToggleAndFireVisible_chipHidden() {
        let state = makeRenderState(host: .omnibar)
        XCTAssertTrue(state.isToggleVisible)
        XCTAssertTrue(state.isFireVisible)
        XCTAssertTrue(state.isSuggestionsAllowed)
        XCTAssertTrue(state.isFloatingSubmitAllowed)
        XCTAssertFalse(state.isPageContextChipVisible)
    }

    func test_contextualChatHost_renderState_hidesToggleFireSuggestionsFloatingSubmit_showsChip() {
        let state = makeRenderState(host: .contextualChat)
        XCTAssertFalse(state.isToggleVisible)
        XCTAssertFalse(state.isFireVisible)
        XCTAssertFalse(state.isSuggestionsAllowed)
        XCTAssertFalse(state.isFloatingSubmitAllowed)
        XCTAssertTrue(state.isPageContextChipVisible)
    }
```

Add a `makeRenderState(host:)` helper at the bottom of the test class that constructs a `UTIRenderState` representative of an "expanded, active" state for the given host (mirror existing helpers in the file).

- [ ] **Step 3: Run tests — they will fail until Task 7 wires the host into the derivation**

Expected: tests fail (either compile error or wrong default values).

- [ ] **Step 4: Commit (failing — to be fixed in Task 7)**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/UTIRenderState.swift \
        iOS/DuckDuckGoTests/UnifiedToggleInput/UTIRenderStateTests.swift
git commit -m "Add host-driven render flags to UTIRenderState (tests pending wire-up)"
```

---

## Task 7: Wire host into `computeRenderState()` to set the new flags correctly

**Files:**
- Modify: `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputCoordinator.swift` (around line 726-763 per prior mapping — `computeRenderState()` / `UTIRenderState` construction sites)

- [ ] **Step 1: Locate `computeRenderState()`**

```bash
grep -n "computeRenderState\|UTIRenderState(" iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputCoordinator.swift
```

- [ ] **Step 2: Update construction sites**

For every `UTIRenderState(...)` call in the coordinator, add the new fields. Derive from the host:

```swift
        UTIRenderState(
            // ...existing fields...
            inputMode: inputMode,
            isToggleVisible: host == .omnibar,
            isFireVisible: host == .omnibar,
            isSuggestionsAllowed: host == .omnibar,
            isFloatingSubmitAllowed: host == .omnibar,
            isPageContextChipVisible: host == .contextualChat
        )
```

(All five flags are currently a clean omnibar-vs-contextualChat split. If `aiTab` is treated separately from `omnibar` in the existing display state, use `host == .omnibar` since `.aiTab` is *also* the omnibar host today — both share `MainViewController`.)

- [ ] **Step 3: Run UTIRenderState tests**

Expected: pass.

- [ ] **Step 4: Run full UnifiedToggleInput test suite**

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputCoordinator.swift
git commit -m "Derive UTI render flags from host"
```

---

## Task 8: Honor `isToggleVisible` and `isFireVisible` in the view layer

**Files:**
- Modify: `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputView.swift`
- Modify: `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputToolbarView.swift`

- [ ] **Step 1: View — toggle visibility**

In `UnifiedToggleInputView.apply(_ config:, animated:)` (or wherever `UTIViewConfig` is consumed for visual changes), branch on `config.isToggleVisible` (you'll need to thread that flag through `UTIViewConfig` from Task 6). Set `toggleView.isHidden = !config.isToggleVisible` and adjust the leading constraint of the text-entry view to account for the absent toggle row.

- [ ] **Step 2: Toolbar — fire visibility**

Add `var isFireVisible: Bool = true` to `UnifiedToggleInputToolbarView`, and in its layout method hide/show the fire button accordingly. Expose via the view controller so the coordinator can flip it from `UTIRenderState.isFireVisible`.

- [ ] **Step 3: Always-expanded enforcement for `.contextualChat` host**

In the coordinator, when `host == .contextualChat`, set `displayState = .aiTab(.expanded)` at construction and **never** transition to `.collapsed` from internal triggers. The cleanest expression is to gate `showCollapsed()` with an early return when `host == .contextualChat`.

- [ ] **Step 4: Suggestions overlay suppression**

In wherever the coordinator decides whether to install / present `contentViewController` (the suggestions overlay), branch on `host == .omnibar`. For `.contextualChat`, the overlay is never shown.

- [ ] **Step 5: Floating submit suppression**

Likewise, only install/present `floatingSubmitViewController` when `host == .omnibar`.

- [ ] **Step 6: Build + run UnifiedToggleInput tests**

Expected: all pass. Existing omnibar behavior unchanged.

- [ ] **Step 7: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput
git commit -m "Honor host-driven render flags in UTI view + toolbar"
```

---

# Chunk C — Page-context chip

## Task 9: `UnifiedToggleInputPageContextChipViewModel` — visibility state machine

**Files:**
- Create: `iOS/DuckDuckGo/UnifiedToggleInput/PageContextChip/UnifiedToggleInputPageContextChipViewModel.swift`
- Create: `iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedToggleInputPageContextChipViewModelTests.swift`

The view-model exposes a `@Published var isVisible: Bool` and a `tapped()` method. It takes two upstream signals: the originating tab's URL and the most-recently-attached page URL (both as `URL?` publishers).

- [ ] **Step 1: Write failing tests**

```swift
import Combine
import XCTest
@testable import DuckDuckGo

@MainActor
final class UnifiedToggleInputPageContextChipViewModelTests: XCTestCase {

    private var originatingURL: CurrentValueSubject<URL?, Never>!
    private var attachedURL: CurrentValueSubject<URL?, Never>!
    private var sut: UnifiedToggleInputPageContextChipViewModel!
    private var attachCalls: [URL] = []

    override func setUp() async throws {
        try await super.setUp()
        originatingURL = .init(nil)
        attachedURL = .init(nil)
        attachCalls = []
        sut = UnifiedToggleInputPageContextChipViewModel(
            originatingURLPublisher: originatingURL.eraseToAnyPublisher(),
            attachedURLPublisher: attachedURL.eraseToAnyPublisher(),
            onAttach: { [weak self] url in self?.attachCalls.append(url) }
        )
    }

    func test_initial_noURLs_chipHidden() {
        XCTAssertFalse(sut.isVisible)
    }

    func test_originatingURL_set_attachedNil_showsPlaceholder() {
        let url = URL(string: "https://example.com/a")!
        originatingURL.send(url)
        XCTAssertTrue(sut.isVisible)
    }

    func test_originatingMatchesAttached_chipHidden() {
        let url = URL(string: "https://example.com/a")!
        originatingURL.send(url)
        attachedURL.send(url)
        XCTAssertFalse(sut.isVisible)
    }

    func test_originatingChangesAfterAttach_chipReappears() {
        let urlA = URL(string: "https://example.com/a")!
        let urlB = URL(string: "https://example.com/b")!
        originatingURL.send(urlA)
        attachedURL.send(urlA)
        XCTAssertFalse(sut.isVisible)
        originatingURL.send(urlB)
        XCTAssertTrue(sut.isVisible)
    }

    func test_tapped_callsOnAttach_withCurrentOriginatingURL() {
        let url = URL(string: "https://example.com/a")!
        originatingURL.send(url)
        sut.tapped()
        XCTAssertEqual(attachCalls, [url])
    }

    func test_tapped_noOriginatingURL_doesNotCallOnAttach() {
        sut.tapped()
        XCTAssertTrue(attachCalls.isEmpty)
    }
}
```

- [ ] **Step 2: Run — verify failure**

Expected: compile failure (`UnifiedToggleInputPageContextChipViewModel` not found).

- [ ] **Step 3: Implement the view-model**

Create `UnifiedToggleInputPageContextChipViewModel.swift`:

```swift
//
//  UnifiedToggleInputPageContextChipViewModel.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  ... (Apache 2 header)
//

import Combine
import Foundation
import os.log

@MainActor
final class UnifiedToggleInputPageContextChipViewModel: ObservableObject {

    @Published private(set) var isVisible: Bool = false

    private let onAttach: (URL) -> Void
    private var originatingURL: URL?
    private var attachedURL: URL?
    private var cancellables = Set<AnyCancellable>()

    init(
        originatingURLPublisher: AnyPublisher<URL?, Never>,
        attachedURLPublisher: AnyPublisher<URL?, Never>,
        onAttach: @escaping (URL) -> Void
    ) {
        self.onAttach = onAttach
        originatingURLPublisher
            .sink { [weak self] in self?.handleOriginatingURL($0) }
            .store(in: &cancellables)
        attachedURLPublisher
            .sink { [weak self] in self?.handleAttachedURL($0) }
            .store(in: &cancellables)
    }

    func tapped() {
        guard let url = originatingURL else {
            Logger.contextualUTI.debug("PageContextChip tapped but no originating URL — ignoring")
            return
        }
        Logger.contextualUTI.info("PageContextChip tapped — attaching \(url.absoluteString, privacy: .public)")
        onAttach(url)
    }

    private func handleOriginatingURL(_ url: URL?) {
        originatingURL = url
        recomputeVisibility(reason: "originatingURL changed")
    }

    private func handleAttachedURL(_ url: URL?) {
        attachedURL = url
        recomputeVisibility(reason: "attachedURL changed")
    }

    private func recomputeVisibility(reason: String) {
        let next: Bool
        if let originating = originatingURL, originating != attachedURL {
            next = true
        } else {
            next = false
        }
        if next != isVisible {
            Logger.contextualUTI.debug("PageContextChip visibility \(self.isVisible) → \(next) — \(reason, privacy: .public)")
            isVisible = next
        }
    }
}
```

- [ ] **Step 4: Add to Xcode via MCP**

`mcp__xcode__XcodeMakeDir` for `DuckDuckGo/UnifiedToggleInput/PageContextChip/`, then `XcodeWrite` the file.

- [ ] **Step 5: Run tests — pass**

Expected: 6/6 pass.

- [ ] **Step 6: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/PageContextChip iOS/DuckDuckGoTests/UnifiedToggleInput iOS/DuckDuckGo.xcodeproj/project.pbxproj
git commit -m "Add PageContextChipViewModel with visibility state machine"
```

---

## Task 10: `UnifiedToggleInputPageContextChipView` — pill view

**Files:**
- Create: `iOS/DuckDuckGo/UnifiedToggleInput/PageContextChip/UnifiedToggleInputPageContextChipView.swift`

This is a UIKit view that mirrors the styling of `AIChatContextualQuickAction` pills (icon + label, rounded). No unit tests — purely visual; will be exercised manually in the smoke step. Snapshot tests are out of scope for this task.

- [ ] **Step 1: Create the view**

```swift
//
//  UnifiedToggleInputPageContextChipView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  ... (Apache 2 header)
//

import Combine
import DesignResourcesKit
import UIKit

final class UnifiedToggleInputPageContextChipView: UIControl {

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private var cancellables = Set<AnyCancellable>()

    var onTap: (() -> Void)?

    init() {
        super.init(frame: .zero)
        setupUI()
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func bind(to viewModel: UnifiedToggleInputPageContextChipViewModel) {
        viewModel.$isVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isHidden = !$0 }
            .store(in: &cancellables)
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor(designSystemColor: .surface)
        layer.cornerRadius = 14
        layer.borderColor = UIColor(designSystemColor: .lines).cgColor
        layer.borderWidth = 1

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = DesignSystemImages.Glyphs.Size16.linkAdd  // confirm exact icon during impl; AIChatContextualQuickAction.askAboutPage's icon is the closest match
        iconView.tintColor = UIColor(designSystemColor: .icons)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = UserText.aiChatAttachPageContent  // existing string "Attach Page Content"
        titleLabel.font = .preferredFont(forTextStyle: .footnote)
        titleLabel.textColor = UIColor(designSystemColor: .textPrimary)

        addSubview(iconView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            heightAnchor.constraint(equalToConstant: 28),
        ])

        isHidden = true
    }

    @objc private func handleTap() {
        onTap?()
    }
}
```

- [ ] **Step 2: Add via MCP and build**

`mcp__xcode__XcodeWrite` for the file. `BuildProject`. Expected: pass.

- [ ] **Step 3: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/PageContextChip iOS/DuckDuckGo.xcodeproj/project.pbxproj
git commit -m "Add PageContextChipView (pill) with view-model binding"
```

---

## Task 11: Slot the chip into `UnifiedToggleInputView`

**Files:**
- Modify: `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputView.swift`

Place the chip view between the `textEntryView` and the `attachmentsStrip`. The chip is added unconditionally (zero-height when its `isHidden` is true via the binding); the host abstracts whether it's used at all.

- [ ] **Step 1: Add chip to the view's component list**

After line 257 (after `toolsToolbar`), add:

```swift
    let pageContextChip = UnifiedToggleInputPageContextChipView()
```

(Public-internal so the coordinator can `bind(to:)` from outside.)

- [ ] **Step 2: Add to view hierarchy**

In `setupUI()` (find by searching for `addSubview(textEntryView)` or similar), add the chip as a sibling subview of the existing stack, anchored:
- top: `textEntryView.bottomAnchor` + spacing
- leading/trailing: same as `textEntryView`
- bottom: chained into `attachmentsStrip.topAnchor` (which currently anchors to `textEntryView.bottomAnchor`).

This means changing the existing `attachmentsStrip` top anchor to anchor to `pageContextChip.bottomAnchor` instead. Verify by reading the exact existing constraint in `setupUI()`.

The chip starts `isHidden = true` (set in the chip view itself). When hidden, its 28pt height contributes nothing because UIStackView would collapse it — but since UTI uses raw constraints, you'll need a height constraint that we deactivate when hidden, OR wrap the chip in a small "row" container that animates height. **Simpler:** use a height-anchor constraint with priority `.defaultHigh - 1` and let `intrinsicContentSize` handle visibility (UIControl returns `.zero` when hidden).

If that doesn't compose cleanly with the surrounding layout, fall back to: bind chip's height-constraint constant from view-model's `isVisible` (28 / 0). One line of additional binding.

- [ ] **Step 3: Build and verify nothing breaks visually**

Build. Run the existing UTI snapshot/UI tests if any (search `iOS/DuckDuckGoTests` for tests that screenshot UTI). Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputView.swift
git commit -m "Slot page-context chip into UTI view between text entry and attachments strip"
```

---

# Chunk D — Originating tab URL stream

## Task 12: Expose originating-tab URL publisher from `AIChatContextualSheetCoordinator`

**Files:**
- Modify: `iOS/DuckDuckGo/AIChat/ContextualMode/AIChatContextualSheetCoordinator.swift`

The coordinator already subscribes to `pageContextHandler.contextPublisher` (line 242). The page context's `url` is the originating-tab URL we need. We re-publish it as a stripped `AnyPublisher<URL?, Never>` for the chip.

- [ ] **Step 1: Add a `CurrentValueSubject` and public publisher**

Inside `AIChatContextualSheetCoordinator`, add near line 78 (alongside other `private var ...Subject`):

```swift
    private let originatingURLSubject = CurrentValueSubject<URL?, Never>(nil)
    var originatingURLPublisher: AnyPublisher<URL?, Never> {
        originatingURLSubject.eraseToAnyPublisher()
    }
```

- [ ] **Step 2: Update the existing handler to push to the subject**

In `handleContextDataUpdate(_ context:)` (line 255), append:

```swift
    func handleContextDataUpdate(_ context: AIChatPageContext?) {
        sessionState.updateContext(context)
        originatingURLSubject.send(context?.url)  // <-- new
    }
```

(Confirm `AIChatPageContext` exposes `.url`. If not, derive it from `context?.contextData.url` or whichever property holds the source URL — read `AIChatPageContext.swift` to confirm.)

- [ ] **Step 3: Also push the initial URL on bind**

When the sheet is first presented, push the *current* originating URL even before the first `pageContextHandler.contextPublisher` event (which is `dropFirst()`-ed). Right after `startObservingContextUpdates()` runs, also do:

```swift
        originatingURLSubject.send(pageContextHandler.currentContext?.url)
```

(Confirm `pageContextHandler` exposes a `currentContext` accessor; if not, add one or capture from the buffered initial value.)

- [ ] **Step 4: Build and run existing contextual-mode tests**

Run `AIChatContextualModePixelHandlerTests`, `AIChatContextualModeFeatureTests`. Expected: pass (these don't exercise the new publisher, but should not regress).

- [ ] **Step 5: Commit**

```bash
git add iOS/DuckDuckGo/AIChat/ContextualMode/AIChatContextualSheetCoordinator.swift
git commit -m "Expose originating-tab URL publisher from contextual sheet coordinator"
```

---

# Chunk E — Contextual UTI host installer

## Task 13: Create `AIChatContextualUTIHost`

**Files:**
- Create: `iOS/DuckDuckGo/AIChat/ContextualMode/AIChatContextualUTIHost.swift`

This class owns the UTI coordinator constructed with `host: .contextualChat`, embeds the UTI view controller as a child of the contextual web VC, and wires:
- chip view-model → coordinator.viewController.unifiedToggleInputView.pageContextChip
- chip onAttach → calls `pageContextHandler.triggerContextCollection()` and then `webVC.pushPageContext(...)` once context arrives
- attachedURL publisher → derived from `sessionState.latestContext?.url` (or via a new subject in sessionState)
- coordinator's `didSubmitPrompt` → `webVC.submitPrompt(prompt, pageContext: nil)`

- [ ] **Step 1: Create the host class**

```swift
//
//  AIChatContextualUTIHost.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  ... (Apache 2 header)
//

import AIChat
import Combine
import UIKit
import os.log

/// Owns a `UnifiedToggleInputCoordinator` configured for the contextual chat surface, and
/// installs the UTI's view controller as a child of `AIChatContextualWebViewController`.
///
/// Wires the page-context chip's tap to the existing page-context plumbing
/// (`AIChatPageContextHandling.triggerContextCollection()` → `webVC.pushPageContext(...)`) and
/// routes prompt submission to `webVC.submitPrompt(...)`.
@MainActor
final class AIChatContextualUTIHost {

    private let coordinator: UnifiedToggleInputCoordinator
    private let pageContextHandler: AIChatPageContextHandling
    private weak var webVC: AIChatContextualWebViewController?
    private var cancellables = Set<AnyCancellable>()

    init(
        webVC: AIChatContextualWebViewController,
        originatingURLPublisher: AnyPublisher<URL?, Never>,
        attachedURLPublisher: AnyPublisher<URL?, Never>,
        pageContextHandler: AIChatPageContextHandling,
        isFireTab: Bool
    ) {
        self.webVC = webVC
        self.pageContextHandler = pageContextHandler
        self.coordinator = UnifiedToggleInputCoordinator(
            host: .contextualChat,
            isToggleEnabled: false,
            isFireTab: isFireTab
        )

        // Chip wiring
        let chipViewModel = UnifiedToggleInputPageContextChipViewModel(
            originatingURLPublisher: originatingURLPublisher,
            attachedURLPublisher: attachedURLPublisher,
            onAttach: { [weak self] _ in
                Logger.contextualUTI.info("UTIHost: chip onAttach — triggering context collection")
                _ = self?.pageContextHandler.triggerContextCollection()
            }
        )
        coordinator.viewController.unifiedToggleInputView.pageContextChip.bind(to: chipViewModel)
        coordinator.viewController.unifiedToggleInputView.pageContextChip.onTap = {
            chipViewModel.tapped()
        }

        // Submit wiring
        coordinator.didSubmitPrompt
            .sink { [weak self] prompt in
                Logger.contextualUTI.info("UTIHost: didSubmitPrompt — forwarding to web VC")
                self?.webVC?.submitPrompt(prompt, pageContext: nil)
            }
            .store(in: &cancellables)
    }

    func install(in webVC: AIChatContextualWebViewController) {
        webVC.addChild(coordinator.viewController)
        webVC.view.addSubview(coordinator.viewController.view)
        coordinator.viewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            coordinator.viewController.view.leadingAnchor.constraint(equalTo: webVC.view.leadingAnchor),
            coordinator.viewController.view.trailingAnchor.constraint(equalTo: webVC.view.trailingAnchor),
            coordinator.viewController.view.bottomAnchor.constraint(equalTo: webVC.view.keyboardLayoutGuide.topAnchor),
        ])
        coordinator.viewController.didMove(toParent: webVC)
        coordinator.showExpanded()  // contextualChat host stays expanded
        Logger.contextualUTI.info("UTIHost: installed at bottom of contextual web VC")
    }
}
```

- [ ] **Step 2: Note required exposures**

Two things this code reaches for that may need exposing:
- `coordinator.viewController.unifiedToggleInputView` — confirm `unifiedToggleInputView` is reachable from `UnifiedToggleInputViewController`. If not, expose it as `let unifiedToggleInputView: UnifiedToggleInputView` on the view controller.
- `pageContextChip` on the view — needs to be `internal` (not `private`).

Make those exposures in this same task.

- [ ] **Step 3: Add to Xcode via MCP**

`mcp__xcode__XcodeWrite` with path `DuckDuckGo/AIChat/ContextualMode/AIChatContextualUTIHost.swift`.

- [ ] **Step 4: Build**

Expected: pass.

- [ ] **Step 5: Smoke test (write a basic XCTest)**

Create `iOS/DuckDuckGoTests/AIChat/AIChatContextualUTIHostTests.swift` with one test that constructs the host with stub publishers and asserts it doesn't crash, the chip view-model exists, and `install(in:)` adds a child VC. Keep it minimal — exhaustive coverage isn't worth the setup ceremony for an integration class.

- [ ] **Step 6: Commit**

```bash
git add iOS/DuckDuckGo/AIChat/ContextualMode/AIChatContextualUTIHost.swift \
        iOS/DuckDuckGoTests/AIChat/AIChatContextualUTIHostTests.swift \
        iOS/DuckDuckGo/UnifiedToggleInput \
        iOS/DuckDuckGo.xcodeproj/project.pbxproj
git commit -m "Add AIChatContextualUTIHost installer"
```

---

## Task 14: Wire the host into `AIChatContextualWebViewController` behind the flag

**Files:**
- Modify: `iOS/DuckDuckGo/AIChat/ContextualMode/AIChatContextualWebViewController.swift`
- Modify: `iOS/DuckDuckGo/AIChat/ContextualMode/AIChatContextualSheetCoordinator.swift` (factory method `makeWebViewController` — pass the publishers + handler in)

- [ ] **Step 1: Extend the web VC init to accept the host injection**

Add to `AIChatContextualWebViewController`'s init (after `userAgentManager`):

```swift
    /// When provided AND the unifiedToggleInput flag is on, installs a native UTI at the bottom of this view
    /// instead of the FE-rendered composer.
    private let utiHostFactory: (() -> AIChatContextualUTIHost)?
```

Add `utiHostFactory: (() -> AIChatContextualUTIHost)? = nil` to the init parameter list. Store it.

- [ ] **Step 2: Install in `viewDidLoad`**

After `setupUI()` in `viewDidLoad`:

```swift
        if featureFlagger.isFeatureOn(.unifiedToggleInput), let factory = utiHostFactory {
            let host = factory()
            host.install(in: self)
            self.utiHost = host  // strong reference
            // also: inset web view's bottom safe-area / scroll insets so content doesn't hide under UTI
        }
```

Add storage:

```swift
    private var utiHost: AIChatContextualUTIHost?
```

- [ ] **Step 3: Update `makeWebViewController()` in the sheet coordinator**

In `AIChatContextualSheetCoordinator.swift:260`, supply the factory:

```swift
        let webVC = AIChatContextualWebViewController(
            // ...existing args...
            utiHostFactory: { [weak self] in
                guard let self = self else {
                    fatalError("Coordinator deallocated before web VC creation")
                }
                let attachedURLPublisher = self.sessionState.$latestContext  // confirm property exists, type AIChatPageContext?
                    .map { $0?.url }
                    .eraseToAnyPublisher()
                return AIChatContextualUTIHost(
                    webVC: webVC,  // <-- circular; resolve via late-bind
                    originatingURLPublisher: self.originatingURLPublisher,
                    attachedURLPublisher: attachedURLPublisher,
                    pageContextHandler: self.pageContextHandler,
                    isFireTab: self.isFireTab
                )
            }
        )
```

The `webVC` self-reference is circular. Resolve by:
- Either: split init and install — construct the host *after* the web VC, then call a setter `webVC.installUTIHost(_ host:)`.
- Or: pass the web VC into the host's `install(in:)` instead of into init (already the API), and store an installer closure on the web VC that the web VC invokes during `viewDidLoad` with `self`.

Pick the second pattern: change the web VC parameter from `utiHostFactory: (() -> AIChatContextualUTIHost)?` to `utiHostInstaller: ((AIChatContextualWebViewController) -> Void)?` and call `utiHostInstaller?(self)` after `setupUI()`.

Update `AIChatContextualUTIHost.init` to drop `webVC` (it gets it via `install(in:)` already), and update Task 13 retroactively if needed — minor adjustment, included here for clarity.

- [ ] **Step 4: Build**

Expected: pass. UTI does NOT yet appear in the contextual chat — flag must be on.

- [ ] **Step 5: Manual flag-on test (deferred to Task 15)**

Continue.

- [ ] **Step 6: Commit**

```bash
git add iOS/DuckDuckGo/AIChat/ContextualMode
git commit -m "Wire native UTI installer into contextual web VC behind unifiedToggleInput flag"
```

---

# Chunk F — Smoke + polish

## Task 15: Manual smoke test on simulator

**Files:** none (verification only)

Per project memory: build, install, stamp the simulator, and stream logs autonomously — never ask the user to drive the build. The user only does the on-device gestures.

- [ ] **Step 1: Build via Xcode MCP**

Use `mcp__xcode__BuildProject` against the worktree's tab.

- [ ] **Step 2: Locate the worktree's claimed simulator**

```bash
cat .sim-udid
```

- [ ] **Step 3: Find the worktree's `DuckDuckGo.app`**

(Use the snippet from `~/.claude/memories/apple-browsers.md` "Build, install, and stream simulator logs autonomously".)

- [ ] **Step 4: Install + relaunch**

```bash
xcrun simctl install <udid> <app-path>
xcrun simctl spawn <udid> log config --subsystem com.duckduckgo.mobile.ios --mode "level:debug, persist:debug"
xcrun simctl launch --terminate-running-process <udid> com.duckduckgo.mobile.ios
```

- [ ] **Step 5: Stamp the simulator status bar with build counter**

(Per project memory — bump `.build-counter`, set status bar `HH:MM`, mention `Build NN — ...` at the top of the next reply.)

- [ ] **Step 6: Stream logs**

```bash
xcrun simctl spawn <udid> log stream --predicate 'subsystem == "com.duckduckgo.mobile.ios" AND (category == "ContextualUTI" OR category == "AIChat")' --style compact --level debug
```

Run as background process (`run_in_background: true`); capture into a file and tail.

- [ ] **Step 7: Ask the user to walk the path**

Ask the user to:
1. Toggle `unifiedToggleInput` flag on (debug menu / feature-flag override).
2. Open a regular tab, navigate to a page (e.g. `https://en.wikipedia.org/wiki/Cat`).
3. Tap the duck.ai button → verify the half-sheet opens unchanged (this is *not* affected).
4. Tap the "Ask about page" pill so the page is attached.
5. Type a prompt and submit → verify the post-submit chat opens with the **native UTI** at the bottom (not the FE composer).
6. Verify the page-context chip is **hidden** (page already attached).
7. (Resize the chat / open the underlying tab and navigate to a different page if the UI permits) → verify the chip reappears as "Attach Page Content".
8. Tap the chip → verify it hides (page now re-attached) and the conversation reflects the new page.
9. Type and submit follow-up prompts → verify they go through.
10. Toggle flag off → verify FE composer renders and chip is absent.

- [ ] **Step 8: Sweep logs for layout warnings**

Per project memory:

```bash
grep -iE 'constraint|unsupported|layout cycle|bound preference|update multiple times' <log-file>
```

Mention any matches in the reply, even if tangential.

- [ ] **Step 9: If issues found, fix and re-iterate (loop back to relevant chunk)**

- [ ] **Step 10: Commit any final fixes**

```bash
git add <touched files>
git commit -m "<concise summary of fix>"
```

---

## Task 16: Logging review pass

- [ ] **Step 1: Skim every `Logger.contextualUTI` call**

Confirm:
- All URLs use `privacy: .public` (already user-visible).
- No prompt/page-context bodies are logged.
- Each major state transition has at least one log line.

- [ ] **Step 2: Add a `Logger.contextualUTI.info` line at presentation time of the contextual web VC** capturing the flag state ("contextual chat presenting — unifiedToggleInput=on/off"). Right after the flag check in `viewDidLoad`.

- [ ] **Step 3: Re-stream logs and validate**

Run the smoke flow again and verify logs paint the picture without ambiguity. If any transition is silent, add a log.

- [ ] **Step 4: Commit**

```bash
git add iOS/DuckDuckGo/AIChat/ContextualMode iOS/DuckDuckGo/UnifiedToggleInput
git commit -m "Tighten ContextualUTI logging coverage"
```

---

## Task 17: Final review + run full UTI test target

- [ ] **Step 1: Run all UTI tests via MCP**

`mcp__xcode__RunSomeTests` with class filter `Unified*` + `UTI*` + `AIChatContextualUTIHostTests` + `AIChatURLParametersTests`.

Expected: all pass.

- [ ] **Step 2: Run all tests in `iOS/DuckDuckGoTests/AIChat/`**

Expected: all pass.

- [ ] **Step 3: Read the diff start-to-end (`git diff main...HEAD`) and look for**

- Stale `print` statements (per project memory: only `os.Logger`).
- Commented-out code.
- TODO / FIXME comments — every one needs a justification or removal.
- Any change outside the file structure section above — should not happen; if it has, justify in the commit.

- [ ] **Step 4: Commit any cleanup**

```bash
git add <touched files>
git commit -m "Cleanup pass before review"
```

---

# Acceptance criteria

When the plan is fully executed:

1. With `unifiedToggleInput` flag **off**: the contextual chat renders the FE-rendered composer exactly as today — no UTI, no chip. All existing tests pass.
2. With `unifiedToggleInput` flag **on**: the contextual chat shows the native UTI at the bottom in place of the FE composer, with the toggle / fire / suggestions / floating-submit hidden, attachments + tools + reasoning + model + voice + submit all functional.
3. The page-context chip slot is between the text-entry and the attachments strip; it is hidden when the originating page is already attached, visible otherwise; tapping it triggers the existing context-collection + push path.
4. Log category `ContextualUTI` shows clean trace through flag detection, install, chip state transitions, attaches, and submits.
5. All new code has unit tests for the URL helper and the chip view-model. `UTIRenderState` host derivation is covered.
6. No regression in `iOS/DuckDuckGoTests/UnifiedToggleInput/*` or `iOS/DuckDuckGoTests/AIChat/*`.

---

# Open implementation questions to resolve during execution

- **`AIChatPageContext.url` accessor name** — confirm the exact property name when implementing Task 12 (read `AIChatPageContext.swift`).
- **`pageContextHandler.currentContext` accessor** — may not exist; if not, capture the initial value when the sheet is presented and seed the subject directly.
- **`UnifiedToggleInputViewController.unifiedToggleInputView` exposure** — may need to make it `internal` from `private`. Same for `pageContextChip` on the view.
- **Layout collapse when chip hidden** — the simplest approach is to bind the chip's height-anchor constant (28 / 0) from the view-model's `isVisible` publisher rather than relying on `intrinsicContentSize` of a hidden `UIControl`. Decide during Task 11.
- **Sheet ↔ keyboard** — verify that anchoring UTI to `webVC.view.keyboardLayoutGuide.topAnchor` works inside the sheet without manual keyboard observers. If not, fall back to NotificationCenter keyboard observers like `MainViewController` does.
- **First-paint flicker** — install UTI synchronously in `viewDidLoad` before the web view starts loading, so by the time the page paints there is already a UTI bar at the bottom. Already accounted for in Task 14.
