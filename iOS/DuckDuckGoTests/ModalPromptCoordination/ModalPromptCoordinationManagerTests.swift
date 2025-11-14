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
            modalPromptScheduling: schedulerMock
        )
        #expect(!cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)
        schedulerMock.executeScheduledBlock()

        // THEN
        #expect(cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
    }

    @Test("Check Cooldown Is Not Recorded When No Modal Is Presented")
    func whenNoModalIsPresentedThenCooldownIsNotRecorded() {
        // GIVEN
        cooldownManagerMock.cooldownInfoToReturn = .notInCoolDown
        let provider = MockModalPromptProvider(shouldReturnPrompt: false)
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManagerMock,
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
            modalPromptScheduling: schedulerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)
        schedulerMock.executeScheduledBlock()

        // THEN
        #expect(!cooldownManagerMock.didCallRecordLastPromptPresentationTimestamp)
    }
}
