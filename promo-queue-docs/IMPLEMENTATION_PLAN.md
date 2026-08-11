# Promo Queue iteration 1 — implementation and landing plan

## Purpose

This document records how iteration one is split across three app pull requests and which architecture is current. Detailed remaining work is in `Q3_IMPLEMENTATION_PLAN.md`; the consolidated target is in `TECH_DESIGN_FINAL.md`.

The project remains a narrow iOS coordination seam between launch-modal promos and NTP RMF cards. It does not create a general promo queue or move policy into RMF.

## Current status

| Slice | Branch / PR | Status | Responsibility |
| --- | --- | --- | --- |
| PR 1 | `bartosz/promo-q-1`, merged as [#6087](https://github.com/duckduckgo/apple-browsers/pull/6087) | Merged to `main` | Disabled-by-default iOS feature mapping, initial transactional arbiter/injection, coordinated modal attempt foundation |
| PR 2 | `bartosz/promo-q-2` at `12e24676eb` → `main` | Open | Lifecycle-safe modal scheduling, provider revalidation, coordinated NTP render gate, all known NTP hosts, feature-off compatibility |
| PR 2 fixes | `bartosz/promo-q-2-fixes` at `37b99b0d78` → `bartosz/promo-q-2` | Open and agreed | Startup-latched mode, singular global owner, truthful physical RMF release, guarded release handoff, host/readiness hardening, provider simplification |
| PR 3 | final branch based on the frozen PR 2-fixes endpoint | Remaining | Directional cooldowns, animation correction, debug projection, focused cooldown/animation validation |

The existing `origin/bartosz/promo-q-3` tip (`59dfec29f7`, draft [#6217](https://github.com/duckduckgo/apple-browsers/pull/6217)) was built on the pre-simplification Q2 architecture. It is not a mergeable implementation baseline. Preserve it as evidence, then rebuild the final slice from the accepted Q2-fixes endpoint when authorized.

Temporary files under `promo-queue-docs/` and `project_log.md` must not be merged into `main` through any app PR.

## Source hierarchy

For the second and third slices, resolve conflicts in this order:

1. `origin/bartosz/promo-q-2-fixes` implementation;
2. the agreed shared Q2 simplification plan;
3. the agreed shared Q3 simplification plan;
4. `TECH_DESIGN_FINAL.md` and `Q3_IMPLEMENTATION_PLAN.md` in this directory;
5. older implementation plans and commits as historical evidence only.

## Final architecture

### Feature mode

`PromoCoordinationFactory` samples `.promoPresentationCoordination` once when constructing the process-wide service graph. The resulting `.legacy` or `.coordinated` mode is immutable.

- No feature-update subscription or live transition barrier.
- A local override must be set before graph construction.
- A remote kill-switch change takes effect after force-quit/relaunch, not inside the running process.
- Legacy mode preserves the existing lease-free modal path and direct/eager RMF behavior.

### Mutual exclusion

`PromoQueueLeaseArbiter` has one identity-bearing global owner: modal, one RMF, or none. It remains main-actor, transient, and history-free.

- Any owner blocks every other coordinated request.
- Two NTP RMFs do not coexist as owners.
- Tokens release exactly once and stale tokens cannot release replacements.
- Weak token pruning prevents an abandoned token from permanently wedging admission.

### Modal integration

The service preserves launch-source/unrelated-modal gates, then acquires the modal owner before provider or cooldown evaluation. The manager retains the lease through evaluating, committed, and presentation-active phases and releases only after the exact modal root is gone.

The manager continues to own:

- the existing seven-provider order;
- onboarding and provider eligibility;
- the existing remotely tunable modal→modal cooldown;
- prepared/retained prompt validation and safe replacement;
- the named inherited `0.1`-second presentation delay;
- UIKit presentation and provider accounting; and
- actual-presentation history and sync-promo suppression.

### RMF integration

The NTP model retains the candidate, gate, render session, mount identities, and admission. It publishes coordinated card content only after admission and records appearance only from the admitted card.

The standard NTP, suggestion tray, and unified-input hosts explicitly supply renderability/exposure. Logical withdrawal removes the card first; the owner is released only after matching physical removal and one following main turn. A successful release may retry another ready weakly registered NTP in stable order.

Future covering hosts must integrate this seam manually.

### Directional cooldowns

The final PR adds a service-owned pure policy with one existing modal timestamp and one new confirmed-RMF timestamp:

| Source | Target | Delay |
| --- | --- | --- |
| Modal | RMF | 10 minutes |
| RMF | RMF | 10 minutes |
| RMF | Modal | 24 hours |
| Modal | Modal | Existing remote-tunable interval, currently/default 24 hours |

Requests acquire the singular owner before policy evaluation. An admitted RMF confirms history once on its first matching card appearance. Cooldown denial releases raw ownership and retains work without accounting. No provisional reservation or cooldown timer is required.

Reconsideration is checkpoint-only. Time reaching a boundary does not itself run code.

## Pull-request contents

### PR 1 — merged foundation

PR 1 established the iOS flag mapping, initial app-scoped ownership seam, modal admission, and identity-safe lease foundation. PR 2 fixes legitimately revise parts of this implementation, especially the flag lifecycle and owner representation.

### PR 2 plus fixes — accepted Q2 endpoint

Together the two open stacked branches must land as one coherent second slice:

- lifecycle-safe/cancellable modal scheduling and exact-root reconciliation;
- provider validity contract and optional safe replacement;
- coordinated NTP candidate gate and physical mount tracking;
- standard, tray, and unified-input host exposure;
- immutable process mode sampled once;
- one singular global owner;
- self-owned release-only RMF admission;
- readiness-gated release handoff and foreground token hardening;
- stale host completion protections; and
- focused unit, real-UIKit, host, and behavioral integration coverage.

Q2 deliberately excludes directional cooldowns, RMF history, appearance confirmation, cooldown diagnostics, and atomic unique-shown reservation.

### PR 3 — final iteration-one slice

Implement the dependency-ordered phases in `Q3_IMPLEMENTATION_PLAN.md`:

1. restore the coordinated scale/opacity removal transition and prove truthful owner lifetime;
2. add the pure cooldown policy and robust confirmed-RMF timestamp store;
3. extend the admission with exactly-once appearance confirmation and integrate both target transactions;
4. prove checkpoint-only cooldown liveness and elapsed-time ownership;
5. extend the existing debug screen with process mode, singular owner, modal state, confirmed history, and derived boundaries; and
6. run focused validation and manual host QA.

Do not port these obsolete old-Q3 shapes:

- live flag transitions or transition callbacks;
- per-surface/plural RMF ownership;
- provisional cooldown reservation/token;
- exact-boundary retry scheduler/timer;
- detailed denial cases in the public NTP facade;
- production in-memory history fallbacks;
- plural-owner, transition, reservation, or timer debug rows; or
- collision/cooldown telemetry.

The old Q3 commits can still supply useful boundary cases, persistence-failure cases, and test scenario names. Re-author them against the current API instead of resolving a large mechanical cherry-pick conflict.

## Review-efficient landing workflow

1. Let review finish on `bartosz/promo-q-2` and `bartosz/promo-q-2-fixes`; keep the fixes branch as the sole place for Q2 review feedback.
2. Freeze the accepted Q2-fixes tip.
3. Prefer creating/rebuilding Q3 from merged `main`. If timing requires stacking, base it on the exact frozen Q2-fixes tip and avoid further Q2-only edits in Q3.
4. Keep Q3 commits dependency-ordered and reviewable, but submit one final app PR rather than creating another stack.
5. If Q2 feedback arrives after Q3 starts, apply the correction to the lowest owning branch, then perform one controlled Q3 rebase after that branch is final.
6. Do not repeatedly rebase Q3 for unrelated `main` movement while the Q2 stack is still under review.
7. Keep the separate privacy-config rollout out of this repository/PR series.

This minimizes duplicated conflict resolution and review churn while retaining three atomic product slices.

## Tests already present at the Q2-fixes endpoint

The current stack contains focused coverage for:

- one-time feature sampling and absence of live subscription;
- singular-owner acquisition, stale release, and weak pruning;
- modal lease-first provider evaluation and exact-root lifetime;
- pending work, background cancellation, UIKit attachment/refusal, and provider revalidation;
- retained blocked RMF candidates and once-per-session appearance;
- same-ID continuity, changed-ID replacement, overlapping mounts, teardown, and physical release;
- all three known NTP host exposure paths;
- foreground readiness and stale callback rejection;
- stable, reentrant-safe cross-surface release handoff; and
- representative real modal/RMF lifecycle integration.

Do not duplicate this suite in Q3. Add only cooldown, animation, new debug snapshot, and their cross-component scenarios.

## Remaining scope decision

`HomePageConfiguration` still has a potentially racy asynchronous `remoteMessageShownUnique` check/write. The original design treated an atomic winner as required; both agreed simplification plans moved it to an optional independent correctness change.

It is not required for mutual exclusion or cooldown correctness. Keep it out of the core Q3 definition of done unless separately approved. If approved, add it as one isolated commit with deterministic delayed-store coverage.

## Explicit concerns relative to the original plan

1. **Rollback latency:** flag changes require a new process; the original design promised live rollback.
2. **Stricter serialization:** a second RMF cannot appear after 10 minutes while the first remains mounted; the original design allowed per-surface coexistence.
3. **Checkpoint-only liveness:** an eligible promo may wait indefinitely after its boundary; the original design scheduled an exact-boundary RMF retry.
4. **Manual host completeness:** future covering hosts are not compiler-enforced.
5. **Cached Default Browser validity:** retained work can temporarily use stale status after an external setting change.
6. **Deferred atomic unique accounting:** the old requirement is no longer part of core Q3.

These are accepted Q2 simplifications or explicitly deferred scope, not accidental omissions. They must remain visible in code review and rollout notes.

The coordinated `.transition(.identity)` change is different: it is an unresolved visible regression and must be corrected in Q3 or explicitly approved by product/design.

## Rollout

The app flag remains disabled by default. Privacy-config enablement is a separate change after all three app slices land and the first containing version is known.

Because mode is process-latched:

- internal/local override testing must relaunch after changing the value;
- staged enablement is observed on newly launched processes; and
- emergency remote disable does not reconfigure a running/suspended process until relaunch.

Promo Queue telemetry is a separate project. Iteration one relies on the read-only debug projection plus existing RMF/provider accounting.

## Definition of done

Iteration one is complete when:

- the three app slices have landed from the reviewed branch stack;
- legacy mode preserves prior modal and RMF behavior;
- coordinated mode has one truthful global owner across modal and all known NTP paths;
- provider work cannot occur before modal ownership and cooldown admission;
- blocked/denied RMF work is retained and unaccounted;
- modal and RMF ownership survive their real visible lifetimes;
- the four cooldown directions use confirmed history and exact inclusive boundaries;
- cooldown passage alone creates no timer-driven retry;
- coordinated RMF keeps its scale/opacity removal animation;
- the debug screen reflects process-latched, singular-owner, checkpoint-only state;
- focused unit/integration/manual QA passes;
- no new Promo Queue telemetry is bundled; and
- privacy-config rollout remains separately tracked.
