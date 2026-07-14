# UTI Test Seams & Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the UTI chrome/toolbar visibility logic into one pure, exhaustively-tested `resolve(inputs) -> ChromeState` decision (rendered by one `apply`), delete the self-heal clamp via a single constraint writer, consolidate the chrome background decision into the same seam, and make the persistence cleanup-race a tested predicate.

**Architecture:** Mirror the existing tested seam `MainViewController.decideRefreshAction(for:)` — a pure static function over a value-only `Inputs` struct fed by a thin live→inputs mapper, exercised by a plain `XCTestCase` with no view-controller instantiation. New decision types live in standalone files in `UnifiedToggleInput/`, matching `AIBoundaryNavigationDecision.swift` / `UTIAttachmentPolicy.swift`.

**Tech Stack:** Swift, UIKit, XCTest. Build/test via Xcode MCP on the per-worktree simulator (`.sim-udid`). New files added to the target via `mcp__xcode__XcodeWrite` (never hand-edit `project.pbxproj`).

## Global Constraints

- iPhone-only feature; the non-UTI path is the iPad experience — the coordinator stays optional, never force-unwrapped or deleted.
- Behaviour-preserving except two sanctioned changes: the 1B predicate (Phase 5) and the single-writer clamp deletion (Phase 4). Everything else must not change observable behaviour; Maestro unchanged.
- No use of the word "track"/"tracking" in code, names, or comments.
- `os.Logger` for any logging, never `print`.
- Self-explanatory code; comments 1–2 lines max, only for non-obvious WHY.
- Every existing UTI test must stay green; existing clearText/hide draft-preservation tests must pass unchanged.

---

## File Structure

- **Create** `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputChromeState.swift` — the pure decision: `UnifiedInputChromeResolverInputs`, `ChromeState` (+ `ToolbarVisibility`), `UnifiedInputChromeResolver.resolve`. Zero UIKit mutation.
- **Create** `iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedInputChromeResolverTests.swift` — exhaustive table tests for the resolver.
- **Modify** `iOS/DuckDuckGo/UnifiedToggleInput/MainViewController+UnifiedToggleInput.swift` — add the thin `chromeResolverInputs(for:)` mapper and `applyChromeState(_:)`; replace the bodies of `reconcileToolbarVisibilityForCurrentTab` / `reconcileAIChatInputChromeForCurrentTab` / `reconcileVoiceSessionChromeForCurrentTab` with resolve+apply.
- **Create** `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputTextChangeGate.swift` — the pure 1B predicate.
- **Create** `iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedInputTextChangeGateTests.swift` — 1B tests.
- **Modify** `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputCoordinator.swift:1895` — route the dismiss-cleanup gate through the predicate.

---

## Phase 1 — Toolbar visibility decision + clamp regression test

Extracts `reconcileToolbarVisibilityForCurrentTab` (`MainViewController+UnifiedToggleInput.swift:190–222`) into a pure decision. The self-heal clamp is **kept** here and pinned by a test; Phase 4 later deletes it via a single writer.

### Task 1: `ToolbarVisibility` + resolver skeleton with the toolbar decision

**Files:**
- Create: `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputChromeState.swift`
- Test: `iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedInputChromeResolverTests.swift`

**Interfaces:**
- Produces:
  - `struct UnifiedInputChromeResolverInputs: Equatable` with fields (this phase): `isCurrentTabUsingUnifiedInputAIChrome: Bool`, `isFocusedOmnibarSession: Bool`, `isLargeWidth: Bool`, `isInMinimalChromeLayout: Bool`, `currentToolbarIsHidden: Bool`, `toolbarAlpha: CGFloat`, `toolbarBottomConstant: CGFloat`.
  - `enum ToolbarVisibility: Equatable { case hidden; case visible(healsClampConstant: Bool) }`
  - `struct ChromeState: Equatable { let toolbar: ToolbarVisibility; let recomputesBars: Bool }`
  - `enum UnifiedInputChromeResolver { static func resolve(_ inputs: UnifiedInputChromeResolverInputs) -> ChromeState }`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import DuckDuckGo

final class UnifiedInputChromeResolverTests: XCTestCase {

    // MARK: - Toolbar hidden on AI chrome (non-omnibar)

    func test_aiChrome_notOmnibarSession_hidesToolbar() {
        let state = resolve(isCurrentTabUsingUnifiedInputAIChrome: true, isFocusedOmnibarSession: false)
        XCTAssertEqual(state.toolbar, .hidden)
    }

