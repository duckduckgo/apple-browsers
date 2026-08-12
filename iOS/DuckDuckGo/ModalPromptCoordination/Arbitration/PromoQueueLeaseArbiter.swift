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
    /// The associated session names the logical remote message that currently owns the global slot.
    case remoteMessage(PromoQueueRemoteMessageSession)
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

    var remoteMessageSession: PromoQueueRemoteMessageSession? {
        guard case .remoteMessage(let session) = activeOwner else {
            return nil
        }

        return session
    }
}

enum PromoQueueModalLeaseAcquisitionResult {
    /// The caller now owns the lease and is responsible for releasing it.
    case acquired(PromoQueueModalLease)
    /// A modal lease already owns the global slot, carried as its attempt identity.
    case blockedByModal(PromoQueueModalAttemptIdentity)
    /// A logical remote-message lease already owns the global slot, carried as its session identity.
    case blockedByRemoteMessage(PromoQueueRemoteMessageSession)
}

enum PromoQueueRemoteMessageLeaseAcquisitionResult {
    /// The caller now owns the lease and is responsible for releasing it.
    case acquired(PromoQueueRemoteMessageLease)
    /// A modal lease already owns the global slot, carried as its attempt identity.
    case blockedByModal(PromoQueueModalAttemptIdentity)
    /// A logical remote-message lease already owns the global slot, carried as its session identity.
    case blockedByRemoteMessage(PromoQueueRemoteMessageSession)
}

/// The single mutual-exclusion authority for promo slots. It owns no provider policy, RMF selection, cooldown, or persistent history.
@MainActor
protocol PromoQueueLeaseArbitrating: AnyObject {
    /// Read-only view of the current lease, for tests and the debug screen.
    var snapshot: PromoQueueLeaseSnapshot { get }

    /// Acquires the modal lease, which succeeds only when the global slot is free.
    func acquireModalLease() -> PromoQueueModalLeaseAcquisitionResult
    /// Acquires a logical remote-message lease, which succeeds only when the global slot is free.
    func acquireRemoteMessageLease(for session: PromoQueueRemoteMessageSession) -> PromoQueueRemoteMessageLeaseAcquisitionResult
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
final class PromoQueueRemoteMessageLease {
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

    /// `id` is minted per acquisition but `session` is supplied by the service. Release must be keyed on the acquisition
    /// ID so a stale token cannot clear a replacement, including a replacement for the same message.
    ///
    /// `token` is weak for the same reason as `ModalLeaseRecord.token`.
    private struct RemoteMessageLeaseRecord {
        let id: UUID
        let session: PromoQueueRemoteMessageSession
        weak var token: PromoQueueRemoteMessageLease?
    }

    private enum ActiveOwner {
        case modal(ModalLeaseRecord)
        case remoteMessage(RemoteMessageLeaseRecord)
    }

    private var activeOwner: ActiveOwner?

    /// Observational projection of the current lease. A record whose weak token has deallocated is reported as idle,
    /// but reads never mutate arbitration state; the next acquisition performs reclamation.
    var snapshot: PromoQueueLeaseSnapshot {
        let ownerSnapshot: PromoQueueActiveOwnerSnapshot?
        switch activeOwner {
        case .modal(let record) where record.token != nil:
            ownerSnapshot = .modal(record.attemptIdentity)
        case .remoteMessage(let record) where record.token != nil:
            ownerSnapshot = .remoteMessage(record.session)
        default:
            ownerSnapshot = nil
        }
        return PromoQueueLeaseSnapshot(activeOwner: ownerSnapshot)
    }

    func acquireModalLease() -> PromoQueueModalLeaseAcquisitionResult {
        pruneLeasesWithDeallocatedTokens()

        switch activeOwner {
        case .modal(let record):
            return .blockedByModal(record.attemptIdentity)
        case .remoteMessage(let record):
            return .blockedByRemoteMessage(record.session)
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

    func acquireRemoteMessageLease(for session: PromoQueueRemoteMessageSession) -> PromoQueueRemoteMessageLeaseAcquisitionResult {
        pruneLeasesWithDeallocatedTokens()

        switch activeOwner {
        case .modal(let record):
            return .blockedByModal(record.attemptIdentity)
        case .remoteMessage(let record):
            return .blockedByRemoteMessage(record.session)
        case nil:
            break
        }

        let leaseID = UUID()
        let lease = PromoQueueRemoteMessageLease { [weak self] in
            self?.releaseRemoteMessageLease(id: leaseID) ?? false
        }
        activeOwner = .remoteMessage(
            RemoteMessageLeaseRecord(
                id: leaseID,
                session: session,
                token: lease
            )
        )
        return .acquired(lease)
    }

    /// Reclaims leases whose token deallocated without `release()`, so a dropped token cannot wedge the arbiter for the
    /// rest of the session: one leaked remote-message token would otherwise block every launch modal, and a leaked modal
    /// token would block every remote message, with no timeout and no recovery.
    private func pruneLeasesWithDeallocatedTokens() {
        let prunedOwnerDescription: String?
        switch activeOwner {
        case .modal(let record) where record.token == nil:
            activeOwner = nil
            prunedOwnerDescription = "modal"
        case .remoteMessage(let record) where record.token == nil:
            activeOwner = nil
            prunedOwnerDescription = "remote message \(record.session.messageID)"
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

    private func releaseRemoteMessageLease(id: UUID) -> Bool {
        // `id` proves the global record is this token's, so a stale token cannot release its replacement.
        guard case .remoteMessage(let record) = activeOwner,
              record.id == id else {
            return false
        }

        activeOwner = nil
        return true
    }
}
