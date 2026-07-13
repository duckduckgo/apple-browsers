# UTI Test Seams — assumptions & questions

For the scoper. You already know the task, so this is only the *new* stuff: the design calls
I've made (assumptions I'll run with unless you push back) and the one thing I still need you to
decide. [Asana task](https://app.asana.com/1/137249556945/project/72649045549333/task/1215631257622242) · branch `jacek/uti-test-seams`.

## Assumptions — I'll proceed with these unless you object

**A1 — Fold the two decisions into one.** The card names two seams,
`ChromeVisibilityDecision` and `ToolbarVisibilityDecision`. I want to implement them as a
*single* pure function `resolve(inputs) -> ChromeState` in a new file `UnifiedInputChromeState.swift`,
with one dumb `apply` step that renders the result. Right now the same logic is spread across
three `reconcile…` methods plus an umbrella method whose only job is to call them together;
this collapses all of that into one path. It's still tested exhaustively over every tab type ×
state, so both named decisions are fully covered — they just live in one struct instead of two.

**A2 — Delete the self-heal clamp via a single writer.** I want to go all the way here rather
than preserve the clamp. The self-heal clamp
(`MainViewController+UnifiedToggleInput.swift:212–216`) only exists because the toolbar bottom
constraint is written from several places out of order, leaving a stale off-screen value. If the
`apply` step becomes the single writer that always derives that constant from the toolbar's
hidden/visible state, the stale value can't happen and the clamp becomes dead code — so I'll
remove it. This is **behaviour-changing**, so it gets verified on the simulator, and the
success-criterion test shifts from "clamp heals a stale value" to "the single writer always
produces the correct constant" (flip one branch → exactly one test red still holds).

**A3 — Bring the chrome background *coloring* into the same seam.** Beyond visibility, the chrome
background tint is set by `applyUnifiedInputChromeBackground` from ~10 imperative call sites, each
picking the colour state by hand. I want to fold that decision into the same
`resolve(inputs) -> ChromeState` (adding a `background` field) so there's a single source of
truth for the whole chrome, and route those call sites through the one `apply`. Intended to be
behaviour-preserving for the colours themselves — the change is *where* the choice is made, not
*what* it resolves to — but because it touches many sites it gets careful before/after
verification on the simulator.

**A4 — The 1B predicate is a real (intended) behaviour change.** I'll replace the dismiss-cleanup
gate at `UnifiedToggleInputCoordinator.swift:1895` with the predicate
`isPerformingDismissCleanup && text.isEmpty`. Today the gate swallows *every* text change during
the cleanup window; with the predicate it only swallows the empty blanking that cleanup itself
causes, so a genuine keystroke landing in that window is now preserved. This is the behaviour
your success criterion asks for, and it's safe by construction — it can only ever preserve more
input, never less.

**A5 — Architecture A is excluded.** I won't cover the `OmniBarEditingStateViewController` path.
It doesn't share this visibility code (every reconcile call site is gated on the UTI
feature/coordinator), and it's on its way out, so covering it would be wasted effort.

**A6 — The blocker is moot.** The task said it was blocked on `jacek/refactor-uti-suggestions`
landing. That branch never merged, but our branch sits on current `main` and everything the work
needs is already there, so I'm treating the blocker as resolved and proceeding.

## Question — I need your call on this

**Q1 — Which estimate is real?** The numbers disagree: the title says 5 days, the body timeline
adds up to ~7, and the subtask titles total 5. Due date is 2026-07-17. This is purely a planning
question and doesn't affect the design, but note that A2 (clamp deletion) and A3 (background
consolidation) both add scope beyond a pure test-seam pass, so the higher end is more realistic.
