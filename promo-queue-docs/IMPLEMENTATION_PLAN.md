# Promo Queue iteration 1 — implementation and landing plan

## Purpose

This document records the final two-PR delivery stack and assigns each part of iteration one to its owning pull request. The consolidated architecture is in `TECH_DESIGN_FINAL.md`; the central RMF redesign is recorded in `PROMO_QUEUE_LOGICAL_RMF_OWNER_IMPLEMENTATION_PLAN.md`; the final cooldown/diagnostics slice is in `Q3_IMPLEMENTATION_PLAN.md`.

## Current status

| Slice | Branch / PR | Status | Responsibility |
| --- | --- | --- | --- |
| PR 1 | `bartosz/promo-q-1`, [#6087](https://github.com/duckduckgo/apple-browsers/pull/6087) | Merged to `main` | Disabled-by-default feature mapping, initial transactional arbiter/injection, and coordinated modal-attempt foundation |
| PR 2 | `bartosz/promo-q-2` at `9e82601a9f`, [#6194](https://github.com/duckduckgo/apple-browsers/pull/6194) → `main` | Open | Complete modal lifecycle/provider hardening, startup-latched mode, one global owner, central logical RMF session, one authorized renderer, known-host eligibility, exact OS-specific removal, and lifecycle coverage |
| PR 3 | `bartosz/promo-q-3` at `9321268231`, [#6291](https://github.com/duckduckgo/apple-browsers/pull/6291) → PR 2 | Open | Directional cooldown policy/persistence, service integration and appearance confirmation, read-only diagnostics, and focused time-limit coverage |

The active stack is `main` → `bartosz/promo-q-2` → `bartosz/promo-q-3`. The accepted fixes formerly reviewed separately are folded into PR 2; there is no third active layer between Q2 and Q3.

Temporary files under `promo-queue-docs/` and `project_log.md` must not be merged through either app PR.

## Source hierarchy

For implementation and review conflicts, use:

1. `origin/bartosz/promo-q-3` at `9321268231` for the final cumulative implementation;
2. `origin/bartosz/promo-q-2` at `9e82601a9f` for the central-owner foundation;
3. `PROMO_QUEUE_LOGICAL_RMF_OWNER_IMPLEMENTATION_PLAN.md` for the Q2 redesign decisions;
4. `Q3_IMPLEMENTATION_PLAN.md` for the final cooldown/diagnostics slice; and
5. `TECH_DESIGN_FINAL.md` for the consolidated contract.

Earlier per-model admission, gate/mount, multiple-outgoing-session, and universal animation descriptions are superseded.

## Final architecture by slice

### PR 1 — merged foundation

- Adds `.promoPresentationCoordination`, disabled by default.
- Introduces the app-scoped main-actor arbiter and dependency-injection seam.
- Establishes coordinated modal attempt identity and lease propagation.
- Leaves the flag-off path unchanged.

### PR 2 — modal lifecycle and central logical RMF owner

PR 2 owns all transient visibility safety.

Modal work includes:

- acquisition before provider evaluation;
- exact UIKit-root lifetime across scheduling and nested presentation;
- provider revalidation and explicitly safe replacement;
- foreground/readiness hardening; and
- startup-latched feature mode.

RMF work includes:

- one service-owned `idle` / `owned` / `draining` state machine;
- logical `(messageID, sessionID)` ownership, independent of renderer;
- weak renderer registrations with generation identity and stable ordering;
- one authorized physical renderer at a time;
- coalesced, non-reentrant reconciliation;
- same-message transfer under one lease;
- exact presentation/removal identity checks;
- fail-closed unexpected renderer loss or missing terminal; and
- known-host exposure as renderer eligibility.

Removal is intentionally OS-specific:

- iOS 17+ uses scale/opacity with native SwiftUI `.removed` completion;
- iOS 15/16 clears synchronously with animations disabled and therefore has no coordinated dismissal animation; and
- release or transfer follows the accepted terminal plus one main-queue settlement turn.

The central-owner redesign landed as three reviewable Q2 commits:

1. `ea66bd7bef` — centralize logical RMF ownership;
2. `ea60ee258d` — replace logical RMF lifecycle coverage; and
3. `9e82601a9f` — cover logical RMF session integration.

### PR 3 — directional cooldowns and diagnostics

PR 3 preserves the Q2 state machine and layers policy after owner acquisition.

- `02ae39b217` — add the fixed directional policy and persisted RMF history.
- `a1207bf6ef` — integrate owner-first admission and once-per-logical-session appearance confirmation.
- `a770166f88` — add the read-only Promo Queue debug projection.
- `75717015b3` — make diagnostics side-effect free.
- `9321268231` — add focused Promo Queue time-limit coverage.

The implemented matrix is:

| Confirmed source | Requested target | Minimum delay |
| --- | --- | --- |
| Modal | RMF | 10 minutes |
| RMF | RMF | 10 minutes |
| RMF | Modal | 24 hours |
| Modal | Modal | Existing remotely tunable interval, currently/default 24 hours |

Q3 confirms RMF queue history once per logical session. A same-message physical handoff is continuity of that session and does not restart the timestamp. Ordinary RMF appearance accounting remains once per accepted physical presentation.

No boundary timer is added. Candidate, renderer, lifecycle/readiness, successful-release, and removal-settlement checkpoints drive reconsideration.

## Review-efficient landing workflow

1. Review and fix the lowest owning branch. Visibility/session/removal changes belong on Q2; cooldown/history/debug changes belong on Q3.
2. Do not duplicate a Q2 fix in Q3. Restack Q3 once after the Q2 commit is final.
3. Land Q2 to `main`.
4. Rebase or retarget Q3 onto the resulting `main`, resolve conflicts once, and verify its five-commit scope remains intact.
5. Complete final cumulative review and the explicitly remaining runtime/manual validation before enabling the feature.

This keeps feedback propagation linear and avoids maintaining parallel versions of the same fix.

## Requirements retained by the redesign

- No modal and RMF are visibly presented together.
- No two physical RMF renderers are authorized together.
- A lease remains authoritative after a cooldown elapses and until exact removal.
- All four directional cooldown rows use confirmed source appearances.
- Existing modal provider order, validation, modal cooldown, and accounting remain unchanged.
- The feature flag is sampled once per graph; feature off preserves the legacy path.
- Blocked work is retained and consumes no shown/dismissed/provider accounting.
- Time passage alone does not schedule work.
- No Promo Queue telemetry or privacy-config rollout is bundled.

## Explicit accepted deltas

- `PromoCoordinationService`, not each NTP model, owns the logical RMF lease and transfer state.
- Same-message handoff keeps one logical session and one queue-history confirmation.
- Stable registration order resolves simultaneous renderer candidates.
- If no renderer remains eligible, the service removes the card and ends the session after its terminal; a later return is a fresh cooldown-governed session.
- Missing exact removal proof fails closed.
- iOS 15/16 coordinated RMF removal is intentionally not animated. iOS 17+ preserves scale/opacity.
- Host exposure signals remain necessary; the implementation is simpler, not view-agnostic.

## Remaining work

No further iteration-one product code is planned against the current technical design. The remaining work is review, branch landing, and validation:

- resolve any Q2/main rebase conflicts and restack Q3;
- verify the cumulative final diff after restacking;
- run approved focused tests/builds;
- smoke-test the real iOS 15/16 removal path;
- manually exercise the standard NTP, suggestion tray, and unified-input hosts;
- confirm whether final reviewers need a separately labeled cooldown/drain reason beyond the implemented diagnostic boundaries and continuation; and
- stage the separate privacy-config enablement only after both PRs land.

Atomic unique-shown reservation, queue telemetry, and additional promo surfaces are separate decisions, not unfinished iteration-one work.

## Definition of done

Iteration one is complete when:

1. PR 2 and PR 3 land in order with their documented scope intact;
2. one global owner prevents modal/RMF and RMF/RMF overlap;
3. service-owned renderer transfer never authorizes an incoming card before the outgoing exact terminal and settlement;
4. the cooldown matrix and persistence semantics are verified at inclusive boundaries;
5. feature-off behavior remains legacy and feature changes require a fresh graph;
6. the known hosts pass lifecycle/manual checks, including the approved old-OS no-animation behavior;
7. diagnostics describe the central logical-owner architecture without mutating production state; and
8. temporary documentation, telemetry, and rollout changes remain outside the app PRs.
