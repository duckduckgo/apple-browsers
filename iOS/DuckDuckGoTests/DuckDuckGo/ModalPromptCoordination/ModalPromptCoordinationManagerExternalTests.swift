//
//  ModalPromptCoordinationManagerExternalTests.swift
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
import UIKit
@testable import DuckDuckGo

@MainActor
@Suite("Modal Prompt Coordination - External Promos")
final class ModalPromptCoordinationManagerExternalTests {
    private let cooldownManagerMock = MockPromptCooldownManager()
    private let schedulerMock = MockModalPromptScheduler()
    private let presenterMock = MockModalPromptPresenter()
    private let arbiter = PromoQueueLeaseArbiter()
    private let exposureReporter = MockPromptExposureReporter()

    init() {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
    }

    // MARK: - Taking the slot

    @available(iOS 16, *)
    @Test("An external provider holds the slot while it presents its own UI", .timeLimit(.minutes(1)))
    func externalProviderHoldsSlotWhilePresenting() throws {
        let provider = makeExternalProvider(isEligible: true)
        let sut = makeManager(providers: [provider])
        let lease = try acquiredModalLease()

        sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(provider.presentExternalPromptCallCount == 1)
        #expect(!provider.didCallProvideModalPrompt)
        #expect(!presenterMock.didCallPresent)
        #expect(!schedulerMock.didCallSchedule)
        #expect(!cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
        #expect(sut.modalAttemptPhase == .external(lease.ownershipIdentity))
        #expect(sut.hasActiveOrPendingModalAttempt)
        #expect(arbiter.snapshot.hasModalLease)
    }

    @available(iOS 16, *)
    @Test("An ineligible external provider yields to the next provider", .timeLimit(.minutes(1)))
    func ineligibleExternalProviderYields() throws {
        let externalProvider = makeExternalProvider(isEligible: false)
        let modalProvider = MockModalPromptProvider()
        modalProvider.isEligibleToPresentResult = true
        let sut = makeManager(providers: [externalProvider, modalProvider])
        let lease = try acquiredModalLease()

        sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(externalProvider.presentExternalPromptCallCount == 0)
        #expect(modalProvider.didCallProvideModalPrompt)
        #expect(sut.modalAttemptPhase == .committed(lease.ownershipIdentity))
    }

    @available(iOS 16, *)
    @Test("An external provider ahead of a modal provider wins the slot", .timeLimit(.minutes(1)))
    func externalProviderWinsOverLaterModalProvider() throws {
        let externalProvider = makeExternalProvider(isEligible: true)
        let modalProvider = MockModalPromptProvider()
        modalProvider.isEligibleToPresentResult = true
        let sut = makeManager(providers: [externalProvider, modalProvider])

        sut.presentModalPromptIfNeeded(from: presenterMock, with: try acquiredModalLease())

        #expect(externalProvider.presentExternalPromptCallCount == 1)
        #expect(!modalProvider.didCallProvideModalPrompt)
    }

    @available(iOS 16, *)
    @Test("An external provider is not selected during the cooldown", .timeLimit(.minutes(1)))
    func externalProviderIsNotSelectedDuringCooldown() throws {
        cooldownManagerMock.cooldownInfoToReturn = .inCoolDown
        let provider = makeExternalProvider(isEligible: true)
        let sut = makeManager(providers: [provider])

        sut.presentModalPromptIfNeeded(from: presenterMock, with: try acquiredModalLease())

        #expect(provider.presentExternalPromptCallCount == 0)
        #expect(sut.modalAttemptPhase == .idle)
        #expect(!arbiter.snapshot.hasModalLease)
    }

    // MARK: - Completing

    @available(iOS 16, *)
    @Test("A shown external prompt starts the cooldown, reports the exposure and frees the slot", .timeLimit(.minutes(1)))
    func shownExternalPromptStartsCooldownAndFreesSlot() throws {
        let provider = makeExternalProvider(isEligible: true)
        let sut = makeManager(providers: [provider])
        sut.presentModalPromptIfNeeded(from: presenterMock, with: try acquiredModalLease())

        provider.externalPromptCompletion?(.shown(.remoteMessageModal))

        #expect(cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
        #expect(provider.didCallDidPresentModal)
        #expect(exposureReporter.shownPrompts == [.remoteMessageModal])
        #expect(exposureReporter.shownCoordinatedPrompts == [.modal])
        #expect(sut.didActuallyPresentModalPromptThisSession)
        #expect(sut.modalAttemptPhase == .idle)
        #expect(!arbiter.snapshot.hasModalLease)
    }

