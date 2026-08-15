//
//  ModalPromptCoordinationManagerPromoQueueTests.swift
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

import UIKit
import Foundation
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("Modal Prompt Coordination - Coordination Manager Promo Queue")
final class ModalPromptCoordinationManagerPromoQueueTests {
    private let cooldownManagerMock: MockPromptCooldownManager
    private let schedulerMock: MockModalPromptScheduler
    private let presenterMock: MockModalPromptPresenter
    private let promoQueueLeaseArbiter: PromoQueueLeaseArbiter
    private var sut: ModalPromptCoordinationManager!

    init() {
        cooldownManagerMock = MockPromptCooldownManager()
        schedulerMock = MockModalPromptScheduler()
        presenterMock = MockModalPromptPresenter()
        promoQueueLeaseArbiter = PromoQueueLeaseArbiter()
    }

    // MARK: - Promo Queue Attempt Phases

    @available(iOS 16, *)
    @Test("Coordinated Cooldown Releases Lease Without Querying Providers", .timeLimit(.minutes(1)))
    func whenCoordinatedAttemptIsInCooldownThenLeaseIsReleasedSynchronously() throws {
        cooldownManagerMock.cooldownInfoToReturn = .inCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            modalPromptScheduling: schedulerMock
        )
        let lease = try acquireModalLease()

        sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(sut.modalAttemptPhase == .idle)
        #expect(!provider.didCallProvideModalPrompt)
    }

    @available(iOS 16, *)
    @Test("Coordinated No Provider Releases Lease", .timeLimit(.minutes(1)))
    func whenNoCoordinatedProviderReturnsPromptThenLeaseIsReleasedSynchronously() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider(shouldReturnPrompt: false)
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            modalPromptScheduling: schedulerMock
        )
        let lease = try acquireModalLease()

        sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(provider.didCallProvideModalPrompt)
        #expect(!sut.hasActiveOrPendingModalAttempt)
    }

    @available(iOS 16, *)
    @Test("Coordinated Selection Respects Provider Eligibility And Order", .timeLimit(.minutes(1)))
    func whenCoordinatedProvidersHaveDifferentEligibilityThenFirstEligiblePromptIsSelected() throws {
        // Every provider here forces its own answer, so this covers the eligibility gate and provider order only. The
        // onboarding gate itself is covered separately, by a provider that uses the protocol's default implementation.
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let ineligibleProvider = MockModalPromptProvider()
        ineligibleProvider.isEligibleToPresentResult = false
        let selectedProvider = MockModalPromptProvider()
        selectedProvider.isEligibleToPresentResult = true
        let lowerPriorityProvider = MockModalPromptProvider()
        lowerPriorityProvider.isEligibleToPresentResult = true
        sut = ModalPromptCoordinationManager(
            providers: [ineligibleProvider, selectedProvider, lowerPriorityProvider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: false),
            modalPromptScheduling: schedulerMock
        )
        let lease = try acquireModalLease()

        sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(ineligibleProvider.capturedIsOnboardingComplete == false)
        #expect(!ineligibleProvider.didCallProvideModalPrompt)
        #expect(selectedProvider.capturedIsOnboardingComplete == false)
        #expect(selectedProvider.didCallProvideModalPrompt)
        #expect(lowerPriorityProvider.capturedIsOnboardingComplete == nil)
        #expect(!lowerPriorityProvider.didCallProvideModalPrompt)

        schedulerMock.executeScheduledBlock()

        #expect(!ineligibleProvider.didCallDidPresentModal)
        #expect(selectedProvider.didCallDidPresentModal)
        #expect(!lowerPriorityProvider.didCallDidPresentModal)
    }

    @available(iOS 16, *)
    @Test("Coordinated Selection Gates A Default-Gated Provider On Incomplete Onboarding", .timeLimit(.minutes(1)))
    func whenOnboardingIsIncompleteThenDefaultGatedCoordinatedProviderIsNotAsked() throws {
        // GIVEN a provider that leaves `isEligibleToPresent(isOnboardingComplete:)` to the protocol's default
        // implementation, which is what every real provider does.
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: false),
            modalPromptScheduling: schedulerMock
        )
        let lease = try acquireModalLease()

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        // THEN — incomplete onboarding gates the provider out before it is ever asked for a prompt, and the lease goes
        // straight back so a waiting promo is not blocked by an attempt that can never present.
        #expect(provider.capturedIsOnboardingComplete == false)
        #expect(!provider.didCallProvideModalPrompt)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(sut.modalAttemptPhase == .idle)
        #expect(!sut.hasActiveOrPendingModalAttempt)
        #expect(!schedulerMock.didCallSchedule)
    }

    @available(iOS 16, *)
    @Test("Same Lease Attempt Moves From Committed To Presentation Active", .timeLimit(.minutes(1)))
    func whenCoordinatedPromptIsSelectedThenSameOwnershipIdentityMovesThroughPhases() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            modalPromptScheduling: schedulerMock
        )
        let lease = try acquireModalLease()

        sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(sut.modalAttemptPhase == .committed(lease.ownershipIdentity))
        #expect(!sut.didActuallyPresentModalPromptThisSession)
        #expect(sut.didPresentModalPromptThisSession)

        schedulerMock.executeScheduledBlock()

        #expect(sut.modalAttemptPhase == .presentationActive(lease.ownershipIdentity))
        #expect(sut.didActuallyPresentModalPromptThisSession)
        #expect(promoQueueLeaseArbiter.snapshot.modalOwnershipIdentity == lease.ownershipIdentity)
    }

    @available(iOS 16, *)
    @Test("Deallocated Presented Root Releases The Modal Lease", .timeLimit(.minutes(1)))
    func whenPresentedRootIsDeallocatedThenReconciliationReleasesLease() throws {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let scheduler = BlockReleasingModalPromptScheduler()
        let attachmentChecker = MockModalPromptRootAttachmentChecker()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            modalPromptScheduling: scheduler,
            rootAttachmentChecker: attachmentChecker
        )
        let lease = try acquireModalLease()
        weak var weakExactRoot: UIViewController?

        autoreleasepool {
            var exactRoot: UIViewController! = UIViewController()
            weakExactRoot = exactRoot
            provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: exactRoot)
            attachmentChecker.markAttached(exactRoot)

            sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)
            scheduler.executeAndReleaseScheduledBlock()

            #expect(sut.modalAttemptPhase == .presentationActive(lease.ownershipIdentity))
            #expect(!sut.reconcilePresentedModal())
            #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)

            // WHEN every fixture reference is dropped, the manager is the only thing that could keep the root alive.
            provider.modalConfigurationToReturn = nil
            presenterMock.reset()
            exactRoot = nil
        }

        // THEN — the presented modal is gone, so its lease must be released rather than pinned until the next
        // foreground, and the manager must not be the last owner of the whole view-controller hierarchy.
        #expect(weakExactRoot == nil)
        #expect(sut.reconcilePresentedModal())
        #expect(sut.modalAttemptPhase == .idle)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
    }

    private func acquireModalLease() throws -> PromoQueueModalLease {
        guard case .acquired(let lease) = promoQueueLeaseArbiter.acquireModalLease() else {
            throw TestError.expectedAcquiredLease
        }
        return lease
    }
}

