//
//  ModalPromptCoordinationManagerTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@Suite("Modal Prompt Coordination - Coordination Manager")
final class ModalPromptCoordinationManagerTests {
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

    // MARK: - Cooldown Period Tests

    @Test("Check Modal Is Not Presented When In Cooldown Period")
    func whenInCooldownPeriodThenNoModalIsPresented() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .inCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        #expect(!presenterMock.didCallPresent)
        #expect(!provider.didCallProvideModalPrompt)

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(!presenterMock.didCallPresent)
        #expect(!provider.didCallProvideModalPrompt)
        #expect(!cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
        #expect(!provider.didCallDidPresentModal)
    }

    @Test("Check Modal Is Presented When Not In Cooldown Period")
    func whenNotInCooldownPeriodThenModalIsPresented() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        #expect(!presenterMock.didCallPresent)

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(provider.didCallProvideModalPrompt)
        #expect(schedulerMock.didCallSchedule)
        #expect(schedulerMock.capturedScheduledDelay == 0.1)

        // Execute scheduled presentation
        schedulerMock.executeScheduledBlock()
        #expect(presenterMock.didCallPresent)
        #expect(cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
        #expect(provider.didCallDidPresentModal)
    }

    // MARK: - Priority Tests

    @Test("Check First Provider Is Checked First")
    func whenMultipleProvidersThenFirstProviderIsCheckedFirst() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let firstProvider = MockModalPromptProvider()
        let secondProvider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [firstProvider, secondProvider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(firstProvider.didCallProvideModalPrompt)
        #expect(!secondProvider.didCallProvideModalPrompt)

        // Execute scheduled presentation
        schedulerMock.executeScheduledBlock()

        #expect(firstProvider.didCallDidPresentModal)
        #expect(!secondProvider.didCallDidPresentModal)
    }

    @Test("Check Second Provider Is Used When First Returns Nil")
    func whenFirstProviderReturnsNilThenSecondProviderIsChecked() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let firstProvider = MockModalPromptProvider(shouldReturnPrompt: false)
        let secondProvider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [firstProvider, secondProvider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(firstProvider.didCallProvideModalPrompt)
        #expect(secondProvider.didCallProvideModalPrompt)

        // Execute scheduled presentation
        schedulerMock.executeScheduledBlock()

        #expect(!firstProvider.didCallDidPresentModal)
        #expect(secondProvider.didCallDidPresentModal)
    }

    @Test("Check The Right Provider Is Used When Others Return Nil")
    func whenFirstTwoProvidersReturnNilThenThirdProviderIsChecked() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let firstProvider = MockModalPromptProvider(shouldReturnPrompt: false)
        let secondProvider = MockModalPromptProvider(shouldReturnPrompt: false)
        let thirdProvider = MockModalPromptProvider(shouldReturnPrompt: true)
        let fourthProvider = MockModalPromptProvider(shouldReturnPrompt: false)
        let fifthProvider = MockModalPromptProvider(shouldReturnPrompt: false)

        sut = ModalPromptCoordinationManager(
            providers: [firstProvider, secondProvider, thirdProvider, fourthProvider, fifthProvider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(firstProvider.didCallProvideModalPrompt)
        #expect(secondProvider.didCallProvideModalPrompt)
        #expect(thirdProvider.didCallProvideModalPrompt)
        #expect(!fourthProvider.didCallProvideModalPrompt)
        #expect(!fifthProvider.didCallProvideModalPrompt)

        // Execute scheduled presentation
        schedulerMock.executeScheduledBlock()

        #expect(!firstProvider.didCallDidPresentModal)
        #expect(!secondProvider.didCallDidPresentModal)
        #expect(thirdProvider.didCallDidPresentModal)
        #expect(!fourthProvider.didCallDidPresentModal)
        #expect(!fifthProvider.didCallDidPresentModal)
    }

    @Test("Check No Modal Is Presented When All Providers Return Nil")
    func whenAllProvidersReturnNilThenNoModalIsPresented() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let firstProvider = MockModalPromptProvider(shouldReturnPrompt: false)
        let secondProvider = MockModalPromptProvider(shouldReturnPrompt: false)
        let thirdProvider = MockModalPromptProvider(shouldReturnPrompt: false)
        sut = ModalPromptCoordinationManager(
            providers: [firstProvider, secondProvider, thirdProvider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(firstProvider.didCallProvideModalPrompt)
        #expect(secondProvider.didCallProvideModalPrompt)
        #expect(thirdProvider.didCallProvideModalPrompt)
        #expect(!schedulerMock.didCallSchedule)
        #expect(!presenterMock.didCallPresent)
        #expect(!cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
    }

    // MARK: - Presentation Tests

    @Test("Check View Controller From Provider Is Presented")
    func whenPresentingModalThenViewControllerFromProviderIsPresented() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let viewController = UIViewController()
        viewController.modalPresentationStyle = .pageSheet
        viewController.modalTransitionStyle = .coverVertical
        viewController.isModalInPresentation = true
        provider.modalConfigurationToReturn = ModalPromptConfiguration(
            viewController: viewController,
            animated: true
        )
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)
        schedulerMock.executeScheduledBlock()

        // THEN
        let presentedVC = presenterMock.capturedViewController
        #expect(presenterMock.capturedViewController === presentedVC)
        #expect(presentedVC?.modalPresentationStyle == .pageSheet)
        #expect(presentedVC?.modalTransitionStyle == .coverVertical)
        #expect(presentedVC?.isModalInPresentation == true)
        #expect(presenterMock.capturedAnimated == true)
    }

    @Test(
        "Check Animated Flag Is Applied Correctly",
        arguments: [true, false]
    )
    func whenDifferentAnimatedSettingsThenAnimatedFlagIsPassedCorrectly(animated: Bool) {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(
            viewController: UIViewController(),
            animated: animated
        )
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)
        schedulerMock.executeScheduledBlock()

        // THEN
        #expect(presenterMock.capturedAnimated == animated)
    }

    // MARK: - Scheduler Tests

    @Test("Check Presentation Is Scheduled With Correct Delay")
    func whenPresentingModalThenSchedulerIsCalledWithCorrectDelay() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(schedulerMock.didCallSchedule)
        #expect(schedulerMock.capturedScheduledDelay == 0.1)
    }

    @Test("Check Presentation Happens Only After Scheduled Delay")
    func whenScheduledThenPresentationDoesNotHappenImmediately() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN (before executing scheduled block)
        #expect(!presenterMock.didCallPresent)

        // WHEN (executing scheduled block)
        schedulerMock.executeScheduledBlock()

        // THEN (after executing scheduled block)
        #expect(presenterMock.didCallPresent)
    }

    // MARK: - Cooldown Recording Tests

    @Test("Check Cooldown Is Recorded After Successful Presentation")
    func whenModalIsPresentedThenCooldownIsRecorded() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        #expect(!cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)
        schedulerMock.executeScheduledBlock()

        // THEN
        #expect(cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
    }

    @available(iOS 16, *)
    @Test("Check Session Flag Is Set After Successful Presentation", .timeLimit(.minutes(1)))
    func whenModalIsPresentedThenSessionFlagIsSet() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        #expect(!sut.didPresentModalPromptThisSession)

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(sut.didPresentModalPromptThisSession)
    }

    @available(iOS 16, *)
    @Test("Check Session Flag Survives The Legacy Presentation Completion", .timeLimit(.minutes(1)))
    func whenLegacyPresentationCompletesThenSessionFlagRemainsSet() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        sut.presentModalPromptIfNeeded(from: presenterMock)
        // Held up by the in-flight legacy attempt alone: UIKit has not presented anything yet.
        #expect(sut.didPresentModalPromptThisSession)
        #expect(!sut.didActuallyPresentModalPromptThisSession)

        // WHEN the scheduled presentation runs, the completion clears that in-flight attempt — so it has to latch
        // actual session history in the same breath or suppression collapses exactly as the modal appears.
        schedulerMock.executeScheduledBlock()

        // THEN
        #expect(sut.didActuallyPresentModalPromptThisSession)
        #expect(sut.didPresentModalPromptThisSession)
        #expect(provider.didCallDidPresentModal)
    }

    @available(iOS 16, *)
    @Test("Check Session Flag Is Not Set When No Modal Is Presented", .timeLimit(.minutes(1)))
    func whenNoModalIsPresentedThenSessionFlagIsNotSet() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider(shouldReturnPrompt: false)
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)
        schedulerMock.executeScheduledBlock()

        // THEN
        #expect(!sut.didPresentModalPromptThisSession)
    }

    @Test("Check Cooldown Is Not Recorded When No Modal Is Presented")
    func whenNoModalIsPresentedThenCooldownIsNotRecorded() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider(shouldReturnPrompt: false)
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)
        schedulerMock.executeScheduledBlock()

        // THEN
        #expect(!cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
    }

    @Test("Check Cooldown Is Not Recorded When Already In Cooldown Period")
    func whenInCooldownPeriodThenCooldownIsNotRecorded() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .inCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)
        schedulerMock.executeScheduledBlock()

        // THEN
        #expect(!cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
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
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let lease = try acquireModalLease()

        let disposition = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(disposition == .released)
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
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let lease = try acquireModalLease()

        let disposition = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(disposition == .released)
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
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let lease = try acquireModalLease()

        let disposition = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(disposition == .retained)
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
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let lease = try acquireModalLease()

        // WHEN
        let disposition = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        // THEN — incomplete onboarding gates the provider out before it is ever asked for a prompt, and the lease goes
        // straight back so a waiting promo is not blocked by an attempt that can never present.
        #expect(disposition == .released)
        #expect(provider.capturedIsOnboardingComplete == false)
        #expect(!provider.didCallProvideModalPrompt)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(sut.modalAttemptPhase == .idle)
        #expect(!sut.hasActiveOrPendingModalAttempt)
        #expect(!schedulerMock.didCallSchedule)
    }

    @available(iOS 16, *)
    @Test("Same Lease Attempt Moves From Committed To Presentation Active", .timeLimit(.minutes(1)))
    func whenCoordinatedPromptIsSelectedThenSameAttemptIdentityMovesThroughPhases() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let lease = try acquireModalLease()

        let disposition = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(disposition == .retained)
        #expect(sut.modalAttemptPhase == .committed(lease.attemptIdentity))
        #expect(!sut.didActuallyPresentModalPromptThisSession)
        #expect(sut.didPresentModalPromptThisSession)

        schedulerMock.executeScheduledBlock()

        #expect(sut.modalAttemptPhase == .presentationActive(lease.attemptIdentity))
        #expect(sut.didActuallyPresentModalPromptThisSession)
        #expect(promoQueueLeaseArbiter.snapshot.modalAttemptIdentity == lease.attemptIdentity)
    }

    @available(iOS 16, *)
    @Test("Nested Child Does Not Release Exact Selected Root", .timeLimit(.minutes(1)))
    func whenSelectedRootPresentsNestedChildThenReconciliationRetainsLease() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let exactRoot = UIViewController()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: exactRoot)
        let attachmentChecker = MockModalPromptRootAttachmentChecker()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock,
            rootAttachmentChecker: attachmentChecker
        )
        let lease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)
        schedulerMock.executeScheduledBlock()

        // Give the selected root a real child presentation. The window exists only so UIKit accepts the nesting:
        // without it `exactRoot.presentedViewController` stays nil and a topmost walk would resolve straight back to
        // the exact root, leaving the two implementations indistinguishable.
        let window = makeKeyWindow(withRoot: exactRoot)
        defer { window.isHidden = true }
        let nestedChild = UIViewController()
        exactRoot.present(nestedChild, animated: false, completion: nil)

        // Assert the UIKit nesting the rest of the test depends on before drawing conclusions from it.
        #expect(exactRoot.presentedViewController === nestedChild)
        #expect(nestedChild.presentingViewController === exactRoot)

        // Only the exact root is attached as far as coordination is concerned: the child is never registered, so an
        // implementation that consulted the topmost controller would report the attempt finished and drop the lease.
        attachmentChecker.markAttached(exactRoot)

        #expect(!sut.reconcilePresentedModal())
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(attachmentChecker.didQuery(exactRoot))
        #expect(!attachmentChecker.didQuery(nestedChild))

        // The lease is released only once the retained root itself goes away, child presentation or not.
        attachmentChecker.attachedRoots.remove(ObjectIdentifier(exactRoot))

        #expect(sut.reconcilePresentedModal())
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
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
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
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

            _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)
            scheduler.executeAndReleaseScheduledBlock()

            #expect(sut.modalAttemptPhase == .presentationActive(lease.attemptIdentity))
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

    @available(iOS 16, *)
    @Test("Disable Releases Coordination But Preserves Actual History And Visible Controller", .timeLimit(.minutes(1)))
    func whenFeatureDisablesAfterPresentationThenHistoryAndUIKitModalRemain() throws {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let lease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)
        schedulerMock.executeScheduledBlock()
        let presentedRoot = presenterMock.capturedViewController

        sut.promoQueueWillTransition(to: .disabled)

        #expect(sut.modalAttemptPhase == .idle)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(sut.didActuallyPresentModalPromptThisSession)
        #expect(presenterMock.capturedViewController === presentedRoot)
    }

    @available(iOS 16, *)
    @Test("Disable During Present Animation Preserves Actual History", .timeLimit(.minutes(1)))
    func whenFeatureDisablesDuringPresentAnimationThenActualHistoryIsPreserved() throws {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let exactRoot = UIViewController()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: exactRoot)
        let deferredPresenter = DeferredCompletionModalPromptPresenter()
        // This test's premise is that the modal really is on screen animating in. The deferred presenter cannot
        // reproduce that on its own — it never hands the root to UIKit — so the checker states the premise explicitly
        // instead of leaving it to whatever the real attachment predicate happens to answer for a detached controller.
        let attachmentChecker = MockModalPromptRootAttachmentChecker()
        attachmentChecker.markAttached(exactRoot)
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock,
            rootAttachmentChecker: attachmentChecker
        )
        let lease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: deferredPresenter, with: lease)
        schedulerMock.executeScheduledBlock()
        let presentedRoot = deferredPresenter.capturedViewController

        // The presentation is in flight: the modal is on screen but UIKit has not run the completion yet.
        #expect(deferredPresenter.didCallPresent)
        #expect(presentedRoot === exactRoot)
        #expect(sut.modalAttemptPhase == .presentationActive(lease.attemptIdentity))
        #expect(!sut.didActuallyPresentModalPromptThisSession)
        #expect(sut.didPresentModalPromptThisSession)

        // WHEN
        sut.promoQueueWillTransition(to: .disabled)

        // THEN
        #expect(sut.modalAttemptPhase == .idle)
        #expect(sut.didActuallyPresentModalPromptThisSession)
        #expect(sut.didPresentModalPromptThisSession)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(deferredPresenter.capturedViewController === presentedRoot)

        // WHEN the withheld UIKit completion finally lands, session history stays latched.
        deferredPresenter.completePendingPresentation()

        // THEN
        #expect(sut.modalAttemptPhase == .idle)
        #expect(sut.didPresentModalPromptThisSession)
        #expect(provider.didCallDidPresentModal)
    }

    @available(iOS 16, *)
    @Test("Disable After Refused Presentation Does Not Latch Actual History", .timeLimit(.minutes(1)))
    func whenPresentationWasRefusedThenDisablingDoesNotLatchActualHistory() throws {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let exactRoot = UIViewController()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: exactRoot)
        // UIKit silently refused the presentation: `present` was called, the root never became attached, and the
        // completion never runs. The attempt still reaches `.presentationActive` because that happens before `present`.
        let deferredPresenter = DeferredCompletionModalPromptPresenter()
        let attachmentChecker = MockModalPromptRootAttachmentChecker()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock,
            rootAttachmentChecker: attachmentChecker
        )
        let lease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: deferredPresenter, with: lease)
        schedulerMock.executeScheduledBlock()

        #expect(deferredPresenter.didCallPresent)
        #expect(sut.modalAttemptPhase == .presentationActive(lease.attemptIdentity))
        #expect(!sut.didActuallyPresentModalPromptThisSession)

        // WHEN
        sut.promoQueueWillTransition(to: .disabled)

        // THEN — the transition consults attachment for the exact selected root, and a modal that never appeared must
        // not suppress every other promo for the rest of the session.
        #expect(attachmentChecker.didQuery(exactRoot))
        #expect(sut.modalAttemptPhase == .idle)
        #expect(!sut.didActuallyPresentModalPromptThisSession)
        #expect(!sut.didPresentModalPromptThisSession)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
    }

    @available(iOS 16, *)
    @Test("Enabling Re-Adopts Attached Root Observed On Legacy Path", .timeLimit(.minutes(1)))
    func whenLegacyRootIsAttachedThenEnablingReAdoptsModalLease() {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let exactRoot = UIViewController()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: exactRoot)
        let attachmentChecker = MockModalPromptRootAttachmentChecker()
        attachmentChecker.attachedRoots.insert(ObjectIdentifier(exactRoot))
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock,
            rootAttachmentChecker: attachmentChecker
        )
        sut.presentModalPromptIfNeeded(from: presenterMock)
        schedulerMock.executeScheduledBlock()

        sut.promoQueueWillTransition(to: .enabled)
        promoQueueLeaseArbiter.invalidateAllLeases()
        sut.promoQueueDidTransition(to: .enabled)

        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)
        guard case .presentationActive = sut.modalAttemptPhase else {
            Issue.record("Expected attached legacy root to be re-adopted as presentation active")
            return
        }
    }

    @available(iOS 16, *)
    @Test("Enabling Re-Adopts Exact Root Attached To A Different Host", .timeLimit(.minutes(1)))
    func whenLegacyRootIsAttachedToAnotherHostThenEnablingReAdoptsModalLease() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let exactRoot = UIViewController()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: exactRoot)
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        sut.presentModalPromptIfNeeded(from: presenterMock)
        schedulerMock.executeScheduledBlock()

        let actualPresentationHost = UIViewController()
        let window = makeKeyWindow(withRoot: actualPresentationHost)
        defer { window.isHidden = true }
        actualPresentationHost.present(exactRoot, animated: false, completion: nil)
        #expect(exactRoot.presentingViewController === actualPresentationHost)

        // WHEN
        sut.promoQueueWillTransition(to: .enabled)
        promoQueueLeaseArbiter.invalidateAllLeases()
        sut.promoQueueDidTransition(to: .enabled)

        // THEN
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)
        guard case .presentationActive = sut.modalAttemptPhase else {
            Issue.record("Expected the attached exact root to be re-adopted regardless of its presentation host")
            return
        }
    }

    @available(iOS 16, *)
    @Test("Enabling Does Not Re-Adopt A Root That Was Only Selected", .timeLimit(.minutes(1)))
    func whenSelectedRootWasNeverPresentedThenEnablingDoesNotReAdoptModalLease() throws {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let exactRoot = UIViewController()
        provider.modalConfigurationToReturn = ModalPromptConfiguration(viewController: exactRoot)
        // The root would satisfy the attachment predicate, so only the absence of an actual presentation can stop the
        // manager re-adopting it.
        let attachmentChecker = MockModalPromptRootAttachmentChecker()
        attachmentChecker.markAttached(exactRoot)
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock,
            rootAttachmentChecker: attachmentChecker
        )
        let lease = try acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        // The prompt is selected and committed, but its scheduled presentation never runs.
        #expect(sut.modalAttemptPhase == .committed(lease.attemptIdentity))
        #expect(!presenterMock.didCallPresent)

        // WHEN
        sut.promoQueueWillTransition(to: .enabled)
        promoQueueLeaseArbiter.invalidateAllLeases()
        sut.promoQueueDidTransition(to: .enabled)

        // THEN — nothing ever reached the screen, so there is nothing to re-adopt: the manager must not park itself in
        // `.presentationActive` holding the modal lease, and must not even consider the merely selected root.
        #expect(sut.modalAttemptPhase == .idle)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(!sut.hasActiveOrPendingModalAttempt)
        #expect(!attachmentChecker.didQuery(exactRoot))
    }

    @available(iOS 16, *)
    @Test("Enabling Invalidates Legacy Delayed Presentation", .timeLimit(.minutes(1)))
    func whenFeatureEnablesDuringLegacyDelayThenStaleClosureCannotPresent() {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        sut.presentModalPromptIfNeeded(from: presenterMock)

        sut.promoQueueWillTransition(to: .enabled)
        promoQueueLeaseArbiter.invalidateAllLeases()
        sut.promoQueueDidTransition(to: .enabled)
        schedulerMock.executeScheduledBlock()

        #expect(!presenterMock.didCallPresent)
        #expect(!sut.hasActiveOrPendingModalAttempt)
        #expect(!sut.didActuallyPresentModalPromptThisSession)
    }

    // MARK: - OmniBarEditingState Present-On-Top Tests

    @Test("Check Modal Is Presented On Top When Non-OmniBar ViewController Is Presented")
    func whenNonOmniBarViewControllerIsPresentedThenFallbackPathIsUsed() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let someVC = MockDismissibleViewController()
        presenterMock.presentedViewController = someVC
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)
        schedulerMock.executeScheduledBlock()

        // THEN — fallback presents on the presenter directly
        #expect(presenterMock.didCallPresent)
        #expect(!someVC.didCallPresent)
    }

    @Test("Check Modal Presents Directly When No ViewController Is Presented")
    func whenNoPresentedViewControllerThenModalPresentsDirectly() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        presenterMock.presentedViewController = nil
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)
        schedulerMock.executeScheduledBlock()

        // THEN
        #expect(presenterMock.didCallPresent)
        #expect(provider.didCallDidPresentModal)
    }

    private func acquireModalLease() throws -> PromoQueueModalLease {
        guard case .acquired(let lease) = promoQueueLeaseArbiter.acquireModalLease() else {
            throw TestError.expectedAcquiredLease
        }
        return lease
    }

    /// Stands up a visible window so UIKit accepts synchronous, unanimated presentations from `root`.
    ///
    /// Callers must hide the returned window again so it does not stay key for later tests.
    private func makeKeyWindow(withRoot root: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = root
        window.makeKeyAndVisible()
        return window
    }
}