    func test_aiChrome_omnibarSession_keepsToolbarTabLike() {
        // Focused omnibar opened from a Duck.ai tab keeps the toolbar (standard browser controls).
        let state = resolve(isCurrentTabUsingUnifiedInputAIChrome: true, isFocusedOmnibarSession: true)
        XCTAssertEqual(state.toolbar, .visible(healsClampConstant: false))
    }

    // MARK: - Non-AI branch (iPad / minimal chrome)

    func test_nonAIChrome_largeWidth_hidesToolbar() {
        let state = resolve(isLargeWidth: true)
        XCTAssertEqual(state.toolbar, .hidden)
    }

    func test_nonAIChrome_minimalChrome_hidesToolbar() {
        let state = resolve(isInMinimalChromeLayout: true)
        XCTAssertEqual(state.toolbar, .hidden)
    }

    func test_nonAIChrome_phone_showsToolbar() {
        let state = resolve()
        XCTAssertEqual(state.toolbar, .visible(healsClampConstant: false))
    }

    // MARK: - Self-heal clamp (kept in Phase 1; Phase 4 deletes it)

    func test_visibleToolbar_staleOffscreenConstant_healsClamp() {
        let state = resolve(toolbarAlpha: 1.0, toolbarBottomConstant: 49)
        XCTAssertEqual(state.toolbar, .visible(healsClampConstant: true))
    }

    func test_visibleToolbar_partialAlpha_doesNotHeal() {
        // alpha < 1 == mid-scroll partial hide; not a stale clamp.
        let state = resolve(toolbarAlpha: 0.5, toolbarBottomConstant: 49)
        XCTAssertEqual(state.toolbar, .visible(healsClampConstant: false))
    }

    func test_visibleToolbar_constantAlreadyZero_doesNotHeal() {
        let state = resolve(toolbarAlpha: 1.0, toolbarBottomConstant: 0)
        XCTAssertEqual(state.toolbar, .visible(healsClampConstant: false))
    }

    // MARK: - Bars recompute on hidden-flip

    func test_recomputesBars_whenHiddenFlips() {
        let flips = resolve(isCurrentTabUsingUnifiedInputAIChrome: true, currentToolbarIsHidden: false)
        XCTAssertTrue(flips.recomputesBars)
        let stable = resolve(isCurrentTabUsingUnifiedInputAIChrome: true, currentToolbarIsHidden: true)
        XCTAssertFalse(stable.recomputesBars)
    }

    // MARK: - Helper

    private func resolve(
        isCurrentTabUsingUnifiedInputAIChrome: Bool = false,
        isFocusedOmnibarSession: Bool = false,
        isLargeWidth: Bool = false,
        isInMinimalChromeLayout: Bool = false,
        currentToolbarIsHidden: Bool = false,
        toolbarAlpha: CGFloat = 1.0,
        toolbarBottomConstant: CGFloat = 0
    ) -> ChromeState {
        UnifiedInputChromeResolver.resolve(.init(
            isCurrentTabUsingUnifiedInputAIChrome: isCurrentTabUsingUnifiedInputAIChrome,
            isFocusedOmnibarSession: isFocusedOmnibarSession,
            isLargeWidth: isLargeWidth,
            isInMinimalChromeLayout: isInMinimalChromeLayout,
            currentToolbarIsHidden: currentToolbarIsHidden,
            toolbarAlpha: toolbarAlpha,
            toolbarBottomConstant: toolbarBottomConstant
        ))
    }
}
```

- [ ] **Step 2: Add both files to the target and run the tests to confirm they fail**

Create `UnifiedInputChromeState.swift` empty (license header only) and the test file via `mcp__xcode__XcodeWrite`. Run `mcp__xcode__RunSomeTests` for `UnifiedInputChromeResolverTests`.
Expected: FAIL to compile — `UnifiedInputChromeResolver` / `ChromeState` unresolved.

- [ ] **Step 3: Implement the resolver (toolbar only)**

```swift
import CoreGraphics

struct UnifiedInputChromeResolverInputs: Equatable {
    let isCurrentTabUsingUnifiedInputAIChrome: Bool
    let isFocusedOmnibarSession: Bool
    let isLargeWidth: Bool
    let isInMinimalChromeLayout: Bool
    let currentToolbarIsHidden: Bool
    let toolbarAlpha: CGFloat
    let toolbarBottomConstant: CGFloat
}

enum ToolbarVisibility: Equatable {
    case hidden
    case visible(healsClampConstant: Bool)
}

struct ChromeState: Equatable {
    let toolbar: ToolbarVisibility
    let recomputesBars: Bool
}

