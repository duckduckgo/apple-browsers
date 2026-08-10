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
        #expect(arbiter.snapshot.activeOwner == .modal(lease.attemptIdentity))
        #expect(arbiter.snapshot.visiblePromoIdentity == nil)
    }

    @available(iOS 16, *)
    @Test("Visible promo lease can be acquired from idle", .timeLimit(.minutes(1)))
    func acquireVisiblePromoLeaseFromIdle() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let identity = makeVisiblePromoIdentity()

        let lease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: identity))

        #expect(!arbiter.snapshot.hasModalLease)
        #expect(arbiter.snapshot.activeOwner == .visible(identity))
        _ = lease
    }

    @available(iOS 16, *)
    @Test("Visible promo blocks modal acquisition with its identity", .timeLimit(.minutes(1)))
    func visiblePromoBlocksModalAcquisition() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let identity = makeVisiblePromoIdentity()
        let lease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: identity))

        let result = arbiter.acquireModalLease()

        guard case .blockedByVisiblePromo(let occupyingIdentity) = result else {
            Issue.record("Expected modal acquisition to be blocked by the visible promo")
            return
        }
        #expect(occupyingIdentity == identity)
        #expect(!arbiter.snapshot.hasModalLease)
        _ = lease
    }

    @available(iOS 16, *)
    @Test("Modal lease blocks visible promo acquisition", .timeLimit(.minutes(1)))
    func modalLeaseBlocksVisiblePromoAcquisition() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let modalLease = try acquiredLease(from: arbiter.acquireModalLease())

        let result = arbiter.acquireVisiblePromoLease(for: makeVisiblePromoIdentity())

        guard case .blockedByModal(let attemptIdentity) = result else {
            Issue.record("Expected visible promo acquisition to be blocked by the modal")
            return
        }
        #expect(attemptIdentity == modalLease.attemptIdentity)
        #expect(arbiter.snapshot.visiblePromoIdentity == nil)
        _ = modalLease
    }

    @available(iOS 16, *)
    @Test("Existing modal lease blocks another modal acquisition", .timeLimit(.minutes(1)))
    func modalLeaseBlocksAnotherModalAcquisition() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let modalLease = try acquiredLease(from: arbiter.acquireModalLease())

        let result = arbiter.acquireModalLease()

        guard case .blockedByModal(let attemptIdentity) = result else {
            Issue.record("Expected modal acquisition to be blocked by the existing modal")
            return
        }
        #expect(attemptIdentity == modalLease.attemptIdentity)
        #expect(arbiter.snapshot.hasModalLease)
        _ = modalLease
    }

    @available(iOS 16, *)
    @Test("A visible promo blocks a different promo on a different surface", .timeLimit(.minutes(1)))
    func visiblePromoBlocksDifferentPromoOnDifferentSurface() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let firstIdentity = makeVisiblePromoIdentity(surfaceID: UUID(), promoID: "first")
        let secondIdentity = makeVisiblePromoIdentity(surfaceID: UUID(), promoID: "second")
        let firstLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: firstIdentity))

        let result = arbiter.acquireVisiblePromoLease(for: secondIdentity)

        guard case .blockedByVisiblePromo(let occupyingIdentity) = result else {
            Issue.record("Expected the global visible owner to block every other surface and promo")
            return
        }
        #expect(occupyingIdentity == firstIdentity)
        #expect(arbiter.snapshot.activeOwner == .visible(firstIdentity))
        _ = firstLease
    }

    @available(iOS 16, *)
    @Test("Releasing the visible owner permits a different visible acquisition", .timeLimit(.minutes(1)))
    func releasingVisibleOwnerPermitsDifferentVisibleAcquisition() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let firstIdentity = makeVisiblePromoIdentity(promoID: "first")
        let secondIdentity = makeVisiblePromoIdentity(promoID: "second")
        let firstLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: firstIdentity))

        #expect(firstLease.release())
        let secondLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: secondIdentity))

        #expect(arbiter.snapshot.activeOwner == .visible(secondIdentity))
        _ = secondLease
    }

    @available(iOS 16, *)
    @Test("Releasing a modal lease more than once is harmless", .timeLimit(.minutes(1)))
    func duplicateModalReleaseIsHarmless() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let lease = try acquiredLease(from: arbiter.acquireModalLease())

        lease.release()
        let reacquiredLease = try acquiredLease(from: arbiter.acquireModalLease())

        lease.release()

        #expect(arbiter.snapshot.activeOwner == .modal(reacquiredLease.attemptIdentity))
        _ = reacquiredLease
    }

    @available(iOS 16, *)
    @Test("Releasing a visible promo lease more than once is harmless", .timeLimit(.minutes(1)))
    func duplicateVisiblePromoReleaseIsHarmless() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let identity = makeVisiblePromoIdentity()
        let lease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: identity))

        #expect(lease.release())
        let reacquiredLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: identity))

        #expect(!lease.release())
        #expect(arbiter.snapshot.activeOwner == .visible(identity))
        _ = reacquiredLease
    }

    @available(iOS 16, *)
    @Test("A dropped visible promo token stops blocking modal acquisition", .timeLimit(.minutes(1)))
    func droppedVisiblePromoTokenStopsBlockingModalAcquisition() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let identity = makeVisiblePromoIdentity()
        do {
            let droppedLease = try acquiredLease(from: arbiter.acquireVisiblePromoLease(for: identity))
            #expect(arbiter.snapshot.activeOwner == .visible(identity))
            _ = droppedLease
        }

        #expect(arbiter.snapshot.activeOwner == nil)
        let modalLease = try acquiredLease(from: arbiter.acquireModalLease())
        #expect(arbiter.snapshot.activeOwner == .modal(modalLease.attemptIdentity))
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

        #expect(arbiter.snapshot.activeOwner == .visible(identity))
        _ = visibleLease
    }

    private func makeVisiblePromoIdentity(
        surfaceID: UUID = UUID(),
        promoID: String = "message"
    ) -> VisiblePromoIdentity {
        VisiblePromoIdentity(surfaceID: surfaceID, promoType: .remoteMessage, promoID: promoID)
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
