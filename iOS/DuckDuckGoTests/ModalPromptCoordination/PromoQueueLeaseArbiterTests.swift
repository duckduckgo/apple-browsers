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

import Testing
@testable import DuckDuckGo

@MainActor
@Suite("Promo Queue Lease Arbiter")
struct PromoQueueLeaseArbiterTests {

    @available(iOS 16, *)
    @Test("Modal and remote-message leases are mutually exclusive", .timeLimit(.minutes(1)))
    func crossKindMutualExclusion() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let modalLease = try acquiredModalLease(from: arbiter.acquireModalLease())

        guard case .blockedByModal = arbiter.acquireRemoteMessageLease(for: "message") else {
            Issue.record("Expected the modal owner to block a remote message")
            return
        }

        modalLease.release()
        let remoteMessageLease = try acquiredRemoteMessageLease(from: arbiter.acquireRemoteMessageLease(for: "message"))
        guard case .blockedByRemoteMessage(messageID: "message") = arbiter.acquireModalLease() else {
            Issue.record("Expected the remote-message owner to block a modal")
            return
        }
        _ = remoteMessageLease
    }

    @available(iOS 16, *)
    @Test("Release is idempotent and cannot release a replacement", .timeLimit(.minutes(1)))
    func identitySafeIdempotentRelease() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let firstLease = try acquiredRemoteMessageLease(from: arbiter.acquireRemoteMessageLease(for: "first"))

        firstLease.release()
        firstLease.release()
        let replacementLease = try acquiredRemoteMessageLease(from: arbiter.acquireRemoteMessageLease(for: "replacement"))
        firstLease.release()

        #expect(
            arbiter.snapshot.owner == .remoteMessage(
                messageID: "replacement",
                acquisitionIdentity: replacementLease.acquisitionIdentity,
                appearanceConfirmed: false
            )
        )
        _ = replacementLease
    }

    @available(iOS 16, *)
    @Test("A deallocated token relinquishes ownership", .timeLimit(.minutes(1)))
    func weakTokenRecovery() throws {
        let arbiter = PromoQueueLeaseArbiter()

        do {
            let droppedLease = try acquiredRemoteMessageLease(from: arbiter.acquireRemoteMessageLease(for: "message"))
            #expect(
                arbiter.snapshot.owner == .remoteMessage(
                    messageID: "message",
                    acquisitionIdentity: droppedLease.acquisitionIdentity,
                    appearanceConfirmed: false
                )
            )
            _ = droppedLease
        }

        #expect(arbiter.snapshot.owner == nil)
        let modalLease = try acquiredModalLease(from: arbiter.acquireModalLease())
        #expect(arbiter.snapshot.owner == .modal(ownershipIdentity: modalLease.ownershipIdentity))
    }

    @available(iOS 16, *)
    @Test("Only the first valid appearance confirmation succeeds", .timeLimit(.minutes(1)))
    func firstValidAppearanceConfirmation() throws {
        let arbiter = PromoQueueLeaseArbiter()
        let lease = try acquiredRemoteMessageLease(from: arbiter.acquireRemoteMessageLease(for: "message"))

        #expect(lease.confirmAppearance())
        #expect(!lease.confirmAppearance())
        #expect(
            arbiter.snapshot.owner == .remoteMessage(
                messageID: "message",
                acquisitionIdentity: lease.acquisitionIdentity,
                appearanceConfirmed: true
            )
        )

        lease.release()
        #expect(!lease.confirmAppearance())
        #expect(arbiter.snapshot.owner == nil)
    }

    private func acquiredModalLease(from result: PromoQueueModalLeaseAcquisitionResult) throws -> PromoQueueModalLease {
        guard case .acquired(let lease) = result else {
            throw TestError.expectedAcquiredLease
        }
        return lease
    }

    private func acquiredRemoteMessageLease(
        from result: PromoQueueRemoteMessageLeaseAcquisitionResult
    ) throws -> PromoQueueRemoteMessageArbiterLease {
        guard case .acquired(let lease) = result else {
            throw TestError.expectedAcquiredLease
        }
        return lease
    }
}

private enum TestError: Error {
    case expectedAcquiredLease
}
