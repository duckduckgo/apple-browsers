//
//  PromoQueueLeaseArbiterTests.swift
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
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("Promo Queue Lease Arbiter")
struct PromoQueueLeaseArbiterTests {

    // The arbiter reclaims a lease whose token has deallocated, so a test that needs a lease to keep holding its slot
    // must bind the token and keep it alive for as long as the assertions depend on it.

    @available(iOS 16, *)
    @Test("Modal lease can be acquired from idle", .timeLimit(.minutes(1)))
    func acquireModalLeaseFromIdle() throws {
        let arbiter = PromoQueueLeaseArbiter()

        let lease = try acquiredLease(from: arbiter.acquireModalLease())

        #expect(arbiter.snapshot.hasModalLease)
        #expect(arbiter.snapshot.modalAttemptIdentity == lease.attemptIdentity)
        #expect(arbiter.snapshot.visiblePromoIdentities.isEmpty)
    }

    @available(iOS 16, *)
    @Test("Visible promo lease can be acquired from idle", .timeLimit(.minutes(1)))
    func acquireVisiblePromoLeaseFromIdle() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let identity = makeVisiblePromoIdentity()

        let lease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: identity))

        #expect(!arbiter.snapshot.hasModalLease)
        #expect(arbiter.snapshot.visiblePromoIdentities == [identity])
        _ = lease
    }

    @available(iOS 16, *)
    @Test("Visible promos block modal acquisition with their identities", .timeLimit(.minutes(1)))
    func visiblePromosBlockModalAcquisition() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let firstIdentity = makeVisiblePromoIdentity(promoID: "first")
        let secondIdentity = makeVisiblePromoIdentity(promoID: "second")
        let firstLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: firstIdentity))
        let secondLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: secondIdentity))

        let result = arbiter.acquireModalLease()

        guard case .blockedByVisiblePromos(let identities) = result else {
            Issue.record("Expected modal acquisition to be blocked by visible promos")
            return
        }
        #expect(identities == [firstIdentity, secondIdentity])
        #expect(!arbiter.snapshot.hasModalLease)
        _ = (firstLease, secondLease)
    }

    @available(iOS 16, *)
    @Test("Modal lease blocks visible promo acquisition", .timeLimit(.minutes(1)))
    func modalLeaseBlocksVisiblePromoAcquisition() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let modalLease = try acquiredLease(from: arbiter.acquireModalLease())

        let result = arbiter.acquireVisiblePromoLease(for: makeVisiblePromoIdentity())

        guard case .blockedByModal = result else {
            Issue.record("Expected visible promo acquisition to be blocked by the modal")
            return
        }
        #expect(arbiter.snapshot.visiblePromoIdentities.isEmpty)
        _ = modalLease
    }

    @available(iOS 16, *)
    @Test("Existing modal lease blocks another modal acquisition", .timeLimit(.minutes(1)))
    func modalLeaseBlocksAnotherModalAcquisition() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let modalLease = try acquiredLease(from: arbiter.acquireModalLease())

        let result = arbiter.acquireModalLease()

        guard case .blockedByModal = result else {
            Issue.record("Expected modal acquisition to be blocked by the existing modal")
            return
        }
        #expect(arbiter.snapshot.hasModalLease)
        _ = modalLease
    }

    @available(iOS 16, *)
    @Test("The same visible promo can hold leases on different surfaces", .timeLimit(.minutes(1)))
    func sameVisiblePromoCanHoldLeasesOnDifferentSurfaces() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let firstIdentity = makeVisiblePromoIdentity(
            surfaceID: UUID(),
            promoID: "message"
        )
        let secondIdentity = makeVisiblePromoIdentity(
            surfaceID: UUID(),
            promoID: "message"
        )

        let firstLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: firstIdentity))
        let secondLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: secondIdentity))

        #expect(arbiter.snapshot.visiblePromoIdentities == [firstIdentity, secondIdentity])
        #expect(arbiter.snapshot.visiblePromoCount == 2)
        _ = (firstLease, secondLease)
    }

    @available(iOS 16, *)
    @Test("A surface and promo type slot cannot hold two messages", .timeLimit(.minutes(1)))
    func visiblePromoSlotCannotHoldTwoMessages() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let surfaceID = UUID()
        let firstIdentity = makeVisiblePromoIdentity(
            surfaceID: surfaceID,
            promoID: "message-a"
        )
        let secondIdentity = makeVisiblePromoIdentity(
            surfaceID: surfaceID,
            promoID: "message-b"
        )
        let firstLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: firstIdentity))

        let result = arbiter.acquireVisiblePromoLease(for: secondIdentity)

        guard case .occupiedSurfaceSlot(let occupyingIdentity) = result else {
            Issue.record("Expected visible promo acquisition to be blocked by the occupied surface slot")
            return
        }
        #expect(occupyingIdentity == firstIdentity)
        #expect(arbiter.snapshot.visiblePromoIdentities == [firstIdentity])
        _ = firstLease
    }

    @available(iOS 16, *)
    @Test("The same message cannot acquire its occupied surface slot twice", .timeLimit(.minutes(1)))
    func visiblePromoCannotAcquireOccupiedSlotTwice() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let identity = makeVisiblePromoIdentity()
        let lease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: identity))

        let result = arbiter.acquireVisiblePromoLease(for: identity)

        guard case .occupiedSurfaceSlot(let occupyingIdentity) = result else {
            Issue.record("Expected duplicate visible promo acquisition to be blocked by the occupied surface slot")
            return
        }
        #expect(occupyingIdentity == identity)
        #expect(arbiter.snapshot.visiblePromoCount == 1)
        _ = lease
    }

    @available(iOS 16, *)
    @Test("Releasing one visible promo does not release another", .timeLimit(.minutes(1)))
    func releasingVisiblePromoDoesNotReleaseAnother() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let firstIdentity = makeVisiblePromoIdentity(promoID: "first")
        let secondIdentity = makeVisiblePromoIdentity(promoID: "second")
        let firstLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: firstIdentity))
        let secondLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: secondIdentity))

        firstLease.release()

        #expect(arbiter.snapshot.visiblePromoIdentities == [secondIdentity])
        _ = secondLease
    }

    @available(iOS 16, *)
    @Test("Releasing a modal lease more than once is harmless", .timeLimit(.minutes(1)))
    func duplicateModalReleaseIsHarmless() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let lease = try acquiredLease(from: arbiter.acquireModalLease())

        lease.release()
        lease.release()

        #expect(!arbiter.snapshot.hasModalLease)
        let reacquiredLease = try acquiredLease(from: arbiter.acquireModalLease())
        #expect(arbiter.snapshot.hasModalLease)
        _ = reacquiredLease
    }

    @available(iOS 16, *)
    @Test("Releasing a visible promo lease more than once is harmless", .timeLimit(.minutes(1)))
    func duplicateVisiblePromoReleaseIsHarmless() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let identity = makeVisiblePromoIdentity()
        let lease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: identity))

        lease.release()
        lease.release()

        #expect(arbiter.snapshot.visiblePromoIdentities.isEmpty)
        let reacquiredLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: identity))
        #expect(arbiter.snapshot.visiblePromoIdentities == [identity])
        _ = reacquiredLease
    }

    @available(iOS 16, *)
    @Test("A stale visible promo token cannot open the modal gate for the slot it no longer owns", .timeLimit(.minutes(1)))
    func staleVisiblePromoTokenCannotOpenModalGate() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let surfaceID = UUID()
        let staleIdentity = makeVisiblePromoIdentity(
            surfaceID: surfaceID,
            promoID: "message-a"
        )
        let currentIdentity = makeVisiblePromoIdentity(
            surfaceID: surfaceID,
            promoID: "message-b"
        )
        let staleLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: staleIdentity))
        arbiter.invalidateAllLeases()
        let currentLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: currentIdentity))

        staleLease.release()

        #expect(arbiter.snapshot.visiblePromoIdentities == [currentIdentity])
        let result = arbiter.acquireModalLease()
        guard case .blockedByVisiblePromos(let identities) = result else {
            Issue.record("Expected the surviving visible promo lease to keep blocking modal acquisition")
            return
        }
        #expect(identities == [currentIdentity])
        _ = currentLease
    }

    @available(iOS 16, *)
    @Test("Old modal token cannot release a lease acquired after invalidation", .timeLimit(.minutes(1)))
    func oldModalTokenCannotReleaseNewLeaseAfterInvalidation() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let oldLease = try acquiredLease(from: arbiter.acquireModalLease())
        arbiter.invalidateAllLeases()
        let newLease = try acquiredLease(from: arbiter.acquireModalLease())

        oldLease.release()

        #expect(arbiter.snapshot.hasModalLease)
        #expect(newLease.attemptIdentity != oldLease.attemptIdentity)
        #expect(arbiter.snapshot.modalAttemptIdentity == newLease.attemptIdentity)
    }

    @available(iOS 16, *)
    @Test("Old visible promo token cannot release a lease acquired after invalidation", .timeLimit(.minutes(1)))
    func oldVisiblePromoTokenCannotReleaseNewLeaseAfterInvalidation() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let surfaceID = UUID()
        let oldIdentity = makeVisiblePromoIdentity(
            surfaceID: surfaceID,
            promoID: "message-a"
        )
        let newIdentity = makeVisiblePromoIdentity(
            surfaceID: surfaceID,
            promoID: "message-b"
        )
        let oldLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: oldIdentity))
        arbiter.invalidateAllLeases()
        let newLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: newIdentity))

        oldLease.release()

        #expect(arbiter.snapshot.visiblePromoIdentities == [newIdentity])
        _ = newLease
    }

    @available(iOS 16, *)
    @Test("Invalidation clears all leases and leaves outstanding tokens inert", .timeLimit(.minutes(1)))
    func invalidationClearsLeasesAndLeavesOutstandingTokensInert() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let outstandingLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: makeVisiblePromoIdentity()))

        arbiter.invalidateAllLeases()

        #expect(!arbiter.snapshot.hasModalLease)
        #expect(arbiter.snapshot.visiblePromoIdentities.isEmpty)
        // The cleared slot is immediately re-acquirable and the outstanding token cannot clear what replaced it.
        let modalLease = try acquiredLease(from: arbiter.acquireModalLease())
        outstandingLease.release()
        #expect(arbiter.snapshot.modalAttemptIdentity == modalLease.attemptIdentity)
    }

    @available(iOS 16, *)
    @Test("An old token cannot release a re-acquisition of its own identity after invalidation", .timeLimit(.minutes(1)))
    func oldVisiblePromoTokenCannotReleaseReacquisitionOfSameIdentity() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let identity = makeVisiblePromoIdentity()
        let oldLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: identity))
        arbiter.invalidateAllLeases()
        let currentLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: identity))

        oldLease.release()

        #expect(arbiter.snapshot.visiblePromoIdentities == [identity])
        _ = currentLease
    }

    @available(iOS 16, *)
    @Test("A dropped visible promo token stops blocking modal acquisition", .timeLimit(.minutes(1)))
    func droppedVisiblePromoTokenStopsBlockingModalAcquisition() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let identity = makeVisiblePromoIdentity()
        do {
            let droppedLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: identity))
            #expect(arbiter.snapshot.visiblePromoIdentities == [identity])
            _ = droppedLease
        }

        // The token left scope without `release()`, which must not wedge the modal slot for the rest of the session.
        #expect(arbiter.snapshot.visiblePromoIdentities.isEmpty)
        let modalLease = try acquiredLease(from: arbiter.acquireModalLease())
        #expect(arbiter.snapshot.modalAttemptIdentity == modalLease.attemptIdentity)
        _ = modalLease
    }

    @available(iOS 16, *)
    @Test("A dropped modal token stops blocking visible promo acquisition", .timeLimit(.minutes(1)))
    func droppedModalTokenStopsBlockingVisiblePromoAcquisition() throws {
        let arbiter = PromoQueueLeaseArbiter()
        do {
            let droppedLease = try acquiredLease(from: arbiter.acquireModalLease())
            #expect(arbiter.snapshot.hasModalLease)
            _ = droppedLease
        }

        let identity = makeVisiblePromoIdentity()
        let visibleLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: identity))

        #expect(!arbiter.snapshot.hasModalLease)
        #expect(arbiter.snapshot.visiblePromoIdentities == [identity])
        _ = visibleLease
    }

    @Test("A new process-scoped arbiter starts empty")
    func newProcessScopedArbiterStartsWithoutInheritedLeases() throws {
        let previousProcessArbiter = PromoQueueLeaseArbiter()
        _ = try acquiredLease(
            from: previousProcessArbiter.acquireVisiblePromoLease(
                for: makeVisiblePromoIdentity()
            )
        )

        let newProcessArbiter = PromoQueueLeaseArbiter()

        #expect(previousProcessArbiter.snapshot.visiblePromoCount == 1)
        #expect(!newProcessArbiter.snapshot.hasModalLease)
        #expect(newProcessArbiter.snapshot.visiblePromoIdentities.isEmpty)
    }

    private func makeVisiblePromoIdentity(
        surfaceID: UUID = UUID(),
        promoID: String = "message"
    ) -> VisiblePromoIdentity {
        VisiblePromoIdentity(
            surfaceID: surfaceID,
            promoType: .remoteMessage,
            promoID: promoID
        )
    }

    private func acquiredLease(
        from result: PromoQueueModalLeaseAcquisitionResult
    ) throws -> PromoQueueModalLease {
        guard case .acquired(let lease) = result else {
            throw TestError.expectedAcquiredLease
        }
        return lease
    }

    private func acquiredLease(
        from result: PromoQueueVisiblePromoLeaseAcquisitionResult
    ) throws -> PromoQueueVisiblePromoLease {
        guard case .acquired(let lease) = result else {
            throw TestError.expectedAcquiredLease
        }
        return lease
    }
}

private enum TestError: Error {
    case expectedAcquiredLease
}
