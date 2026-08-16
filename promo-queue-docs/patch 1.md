# Promo Queue: Phase 1 alignment patch

> **Completed historical record — 2026-08-16.** This patch is already present in `bartosz/promo-q-simp-2` and its descendants. Do not execute the old branch-rewrite workflow or reapply these changes. The requirements below remain as review criteria for the PR 1 layer.

## Purpose

This small follow-up to the Phase 1 foundation did not change product behavior or add a new architecture. It removed redundant modal state, made lease ownership transfer unambiguous, and completed one missing storage-fallback assertion.

Phase 0 requires no changes.

The intended end state of this patch is:

1. one typed opaque identity for an entire modal ownership;
2. a `Void`-returning transfer into `ModalPromptCoordinationManager`, after which only the manager retains or releases the lease; and
3. compact coverage proving that a first RMF-history read failure with no cache behaves as no known history.

## Documentation and branch placement

The implementation belongs to the PR 1 production layer on `bartosz/promo-q-simp-2`. Its project documentation belongs only on `bartosz/promo-q-simp-master`. The production branches `bartosz/promo-q-simp-2`, `bartosz/promo-q-simp-3`, and `bartosz/promo-q-simp-4` must not contain `project_log.md`, `project_lessons/`, `promo-queue-docs/`, or project-only handoff notes.

Read this record from the master branch with `git show`, or use a separate worktree while reviewing production. Documentation edits may be committed locally on `bartosz/promo-q-simp-master`; do not push that branch or copy/cherry-pick its documentation commits into a production branch unless the user explicitly asks.

The original pre-implementation workflow and hashes are intentionally not executable instructions anymore. Review the current PR 1 layer as `main...bartosz/promo-q-simp-2`, verify the requirements below, and preserve the open stack.

## Patch A — use one modal ownership identity

Update `iOS/DuckDuckGo/ModalPromptCoordination/Arbitration/PromoQueueLeaseArbiter.swift`.

- Replace the modal attempt/acquisition identity pair with one opaque, hashable `PromoQueueModalOwnershipIdentity`.
- Let that typed identity own the UUID directly. Keep construction controlled by the arbiter and do not expose the raw UUID.
- Give `PromoQueueModalLease` one `ownershipIdentity`.
- Store only that identity and the weak token in the modal owner record.
- Use the same identity for:
  - arbiter owner matching;
  - identity-checked/idempotent release;
  - modal-manager phase transitions;
  - stale scheduled-callback validation; and
  - diagnostic snapshots.
- Rename snapshot cases/properties consistently, for example `.modal(ownershipIdentity:)`.
- Remove `PromoQueueModalAttemptIdentity` and the modal path's redundant use of `PromoQueueAcquisitionIdentity`.
- Leave the RMF acquisition identity unchanged. It has a separate production purpose in callback validation and SwiftUI diffing.

Update modal identity references in:

- `iOS/DuckDuckGo/ModalPromptCoordination/ModalPromptCoordinationManager.swift`;
- `iOS/DuckDuckGoTests/ModalPromptCoordination/PromoQueueLeaseArbiterTests.swift`;
- `iOS/DuckDuckGoTests/ModalPromptCoordination/ModalPromptCoordinationManagerPromoQueueTests.swift`; and
- `iOS/DuckDuckGoTests/ModalPromptCoordination/ModalPromptCoordinationRealUIKitTests.swift`;
- `iOS/IntegrationTests/ModalPromptCoordination/ModalPromptCoordinationManagerIntegrationTests.swift`.

Do not expose identity-generation state or widen access solely for tests. Assert lease behavior, manager phase, and stale-callback outcomes through existing production contracts.

## Patch B — make transferred modal-lease handling return `Void`

Update the coordinated manager protocol and implementation in `ModalPromptCoordinationManager.swift` so the transferred-lease operation returns `Void`:

```swift
func presentModalPromptIfNeeded(
    from presenter: ModalPromptPresenter,
    with lease: PromoQueueModalLease
)
```

Delete `ModalPromptLeaseDisposition`.

Ownership rule: once `PromoCoordinationService` calls this method, the manager exclusively owns the transferred lease. The manager:

