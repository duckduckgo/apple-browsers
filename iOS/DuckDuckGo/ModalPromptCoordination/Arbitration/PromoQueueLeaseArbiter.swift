//
//  PromoQueueLeaseArbiter.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

enum PromoType: Hashable {
    case remoteMessage
}

struct VisiblePromoIdentity: Hashable {
    let surfaceID: UUID
    let promoType: PromoType
    let promoID: String
}

/// Opaque per-acquisition identity that travels with its modal lease through the evaluating, committed, and
/// presentation-active phases, so a callback for an older attempt can be recognised and ignored.
struct PromoQueueModalAttemptIdentity: Hashable {
    fileprivate let id: UUID

    fileprivate init() {
        id = UUID()
    }
}

struct PromoQueueLeaseSnapshot: Equatable {
    let modalAttemptIdentity: PromoQueueModalAttemptIdentity?
    let visiblePromoIdentities: Set<VisiblePromoIdentity>

    var hasModalLease: Bool {
        modalAttemptIdentity != nil
    }

    var visiblePromoCount: Int {
        visiblePromoIdentities.count
    }
}

enum PromoQueueModalLeaseAcquisitionResult {
    /// The caller now owns the lease and is responsible for releasing it.
    case acquired(PromoQueueModalLease)
    /// A modal lease already owns the slot.
    case blockedByModal
    /// One or more visible promos own the slot, carried as their identities.
    case blockedByVisiblePromos(Set<VisiblePromoIdentity>)
}

enum PromoQueueVisiblePromoLeaseAcquisitionResult {
    /// The caller now owns the lease and is responsible for releasing it.
    case acquired(PromoQueueVisiblePromoLease)
    /// A modal lease already owns the slot.
    case blockedByModal
    /// The requested `(surfaceID, promoType)` slot already holds the carried identity, even when the promo ID differs.
    case occupiedSurfaceSlot(VisiblePromoIdentity)
}

/// The single mutual-exclusion authority for promo slots. It owns no provider policy, RMF selection, cooldown, or persistent history.
@MainActor
protocol PromoQueueLeaseArbitrating: AnyObject {
    /// Read-only view of the current leases, for tests and the debug screen.
    var snapshot: PromoQueueLeaseSnapshot { get }

    /// Acquires the modal lease, which succeeds only when there is no modal lease and no visible-promo leases.
    func acquireModalLease() -> PromoQueueModalLeaseAcquisitionResult
    /// Acquires a visible-promo lease, which succeeds only when there is no modal lease and the identity's
    /// `(surfaceID, promoType)` slot is free, so several surfaces may hold leases concurrently but one slot may not hold two.
    func acquireVisiblePromoLease(for identity: VisiblePromoIdentity) -> PromoQueueVisiblePromoLeaseAcquisitionResult
    /// Clears every lease, so outstanding tokens become no-ops. Used on a live feature-flag transition.
    func invalidateAllLeases()
}

@MainActor
final class PromoQueueModalLease {
    let attemptIdentity: PromoQueueModalAttemptIdentity

    private var releaseHandler: (() -> Void)?

    fileprivate init(
        attemptIdentity: PromoQueueModalAttemptIdentity,
        releaseHandler: @escaping () -> Void
    ) {
        self.attemptIdentity = attemptIdentity
        self.releaseHandler = releaseHandler
    }

    func release() {
        let releaseHandler = releaseHandler
        self.releaseHandler = nil
        releaseHandler?()
    }
}

@MainActor
final class PromoQueueVisiblePromoLease {
    private var releaseHandler: (() -> Void)?

    fileprivate init(releaseHandler: @escaping () -> Void) {
        self.releaseHandler = releaseHandler
    }

    func release() {
        let releaseHandler = releaseHandler
        self.releaseHandler = nil
        releaseHandler?()
    }
}

@MainActor
final class PromoQueueLeaseArbiter: PromoQueueLeaseArbitrating {
    /// `token` is weak so that a lease whose owner dropped it without calling `release()` can be reclaimed. It cannot
    /// retain the token: the acquirer owns the lease, and a strong reference here would keep every lease alive forever.
    private struct ModalLeaseRecord {
        let attemptIdentity: PromoQueueModalAttemptIdentity
        weak var token: PromoQueueModalLease?
    }

    private struct VisiblePromoSlot: Hashable {
        let surfaceID: UUID
        let promoType: PromoType

        init(identity: VisiblePromoIdentity) {
            surfaceID = identity.surfaceID
            promoType = identity.promoType
        }
    }

    /// `id` is minted per acquisition but `identity` is not: the same `(surfaceID, promoType, promoID)` may hold the
    /// slot again while an earlier token is still armed, so release has to be keyed on `id` rather than on `identity`.
    ///
    /// `token` is weak for the same reason as `ModalLeaseRecord.token`.
    private struct VisiblePromoLeaseRecord {
        let id: UUID
        let identity: VisiblePromoIdentity
        weak var token: PromoQueueVisiblePromoLease?
    }

