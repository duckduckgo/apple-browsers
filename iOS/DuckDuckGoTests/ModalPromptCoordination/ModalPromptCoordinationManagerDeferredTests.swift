//
//  ModalPromptCoordinationManagerDeferredTests.swift
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
@Suite("Modal Prompt Coordination - Deferred Promos")
final class ModalPromptCoordinationManagerDeferredTests {
    private let cooldownManagerMock = MockPromptCooldownManager()
    private let schedulerMock = MockModalPromptScheduler()
    private let presenterMock = MockModalPromptPresenter()
    private let arbiter = PromoQueueLeaseArbiter()

    init() {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
    }

    // MARK: - Taking the slot

    @available(iOS 16, *)
    @Test("A deferred provider holds the slot without presenting anything", .timeLimit(.minutes(1)))
    func deferredProviderHoldsSlotWithoutPresenting() throws {
        let provider = makeDeferredProvider(isEligible: true)
        let sut = makeManager(providers: [provider])
        let lease = try acquiredModalLease()

        sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(!schedulerMock.didCallSchedule)
        #expect(!presenterMock.didCallPresent)
        #expect(!provider.didCallProvideModalPrompt)
        #expect(!cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
        #expect(!provider.didCallDidPresentModal)
        #expect(sut.modalAttemptPhase == .deferred(lease.ownershipIdentity))
        #expect(arbiter.snapshot.hasModalLease)
    }

    @available(iOS 16, *)
    @Test("Holding the slot is not reported as a prompt the user saw", .timeLimit(.minutes(1)))
    func holdingSlotIsNotReportedAsPresented() throws {
        let sut = makeManager(providers: [makeDeferredProvider(isEligible: true)])
        let lease = try acquiredModalLease()

        sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(!sut.didActuallyPresentModalPromptThisSession)
        #expect(!sut.hasActiveOrPendingModalAttempt)
        #expect(!sut.didPresentModalPromptThisSession)
    }

    @available(iOS 16, *)
    @Test("An ineligible deferred provider yields to the next provider", .timeLimit(.minutes(1)))
    func ineligibleDeferredProviderYields() throws {
        let deferredProvider = makeDeferredProvider(isEligible: false)
        let modalProvider = MockModalPromptProvider()
        modalProvider.isEligibleToPresentResult = true
        let sut = makeManager(providers: [deferredProvider, modalProvider])
        let lease = try acquiredModalLease()

        sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(!deferredProvider.didCallProvideModalPrompt)
        #expect(modalProvider.didCallProvideModalPrompt)
        #expect(sut.modalAttemptPhase == .committed(lease.ownershipIdentity))
        #expect(!sut.redeemDeferredModal())
    }

    @available(iOS 16, *)
    @Test("A deferred provider ahead of a modal provider wins the slot", .timeLimit(.minutes(1)))
    func deferredProviderWinsOverLaterModalProvider() throws {
        let deferredProvider = makeDeferredProvider(isEligible: true)
        let modalProvider = MockModalPromptProvider()
        modalProvider.isEligibleToPresentResult = true
        let sut = makeManager(providers: [deferredProvider, modalProvider])
        let lease = try acquiredModalLease()

        sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(!modalProvider.didCallProvideModalPrompt)
        #expect(sut.modalAttemptPhase == .deferred(lease.ownershipIdentity))
    }

    @available(iOS 16, *)
    @Test("The modal cooldown blocks a deferred provider before it is evaluated", .timeLimit(.minutes(1)))
    func modalCooldownBlocksDeferredProvider() throws {
        cooldownManagerMock.cooldownInfoToReturn = .inCoolDown
        let provider = makeDeferredProvider(isEligible: true)
        let sut = makeManager(providers: [provider])
        let lease = try acquiredModalLease()

        sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(sut.modalAttemptPhase == .idle)
        #expect(arbiter.snapshot.owner == nil)
        #expect(!sut.redeemDeferredModal())
    }

    // MARK: - Reconciliation

    @available(iOS 16, *)
    @Test("Reconciliation does not release a held deferred slot", .timeLimit(.minutes(1)))
    func reconciliationDoesNotReleaseDeferredSlot() throws {
        let sut = makeManager(providers: [makeDeferredProvider(isEligible: true)])
        let lease = try acquiredModalLease()
        sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        sut.reconcilePresentedModal()

        #expect(sut.modalAttemptPhase == .deferred(lease.ownershipIdentity))
        #expect(arbiter.snapshot.hasModalLease)
    }

    // MARK: - Redemption