- releases it synchronously if another coordinated attempt is unexpectedly active;
- releases it synchronously when modal-to-modal cooldown blocks selection;
- releases it synchronously when no provider produces a prompt; and
- retains it when a prompt is committed, carrying the same lease through scheduling, presentation, and exact-root reconciliation.

Retain the manager's existing cooldown/no-provider/presentation logs beside those decisions. Do not add replacement logging state or instrumentation merely because the service's disposition logs disappear. No provider should release the lease itself.

Update `iOS/DuckDuckGo/AppServices/PromoCoordinationService.swift`:

- replace the disposition switch with one direct manager call;
- remove service-side retained/released outcome logging that depends on the disposition; and
- never release the lease after the call. Service-owned release remains valid only before transfer, such as cross-promo cooldown denial.

Convert every production and test call to a direct `Void` call. Remove both disposition assignments and redundant `_ =` discards.

Update `iOS/SharedTestUtils/Mocks/DuckDuckGo/ModalPromptCoordination/MockModalPromptCoordinationManager.swift`:

- remove configurable returned disposition;
- make the coordinated operation return `Void`; and
- continue capturing the transferred lease if existing tests need to observe retention through production behavior.

Do not invent a replacement result enum, lease protocol, test-only initializer, or production hook. Tests should assert observable arbiter availability, manager phase, provider evaluation, scheduling/presentation, and synchronous no-selection release.

## Patch C — complete the compact storage-fallback test

No production change is expected in `PromoQueueCooldownPolicy.swift`.

In `iOS/DuckDuckGoTests/ModalPromptCoordination/Cooldown/PromoQueueCooldownPolicyTests.swift`, add one focused case using the existing storage fixture and production history getter:

1. create a fresh RMF history with no cached value;
2. make its first storage read fail; and
3. assert that the last confirmed RMF appearance is `nil` (no known history).

Existing coverage already proves cached-value fallback after a later read failure, failed-write in-process authority, and service-wrapper behavior after durable write failure. Do not duplicate those cases, inspect private cache state, or add reset-failure permutations.

## Focused verification

After obtaining the permission required by repository instructions, run the existing suites containing:

- `PromoQueueLeaseArbiterTests`;
- `ModalPromptCoordinationManagerPromoQueueTests`;
- `ModalPromptCoordinationRealUIKitTests`;
- `ModalPromptCoordinationManagerIntegrationTests`;
- `PromoCoordinationServicePromoQueueTests`; and
- `PromoQueueCooldownPolicyTests`.

Use XcodeBuildMCP with help-first command discovery; do not substitute raw `xcodebuild`, `xcrun`, or `simctl`. Use the `iOS Unit Tests` scheme for the unit suites and the `iOS Integration Tests` scheme for `ModalPromptCoordinationManagerIntegrationTests`, with exact identifiers accepted by the local tooling. Then run the relevant iOS build and `git diff --check`. If XcodeBuildMCP creates an unrelated root `Makefile`, keep it out of the patch.

No `project.pbxproj` change should be necessary because this patch adds or removes no Swift file. If the implementation unexpectedly creates a file, stop and reconsider before expanding scope.

## Completion checklist

- Phase 0 remains unchanged.
- No `PromoQueueModalAttemptIdentity` remains.
- No `ModalPromptLeaseDisposition` remains.
- No coordinated transferred-lease call assigns or discards a return value, including with `_ =`.
- Modal ownership uses one typed identity through acquisition, evaluation, scheduling, presentation, and release.
- The transferred manager operation returns `Void`; the service never makes a post-transfer lease decision.
- The fresh-read-failure/no-cache history case passes.
- Existing exact-root, weak-token, cooldown, service, and legacy behavior remains green.
- No private declaration was widened and no production API was introduced solely for testing.
- The diff contains only the narrow Phase 1 alignment and its focused tests.
- `project_log.md` and the PR 1 handoff on `bartosz/promo-q-simp-master` record the patch and actual verification evidence; neither file is present on a production branch.
- Review work does not rewrite, push, retarget, or otherwise mutate the open pull request.

If review evidence changes the PR 1 summary, update its suggested title/description only in the master-branch handoff. Do not add that handoff to the production branch or mutate the open pull request without separate authorization.
