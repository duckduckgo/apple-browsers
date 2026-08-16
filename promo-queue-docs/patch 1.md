# Promo Queue: Phase 1 alignment patch

## Purpose

Apply a small follow-up to the completed Phase 1 foundation before Phase 2 begins. This patch does not change product behavior or add a new architecture. It removes redundant modal state, makes lease ownership transfer unambiguous, and completes one missing storage-fallback assertion.

Phase 0 requires no changes.

The intended end state of this patch is:

1. one typed opaque identity for an entire modal ownership;
2. a `Void`-returning transfer into `ModalPromptCoordinationManager`, after which only the manager retains or releases the lease; and
3. compact coverage proving that a first RMF-history read failure with no cache behaves as no known history.

## Local-only workflow and branch placement

All work must remain local. Do not push, open or retarget a pull request, merge, edit an external repository, deploy configuration, or mutate a project tracker.

1. Read the repository `AGENTS.md`, the permitted relevant rules, `project_log.md`, and the existing local PR handoff.
2. Run read-only `git status`, branch, log, and divergence checks. Preserve every tracked/untracked and concurrent change.
3. Inspect both tips. Confirm that `bartosz/promo-q-simp-2` still contains the completed Phase 0/1 foundation, that `bartosz/promo-q-simp-3` contains only documentation beyond that base, and that no Phase 2 production work has begun before rewriting the local stack.
4. Implement this patch on local `bartosz/promo-q-simp-2`, because it belongs to the PR 1 foundation.
5. After focused verification and human-authorized git writes, rebase the existing documentation-only `bartosz/promo-q-simp-3` onto the patched Phase 1 head while preserving its documentation commits. Do not recreate or reset it. Act only after inspecting the exact graph and obtaining required permission.
6. If `bartosz/promo-q-simp-3` already contains Phase 2 production work, or either worktree/branch has concurrent changes, stop and report the exact state instead of rewriting history.

At the 2026-08-15 documentation checkpoint, the Phase 0/1 implementation commit is `ab23ea75d5` and its handoff commit is `fbd1dd2ef5`. Treat these hashes as historical evidence, not assumptions; verify the current graph.

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
- `project_log.md` and the local PR 1 handoff record the patch and actual verification evidence.
- No branch was pushed and no pull request was opened.

At handoff, suggest an updated future PR 1 title only if the original title no longer fits, and update its ready-to-paste description with the one-identity/one-way-transfer cleanup and actual test evidence.