@MainActor
@Suite("Modal Prompt Coordination - Root Attachment Checker")
final class ModalPromptRootAttachmentCheckerTests {
    private let sut: ModalPromptRootAttachmentChecker

    init() {
        sut = ModalPromptRootAttachmentChecker()
    }

    @available(iOS 16, *)
    @Test("Presented Root Is Attached", .timeLimit(.minutes(1)))
    func whenRootIsPresentedThenAttachmentCheckPasses() {
        // GIVEN
        let presenter = UIViewController()
        let window = makeKeyWindow(withRoot: presenter)
        defer { window.isHidden = true }
        let root = UIViewController()

        // WHEN
        presenter.present(root, animated: false, completion: nil)

        // THEN
        #expect(root.presentingViewController === presenter)
        #expect(sut.isAttached(root))
    }

    @available(iOS 16, *)
    @Test("Root Presenting Its Own Child Stays Attached", .timeLimit(.minutes(1)))
    func whenRootPresentsNestedChildThenRootRemainsAttached() async {
        // GIVEN
        let intendedPresenter = UIViewController()
        let window = makeKeyWindow(withRoot: intendedPresenter)
        defer { window.isHidden = true }
        let root = UIViewController()
        let nestedChild = UIViewController()
        // Wait on UIKit's own presentation completion rather than a delay. A nested `present` requested while the
        // outer presentation is still in flight is refused, leaving `root.presentedViewController` nil — so the
        // nesting this test draws its conclusion from would never be established.
        await withCheckedContinuation { continuation in
            intendedPresenter.present(root, animated: false) {
                continuation.resume()
            }
        }

        // WHEN
        await withCheckedContinuation { continuation in
            root.present(nestedChild, animated: false) {
                continuation.resume()
            }
        }

        // THEN — a child flow presented by the root does not detach the root itself.
        #expect(root.presentingViewController === intendedPresenter)
        #expect(root.presentedViewController === nestedChild)
        #expect(nestedChild.presentingViewController === root)
        #expect(sut.isAttached(root))
    }