enum UnifiedInputChromeResolver {
    static func resolve(_ inputs: UnifiedInputChromeResolverInputs) -> ChromeState {
        let toolbar = resolveToolbar(inputs)
        let willHide = (toolbar == .hidden)
        return ChromeState(toolbar: toolbar, recomputesBars: inputs.currentToolbarIsHidden != willHide)
    }

    private static func resolveToolbar(_ inputs: UnifiedInputChromeResolverInputs) -> ToolbarVisibility {
        if inputs.isCurrentTabUsingUnifiedInputAIChrome && !inputs.isFocusedOmnibarSession {
            return .hidden
        }
        if inputs.isLargeWidth || inputs.isInMinimalChromeLayout {
            return .hidden
        }
        let heals = inputs.toolbarAlpha == 1.0 && inputs.toolbarBottomConstant != 0
        return .visible(healsClampConstant: heals)
    }
}
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run: `mcp__xcode__RunSomeTests` → `UnifiedInputChromeResolverTests`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputChromeState.swift iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedInputChromeResolverTests.swift
git commit -m "Add pure toolbar visibility decision with clamp regression tests"
```

### Task 2: Wire the toolbar decision into `reconcileToolbarVisibilityForCurrentTab`

**Files:**
- Modify: `iOS/DuckDuckGo/UnifiedToggleInput/MainViewController+UnifiedToggleInput.swift:190–222`

**Interfaces:**
- Consumes: `UnifiedInputChromeResolver.resolve`, `ChromeState`, `ToolbarVisibility` from Task 1.

- [ ] **Step 1: Replace the method body with resolve+apply**

Replace `reconcileToolbarVisibilityForCurrentTab()` (currently `:190–222`) with:

```swift
func reconcileToolbarVisibilityForCurrentTab() {
    let inputs = UnifiedInputChromeResolverInputs(
        isCurrentTabUsingUnifiedInputAIChrome: isCurrentTabUsingUnifiedInputAIChrome,
        isFocusedOmnibarSession: unifiedToggleInputCoordinator?.isOmnibarSession == true,
        isLargeWidth: AppWidthObserver.shared.isLargeWidth,
        isInMinimalChromeLayout: isInMinimalChromeLayout,
        currentToolbarIsHidden: viewCoordinator.toolbar.isHidden,
        toolbarAlpha: viewCoordinator.toolbar.alpha,
        toolbarBottomConstant: viewCoordinator.constraints.toolbarBottom.constant
    )
    applyToolbarVisibility(UnifiedInputChromeResolver.resolve(inputs))
}

private func applyToolbarVisibility(_ state: ChromeState) {
    switch state.toolbar {
    case .hidden:
        viewCoordinator.toolbar.isHidden = true
    case .visible(let healsClampConstant):
        viewCoordinator.toolbar.isHidden = false
        if healsClampConstant {
            viewCoordinator.constraints.toolbarBottom.constant = 0
        }
    }
    if state.recomputesBars {
        setBarsVisibility(currentBarsVisibility, animated: false, animationDuration: nil)
    }
}
```

- [ ] **Step 2: Build and run the full UTI suite + the resolver tests**

Run: `mcp__xcode__BuildProject` then `mcp__xcode__RunSomeTests` for `DuckDuckGoTests/UnifiedToggleInput`.
Expected: PASS, no behaviour change.

- [ ] **Step 3: Mutation check** — temporarily flip one resolver branch (e.g. drop `!inputs.isFocusedOmnibarSession`), run the resolver tests, confirm **exactly one** test goes red, then revert.

- [ ] **Step 4: Commit**

```bash
git add iOS/DuckDuckGo/UnifiedToggleInput/MainViewController+UnifiedToggleInput.swift
git commit -m "Route toolbar visibility through the pure decision"
```

### Task 3: Simulator behaviour check (Phase 1 gate)

- [ ] Build + install on the worktree sim (per the multi-sim workflow), then verify by hand: (a) web tab shows toolbar, (b) Duck.ai chat tab hides it, (c) focused omnibar from a Duck.ai tab keeps it, (d) return from AI tab to web restores an on-screen toolbar (clamp path). Confirm no toolbar-offscreen glitch. No commit (verification only).

---

## Phase 2 — Fold AI-input-hidden + voice chrome into `ChromeState`

Brings `reconcileAIChatInputChromeForCurrentTab` (`:156–161`) and `reconcileVoiceSessionChromeForCurrentTab` (`:164–166`) into the same decision so the `reconcileAIChromeForCurrentTab` umbrella (`:168–173`) collapses to one resolve+apply.

### Task 4: Extend inputs/state and test the two new fields

**Files:**
- Modify: `UnifiedInputChromeState.swift`, `UnifiedInputChromeResolverTests.swift`

**Interfaces:**
- Produces: `UnifiedInputChromeResolverInputs` gains `isOnAITab: Bool`, `isAIChatInputHiddenByFrontend: Bool`, `isVoiceSessionActive: Bool`. `ChromeState` gains `hidesAIChatInput: Bool`, `voiceChromeActive: Bool`.

- [ ] **Step 1: Add failing tests** — `hidesAIChatInput` is true only when `isOnAITab && isAIChatInputHiddenByFrontend`; false on non-AI tabs regardless. `voiceChromeActive == isOnAITab && isVoiceSessionActive`.

```swift
func test_hidesAIChatInput_onlyWhenOnAITabAndFrontendHides() {
    XCTAssertTrue(resolve(isOnAITab: true, isAIChatInputHiddenByFrontend: true).hidesAIChatInput)
    XCTAssertFalse(resolve(isOnAITab: false, isAIChatInputHiddenByFrontend: true).hidesAIChatInput)
    XCTAssertFalse(resolve(isOnAITab: true, isAIChatInputHiddenByFrontend: false).hidesAIChatInput)
}

