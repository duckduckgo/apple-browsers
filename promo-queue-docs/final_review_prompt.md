# Prompt: final Promo Queue stack review and executive HTML appendix

```text
Perform a final, independent review of the completed iOS Promo Queue stack in:

/Users/bkunat/Desktop/ddg-workspace/apple-browsers2

The three stacked production branches are:

1. bartosz/promo-q-simp-2
2. bartosz/promo-q-simp-3
3. bartosz/promo-q-simp-4

Project documentation exists only on bartosz/promo-q-simp-master:

- promo-queue-docs/implementation_plan.md
- promo-queue-docs/tech_design_final.md
- promo-queue-docs/new_direction_proposal.md
- promo-queue-docs/local_pr_handoff.md
- project_log.md
- project_lessons/

The production branches must remain free of project documentation. Your goals are to decide whether the stack is ready to merge, determine how faithfully it implements the simplified proposal, identify correctness/maintainability/testing/feature-gating regressions, and create an evidence-backed executive HTML appendix for reviewers.

Use [$xcodebuildmcp-cli](/Users/bkunat/.codex/skills/xcodebuildmcp-cli/SKILL.md) for all Apple builds, tests, simulator work, or runtime validation. Use [$keep-project-log](/Users/bkunat/.codex/skills/keep-project-log/SKILL.md) for project memory and the final documentation handoff. You have explicit permission to run tests and builds, use simulators, create isolated temporary worktrees or local review branches when useful, commit documentation on bartosz/promo-q-simp-master, and spawn subagents. Do not use raw xcodebuild, xcrun, or simctl.

Safety and scope

- Treat all three production branches as read-only review targets.
- Do not edit their code, rewrite commits, rebase, merge, push, or change their pull-request metadata.
- Do not open additional pull requests.
- Preserve pre-existing local changes. Never reset, clean, overwrite, or silently stash another agent's work.
- You may fetch remote state read-only and inspect open PR metadata to verify heads and bases. Do not mutate GitHub state.
- Keep generated build artifacts, including any root/iOS Makefile produced by tooling, out of tracked diffs.
- Commit the final HTML report and any review-generated project documentation or durable project-memory update only on bartosz/promo-q-simp-master. Do not push that branch.
- Do not copy/cherry-pick documentation commits into bartosz/promo-q-simp-2, bartosz/promo-q-simp-3, or bartosz/promo-q-simp-4.
- Do not implement fixes during this review. Report them with evidence and a recommended resolution.

Start with a read-only preflight

1. Read AGENTS.md and only the relevant repository rules it permits.
2. Read the proposal, final tech design, implementation plan, handoff, project log, and relevant lessons from bartosz/promo-q-simp-master. Use git show or an isolated worktree so the documentation remains available while reviewing production branches. Treat earlier logs as context, not proof.
3. Inspect git status and git worktree list. Preserve concurrent work.
4. Verify local/remote branch heads, linear ancestry, and the actual bases of the three open GitHub pull requests. If GitHub is unavailable, report that limitation and verify local ancestry.
5. Confirm by tree-level checks—not only working-copy diffs—that none of the production branches contains project_log.md, project_lessons/, or promo-queue-docs/.
6. Record the actual production-only file and line counts for each layer and the combined stack.

Review these layers independently:

- PR 1: main...bartosz/promo-q-simp-2
- PR 2: bartosz/promo-q-simp-2...bartosz/promo-q-simp-3
- PR 3: bartosz/promo-q-simp-3...bartosz/promo-q-simp-4

Then review the integrated stack:

- main...bartosz/promo-q-simp-4

Use subagents to reduce context pressure. A sensible split is one subagent per PR layer while the main agent owns integrated architecture, proposal fidelity, feature-gating, test synthesis, and the final verdict. Keep simultaneous branch checkouts isolated. Wait for every subagent, inspect the evidence behind material findings yourself, deduplicate findings, and produce one coherent review. Do not stop after delegation.

Review focus

1. Proposal and design fidelity

- Score fidelity to promo-queue-docs/new_direction_proposal.md from 0–10 and explain the score.
- List every material divergence between the initial proposal, final design, and implementation.
- For each divergence state what changed, why it was introduced, which concrete iOS problem it solves, its maintenance/complexity cost, and whether it is intentional and justified, harmless, unnecessarily complex, or correctness-threatening.
- Do not penalize small iOS-specific refinements simply because they differ. Weight the proposal's core principles most heavily:
  - one app-scoped promo slot;
  - modal admission before provider evaluation and RMF admission before publication;
  - RMF ownership tied to the shared message source rather than physical views;
  - central coordination without renderer visibility, coverage, handoff, retain-count, or lifecycle callbacks;
  - background release;
  - simple checkpoint-driven progress without timers, fairness, or a retry queue; and
  - minimal integration work for future NTP/RMF surfaces.
- Check that the implementation has not recreated the broad state machine the simplified direction was intended to remove.

2. Implementation-plan compliance

- Map every phase, invariant, accepted simplification, completion criterion, and explicitly deferred item to concrete code or evidence.
- Mark each item complete, partially complete, intentionally changed, missing, or external/pending.
- Distinguish an implementation defect from stale historical wording.
- Verify that each stacked layer is independently reviewable and buildable and that its code matches its stated responsibility.

3. Correctness and code quality

Perform a normal severity-first code review. Pay particular attention to:

- lease acquisition, ownership transfer, release, weak-token recovery, and stale callback handling;
- main-actor isolation and global notification marshalling;
- cold/normal/background launch ordering, foreground/background transitions, dismissal, replacement, and same-ID reacquisition;
- first-owner-wins trigger pinning and after-idle-to-no-trigger fallback;
- unsupported or structurally unrenderable messages;
- duplicate physical mounts and once-per-ownership appearance accounting;
- modal admission before stateful provider evaluation;
- exact-root modal ownership and lazy dismissal reconciliation;
- feature-off leakage, observer changes, and shared-state mutation;
- unnecessary abstractions, parallel state, public API, or blast radius; and
- whether a future RMF surface requires only the intended shared preparation/data-source seam rather than multiple coordination callbacks.

Report evidence-backed findings only. Each finding must include severity, affected PR/branch, precise file and line, concrete failure scenario or maintenance impact, and recommended resolution. Separate merge blockers from optional simplifications.

4. Feature flag and legacy behavior

- With .promoPresentationCoordination disabled, existing legacy RMF and modal behavior must remain intact. Coordinated preparation, ownership, notifications, cooldowns, and accounting must not leak into legacy mode.
- With the flag enabled, NTP RMF and launch-promo sheets routed through PromoCoordinationService must not be admitted concurrently.
- Verify startup-latched flag composition and both startup paths.
- Check every current conditional NTP host: standard NTP, legacy/iPad suggestion tray, OmniBar editing/SuggestionTrayManager, and unified input.
- Revisit the previously fixed risk that activation-time prepareForNTP calls could rebuild legacy messages or change after-idle behavior.
- Verify PR 3 diagnostics are observational/internal except for explicit cooldown resets and do not change production admission.

5. Tests and testability

Use judgment; more tests are not automatically better.

- Identify missing high-value tests of observable behavior.
- Identify exact tests that are redundant, excessively parameterized, brittle, implementation-specific, or add little confidence. Recommend removal only when you can name the remaining coverage that protects the behavior.
- Check whether private/internal production APIs were widened solely for tests. Treat that as a code smell. Tests should primarily exercise production behavior; allow only narrow contracts required by real production callers.
- Look for timing-dependent tests, unnecessary mock state machines, duplicated assertions, and tests that merely restate implementation details.
- Do not delete or change tests during review.

Run proportionate validation through XcodeBuildMCP. At minimum when practical:

- build each stacked branch independently;
- run the relevant suites introduced or changed by each layer;
- on bartosz/promo-q-simp-4, run the combined Promo Queue suites and focused SharedState/legacy flag-off coverage; and
- expand only when a failure or code finding justifies it.

Record exact schemes, test selections, devices, branches, and results. Clearly label anything not run or not manually verified. Do not claim success solely from project-log or handoff entries.

Final written review

Return a concise but complete review with:

1. Verdict: ready, ready with non-blocking follow-ups, or changes required.
2. Actionable findings ordered by severity.
3. Proposal-fidelity score and rationale.
4. Proposal divergences table with problem solved, cost, and justification assessment.
5. Implementation-plan compliance by phase and PR.
6. Branch-by-branch review.
7. Integrated-stack and feature-gating assessment.
8. Test assessment: validation performed, missing high-value coverage, redundant/excessive candidates, and any production API exposure made for tests.
9. Documentation-branch hygiene.
10. Remaining manual-validation, rollout, and unverified risks.

If a category has no actionable finding, say so explicitly.

Executive HTML appendix

After the code review and testing are complete, create:

promo-queue-docs/final_feature_review.html

on bartosz/promo-q-simp-master. This is an executive review/technical appendix for a human reviewer, not a substitute for the severity-first findings. It must be grounded in the actual reviewed code and test evidence.

Make it a single self-contained HTML file that opens directly in a modern browser with no build step, CDN, remote font, JavaScript package, or network access. Use semantic HTML, inline CSS, and inline SVG/CSS diagrams. Make it responsive, printable, accessible, high-contrast, and easy to scan. Avoid decorative complexity that obscures the review.

Include, at minimum:

- an executive summary and readiness verdict;
- the user problem and success criterion;
- a stack map showing what each PR contributes, its parent, and production-only size;
- a high-level architecture map showing PromoCoordinationService, the arbiter/cooldown policy, modal providers/manager, HomePageConfiguration, NewTabPageMessagesModel, and current NTP hosts;
- RMF-first and modal-first interaction/sequence diagrams;
- ownership lifecycle/background teardown and cooldown behavior;
- coordinated-versus-legacy feature-flag behavior;
- how a future NTP/RMF surface integrates and what it does not need to report;
- key implementation decisions and reviewer hotspots;
- proposal fidelity score and a complete divergence table explaining why each divergence exists and which issue it solves;
- branch-by-branch change summaries;
- test strategy, tests actually run, any missing coverage, and any overtesting/removal recommendations;
- accepted limitations, manual QA still required, rollout/rollback notes, and post-rollout cleanup; and
- source references to the relevant repository files and reviewed branch ranges.

Add any other evidence or explanation that materially helps a reviewer understand the system. Clearly distinguish verified facts, reasonable inferences, accepted design trade-offs, pending manual checks, and open findings. Do not hide negative findings to make the appendix look polished.

Render and inspect the HTML locally at desktop and narrow/mobile widths. Verify that diagrams, tables, long paths, and print layout do not clip or overflow; that headings and navigation work; and that the report remains understandable without color alone. Fix visual defects before handoff. If local browser automation is unavailable, perform the strongest available static/render inspection and state the limitation.

Update project_log.md with the final verdict, test evidence, HTML path, and unresolved external work. Reconfirm that only documentation files changed on bartosz/promo-q-simp-master, run git diff --check, commit the review-generated documentation and project-memory changes locally with a focused message, and do not push.

In your final response, link the HTML file and local documentation commit, summarize the verdict and highest-severity findings, list test evidence and anything not run, and confirm that no production branch or open pull request was mutated.
```