    private var modalLease: ModalLeaseRecord?
    private var visiblePromoLeases = [VisiblePromoSlot: VisiblePromoLeaseRecord]()

    /// Prunes before reading so neither the debug screen nor a caller can observe a lease whose token is already gone.
    var snapshot: PromoQueueLeaseSnapshot {
        pruneLeasesWithDeallocatedTokens()
        return PromoQueueLeaseSnapshot(
            modalAttemptIdentity: modalLease?.attemptIdentity,
            visiblePromoIdentities: Set(visiblePromoLeases.values.map(\.identity))
        )
    }

    func acquireModalLease() -> PromoQueueModalLeaseAcquisitionResult {
        pruneLeasesWithDeallocatedTokens()

        guard modalLease == nil else {
            return .blockedByModal
        }

        guard visiblePromoLeases.isEmpty else {
            return .blockedByVisiblePromos(Set(visiblePromoLeases.values.map(\.identity)))
        }

        let attemptIdentity = PromoQueueModalAttemptIdentity()
        let lease = PromoQueueModalLease(
            attemptIdentity: attemptIdentity,
            releaseHandler: { [weak self] in
                self?.releaseModalLease(attemptIdentity: attemptIdentity)
            }
        )
        modalLease = ModalLeaseRecord(
            attemptIdentity: attemptIdentity,
            token: lease
        )
        return .acquired(lease)
    }

    func acquireVisiblePromoLease(for identity: VisiblePromoIdentity) -> PromoQueueVisiblePromoLeaseAcquisitionResult {
        pruneLeasesWithDeallocatedTokens()

        guard modalLease == nil else {
            return .blockedByModal
        }

        let slot = VisiblePromoSlot(identity: identity)
        if let existingLease = visiblePromoLeases[slot] {
            return .occupiedSurfaceSlot(existingLease.identity)
        }

        let leaseID = UUID()
        let lease = PromoQueueVisiblePromoLease { [weak self] in
            self?.releaseVisiblePromoLease(for: slot, id: leaseID)
        }
        visiblePromoLeases[slot] = VisiblePromoLeaseRecord(
            id: leaseID,
            identity: identity,
            token: lease
        )
        return .acquired(lease)
    }

    func invalidateAllLeases() {
        let hadModalLease = modalLease != nil
        let visiblePromoLeaseCount = visiblePromoLeases.count
        modalLease = nil
        visiblePromoLeases.removeAll()

        guard hadModalLease || visiblePromoLeaseCount > 0 else { return }

        Logger.modalPrompt.debug(
            """
            [Promo Queue] - Invalidated leases \
            (modal: \(hadModalLease, privacy: .public), visible promos: \(visiblePromoLeaseCount, privacy: .public)).
            """
        )
    }

    /// Reclaims leases whose token deallocated without `release()`, so a dropped token cannot wedge the arbiter for the
    /// rest of the session: one leaked visible-promo token would otherwise block every launch modal, and a leaked modal
    /// token would block every visible promo, with no timeout and no recovery.
    private func pruneLeasesWithDeallocatedTokens() {
        let didPruneModalLease: Bool
        if let modalLease, modalLease.token == nil {
            self.modalLease = nil
            didPruneModalLease = true
        } else {
            didPruneModalLease = false
        }

        let visiblePromoLeaseCount = visiblePromoLeases.count
        visiblePromoLeases = visiblePromoLeases.filter { $0.value.token != nil }
        let prunedVisiblePromoLeaseCount = visiblePromoLeaseCount - visiblePromoLeases.count

        guard didPruneModalLease || prunedVisiblePromoLeaseCount > 0 else { return }

        Logger.modalPrompt.debug(
            """
            [Promo Queue] - Pruned deallocated lease tokens \
            (modal: \(didPruneModalLease, privacy: .public), visible promos: \(prunedVisiblePromoLeaseCount, privacy: .public)).
            """
        )
    }

    private func releaseModalLease(attemptIdentity: PromoQueueModalAttemptIdentity) {
        // `attemptIdentity` is minted per acquisition, so matching it proves the stored record is this token's. A token
        // whose record was cleared, by release or by an invalidation, cannot match whatever replaced it.
        guard let modalLease,
              modalLease.attemptIdentity == attemptIdentity else {
            return
        }

        self.modalLease = nil
    }

    private func releaseVisiblePromoLease(for slot: VisiblePromoSlot, id: UUID) {
        // `id` proves the record in this slot is this token's, so a token for message A cannot release message B.
        guard let visiblePromoLease = visiblePromoLeases[slot],
              visiblePromoLease.id == id else {
            return
        }

        visiblePromoLeases[slot] = nil
    }
}