func test_voiceChromeActive_onlyOnAITab() {
    XCTAssertTrue(resolve(isOnAITab: true, isVoiceSessionActive: true).voiceChromeActive)
    XCTAssertFalse(resolve(isOnAITab: false, isVoiceSessionActive: true).voiceChromeActive)
}
```

(Add the new params to the `resolve` helper with defaults `false`.)

- [ ] **Step 2: Run → fail (compile).** **Step 3:** add the fields to the structs and compute them in `resolve` (mirroring `isAIChatInputHiddenForCurrentTab` / `isVoiceSessionActiveForCurrentTab` at `:143–153`). **Step 4:** run → pass. **Step 5:** commit `"Fold AI-input-hidden and voice chrome into the decision"`.

### Task 5: Collapse the reconcile umbrella into one apply

**Files:**
- Modify: `MainViewController+UnifiedToggleInput.swift:156–222`

- [ ] **Step 1:** Extend `applyToolbarVisibility` into `applyChromeState(_:)` that also runs `viewCoordinator.setAITabBottomChromeHidden(state.hidesAIChatInput)` (guarded by `currentTab?.isAITab == true`, matching `:159`) and `aiChatTabChatHeaderView?.setVoiceSessionActive(state.voiceChromeActive)`. Point `reconcileAIChromeForCurrentTab` and `reconcileToolbarVisibilityForCurrentTab` at one `resolve` + `applyChromeState`. Keep the three public method names (call sites at `MainViewController.swift:1315,1765,2398,2764,2773,6745` and within this file rely on them) as thin wrappers over the single apply to avoid touching every call site.
- [ ] **Step 2:** Build + full UTI suite → pass. **Step 3:** sim check (AI-input hide toggle, voice session pill). **Step 4:** commit `"Collapse chrome reconciles into one decision path"`.

---

## Phase 3 — Consolidate the chrome background decision

**Note (discovered during planning):** the background decision is entangled with `UTIRenderState.isContentVisible`, `viewCoordinator.isNavigationChromeHidden`, and the top/bottom chrome split (`aiTabChromeBackgroundState:780`, `applyTopChromeState:871`, `syncPreservedAITabPresentation:787`, plus hard-coded `.standardChrome`/`.aiTabChatChromeHidden` at ~10 sites). This is more than a mechanical sweep. Treat Phase 3 as its own detailed sub-plan authored after Phase 2 lands, when the exact call-site behaviours can be traced against a green baseline.

### Task 6: Map every `applyUnifiedInputChromeBackground` call site

- [ ] For each of the ~10 call sites, record: the enum passed, the guard around it, and the `updateWebView` flag. Produce a truth table (context → background state). No code change; commit the table into this plan.

### Task 7: Add `background` to `ChromeState` and route AI-tab sites through the resolver

- [ ] TDD: add `background: UnifiedInputChromeBackgroundState` to `ChromeState`, port the `aiTabChromeBackgroundState` rule (`isContentVisible ? .aiTabSearchChromeHidden : .aiTabChatChromeHidden`) and the `.standardChrome` cases into `resolve`, with table tests from Task 6. Wire the sites through `applyChromeState`. **Behaviour-preserving** — before/after sim colour check on: standard web chrome, Duck.ai search-chrome-hidden, Duck.ai chat-chrome-hidden (editing vs idle). Commit per site-group.

---

## Phase 4 — Single-writer toolbar constant (delete the clamp)

Behaviour-changing (sanctioned). Makes `applyChromeState` the single writer of `toolbarBottom.constant` so the stale-value case can't occur, then removes the self-heal clamp field + branch.

### Task 8: Establish the single writer

- [ ] **Step 1:** Trace the four `toolbarBottom.constant` writers (`MainViewController.swift:2634,2774,2791,4040`) and `updateToolbarConstant:4026`. Confirm which are the legitimate derivations (minimal-chrome spacer, `updateToolbarConstant` ratio path) vs. the transient AI-tab writes the clamp compensates for.
- [ ] **Step 2:** Change the apply so that whenever the toolbar becomes visible it recomputes the constant deterministically (call the existing `setBarsVisibility(currentBarsVisibility,…)` / `updateToolbarConstant` path unconditionally on the visible transition) rather than relying on `healsClampConstant`.
- [ ] **Step 3:** Replace the clamp regression test: `ToolbarVisibility.visible` drops `healsClampConstant`; add a test asserting the single writer always produces `constant == 0` for an on-screen toolbar across the transient-AI-tab sequence. Delete the `:212–216` clamp block.
- [ ] **Step 4:** Build + full UTI suite. **Step 5:** sim check the exact sequence that used to need the clamp (AI tab → web return). **Step 6:** commit `"Delete toolbar self-heal clamp via single constraint writer"`.

---

## Phase 5 — Persistence cleanup-race predicate

### Task 9: Pure predicate

**Files:**
- Create: `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputTextChangeGate.swift`
- Test: `iOS/DuckDuckGoTests/UnifiedToggleInput/UnifiedInputTextChangeGateTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import DuckDuckGo