private enum TestError: Error {
    case expectedAcquiredLease
}

/// A scheduler that drops its scheduled block as soon as it has run.
///
/// `MockModalPromptScheduler` keeps the executed block forever, and that block strongly captures the committed attempt
/// and therefore the modal root. A retention test needs the fixture to stop being an owner so that only the manager
/// remains a candidate.
private final class BlockReleasingModalPromptScheduler: ModalPromptScheduling {
    private var scheduledBlock: (@MainActor () -> Void)?

    func schedule(after delay: TimeInterval, execute: @escaping @MainActor () -> Void) {
        scheduledBlock = execute
    }

    @MainActor
    func executeAndReleaseScheduledBlock() {
        let block = scheduledBlock
        scheduledBlock = nil
        block?()
    }
}


/// Models attachment as the set of exact root identities that the test considers attached.
///
/// `queriedRoots` records the root the manager actually asked about, so a test can pin the *subject* of the
/// predicate and not merely its answer — a check resolved against a topmost controller instead of the retained exact
/// root asks about a different object even when both are on screen.
@MainActor
final class MockModalPromptRootAttachmentChecker: ModalPromptRootAttachmentChecking {
    var attachedRoots = Set<ObjectIdentifier>()

    private(set) var queriedRoots: [ObjectIdentifier] = []

    func markAttached(_ root: UIViewController) {
        attachedRoots.insert(ObjectIdentifier(root))
    }

    func didQuery(_ root: UIViewController) -> Bool {
        queriedRoots.contains(ObjectIdentifier(root))
    }

    func isAttached(_ root: UIViewController) -> Bool {
        queriedRoots.append(ObjectIdentifier(root))
        return attachedRoots.contains(ObjectIdentifier(root))
    }
}