    @available(iOS 16, *)
    @Test("Root Being Dismissed Is Not Attached", .timeLimit(.minutes(1)))
    func whenRootIsBeingDismissedThenAttachmentCheckFails() async {
        // GIVEN
        let presenter = UIViewController()
        let window = makeKeyWindow(withRoot: presenter)
        defer { window.isHidden = true }
        let root = UIViewController()
        // Wait on UIKit's own presentation completion rather than a delay. `isBeingDismissed` is only raised once the
        // presentation transition has finished; a dismissal requested while the presentation is still in flight is
        // coalesced into it and never raises the flag, which would make this test pass for the wrong reason.
        await withCheckedContinuation { continuation in
            presenter.present(root, animated: false) {
                continuation.resume()
            }
        }
        #expect(sut.isAttached(root))

        // WHEN
        root.dismiss(animated: true, completion: nil)

        // THEN — UIKit still reports the root as presented and windowed for the whole dismissal animation, so only the
        // dismissal flag distinguishes a modal on its way out from one that is staying.
        #expect(root.isBeingDismissed)
        #expect(root.presentingViewController === presenter)
        #expect(root.viewIfLoaded?.window != nil)
        #expect(!sut.isAttached(root))
    }

    @available(iOS 16, *)
    @Test("Detached Root Is Not Attached", .timeLimit(.minutes(1)))
    func whenRootIsNotAttachedThenAttachmentCheckFails() {
        // GIVEN
        let root = UIViewController()

        // THEN
        #expect(!root.isBeingPresented)
        #expect(root.presentingViewController == nil)
        #expect(root.viewIfLoaded?.window == nil)
        #expect(!sut.isAttached(root))
    }

    /// Stands up a visible window so UIKit accepts synchronous, unanimated presentations from `root`.
    ///
    /// Callers must hide the returned window again so it does not stay key for later tests.
    private func makeKeyWindow(withRoot root: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = root
        window.makeKeyAndVisible()
        return window
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

/// A presenter that withholds the UIKit presentation completion so an attempt can be observed mid-animation.
@MainActor
private final class DeferredCompletionModalPromptPresenter: ModalPromptPresenter {
    var presentedViewController: UIViewController?

    private(set) var didCallPresent = false
    private(set) var capturedViewController: UIViewController?
    private var pendingCompletion: (() -> Void)?

    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?) {
        didCallPresent = true
        capturedViewController = viewControllerToPresent
        pendingCompletion = completion
    }

    func completePendingPresentation() {
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?()
    }
}

/// Models attachment as the set of exact root identities that the test considers attached.
///
/// `queriedRoots` records the root the manager actually asked about, so a test can pin the *subject* of the
/// predicate and not merely its answer — a check resolved against a topmost controller instead of the retained exact
/// root asks about a different object even when both are on screen.
@MainActor
private final class MockModalPromptRootAttachmentChecker: ModalPromptRootAttachmentChecking {
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