final class UnifiedInputTextChangeGateTests: XCTestCase {
    func test_cleanupBlank_isIgnored() {
        XCTAssertTrue(shouldIgnoreTextChange(isPerformingDismissCleanup: true, text: ""))
    }
    func test_genuineInputDuringCleanup_isKept() {
        XCTAssertFalse(shouldIgnoreTextChange(isPerformingDismissCleanup: true, text: "h"))
    }
    func test_normalInput_isKept() {
        XCTAssertFalse(shouldIgnoreTextChange(isPerformingDismissCleanup: false, text: "h"))
        XCTAssertFalse(shouldIgnoreTextChange(isPerformingDismissCleanup: false, text: ""))
    }
}
```

- [ ] **Step 2:** Run → fail. **Step 3:** implement:

```swift
/// The dismiss cleanup only ever blanks the field to empty; a non-empty change in the
/// window is genuine user input and must be kept.
func shouldIgnoreTextChange(isPerformingDismissCleanup: Bool, text: String) -> Bool {
    isPerformingDismissCleanup && text.isEmpty
}
```

- [ ] **Step 4:** Run → pass. **Step 5:** commit `"Add pure dismiss-cleanup text-change predicate"`.

### Task 10: Route the coordinator gate through the predicate

**Files:**
- Modify: `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedToggleInputCoordinator.swift:1895`

- [ ] **Step 1:** Replace `if isPerformingDismissCleanup { return }` with `if shouldIgnoreTextChange(isPerformingDismissCleanup: isPerformingDismissCleanup, text: text) { return }`.
- [ ] **Step 2:** Build + full UTI suite → pass (existing draft-preservation tests confirm the `""` cleanup is still swallowed). **Step 3:** sim check: type during dismiss, confirm the keystroke survives; per-tab-text + new-chat-reset unchanged. **Step 4:** commit `"Preserve genuine user input during dismiss cleanup"`.

---

## Self-Review

- **Spec coverage:** A1 → Phases 1–2 (one resolve/apply). A2 → Phase 4. A3 → Phase 3. A4(1B) → Phase 5. A5/A6 (Arch A excluded, blocker moot) → no task needed. ✅
- **Placeholder scan:** Phases 1 and 5 are fully executable. Phases 3–4 carry an explicit *trace-then-implement* first step because their final apply body legitimately depends on the call-site trace against a green baseline — these are discovery tasks, not hidden placeholders, and each still ends in a TDD cycle + commit.
- **Type consistency:** `ChromeState`, `ToolbarVisibility`, `UnifiedInputChromeResolverInputs`, `UnifiedInputChromeResolver.resolve`, `applyChromeState`, `shouldIgnoreTextChange` used consistently across tasks.
- **Sequencing:** each phase ends green and shippable; Phase 4 depends on Phase 1's decision existing; Phase 3 is deliberately last-but-one given its entanglement.
