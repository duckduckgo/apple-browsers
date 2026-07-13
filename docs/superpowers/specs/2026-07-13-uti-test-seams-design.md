# UTI Test Seams — assumptions & questions

For the scoper. You know the task; below is only what's *new* — decisions I've made (assumptions)
and things I need you to confirm (questions). [Asana](https://app.asana.com/1/137249556945/project/72649045549333/task/1215631257622242) · branch `jacek/uti-test-seams`.

## Assumptions (I'll proceed with these unless you object)

- **A1.** The two named decisions (`ChromeVisibilityDecision` + `ToolbarVisibilityDecision`)
  become **one** pure `resolve(inputs) -> ChromeState` in a new `UnifiedInputChromeState.swift`,
  one dumb `apply`. Collapses the three `reconcile…` methods into one path. Still tested over
  every tab type × state.
- **A2.** Self-heal clamp (`+UnifiedToggleInput.swift:212–216`) is **kept** and pinned as an
  explicit tested field (not deleted).
- **A3.** 1B predicate = `isPerformingDismissCleanup && text.isEmpty` at
  `Coordinator.swift:1895`. This **changes behaviour**: a genuine keystroke in the cleanup
  window is now preserved instead of swallowed (this is your success criterion). Safe by
  construction — only ever preserves more.
- **A4.** Architecture A (`OmniBarEditingStateViewController`) excluded — doesn't share this
  code, and it's retiring.
- **A5.** Blocker (`jacek/refactor-uti-suggestions`) treated as moot — branch is at current
  `main`, all needed infra already present.

## Questions (need your call)

- **Q1 — the big one.** Did "chrome visibility" include the **background *coloring***
  (`applyUnifiedInputChromeBackground`, ~10 call sites)? I've scoped it **out** as a follow-up
  (it's coloring, not visibility). If you meant it in, the branch grows materially.
- **Q2.** OK to file the **single-writer toolbar refactor that deletes the clamp** as a
  separate follow-up (behaviour-changing), rather than doing it here?
- **Q3.** Estimate is inconsistent (title 5d / body ~7d / subtasks 5d) and due 2026-07-17 —
  which is real? (Planning only, doesn't affect the design.)
