# UTI Test Seams & Persistence — Design

- **Task:** iOS: UTI Test Seams & Persistence — [Asana](https://app.asana.com/1/137249556945/project/72649045549333/task/1215631257622242)
- **Branch:** `jacek/uti-test-seams` (off current `main`)
- **DRI:** Jacek · **PA:** Pete
- **Status:** design for review

---

## 1. Goal

Add **tested decision seams** for chrome/toolbar visibility and the persistence
cleanup-race predicate — the foundation that makes the rest of the UTI cleanup program
safe to execute. The work is **behaviour-preserving**: extract pure decision functions,
pin the current behaviour with tests, change nothing the user can see (with one small,
sanctioned exception in 1B — see §5).

UTI (Unified Toggle Input) is **iPhone-only**. The non-UTI path *is* the iPad experience,
not dead code — the coordinator stays optional throughout. We do **not** touch Architecture A
(`OmniBarEditingStateViewController`), which is slated for retirement and does not share this
decision code (all reconcile call sites are gated on the UTI feature/coordinator).

## 2. Why now

`MainViewController+UnifiedToggleInput.swift` (~1,420 lines) carries chrome/toolbar/keyboard
visibility logic that is effectively untested — and that is exactly where layout regressions
originate and recur (#5055, #4729, #4749, #5053). The persistence predicate is easy to break
silently: state fails to persist without warning if `isApplyingState` or
`isPerformingDismissCleanup` is set incorrectly.

## 3. Current state (grounded)

### 3.1 Chrome / toolbar visibility — imperative & scattered

Three reconcile methods each mutate one thing, herded by an umbrella:

- `reconcileToolbarVisibilityForCurrentTab()` — `MainViewController+UnifiedToggleInput.swift:190–222`
  computes `toolbar.isHidden` (two branches: AI-chrome hide vs. iPad/minimal-chrome), then
  runs a **self-heal clamp** at `:212–216`.
- `reconcileAIChatInputChromeForCurrentTab()` — `:156–161`
- `reconcileVoiceSessionChromeForCurrentTab()` — `:164–166`
- `reconcileAIChromeForCurrentTab()` — `:168–173`, which exists *only* to call the two AI
  reconciles together. Its own comment admits the smell: *"call from every refresh path so
  adding a new per-tab signal doesn't require remembering all three call sites."*

**The self-heal clamp is a symptom of multiple writers.** `toolbarBottom.constant` is written
by at least four independent sites (`MainViewController.swift:2634, 2774, 2791, 4040`).
`updateToolbarConstant(_:)` at `:4026–4046` forces the fully-offscreen value whenever
`toolbar.isHidden || isInMinimalChromeLayout`. The UTI AI-tab phase reuses `isHidden = true`
*transiently*; when it flips back to `false`, nothing recomputes the constant, so the toolbar
is unhidden but laid out offscreen. The clamp (`:212–216`) snaps it back to `0`:

```swift
if !viewCoordinator.toolbar.isHidden
    && viewCoordinator.toolbar.alpha == 1.0
    && viewCoordinator.constraints.toolbarBottom.constant != 0 {
    viewCoordinator.constraints.toolbarBottom.constant = 0
}
```

### 3.2 Persistence cleanup-race — the swallow gate

`clearText()` (`UnifiedToggleInputCoordinator.swift:1169–1183`) scrubs the *visible* text on
dismiss while keeping the per-tab draft. It sets `isPerformingDismissCleanup = true`, blanks
the field, and resets the flag on the next runloop tick via `DispatchQueue.main.async`.

The gate in `didChangeText` (`:1894–1902`) currently swallows **every** text change during
that window:

```swift
func unifiedToggleInputVC(_ vc: ..., didChangeText text: String) {
    if isPerformingDismissCleanup { return }   // <-- too broad
    currentText = text
    ...
}
```

The cleanup only ever emits `text == ""`. So a genuine (non-empty) keystroke that lands in the
window is discarded — the exact failure the task's success criteria call out.

### 3.3 The pattern to mirror (this already exists and is tested)

`MainViewController.decideRefreshAction(for:)` (`:389–428`) is a **pure static function** over a
value-only `UnifiedToggleInputRefreshActionInputs` struct, fed by a thin live→inputs mapper
`refreshAction(for:coordinator:)` (`:685–699`), and exercised by
`MainViewControllerRefreshActionTests.swift`. The folder also has standalone pure-decision
value types — `AIBoundaryNavigationDecision.swift`, `UTIAttachmentPolicy.swift`,
`ReasoningModeAccessResolver.swift`, `TabInputState.swift`. This is the established idiom; we
extend it.

## 4. Proposed architecture

### 4.1 1A — one resolve → one `ChromeState` → one apply

New standalone file `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputChromeState.swift`:

```swift
struct UnifiedInputChromeResolverInputs: Equatable {
    // value-only inputs — no live objects, so tests need zero mocks
    let tabKind: TabKind                 // .web / .newTabPage / .ai / .fire
    let isKeyboardUp: Bool
    let isVoiceSessionActive: Bool
    let isAIChatInputHiddenByFrontend: Bool   // FE `hideChatInput`
    let isFocusedOmnibarSession: Bool
    let isLargeWidth: Bool               // iPad / non-UTI branch
    let isInMinimalChromeLayout: Bool
    let isInputEditing: Bool
    // live constraint state the clamp-heal reads:
    let toolbarAlpha: CGFloat
    let toolbarBottomConstant: CGFloat
}

enum ToolbarVisibility: Equatable {
    case hidden
    case visible(healsClampConstant: Bool)
}

struct UnifiedInputChromeState: Equatable {
    let toolbar: ToolbarVisibility
    let hidesAIChatInput: Bool
    let voiceChromeActive: Bool
}

enum UnifiedInputChromeResolver {
    static func resolve(_ inputs: UnifiedInputChromeResolverInputs) -> UnifiedInputChromeState
}
```

`MainViewController` keeps a thin `chromeResolverInputs(for:)` mapper and a **dumb**
`apply(_ state: UnifiedInputChromeState)` that mutates the UI to match — no logic, nothing to
test. This collapses the three reconciles **and** the `reconcileAIChromeForCurrentTab` umbrella
into **one reconcile path**. Adding a new signal later = adding one field to `Inputs` +
`ChromeState`, not remembering a call site.

The self-heal clamp is **kept** (behaviour-preserving) but represented as the explicit
`healsClampConstant` field on `.visible`, pinned by a regression test — satisfying the
"flip one branch → exactly one test red" property.

### 4.2 1B — a pure predicate for the cleanup-race

Extract the user-input-vs-cleanup-clear distinction as a standalone pure predicate (testable
without instantiating the heavy coordinator):

```swift
/// The dismiss cleanup only ever blanks the field to empty. A non-empty change in the
/// window is genuine user input and must be kept.
func shouldIgnoreTextChange(isPerformingDismissCleanup: Bool, text: String) -> Bool {
    isPerformingDismissCleanup && text.isEmpty
}
```

Swap the gate at `UnifiedToggleInputCoordinator.swift:1895` from `if isPerformingDismissCleanup`
to this predicate. **Safe by construction:** it can only ever preserve *more* input, never
swallow more.

## 5. Behaviour change — scoped and sanctioned

Everything is behaviour-preserving **except** the 1B gate, which is a deliberate bug fix the
success criteria require: *"genuine user input arriving during dismiss cleanup is preserved,
not swallowed."* Approved by DRI. Risk is minimal (strictly preserves more) and verified on
simulator against the existing draft-preservation flows.

Note on 1B nuance: `persistDraftToStore()` / `recordUserChoiceToStore()` still guard on
`!isPerformingDismissCleanup`, so a keystroke in the window updates `currentText` (the flush
source of truth) but is not written to the store until the next change or tab-switch flush.
That still satisfies "preserved, not swallowed" and keeps the draft-preservation guards intact.
We leave those guards and the `DispatchQueue.main.async` reset untouched — in scope is the
predicate, not an async rework (the fix actually de-risks that window).

## 6. Explicitly out of scope (follow-ups)

1. **Single-writer toolbar constant → delete the clamp.** The clamp is scaffolding for
   multi-writer partial mutation. Once `apply` is the single writer of `toolbarBottom.constant`,
   the clamp (`:212–216`) and its `alpha == 1.0` guard disappear. Behaviour-changing; the seam
   built here is what makes that deletion safe. **Filed, not done.**
2. **Chrome background *coloring* consolidation.** `applyUnifiedInputChromeBackground` is called
   from ~10 sites, each picking `UnifiedInputChromeBackgroundState` imperatively; a partial
   mapper (`aiTabChromeBackgroundState(for:)`) already exists. This is *coloring*, not
   *visibility* — outside the task title — and folding all sites through the resolver is more
   invasive than a test seam warrants. **Left as follow-up;** `ChromeState` can grow a
   `background` field later without reshaping the resolver.
3. **Architecture A** (`OmniBarEditingStateViewController`) — excluded (retiring, unshared).
4. **Coordinator-owned observable chrome state (full MVVM)** — overshoots the mandate, rewrites
   the coordinator, breaks behaviour-preservation. Not pursued.

## 7. Mapping to the success criteria

| Success criterion | Where it's met |
|---|---|
| `ChromeVisibilityDecision` + `ToolbarVisibilityDecision` are pure functions tested over every tab type × state | `UnifiedInputChromeResolver.resolve` produces one `ChromeState`; its visibility fields = "ChromeVisibilityDecision", its `toolbar` field = "ToolbarVisibilityDecision". Exhaustive table tests over `TabKind` × keyboard/voice/FE-hidden. |
| Self-heal clamp has a test that fails if broken; flip one branch → exactly one test red | `healsClampConstant` is an explicit `ChromeState` field with dedicated assertions; resolver branches are independently table-tested. |
| Maestro unchanged | No user-facing behaviour change in 1A; 1B change is below Maestro's granularity. |
| User-input-vs-cleanup-clear is a tested predicate; genuine input during cleanup preserved | `shouldIgnoreTextChange` predicate + test asserting a non-empty keystroke in the window survives while the `""` cleanup is still swallowed. |
| Existing clearText/hide draft-preservation tests still pass; no behaviour change on per-tab-text / new-chat-reset on sim | Full existing suite green + simulator pass on those flows. |

## 8. Sequencing (TDD; each step independently green & shippable)

1. **Toolbar visibility + clamp regression test.** Resolver starts with just the `toolbar`
   field. Highest bug density, most self-contained. Write table tests first (red), extract
   until green, confirm the mutation property.
2. **AI-input-hidden + voice chrome** folded into the same resolver/`ChromeState`.
3. **1B** predicate + gate swap + preservation test.

New test files added to the Xcode target via `mcp__xcode__XcodeWrite` (never hand-edit
`project.pbxproj`). Build/test via Xcode MCP on the per-worktree simulator.

## 9. Testing strategy

- **Exhaustive table tests** over `TabKind` (web/NTP/AI/fire) × states (keyboard up/down,
  voice active, FE-hidden input) for `resolve`.
- **Mutation-style confidence:** the design goal is that flipping any single decision branch
  turns exactly one test red. Verified by hand-mutating each branch during review.
- **1B:** one test for the swallow (cleanup `""` ignored), one for the fix (non-empty keystroke
  in the window preserved).
- **Regression:** entire existing UTI suite (`DuckDuckGoTests/UnifiedToggleInput/…`) stays green;
  simulator check of per-tab-text and new-chat-reset flows.

## 10. Risks & verification

- **Hidden inputs to the toolbar decision.** The exact `Inputs` field set is finalized in
  step 1 by tracing every real driver of `isHidden` — no invented fields.
- **1B ordering.** The cleanup `""` may be a queued emission; the predicate + retained
  `DispatchQueue.main.async` reset preserve the current ordering assumptions.
- **Verification:** Xcode MCP unit runs per step + a simulator pass on the draft-preservation /
  new-chat-reset flows before the PR.

## 11. Resolved pre-flight questions

- **Blocker** (`jacek/refactor-uti-suggestions`): moot. This branch is at current `main`
  (0 ahead / 0 behind `origin/main`); all needed infra (`decideRefreshAction`,
  `isPerformingDismissCleanup`, `TabInputState`) is present. Proceeding on `main`.
- **Named seam types don't pre-exist:** correct — this work *creates* them, mirroring the
  existing `decideRefreshAction` idiom. "Extend existing seam" = extend the *pattern*.
- **Stale line numbers:** clamp re-located to `:212–216` (card said `:209–213`).
- **Estimate inconsistency (5 vs ~7 vs 5 days) & due date (2026-07-17):** unresolved planning
  item for DRI/PA — surfaced, not silently absorbed. Does not affect the technical design.
