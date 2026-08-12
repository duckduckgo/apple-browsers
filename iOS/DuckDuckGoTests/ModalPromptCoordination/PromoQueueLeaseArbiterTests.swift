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
        #expect(arbiter.snapshot.remoteMessageSession == nil)
    }

    @available(iOS 16, *)
    @Test("Logical remote-message lease can be acquired from idle", .timeLimit(.minutes(1)))
    func acquireRemoteMessageLeaseFromIdle() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let session = makeRemoteMessageSession()

        let lease = try acquiredLease(from: arbiter.acquireRemoteMessageLease(for: session))

        #expect(!arbiter.snapshot.hasModalLease)
        #expect(arbiter.snapshot.activeOwner == .remoteMessage(session))
        #expect(arbiter.snapshot.remoteMessageSession == session)
        _ = lease
    }

    @available(iOS 16, *)
    @Test("Logical owner identity consists of message and session", .timeLimit(.minutes(1)))
    func logicalOwnerIdentityUsesMessageAndSession() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let sessionID = UUID()
        let session = makeRemoteMessageSession(sessionID: sessionID, messageID: "message")
        let lease = try acquiredLease(from: arbiter.acquireRemoteMessageLease(for: session))

        #expect(arbiter.snapshot.remoteMessageSession?.id == sessionID)
        #expect(arbiter.snapshot.remoteMessageSession?.messageID == "message")
        _ = lease
    }

    @available(iOS 16, *)
    @Test("Logical remote message blocks modal acquisition with its session", .timeLimit(.minutes(1)))
    func remoteMessageBlocksModalAcquisition() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let session = makeRemoteMessageSession()
        let lease = try acquiredLease(from: arbiter.acquireRemoteMessageLease(for: session))

        let result = arbiter.acquireModalLease()

        guard case .blockedByRemoteMessage(let occupyingSession) = result else {
            Issue.record("Expected modal acquisition to be blocked by the logical remote message")
            return
        }
        #expect(occupyingSession == session)
        #expect(!arbiter.snapshot.hasModalLease)
        _ = lease
    }

    @available(iOS 16, *)
    @Test("Modal lease blocks logical remote-message acquisition", .timeLimit(.minutes(1)))
    func modalLeaseBlocksRemoteMessageAcquisition() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let modalLease = try acquiredLease(from: arbiter.acquireModalLease())

        let result = arbiter.acquireRemoteMessageLease(for: makeRemoteMessageSession())

        guard case .blockedByModal(let attemptIdentity) = result else {
            Issue.record("Expected logical remote-message acquisition to be blocked by the modal")
            return
        }
        #expect(attemptIdentity == modalLease.attemptIdentity)
        #expect(arbiter.snapshot.remoteMessageSession == nil)
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
    @Test("A logical remote message blocks another logical session", .timeLimit(.minutes(1)))
    func remoteMessageBlocksAnotherLogicalSession() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let firstSession = makeRemoteMessageSession(messageID: "first")
        let secondSession = makeRemoteMessageSession(messageID: "second")
        let firstLease = try acquiredLease(from: arbiter.acquireRemoteMessageLease(for: firstSession))

        let result = arbiter.acquireRemoteMessageLease(for: secondSession)

        guard case .blockedByRemoteMessage(let occupyingSession) = result else {
            Issue.record("Expected the global logical owner to block another remote-message session")
            return
        }
        #expect(occupyingSession == firstSession)
        #expect(arbiter.snapshot.activeOwner == .remoteMessage(firstSession))
        _ = firstLease
    }

    @available(iOS 16, *)
    @Test("Releasing the logical owner permits a different logical acquisition", .timeLimit(.minutes(1)))
    func releasingRemoteMessageOwnerPermitsDifferentAcquisition() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let firstSession = makeRemoteMessageSession(messageID: "first")
        let secondSession = makeRemoteMessageSession(messageID: "second")
        let firstLease = try acquiredLease(from: arbiter.acquireRemoteMessageLease(for: firstSession))

        #expect(firstLease.release())
        let secondLease = try acquiredLease(from: arbiter.acquireRemoteMessageLease(for: secondSession))

        #expect(arbiter.snapshot.activeOwner == .remoteMessage(secondSession))
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
    @Test("A stale remote-message lease cannot release its same-message replacement", .timeLimit(.minutes(1)))
    func staleRemoteMessageReleaseCannotClearReplacement() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let firstSession = makeRemoteMessageSession(messageID: "message")
        let replacementSession = makeRemoteMessageSession(messageID: "message")
        let firstLease = try acquiredLease(from: arbiter.acquireRemoteMessageLease(for: firstSession))

        #expect(firstLease.release())
        let replacementLease = try acquiredLease(from: arbiter.acquireRemoteMessageLease(for: replacementSession))

        #expect(!firstLease.release())
        #expect(arbiter.snapshot.activeOwner == .remoteMessage(replacementSession))
        _ = replacementLease
    }

    @available(iOS 16, *)
    @Test("A dropped remote-message token stops blocking modal acquisition", .timeLimit(.minutes(1)))
    func droppedRemoteMessageTokenStopsBlockingModalAcquisition() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let session = makeRemoteMessageSession()
        do {
            let droppedLease = try acquiredLease(from: arbiter.acquireRemoteMessageLease(for: session))
            #expect(arbiter.snapshot.activeOwner == .remoteMessage(session))
            _ = droppedLease
        }

        #expect(arbiter.snapshot.activeOwner == nil)
        let modalLease = try acquiredLease(from: arbiter.acquireModalLease())
        #expect(arbiter.snapshot.activeOwner == .modal(modalLease.attemptIdentity))
        _ = modalLease
    }

    @available(iOS 16, *)
    @Test("A dropped modal token stops blocking remote-message acquisition", .timeLimit(.minutes(1)))
    func droppedModalTokenStopsBlockingRemoteMessageAcquisition() throws {
        let arbiter = PromoQueueLeaseArbiter()
        do {
            let droppedLease = try acquiredLease(from: arbiter.acquireModalLease())
            #expect(arbiter.snapshot.hasModalLease)
            _ = droppedLease
        }

        let session = makeRemoteMessageSession()
        let remoteMessageLease = try acquiredLease(from: arbiter.acquireRemoteMessageLease(for: session))

        #expect(arbiter.snapshot.activeOwner == .remoteMessage(session))
        _ = remoteMessageLease
    }

    private func makeRemoteMessageSession(
        sessionID: UUID = UUID(),
        messageID: String = "message"
    ) -> PromoQueueRemoteMessageSession {
        PromoQueueRemoteMessageSession(id: sessionID, messageID: messageID)
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
        from result: PromoQueueRemoteMessageLeaseAcquisitionResult
    ) throws -> PromoQueueRemoteMessageLease {
        guard case .acquired(let lease) = result else {
            throw TestError.expectedAcquiredLease
        }
        return lease
    }
}

private enum TestError: Error {
    case expectedAcquiredLease
}