    @available(iOS 16, *)
    @Test("An external prompt that was not shown frees the slot without a cooldown", .timeLimit(.minutes(1)))
    func notShownExternalPromptFreesSlotWithoutCooldown() throws {
        let provider = makeExternalProvider(isEligible: true)
        let sut = makeManager(providers: [provider])
        sut.presentModalPromptIfNeeded(from: presenterMock, with: try acquiredModalLease())

        provider.externalPromptCompletion?(.notShown)

        #expect(!cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
        #expect(!provider.didCallDidPresentModal)
        #expect(exposureReporter.shownPrompts.isEmpty)
        #expect(!sut.didPresentModalPromptThisSession)
        #expect(sut.modalAttemptPhase == .idle)
        #expect(!arbiter.snapshot.hasModalLease)
    }

    @available(iOS 16, *)
    @Test("A completion that arrives after the attempt ended changes nothing", .timeLimit(.minutes(1)))
    func lateCompletionChangesNothing() throws {
        let provider = makeExternalProvider(isEligible: true)
        let sut = makeManager(providers: [provider])
        sut.presentModalPromptIfNeeded(from: presenterMock, with: try acquiredModalLease())
        provider.externalPromptCompletion?(.notShown)

        provider.externalPromptCompletion?(.shown(.remoteMessageModal))

        #expect(!cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
        #expect(exposureReporter.shownPrompts.isEmpty)
    }

    // MARK: - Close handler

    @available(iOS 16, *)
    @Test("A close handler waits for an external prompt to complete", .timeLimit(.minutes(1)))
    func closeHandlerWaitsForExternalPrompt() throws {
        let provider = makeExternalProvider(isEligible: true)
        let sut = makeManager(providers: [provider])
        sut.presentModalPromptIfNeeded(from: presenterMock, with: try acquiredModalLease())

        #expect(sut.runOnceModalPromptCloses {})

        provider.externalPromptCompletion?(.notShown)

        #expect(!sut.runOnceModalPromptCloses {})
    }

    // MARK: - Legacy route

    @available(iOS 16, *)
    @Test("An external provider is presented and completed on the legacy route", .timeLimit(.minutes(1)))
    func externalProviderWorksOnLegacyRoute() {
        let provider = makeExternalProvider(isEligible: true)
        let sut = makeManager(providers: [provider])

        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(provider.presentExternalPromptCallCount == 1)
        #expect(sut.hasActiveOrPendingModalAttempt)

        provider.externalPromptCompletion?(.shown(.remoteMessageModal))

        #expect(cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
        #expect(exposureReporter.shownPrompts == [.remoteMessageModal])
        #expect(exposureReporter.shownCoordinatedPrompts.isEmpty)
        #expect(!sut.hasActiveOrPendingModalAttempt)
    }

    // MARK: - Helpers

    private func makeExternalProvider(isEligible: Bool) -> MockModalPromptProvider {
        let provider = MockModalPromptProvider(shouldReturnPrompt: false)
        provider.presentationKindToReturn = .external
        provider.isEligibleToPresentResult = isEligible
        return provider
    }

    private func makeManager(providers: [any ModalPromptProvider]) -> ModalPromptCoordinationManager {
        ModalPromptCoordinationManager(
            providers: providers,
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            modalPromptScheduling: schedulerMock,
            closeCheckScheduling: schedulerMock,
            promptExposureReporter: exposureReporter
        )
    }

    private func acquiredModalLease() throws -> PromoQueueModalLease {
        guard case .acquired(let lease) = arbiter.acquireModalLease() else {
            throw ExternalPromoTestError.expectedAcquiredLease
        }
        return lease
    }
}

private enum ExternalPromoTestError: Error {
    case expectedAcquiredLease
}
