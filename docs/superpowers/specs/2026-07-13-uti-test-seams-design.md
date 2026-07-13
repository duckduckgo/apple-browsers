# UTI Test Seams & Persistence — Design

[Asana task](https://app.asana.com/1/137249556945/project/72649045549333/task/1215631257622242) · branch `jacek/uti-test-seams` (off current `main`) · DRI Jacek · PA Pete

**Goal:** extract pure, tested decision functions for (1A) chrome/toolbar visibility and
(1B) the persistence cleanup-race. Behaviour-preserving except one sanctioned 1B fix (§4).
iPhone-only; iPad/non-UTI path stays intact; Architecture A untouched.

## 1A — chrome/toolbar visibility

Today: three imperative `reconcile…` methods + an umbrella that exists only to herd them
(`MainViewController+UnifiedToggleInput.swift:156–222`). Untested; source of recurring layout
bugs (#5055, #4729, #4749, #5053).

**Plan:** one new file `UnifiedInputChromeState.swift` with a pure
`resolve(inputs) -> ChromeState` (value-only inputs, no mocks), rendered by one dumb `apply`.
Collapses the three reconciles into **one path**. Mirrors the existing tested seam
`decideRefreshAction`. `ChromeState` carries toolbar visibility (`.hidden` /
`.visible(healsClampConstant:)`), `hidesAIChatInput`, `voiceChromeActive`.

The **self-heal clamp** (`:212–216`) is kept and pinned as an explicit tested field — meets
"flip one branch → exactly one test red".

## 1B — persistence cleanup-race

Today the dismiss-cleanup gate (`UnifiedToggleInputCoordinator.swift:1895`) swallows **every**
text change in the cleanup window, so a genuine keystroke there is lost. Replace with a pure
predicate: `isPerformingDismissCleanup && text.isEmpty`. Only the empty cleanup blank is
swallowed; real input is kept. Safe by construction (only ever preserves *more*).

## Divergences from the card (please react to these)

1. **Two named decisions → one `ChromeState`.** Cleaner single source of truth; still tested
   over every tab type × state, so both named criteria are covered.
2. **One sanctioned behaviour change:** the 1B fix above (the card's own criterion). Everything
   else is behaviour-preserving; Maestro unchanged.
3. **Deferred as follow-ups:** (a) single-writer toolbar constant that would *delete* the clamp
   (behaviour-changing; the clamp is scaffolding for multiple writers); (b) chrome background
   *coloring* consolidation (~10 call sites — it's coloring, not visibility, so out of the task
   title). **← most likely thing to renegotiate if you meant coloring to be in scope.**

## Sequencing (TDD, each step shippable)

1. Toolbar visibility + clamp regression test. 2. Fold in AI-input-hidden + voice.
3. 1B predicate + preservation test.

## Notes

- Blocker (`jacek/refactor-uti-suggestions`) is moot: branch is at current `main`; all needed
  infra already present.
- Named seam types don't pre-exist — this *creates* them (extends the *pattern*).
- **Open planning item for you + Pete:** estimate is inconsistent (title 5d / body ~7d /
  subtasks 5d) and due 2026-07-17 — flagging, doesn't affect the design.
