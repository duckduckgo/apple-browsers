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

struct PromoQueueLeaseGeneration: Hashable {
    fileprivate let id: UUID

    fileprivate init() {
        id = UUID()
    }
}

struct PromoQueueModalAttemptIdentity: Hashable {
    fileprivate let id: UUID

    fileprivate init() {
        id = UUID()
    }
}

struct PromoQueueLeaseSnapshot: Equatable {
    let generation: PromoQueueLeaseGeneration
    let modalAttemptIdentity: PromoQueueModalAttemptIdentity?
    let visiblePromoIdentities: Set<VisiblePromoIdentity>

    var hasModalLease: Bool {
        modalAttemptIdentity != nil
    }

    var visiblePromoCount: Int {
        visiblePromoIdentities.count
    }
}

enum PromoQueueLeaseAcquisitionResult<Lease> {
    case acquired(Lease)
    case blockedByModal
    case blockedByVisiblePromos(Set<VisiblePromoIdentity>)
    case occupiedSurfaceSlot(VisiblePromoIdentity)
}

@MainActor
protocol PromoQueueLeaseArbitrating: AnyObject {
    var snapshot: PromoQueueLeaseSnapshot { get }

    func acquireModalLease() -> PromoQueueLeaseAcquisitionResult<PromoQueueModalLease>
    func acquireVisiblePromoLease(for identity: VisiblePromoIdentity) -> PromoQueueLeaseAcquisitionResult<PromoQueueVisiblePromoLease>
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
    private struct ModalLeaseRecord {
        let id: UUID
        let generation: PromoQueueLeaseGeneration
        let attemptIdentity: PromoQueueModalAttemptIdentity
    }

    private struct VisiblePromoSlot: Hashable {
        let surfaceID: UUID
        let promoType: PromoType

        init(identity: VisiblePromoIdentity) {
            surfaceID = identity.surfaceID
            promoType = identity.promoType
        }
    }

    private struct VisiblePromoLeaseRecord {
        let id: UUID
        let generation: PromoQueueLeaseGeneration
        let identity: VisiblePromoIdentity
    }

    private var generation = PromoQueueLeaseGeneration()
    private var modalLease: ModalLeaseRecord?
    private var visiblePromoLeases = [VisiblePromoSlot: VisiblePromoLeaseRecord]()

    var snapshot: PromoQueueLeaseSnapshot {
        PromoQueueLeaseSnapshot(
            generation: generation,
            modalAttemptIdentity: modalLease?.attemptIdentity,
            visiblePromoIdentities: Set(visiblePromoLeases.values.map(\.identity))
        )
    }

    func acquireModalLease() -> PromoQueueLeaseAcquisitionResult<PromoQueueModalLease> {
        guard modalLease == nil else {
            return .blockedByModal
        }

        guard visiblePromoLeases.isEmpty else {
            return .blockedByVisiblePromos(Set(visiblePromoLeases.values.map(\.identity)))
        }

        let leaseID = UUID()
        let leaseGeneration = generation
        let attemptIdentity = PromoQueueModalAttemptIdentity()
        modalLease = ModalLeaseRecord(
            id: leaseID,
            generation: leaseGeneration,
            attemptIdentity: attemptIdentity
        )

        let lease = PromoQueueModalLease(
            attemptIdentity: attemptIdentity,
            releaseHandler: { [weak self] in
                self?.releaseModalLease(id: leaseID, generation: leaseGeneration)
            }
        )
        return .acquired(lease)
    }

    func acquireVisiblePromoLease(for identity: VisiblePromoIdentity) -> PromoQueueLeaseAcquisitionResult<PromoQueueVisiblePromoLease> {
        guard modalLease == nil else {
            return .blockedByModal
        }

        let slot = VisiblePromoSlot(identity: identity)
        if let existingLease = visiblePromoLeases[slot] {
            return .occupiedSurfaceSlot(existingLease.identity)
        }

        let leaseID = UUID()
        let leaseGeneration = generation
        visiblePromoLeases[slot] = VisiblePromoLeaseRecord(
            id: leaseID,
            generation: leaseGeneration,
            identity: identity
        )

        let lease = PromoQueueVisiblePromoLease { [weak self] in
            self?.releaseVisiblePromoLease(
                for: slot,
                id: leaseID,
                generation: leaseGeneration
            )
        }
        return .acquired(lease)
    }

    func invalidateAllLeases() {
        generation = PromoQueueLeaseGeneration()
        modalLease = nil
        visiblePromoLeases.removeAll()
    }

    private func releaseModalLease(id: UUID, generation: PromoQueueLeaseGeneration) {
        guard let modalLease,
              modalLease.id == id,
              modalLease.generation == generation,
              generation == self.generation else {
            return
        }

        self.modalLease = nil
    }

    private func releaseVisiblePromoLease(
        for slot: VisiblePromoSlot,
        id: UUID,
        generation: PromoQueueLeaseGeneration
    ) {
        guard let visiblePromoLease = visiblePromoLeases[slot],
              visiblePromoLease.id == id,
              visiblePromoLease.generation == generation,
              generation == self.generation else {
            return
        }

        visiblePromoLeases[slot] = nil
    }
}
