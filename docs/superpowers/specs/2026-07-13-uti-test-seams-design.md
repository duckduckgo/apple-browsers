# UTI Test Seams — assumptions & questions

For the scoper. You already know the task, so this is only the *new* stuff: the design calls
I've made (assumptions I'll run with unless you push back) and the few things I genuinely need
you to decide (questions). [Asana task](https://app.asana.com/1/137249556945/project/72649045549333/task/1215631257622242) · branch `jacek/uti-test-seams`.

## Assumptions — I'll proceed with these unless you object

**A1 — Fold the two decisions into one.** The card names two seams,
`ChromeVisibilityDecision` and `ToolbarVisibilityDecision`. I want to implement them as a
*single* pure function `resolve(inputs) -> ChromeState` in a new file `UnifiedInputChromeState.swift`,
with one dumb `apply` step that renders the result. Right now the same logic is spread across
three `reconcile…` methods plus an umbrella method whose only job is to call them together;
this collapses all of that into one path. It's still tested exhaustively over every tab type ×
state, so both named decisions are fully covered — they just live in one struct instead of two.

**A2 — Keep the self-heal clamp, don't delete it.** The toolbar self-heal clamp
(`MainViewController+UnifiedToggleInput.swift:212–216`) stays as-is. I'll represent it as an
explicit, separately-tested field on the decision so a regression there fails loudly, rather
than removing or reworking it in this branch.

**A3 — The 1B predicate is a real (intended) behaviour change.** I'll replace the dismiss-cleanup
gate at `UnifiedToggleInputCoordinator.swift:1895` with the predicate
`isPerformingDismissCleanup && text.isEmpty`. Today the gate swallows *every* text change during
the cleanup window; with the predicate it only swallows the empty blanking that cleanup itself
causes, so a genuine keystroke landing in that window is now preserved. This is the behaviour
your success criterion asks for, and it's safe by construction — it can only ever preserve more
input, never less.

**A4 — Architecture A is excluded.** I won't cover the `OmniBarEditingStateViewController` path.
It doesn't share this visibility code (every reconcile call site is gated on the UTI
feature/coordinator), and it's on its way out, so covering it would be wasted effort.

**A5 — The blocker is moot.** The task said it was blocked on `jacek/refactor-uti-suggestions`
landing. That branch never merged, but our branch sits on current `main` and everything the work
needs is already there, so I'm treating the blocker as resolved and proceeding.

## Questions — I need your call on these

**Q1 — Does "chrome visibility" include the background *coloring*?** There's a separate concern,
`applyUnifiedInputChromeBackground`, that sets the chrome's background tint from ~10 call sites.
I've read it as *coloring*, not *visibility*, and scoped it **out** as a follow-up. If you
actually intended that consolidation to be part of this task, say so — it grows the branch
materially. This is the one answer most likely to change the plan.

**Q2 — Can the clamp deletion be a separate follow-up?** The clean end-state is to funnel the
toolbar constraint through a single writer, which makes the self-heal clamp unnecessary and lets
us delete it entirely. That's behaviour-changing, so I've deferred it and kept the clamp here
(see A2). I want to confirm you're happy filing that deletion as its own follow-up rather than
doing it in this branch.

**Q3 — Which estimate is real?** The numbers disagree: the title says 5 days, the body timeline
adds up to ~7, and the subtask titles total 5. Due date is 2026-07-17. Purely a planning
question — it doesn't affect the design — but I'd rather pin it than guess.