    @available(iOS 16, *)
    @Test("Redeeming writes the cooldown, notifies the provider and frees the slot", .timeLimit(.minutes(1)))
    func redeemingWritesCooldownAndFreesSlot() throws {
        let provider = makeDeferredProvider(isEligible: true)
        let sut = makeManager(providers: [provider])
        let lease = try acquiredModalLease()
        sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(sut.redeemDeferredModal())

        #expect(cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
        #expect(provider.didCallDidPresentModal)
        #expect(!provider.didCallDidReleaseDeferredSlot)
        #expect(sut.didActuallyPresentModalPromptThisSession)
        #expect(sut.modalAttemptPhase == .idle)
        #expect(arbiter.snapshot.owner == nil)
    }

    @available(iOS 16, *)
    @Test("Redeeming twice only redeems once", .timeLimit(.minutes(1)))
    func redeemingTwiceOnlyRedeemsOnce() throws {
        let sut = makeManager(providers: [makeDeferredProvider(isEligible: true)])
        let lease = try acquiredModalLease()
        sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(sut.redeemDeferredModal())
        #expect(!sut.redeemDeferredModal())
    }

    @available(iOS 16, *)
    @Test("Redeeming with no slot held does nothing", .timeLimit(.minutes(1)))
    func redeemingWithoutHeldSlotDoesNothing() {
        let sut = makeManager(providers: [makeDeferredProvider(isEligible: true)])

        #expect(!sut.redeemDeferredModal())
        #expect(!cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
    }

    // MARK: - Release

    @available(iOS 16, *)
    @Test("Releasing frees the slot without a cooldown and notifies the provider", .timeLimit(.minutes(1)))
    func releasingFreesSlotWithoutCooldown() throws {
        let provider = makeDeferredProvider(isEligible: true)
        let sut = makeManager(providers: [provider])
        let lease = try acquiredModalLease()
        sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        sut.releaseDeferredModal()

        #expect(!cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
        #expect(provider.didCallDidReleaseDeferredSlot)
        #expect(!provider.didCallDidPresentModal)
        #expect(!sut.didActuallyPresentModalPromptThisSession)
        #expect(sut.modalAttemptPhase == .idle)
        #expect(arbiter.snapshot.owner == nil)
        #expect(!sut.redeemDeferredModal())
    }

    @available(iOS 16, *)
    @Test("Releasing does not disturb a presented modal attempt", .timeLimit(.minutes(1)))
    func releasingDoesNotDisturbModalAttempt() throws {
        let provider = MockModalPromptProvider()
        provider.isEligibleToPresentResult = true
        let sut = makeManager(providers: [provider])
        let lease = try acquiredModalLease()
        sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        sut.releaseDeferredModal()

        #expect(sut.modalAttemptPhase == .committed(lease.ownershipIdentity))
        #expect(arbiter.snapshot.hasModalLease)
    }

    // MARK: - Legacy route

    /// Deferred promos are coordinated-route only for now. This pins that the legacy route never
    /// ends up holding a slot it cannot release; it does not assert anything about the providers
    /// behind an eligible deferred one, which that route currently suppresses.
    @available(iOS 16, *)
    @Test("The legacy route never holds a slot for a deferred provider", .timeLimit(.minutes(1)))
    func legacyRouteNeverHoldsSlotForDeferredProvider() {
        let provider = makeDeferredProvider(isEligible: true)
        let sut = makeManager(providers: [provider])

        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(!schedulerMock.didCallSchedule)
        #expect(!presenterMock.didCallPresent)
        #expect(sut.modalAttemptPhase == .idle)
        #expect(!sut.redeemDeferredModal())
        #expect(!cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
    }

    @available(iOS 16, *)
    @Test("The legacy route still presents a modal provider behind an ineligible deferred one", .timeLimit(.minutes(1)))
    func legacyRoutePresentsModalProviderBehindDeferredOne() {
        let deferredProvider = makeDeferredProvider(isEligible: false)
        let modalProvider = MockModalPromptProvider()
        modalProvider.isEligibleToPresentResult = true
        let sut = makeManager(providers: [deferredProvider, modalProvider])

        sut.presentModalPromptIfNeeded(from: presenterMock)
        schedulerMock.executeScheduledBlock()

        #expect(presenterMock.didCallPresent)
        #expect(modalProvider.didCallDidPresentModal)
    }

    // MARK: - Helpers

    private func makeDeferredProvider(isEligible: Bool) -> MockModalPromptProvider {
        let provider = MockModalPromptProvider(shouldReturnPrompt: false)
        provider.presentationKindToReturn = .deferred
        provider.isEligibleToPresentResult = isEligible
        return provider
    }

    private func makeManager(providers: [any ModalPromptProvider]) -> ModalPromptCoordinationManager {
        ModalPromptCoordinationManager(
            providers: providers,
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            modalPromptScheduling: schedulerMock
        )
    }

    private func acquiredModalLease() throws -> PromoQueueModalLease {
        guard case .acquired(let lease) = arbiter.acquireModalLease() else {
            throw DeferredPromoTestError.expectedAcquiredLease
        }
        return lease
    }
}

private enum DeferredPromoTestError: Error {
    case expectedAcquiredLease
}
