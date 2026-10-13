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

/// A presenter UIKit refuses: it never calls the completion.
@MainActor
private final class NonCompletingModalPromptPresenter: ModalPromptPresenter {
    var presentedViewController: UIViewController?

    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?) {}
}

@MainActor
@Suite("Modal Prompt Coordination - Coordination Manager")
final class ModalPromptCoordinationManagerTests {
    private let cooldownManagerMock: MockPromptCooldownManager
    private let schedulerMock: MockModalPromptScheduler
    private let presenterMock: MockModalPromptPresenter
    private var sut: ModalPromptCoordinationManager!

    init() {
        cooldownManagerMock = MockPromptCooldownManager()
        schedulerMock = MockModalPromptScheduler()
        presenterMock = MockModalPromptPresenter()
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
    @Test("Check Session Flag Survives The Legacy Presentation Completion", .timeLimit(.minutes(1)))
    func whenLegacyPresentationCompletesThenSessionFlagRemainsSet() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
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

    // MARK: - Close Handler

    private func makeSUTWatchingClose(attachmentChecker: MockModalPromptRootAttachmentChecker,
                                      closeChecks: MockModalPromptScheduler,
                                      hasEligiblePrompt: Bool = true) -> ModalPromptCoordinationManager {
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        return ModalPromptCoordinationManager(
            providers: [MockModalPromptProvider(shouldReturnPrompt: hasEligiblePrompt)],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            modalPromptScheduling: schedulerMock,
            rootAttachmentChecker: attachmentChecker,
            closeCheckScheduling: closeChecks
        )
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check The Close Handler Runs Once The Legacy Prompt Leaves The Screen", .timeLimit(.minutes(1)))
    func whenLegacyPromptLeavesTheScreenThenCloseHandlerRunsOnce() throws {
        // GIVEN
        let attachmentChecker = MockModalPromptRootAttachmentChecker()
        let closeChecks = MockModalPromptScheduler()
        sut = makeSUTWatchingClose(attachmentChecker: attachmentChecker, closeChecks: closeChecks)
        var handlerRunCount = 0
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // WHEN
        #expect(sut.runOnceModalPromptCloses { handlerRunCount += 1 })

        // THEN it waits while the prompt is on its way
        closeChecks.executeScheduledBlock()
        #expect(handlerRunCount == 0)

        // and while it's on screen
        schedulerMock.executeScheduledBlock()
        let root = try #require(presenterMock.capturedViewController)
        attachmentChecker.markAttached(root)
        closeChecks.executeScheduledBlock()
        #expect(handlerRunCount == 0)

        // and runs once it has left
        attachmentChecker.attachedRoots.removeAll()
        closeChecks.executeScheduledBlock()
        #expect(handlerRunCount == 1)
        closeChecks.executeScheduledBlock()
        #expect(handlerRunCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check No Close Handler Is Kept When No Prompt Is Pending", .timeLimit(.minutes(1)))
    func whenNoPromptIsPendingThenCloseHandlerIsNotKept() {
        // GIVEN
        let closeChecks = MockModalPromptScheduler()
        sut = makeSUTWatchingClose(attachmentChecker: MockModalPromptRootAttachmentChecker(),
                                   closeChecks: closeChecks,
                                   hasEligiblePrompt: false)
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // WHEN
        let waits = sut.runOnceModalPromptCloses {}

        // THEN
        #expect(!waits)
        #expect(!closeChecks.didCallSchedule)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check No Close Handler Is Kept For A Prompt UIKit Refused", .timeLimit(.minutes(1)))
    func whenEarlierPromptWasRefusedThenCloseHandlerIsNotKept() {
        // GIVEN a legacy attempt whose presentation never completes, so its ID stays behind
        let closeChecks = MockModalPromptScheduler()
        sut = makeSUTWatchingClose(attachmentChecker: MockModalPromptRootAttachmentChecker(), closeChecks: closeChecks)
        sut.presentModalPromptIfNeeded(from: NonCompletingModalPromptPresenter())
        schedulerMock.executeScheduledBlock()
        #expect(sut.hasActiveOrPendingModalAttempt)

        // WHEN
        let waits = sut.runOnceModalPromptCloses {}

        // THEN
        #expect(!waits)
        #expect(!closeChecks.didCallSchedule)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Invalidating a pending keyboard request stops checking for prompt closure", .timeLimit(.minutes(1)))
    func invalidatedKeyboardRequestStopsChecking() {
        let closeChecks = MockModalPromptScheduler()
        sut = makeSUTWatchingClose(attachmentChecker: MockModalPromptRootAttachmentChecker(), closeChecks: closeChecks)
        var isValid = true
        var validityChecks = 0
        var handlerRunCount = 0
        sut.presentModalPromptIfNeeded(from: presenterMock)
        #expect(sut.runOnceModalPromptCloses(while: {
            validityChecks += 1
            return isValid
        }, { handlerRunCount += 1 }))

        isValid = false
        closeChecks.executeScheduledBlock()
        let checksAfterCancellation = validityChecks
        schedulerMock.executeScheduledBlock()
        closeChecks.executeScheduledBlock()

        #expect(validityChecks == checksAfterCancellation)
        #expect(handlerRunCount == 0)
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
            modalPromptScheduling: schedulerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)
        schedulerMock.executeScheduledBlock()

        // THEN
        #expect(!cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
    }

    // MARK: - Direct Presentation Tests

    @Test("Check Modal Is Presented From Presenter When Non-Dismissible ViewController Is Presented")
    func whenNonDismissibleViewControllerIsPresentedThenPresenterIsUsed() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider()
        let someVC = MockDismissibleViewController()
        presenterMock.presentedViewController = someVC
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
            onboardingStatusProvider: MockContextualOnboardingStatusProvider(hasSeenOnboarding: true),
            modalPromptScheduling: schedulerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)
        schedulerMock.executeScheduledBlock()

        // THEN
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
            modalPromptScheduling: schedulerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)
        schedulerMock.executeScheduledBlock()

        // THEN
        #expect(presenterMock.didCallPresent)
        #expect(provider.didCallDidPresentModal)
    }

}
