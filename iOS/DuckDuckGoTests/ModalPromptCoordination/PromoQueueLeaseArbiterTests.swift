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

    @Test("Modal lease can be acquired from idle")
    func acquireModalLeaseFromIdle() throws {
        let arbiter = PromoQueueLeaseArbiter()

        let lease = try acquiredLease(from: arbiter.acquireModalLease())

        #expect(arbiter.snapshot.hasModalLease)
        #expect(arbiter.snapshot.modalAttemptIdentity == lease.attemptIdentity)
        #expect(arbiter.snapshot.visiblePromoIdentities.isEmpty)
    }

    @Test("Visible promo lease can be acquired from idle")
    func acquireVisiblePromoLeaseFromIdle() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let identity = makeVisiblePromoIdentity()

        _ = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: identity))

        #expect(!arbiter.snapshot.hasModalLease)
        #expect(arbiter.snapshot.visiblePromoIdentities == [identity])
    }

    @Test("Visible promos block modal acquisition with their identities")
    func visiblePromosBlockModalAcquisition() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let firstIdentity = makeVisiblePromoIdentity(promoID: "first")
        let secondIdentity = makeVisiblePromoIdentity(promoID: "second")
        _ = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: firstIdentity))
        _ = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: secondIdentity))

        let result = arbiter.acquireModalLease()

        guard case .blockedByVisiblePromos(let identities) = result else {
            Issue.record("Expected modal acquisition to be blocked by visible promos")
            return
        }
        #expect(identities == [firstIdentity, secondIdentity])
        #expect(!arbiter.snapshot.hasModalLease)
    }

    @Test("Modal lease blocks visible promo acquisition")
    func modalLeaseBlocksVisiblePromoAcquisition() throws {
        let arbiter = PromoQueueLeaseArbiter()
        _ = try acquiredLease(from: arbiter.acquireModalLease())

        let result = arbiter.acquireVisiblePromoLease(for: makeVisiblePromoIdentity())

        guard case .blockedByModal = result else {
            Issue.record("Expected visible promo acquisition to be blocked by the modal")
            return
        }
        #expect(arbiter.snapshot.visiblePromoIdentities.isEmpty)
    }

    @Test("Existing modal lease blocks another modal acquisition")
    func modalLeaseBlocksAnotherModalAcquisition() throws {
        let arbiter = PromoQueueLeaseArbiter()
        _ = try acquiredLease(from: arbiter.acquireModalLease())

        let result = arbiter.acquireModalLease()

        guard case .blockedByModal = result else {
            Issue.record("Expected modal acquisition to be blocked by the existing modal")
            return
        }
        #expect(arbiter.snapshot.hasModalLease)
    }

    @Test("The same visible promo can hold leases on different surfaces")
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

        _ = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: firstIdentity))
        _ = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: secondIdentity))

        #expect(arbiter.snapshot.visiblePromoIdentities == [firstIdentity, secondIdentity])
        #expect(arbiter.snapshot.visiblePromoCount == 2)
    }

    @Test("A surface and promo type slot cannot hold two messages")
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
        _ = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: firstIdentity))

        let result = arbiter.acquireVisiblePromoLease(for: secondIdentity)

        guard case .occupiedSurfaceSlot(let occupyingIdentity) = result else {
            Issue.record("Expected visible promo acquisition to be blocked by the occupied surface slot")
            return
        }
        #expect(occupyingIdentity == firstIdentity)
        #expect(arbiter.snapshot.visiblePromoIdentities == [firstIdentity])
    }

    @Test("The same message cannot acquire its occupied surface slot twice")
    func visiblePromoCannotAcquireOccupiedSlotTwice() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let identity = makeVisiblePromoIdentity()
        _ = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: identity))

        let result = arbiter.acquireVisiblePromoLease(for: identity)

        guard case .occupiedSurfaceSlot(let occupyingIdentity) = result else {
            Issue.record("Expected duplicate visible promo acquisition to be blocked by the occupied surface slot")
            return
        }
        #expect(occupyingIdentity == identity)
        #expect(arbiter.snapshot.visiblePromoCount == 1)
    }

    @Test("Releasing one visible promo does not release another")
    func releasingVisiblePromoDoesNotReleaseAnother() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let firstIdentity = makeVisiblePromoIdentity(promoID: "first")
        let secondIdentity = makeVisiblePromoIdentity(promoID: "second")
        let firstLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: firstIdentity))
        _ = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: secondIdentity))

        firstLease.release()

        #expect(arbiter.snapshot.visiblePromoIdentities == [secondIdentity])
    }

    @Test("Releasing a modal lease more than once is harmless")
    func duplicateModalReleaseIsHarmless() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let lease = try acquiredLease(from: arbiter.acquireModalLease())

        lease.release()
        lease.release()

        #expect(!arbiter.snapshot.hasModalLease)
        _ = try acquiredLease(from: arbiter.acquireModalLease())
        #expect(arbiter.snapshot.hasModalLease)
    }

    @Test("Releasing a visible promo lease more than once is harmless")
    func duplicateVisiblePromoReleaseIsHarmless() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let identity = makeVisiblePromoIdentity()
        let lease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: identity))

        lease.release()
        lease.release()

        #expect(arbiter.snapshot.visiblePromoIdentities.isEmpty)
        _ = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: identity))
        #expect(arbiter.snapshot.visiblePromoIdentities == [identity])
    }

    @Test("A released token cannot release a newer lease for the same slot")
    func staleVisiblePromoReleaseDoesNotReleaseNewLease() throws {
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
        firstLease.release()
        _ = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: secondIdentity))

        firstLease.release()

        #expect(arbiter.snapshot.visiblePromoIdentities == [secondIdentity])
    }

    @Test("Old modal token cannot release a lease acquired after invalidation")
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

    @Test("Old visible promo token cannot release a lease acquired after invalidation")
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
        _ = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: newIdentity))

        oldLease.release()

        #expect(arbiter.snapshot.visiblePromoIdentities == [newIdentity])
    }

    @Test("Invalidation advances generation and clears all leases")
    func invalidationAdvancesGenerationAndClearsLeases() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let initialGeneration = arbiter.snapshot.generation
        _ = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: makeVisiblePromoIdentity()))

        arbiter.invalidateAllLeases()

        #expect(arbiter.snapshot.generation != initialGeneration)
        #expect(!arbiter.snapshot.hasModalLease)
        #expect(arbiter.snapshot.visiblePromoIdentities.isEmpty)
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

    private func acquiredLease<Lease>(
        from result: PromoQueueLeaseAcquisitionResult<Lease>
    ) throws -> Lease {
        guard case .acquired(let lease) = result else {
            throw TestError.expectedAcquiredLease
        }
        return lease
    }
}

private enum TestError: Error {
    case expectedAcquiredLease
}
