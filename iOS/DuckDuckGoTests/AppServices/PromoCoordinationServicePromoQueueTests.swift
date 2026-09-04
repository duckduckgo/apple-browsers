//
//  PromoCoordinationServicePromoQueueTests.swift
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
@Suite("Promo Coordination - Service Promo Queue")
final class PromoCoordinationServicePromoQueueTests {
    private let launchSourceManager = MockLaunchSourceManager()
    private let manager = MockModalPromptCoordinationManager()
    private let presenter = MockModalPromptPresenter()
    private let arbiter = PromoQueueLeaseArbiter()
    private let cooldownPolicy = MockPromoQueueCooldownPolicy()

    init() {
        launchSourceManager.source = .standard
        presenter.presentedViewController = nil
    }

    @available(iOS 16, *)
    @Test("Coordinated modal admission acquires before manager evaluation", .timeLimit(.minutes(1)))
    func coordinatedModalAdmission() async {
        let service = makeService(mode: .coordinated)

        await service.presentModalPromptIfNeeded(from: presenter)

        #expect(manager.capturedModalLease != nil)
        #expect(arbiter.snapshot.hasModalLease)
        #expect(manager.reconcilePresentedModalCallCount == 1)
        #expect(cooldownPolicy.modalAdmissionCallCount == 1)
    }

    @available(iOS 16, *)
    @Test("Remote-message ownership blocks modal evaluation", .timeLimit(.minutes(1)))
    func remoteMessageBlocksModalEvaluation() async throws {
        let remoteMessageLease = try acquiredRemoteMessageLease(from: arbiter.acquireRemoteMessageLease(for: "message"))
        let service = makeService(mode: .coordinated)

        await service.presentModalPromptIfNeeded(from: presenter)

        #expect(!manager.didCallPresentModalPromptIfNeeded)
        #expect(cooldownPolicy.modalAdmissionCallCount == 0)
        #expect(
            arbiter.snapshot.owner == .remoteMessage(
                messageID: "message",
                acquisitionIdentity: remoteMessageLease.acquisitionIdentity,
                appearanceConfirmed: false
            )
        )
        _ = remoteMessageLease
    }

    @available(iOS 16, *)
    @Test("Legacy mode preserves the unarbitrated manager route", .timeLimit(.minutes(1)))
    func legacyModeUsesLegacyManagerRoute() async {
        let service = makeService(mode: .legacy)

        await service.presentModalPromptIfNeeded(from: presenter)

        #expect(manager.didCallPresentModalPromptIfNeeded)
        #expect(manager.capturedModalLease == nil)
        #expect(arbiter.snapshot.owner == nil)
        #expect(manager.reconcilePresentedModalCallCount == 0)
        #expect(cooldownPolicy.modalAdmissionCallCount == 0)
    }

    @available(iOS 16, *)
    @Test("The source gate reconciles modal attachment before RMF acquisition", .timeLimit(.minutes(1)))
    func sourceGateReconcilesBeforeAcquisition() throws {
        let service = makeService(mode: .coordinated)

        let lease = try #require(service.tryAcquireRemoteMessageLease(for: "message"))

        #expect(manager.reconcilePresentedModalCallCount == 1)
        #expect(lease.messageID == "message")
        #expect(cooldownPolicy.remoteMessageAdmissionCallCount == 1)
        #expect(
            arbiter.snapshot.owner == .remoteMessage(
                messageID: "message",
                acquisitionIdentity: lease.acquisitionIdentity,
                appearanceConfirmed: false
            )
        )
    }

    @available(iOS 16, *)
    @Test("RMF-to-modal cooldown releases before provider evaluation", .timeLimit(.minutes(1)))
    func remoteMessageCooldownBlocksModalEvaluation() async {
        cooldownPolicy.modalAdmissionDecision = .blocked(until: .distantFuture)
        let service = makeService(mode: .coordinated)

        await service.presentModalPromptIfNeeded(from: presenter)

        #expect(!manager.didCallPresentModalPromptIfNeeded)
        #expect(arbiter.snapshot.owner == nil)
        #expect(cooldownPolicy.modalAdmissionCallCount == 1)
    }

    @available(iOS 16, *)
    @Test("Incoming RMF cooldown releases its temporary acquisition", .timeLimit(.minutes(1)))
    func remoteMessageCooldownReleasesTemporaryLease() throws {
        cooldownPolicy.remoteMessageAdmissionDecision = .blocked(until: .distantFuture)
        let service = makeService(mode: .coordinated)

        #expect(service.tryAcquireRemoteMessageLease(for: "message") == nil)
        #expect(arbiter.snapshot.owner == nil)
        _ = try acquiredModalLease(from: arbiter.acquireModalLease())
    }

    @available(iOS 16, *)
    @Test("The service-owned RMF lease records only its first valid appearance", .timeLimit(.minutes(1)))
    func remoteMessageLeaseRecordsFirstAppearanceOnly() throws {
        let service = makeService(mode: .coordinated)
        let lease = try #require(service.tryAcquireRemoteMessageLease(for: "message"))

        #expect(lease.markShown())
        #expect(!lease.markShown())
        #expect(cooldownPolicy.recordConfirmedRemoteMessageAppearanceCallCount == 1)

        lease.release()
        #expect(!lease.markShown())
        #expect(cooldownPolicy.recordConfirmedRemoteMessageAppearanceCallCount == 1)
    }

    private func makeService(mode: PromoCoordinationMode) -> PromoCoordinationService {
        PromoCoordinationService(
            launchSourceManager: launchSourceManager,
            modalPromptCoordinationManager: manager,
            mode: mode,
            promoQueueLeaseArbiter: arbiter,
            promoQueueCooldownPolicy: cooldownPolicy
        )
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
