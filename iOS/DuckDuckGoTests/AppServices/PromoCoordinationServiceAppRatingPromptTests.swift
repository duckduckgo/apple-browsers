//
//  PromoCoordinationServiceAppRatingPromptTests.swift
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
final class MockAppRatingPromptCoordinator: AppRatingPromptCoordinating {
    var isCoordinationEnabled = true
    var uncoordinatedDecision = false
    var unredeemedSlotCount = 0

    private(set) var registerUsageCallCount = 0
    private(set) var didRequestRatingCallCount = 0
    private(set) var resetForDebugCallCount = 0

    func registerUsage() { registerUsageCallCount += 1 }
    func shouldRequestUncoordinated() -> Bool { uncoordinatedDecision }
    func didRequestRating() { didRequestRatingCallCount += 1 }
    func resetForDebug() {
        resetForDebugCallCount += 1
        unredeemedSlotCount = 0
    }
}

@MainActor
@Suite("Promo Coordination - App Rating Prompt")
final class PromoCoordinationServiceAppRatingPromptTests {
    private let launchSourceManager = MockLaunchSourceManager()
    private let manager = MockModalPromptCoordinationManager()
    private let presenter = MockModalPromptPresenter()
    private let arbiter = PromoQueueLeaseArbiter()
    private let cooldownPolicy = MockPromoQueueCooldownPolicy()
    private let ratingCoordinator = MockAppRatingPromptCoordinator()

    init() {
        launchSourceManager.source = .standard
        presenter.presentedViewController = nil
    }

    // MARK: - Usage registration

    @available(iOS 16, *)
    @Test("Page loads are registered regardless of coordination", .timeLimit(.minutes(1)))
    func registersUsageRegardlessOfCoordination() {
        ratingCoordinator.isCoordinationEnabled = false
        let service = makeService(mode: .coordinated)

        service.registerAppRatingPromptUsage()

        #expect(ratingCoordinator.registerUsageCallCount == 1)
        // Recording usage must not reach the queue or consume eligibility.
        #expect(manager.redeemDeferredModalCallCount == 0)
        #expect(ratingCoordinator.didRequestRatingCallCount == 0)
    }

    // MARK: - Coordinated path

    @available(iOS 16, *)
    @Test("A search redeems a held slot", .timeLimit(.minutes(1)))
    func searchRedeemsHeldSlot() {
        manager.redeemDeferredModalResult = true
        let service = makeService(mode: .coordinated)

        #expect(service.shouldRequestAppRatingPrompt())
        #expect(manager.redeemDeferredModalCallCount == 1)
        // Asking is not requesting: eligibility is consumed only when the caller reports back.
        #expect(ratingCoordinator.didRequestRatingCallCount == 0)
    }

    @available(iOS 16, *)
    @Test("A search with no held slot does not request the dialog", .timeLimit(.minutes(1)))
    func searchWithoutHeldSlotDoesNothing() {
        manager.redeemDeferredModalResult = false
        ratingCoordinator.uncoordinatedDecision = true
        let service = makeService(mode: .coordinated)

        #expect(!service.shouldRequestAppRatingPrompt())
        #expect(ratingCoordinator.didRequestRatingCallCount == 0)
    }

    // MARK: - Uncoordinated path

    @available(iOS 16, *)
    @Test("With coordination off an eligible prompt is requested directly", .timeLimit(.minutes(1)))
    func coordinationOffRequestsDirectly() {
        ratingCoordinator.isCoordinationEnabled = false
        ratingCoordinator.uncoordinatedDecision = true
        let service = makeService(mode: .coordinated)

        #expect(service.shouldRequestAppRatingPrompt())
        #expect(manager.redeemDeferredModalCallCount == 0)
        #expect(ratingCoordinator.didRequestRatingCallCount == 0)
    }

    // MARK: - Backgrounding

    @available(iOS 16, *)
    @Test("Backgrounding releases a held slot", .timeLimit(.minutes(1)))
    func backgroundingReleasesHeldSlot() {
        let service = makeService(mode: .coordinated)

        service.handleAppBackgrounded()

        #expect(manager.releaseDeferredModalCallCount == 1)
    }

    // MARK: - Debug reset

    @available(iOS 16, *)
    @Test("The debug reset frees the slot before clearing the count", .timeLimit(.minutes(1)))
    func debugResetFreesSlotBeforeClearingCount() {
        let service = makeService(mode: .coordinated)

        service.resetAppRatingPrompt()

        // Releasing bumps the unredeemed count through the provider, so the reset has to run after
        // it to leave the count at zero.
        #expect(manager.releaseDeferredModalCallCount == 1)
        #expect(ratingCoordinator.resetForDebugCallCount == 1)
        #expect(ratingCoordinator.unredeemedSlotCount == 0)
    }

    private func makeService(mode: PromoCoordinationMode) -> PromoCoordinationService {
        PromoCoordinationService(
            launchSourceManager: launchSourceManager,
            modalPromptCoordinationManager: manager,
            mode: mode,
            promoQueueLeaseArbiter: arbiter,
            promoQueueCooldownPolicy: cooldownPolicy,
            appRatingPromptCoordinator: ratingCoordinator
        )
    }
}
