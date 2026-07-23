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

    @Test("Coordinated Cooldown Releases Lease Without Querying Providers")
    func whenCoordinatedAttemptIsInCooldownThenLeaseIsReleasedSynchronously() {
        cooldownManagerMock.cooldownInfoToReturn = .inCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let lease = acquireModalLease()

        let disposition = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(disposition == .released)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(sut.modalAttemptPhase == .idle)
        #expect(!provider.didCallProvideModalPrompt)
    }

    @Test("Coordinated No Provider Releases Lease")
    func whenNoCoordinatedProviderReturnsPromptThenLeaseIsReleasedSynchronously() {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider(shouldReturnPrompt: false)
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let lease = acquireModalLease()

        let disposition = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)

        #expect(disposition == .released)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(provider.didCallProvideModalPrompt)
        #expect(!sut.hasActiveOrPendingModalAttempt)
    }

    @Test("Same Lease Attempt Moves From Committed To Presentation Active")
    func whenCoordinatedPromptIsSelectedThenSameAttemptIdentityMovesThroughPhases() {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let lease = acquireModalLease()

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

    @Test("Nested Child Does Not Release Exact Selected Root")
    func whenSelectedRootPresentsNestedChildThenReconciliationRetainsLease() {
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
        let lease = acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)
        schedulerMock.executeScheduledBlock()
        attachmentChecker.attachedRoots.insert(ObjectIdentifier(exactRoot))
        let nestedChild = UIViewController()
        attachmentChecker.topmostViewController = nestedChild

        #expect(!sut.reconcilePresentedModal())
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)

        attachmentChecker.attachedRoots.remove(ObjectIdentifier(exactRoot))

        #expect(sut.reconcilePresentedModal())
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
    }

    @Test("Disable Releases Coordination But Preserves Actual History And Visible Controller")
    func whenFeatureDisablesAfterPresentationThenHistoryAndUIKitModalRemain() {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            modalPromptScheduling: schedulerMock
        )
        let lease = acquireModalLease()
        _ = sut.presentModalPromptIfNeeded(from: presenterMock, with: lease)
        schedulerMock.executeScheduledBlock()
        let presentedRoot = presenterMock.capturedViewController

        sut.promoQueueWillTransition(to: .disabled)

        #expect(sut.modalAttemptPhase == .idle)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(sut.didActuallyPresentModalPromptThisSession)
        #expect(presenterMock.capturedViewController === presentedRoot)
    }

    @Test("Enabling Re-Adopts Attached Root Observed On Legacy Path")
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

    @Test("Enabling Invalidates Legacy Delayed Presentation")
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

    private func acquireModalLease() -> PromoQueueModalLease {
        guard case .acquired(let lease) = promoQueueLeaseArbiter.acquireModalLease() else {
            Issue.record("Expected modal lease acquisition")
            fatalError("Expected modal lease acquisition")
        }
        return lease
    }
}

@MainActor
private final class MockModalPromptRootAttachmentChecker: ModalPromptRootAttachmentChecking {
    var attachedRoots = Set<ObjectIdentifier>()
    var topmostViewController: UIViewController?

    func isAttached(_ root: UIViewController) -> Bool {
        attachedRoots.contains(ObjectIdentifier(root))
    }

    func isAttached(_ root: UIViewController, to intendedPresenter: UIViewController?) -> Bool {
        isAttached(root)
    }
}
