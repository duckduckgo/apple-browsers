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

    var debugIdentifier: String {
        id.uuidString
    }
}

enum PromoQueueActiveOwnerSnapshot: Equatable {
    /// The associated attempt identity names the modal that currently owns the global slot.
    case modal(PromoQueueModalAttemptIdentity)
    /// The associated promo identity names the visible promo that currently owns the global slot.
    case visible(VisiblePromoIdentity)
}

struct PromoQueueLeaseSnapshot: Equatable {
    let activeOwner: PromoQueueActiveOwnerSnapshot?

    var modalAttemptIdentity: PromoQueueModalAttemptIdentity? {
        guard case .modal(let attemptIdentity) = activeOwner else {
            return nil
        }

        return attemptIdentity
    }

    var hasModalLease: Bool {
        modalAttemptIdentity != nil
    }

    var visiblePromoIdentity: VisiblePromoIdentity? {
        guard case .visible(let identity) = activeOwner else {
            return nil
        }

        return identity
    }
}

enum PromoQueueModalLeaseAcquisitionResult {
    /// The caller now owns the lease and is responsible for releasing it.
    case acquired(PromoQueueModalLease)
    /// A modal lease already owns the global slot, carried as its attempt identity.
    case blockedByModal(PromoQueueModalAttemptIdentity)
    /// A visible promo already owns the global slot, carried as its identity.
    case blockedByVisiblePromo(VisiblePromoIdentity)
}

enum PromoQueueVisiblePromoLeaseAcquisitionResult {
    /// The caller now owns the lease and is responsible for releasing it.
    case acquired(PromoQueueVisiblePromoLease)
    /// A modal lease already owns the global slot, carried as its attempt identity.
    case blockedByModal(PromoQueueModalAttemptIdentity)
    /// A visible promo already owns the global slot, carried as its identity.
    case blockedByVisiblePromo(VisiblePromoIdentity)
}

/// The single mutual-exclusion authority for promo slots. It owns no provider policy, RMF selection, cooldown, or persistent history.
@MainActor
protocol PromoQueueLeaseArbitrating: AnyObject {
    /// Read-only view of the current leases, for tests and the debug screen.
    var snapshot: PromoQueueLeaseSnapshot { get }

    /// Acquires the modal lease, which succeeds only when the global slot is free.
    func acquireModalLease() -> PromoQueueModalLeaseAcquisitionResult
    /// Acquires a visible-promo lease, which succeeds only when the global slot is free.
    func acquireVisiblePromoLease(for identity: VisiblePromoIdentity) -> PromoQueueVisiblePromoLeaseAcquisitionResult
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
    private var releaseHandler: (() -> Bool)?

    fileprivate init(releaseHandler: @escaping () -> Bool) {
        self.releaseHandler = releaseHandler
    }

    /// Returns `true` only when this token cleared the current global owner.
    @discardableResult
    func release() -> Bool {
        let releaseHandler = releaseHandler
        self.releaseHandler = nil
        return releaseHandler?() ?? false
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

    /// `id` is minted per acquisition but `identity` is not: the same identity may own the global slot again while an
    /// earlier token is still armed, so release has to be keyed on `id` rather than on `identity`.
    ///
    /// `token` is weak for the same reason as `ModalLeaseRecord.token`.
    private struct VisiblePromoLeaseRecord {
        let id: UUID
        let identity: VisiblePromoIdentity
        weak var token: PromoQueueVisiblePromoLease?
    }

    private enum ActiveOwner {
        case modal(ModalLeaseRecord)
        case visible(VisiblePromoLeaseRecord)
    }

    private var activeOwner: ActiveOwner?

    /// Prunes before reading so neither the debug screen nor a caller can observe a lease whose token is already gone.
    var snapshot: PromoQueueLeaseSnapshot {
        pruneLeasesWithDeallocatedTokens()
        let ownerSnapshot: PromoQueueActiveOwnerSnapshot?
        switch activeOwner {
        case .modal(let record):
            ownerSnapshot = .modal(record.attemptIdentity)
        case .visible(let record):
            ownerSnapshot = .visible(record.identity)
        case nil:
            ownerSnapshot = nil
        }
        return PromoQueueLeaseSnapshot(activeOwner: ownerSnapshot)
    }

    func acquireModalLease() -> PromoQueueModalLeaseAcquisitionResult {
        pruneLeasesWithDeallocatedTokens()

        switch activeOwner {
        case .modal(let record):
            return .blockedByModal(record.attemptIdentity)
        case .visible(let record):
            return .blockedByVisiblePromo(record.identity)
        case nil:
            break
        }

        let attemptIdentity = PromoQueueModalAttemptIdentity()
        let lease = PromoQueueModalLease(
            attemptIdentity: attemptIdentity,
            releaseHandler: { [weak self] in
                self?.releaseModalLease(attemptIdentity: attemptIdentity)
            }
        )
        activeOwner = .modal(
            ModalLeaseRecord(
                attemptIdentity: attemptIdentity,
                token: lease
            )
        )
        return .acquired(lease)
    }

    func acquireVisiblePromoLease(for identity: VisiblePromoIdentity) -> PromoQueueVisiblePromoLeaseAcquisitionResult {
        pruneLeasesWithDeallocatedTokens()

        switch activeOwner {
        case .modal(let record):
            return .blockedByModal(record.attemptIdentity)
        case .visible(let record):
            return .blockedByVisiblePromo(record.identity)
        case nil:
            break
        }

        let leaseID = UUID()
        let lease = PromoQueueVisiblePromoLease { [weak self] in
            self?.releaseVisiblePromoLease(id: leaseID) ?? false
        }
        activeOwner = .visible(
            VisiblePromoLeaseRecord(
                id: leaseID,
                identity: identity,
                token: lease
            )
        )
        return .acquired(lease)
    }

    /// Reclaims leases whose token deallocated without `release()`, so a dropped token cannot wedge the arbiter for the
    /// rest of the session: one leaked visible-promo token would otherwise block every launch modal, and a leaked modal
    /// token would block every visible promo, with no timeout and no recovery.
    private func pruneLeasesWithDeallocatedTokens() {
        let prunedOwnerDescription: String?
        switch activeOwner {
        case .modal(let record) where record.token == nil:
            activeOwner = nil
            prunedOwnerDescription = "modal"
        case .visible(let record) where record.token == nil:
            activeOwner = nil
            prunedOwnerDescription = "visible promo \(record.identity.promoID)"
        default:
            prunedOwnerDescription = nil
        }

        guard let prunedOwnerDescription else { return }

        Logger.modalPrompt.debug(
            "[Promo Queue] - Pruned deallocated global owner: \(prunedOwnerDescription, privacy: .public)."
        )
    }

    private func releaseModalLease(attemptIdentity: PromoQueueModalAttemptIdentity) {
        // `attemptIdentity` is minted per acquisition, so matching it proves the stored record is this token's. A token
        // whose record was cleared by release cannot match whatever replaced it.
        guard case .modal(let record) = activeOwner,
              record.attemptIdentity == attemptIdentity else {
            return
        }

        activeOwner = nil
    }

    private func releaseVisiblePromoLease(id: UUID) -> Bool {
        // `id` proves the global record is this token's, so a stale token cannot release its replacement.
        guard case .visible(let record) = activeOwner,
              record.id == id else {
            return false
        }

        activeOwner = nil
        return true
    }
}
