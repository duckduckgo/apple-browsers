//
//  DefaultBrowserPromptCoordinatorTests.swift
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

import Foundation
import class UIKit.UIApplication
import Testing
import SetDefaultBrowserTestSupport
@testable import SetDefaultBrowserCore

@MainActor
@Suite("Set Default Browser - Prompt Coordinator")
final class DefaultBrowserPromptCoordinatorTests {
    private var isOnboardingCompleted: Bool = true
    private var dateProviderMock: MockDateProvider
    private var promptStoreMock: MockDefaultBrowserPromptStore
    private var userActivityManagerMock: MockDefaultBrowserPromptUserActivityManager
    private var promptTypeDeciderMock: MockDefaultBrowserPromptTypeDecider
    private var defaultBrowserSettingsNavigator: MockDefaultBrowserPromptSettingsNavigating
    private var eventMapperMock: MockDefaultBrowserPromptEventMapping<DefaultBrowserPromptEvent>
    private var sut: DefaultBrowserPromptCoordinator!

    init() {
        dateProviderMock = MockDateProvider()
        promptStoreMock = MockDefaultBrowserPromptStore()
        userActivityManagerMock = MockDefaultBrowserPromptUserActivityManager()
        promptTypeDeciderMock = MockDefaultBrowserPromptTypeDecider()
        defaultBrowserSettingsNavigator = MockDefaultBrowserPromptSettingsNavigating()
        eventMapperMock = MockDefaultBrowserPromptEventMapping<DefaultBrowserPromptEvent>()

        sut = DefaultBrowserPromptCoordinator(
            isOnboardingCompleted: { self.isOnboardingCompleted },
            promptStore: promptStoreMock,
            userActivityManager: userActivityManagerMock,
            promptTypeDecider: promptTypeDeciderMock,
            defaultBrowserSettingsNavigator: defaultBrowserSettingsNavigator,
            eventMapper: eventMapperMock,
            dateProvider: dateProviderMock.getDate
        )
    }

    @Test("Check Prompt Is Nil When Onboarding Is Not Completed")
    func whenOnboardingNotCompletedThenPromptIsNil() {
        // GIVEN
        isOnboardingCompleted = false
        #expect(!promptTypeDeciderMock.didCallPromptType)

        // WHEN
        let result = sut.getPrompt()

        // THEN
        #expect(!promptTypeDeciderMock.didCallPromptType)
        #expect(result == nil)
    }

    @Test("Check Prompt Is Nil When Onboarding Is Not Completed")
    func whenPromptDeciderReturnsNilThenPromptIsNil() {
        // GIVEN
        promptTypeDeciderMock.promptToReturn = nil
        #expect(!promptTypeDeciderMock.didCallPromptType)

        // WHEN
        let result = sut.getPrompt()

        // THEN
        #expect(promptTypeDeciderMock.didCallPromptType)
        #expect(result == nil)
    }

    @Test(
        "Check Prompt Return the Correct Prompt When Prompt Decider Returns Prompt",
        arguments: [
            DefaultBrowserPromptType.active(.firstModal),
            .active(.secondModal),
            .active(.subsequentModal)
        ]
    )
    func whenPromptDeciderReturnsPromptThenPromptIsReturned(promptType: DefaultBrowserPromptType) {
        // GIVEN
        promptTypeDeciderMock.promptToReturn = promptType
        #expect(!promptTypeDeciderMock.didCallPromptType)

        // WHEN
        let result = sut.getPrompt()

        // THEN
        #expect(promptTypeDeciderMock.didCallPromptType)
        #expect(result == .activeUserModal)
    }

    @Test(
        "Check Prompt Is Set Seen When Prompt Is Not Nil",
        arguments: [
            DefaultBrowserPromptType.active(.firstModal),
            .active(.secondModal),
            .active(.subsequentModal),
            .inactive
        ]
    )
    func whenPromptIsNotNilThenPromptIsSetSeen(promptType: DefaultBrowserPromptType) {
        // GIVEN
        let now = Date(timeIntervalSince1970: 1750896000) // 26 June 2025 12:00:00 AM GMT
        dateProviderMock.setNowDate(now)
        promptTypeDeciderMock.promptToReturn = promptType
        #expect(promptStoreMock.lastModalShownDate == nil)

        // WHEN
        _ = sut.getPrompt()

        // THEN
        #expect(promptStoreMock.lastModalShownDate == now.timeIntervalSince1970)
    }

    @Test(
        "Check Prompt Occurrence Is Incremented For Active Modals When Prompt Is Not Nil",
        arguments: [
            DefaultBrowserPromptType.active(.firstModal),
            .active(.secondModal),
            .active(.subsequentModal),
            .inactive
        ],
        [
            1, 2, 3, 4, 5, 6, 7, 8, 9, 10
        ]
    )
    func whenPromptIsNotNilThenI(promptType: DefaultBrowserPromptType, numberOfModalShown: Int) {
        // GIVEN
        let now = Date(timeIntervalSince1970: 1750896000) // 26 June 2025 12:00:00 AM GMT
        dateProviderMock.setNowDate(now)
        promptTypeDeciderMock.promptToReturn = promptType
        promptStoreMock.modalShownOccurrences = numberOfModalShown

        // WHEN
        _ = sut.getPrompt()

        // THEN
        let expectedNumberOfModalShown = promptType.isActiveModal ? numberOfModalShown + 1 : numberOfModalShown
        #expect(promptStoreMock.modalShownOccurrences == expectedNumberOfModalShown)
    }

    @Test(
        "Check Inactive Modal Flag Is Set When Prompt Is Inactive",
        arguments: zip(
            [
                DefaultBrowserPromptType.active(.firstModal),
                .active(.secondModal),
                .active(.subsequentModal),
                .inactive
            ],
            [
                false,
                false,
                false,
                true
            ]
        )
    )
    func whenPromptIsNotNilThenI(promptType: DefaultBrowserPromptType, expectedHasInactiveModalShownFlag: Bool) {
        // GIVEN
        promptTypeDeciderMock.promptToReturn = promptType

        // WHEN
        _ = sut.getPrompt()

        // THEN
        #expect(promptStoreMock.hasInactiveModalShown == expectedHasInactiveModalShownFlag)
    }

    @Test(
        "Check User Activity Is Reset Once The Prompt Is Shown",
        arguments: [
            DefaultBrowserPromptType.active(.firstModal),
            .active(.secondModal),
            .active(.subsequentModal)
        ]
    )
    func whenPromptIsShownThenUserActivityIsReset(promptType: DefaultBrowserPromptType) {
        // GIVEN
        promptTypeDeciderMock.promptToReturn = promptType
        #expect(!userActivityManagerMock.didCallResetNumberOfActiveDays)

        // WHEN
        _ = sut.getPrompt()

        // THEN
        #expect(userActivityManagerMock.didCallResetNumberOfActiveDays)
    }

    // MARK: - Actions

    @Test("Check Set Default Browser Action Navigate To Default Browser Settings", arguments: [DefaultBrowserPromptPresentationType.activeUserModal, .inactiveUserModal])
    func whenSetDefaultBrowserActionIsCalledThenAskNavigatorToNavigateToDefaultBrowser(promptType: DefaultBrowserPromptPresentationType) {
        // GIVEN
        #expect(!defaultBrowserSettingsNavigator.didCallNavigateToSetDefaultBrowserSettings)

        // WHEN
        sut.setDefaultBrowserAction(forPrompt: promptType)

        // THEN
        #expect(defaultBrowserSettingsNavigator.didCallNavigateToSetDefaultBrowserSettings)
    }

    @Test(
        "Check Dismiss Action Set Permanently Dismissed Only When Action Is To Dismiss Modal Permanently",
        arguments: [
            DefaultBrowserPromptPresentationType.activeUserModal,
            .inactiveUserModal
        ],
        [
            false,
            true
        ]
    )
    func whenDismissActionIsCalledThenPermanentlyDismissedIsSetOnlyWhenNeeded(prompt: DefaultBrowserPromptPresentationType, shouldDismissPromptPermanently: Bool) {
        // GIVEN
        #expect(!promptStoreMock.isPromptPermanentlyDismissed)

        // WHEN
        sut.dismissAction(forPrompt: prompt, shouldDismissPromptPermanently: shouldDismissPromptPermanently)

        // THEN
        let expectedDismissPermanently = prompt == .inactiveUserModal ? false : shouldDismissPromptPermanently
        #expect(promptStoreMock.isPromptPermanentlyDismissed == expectedDismissPermanently)
    }

    // MARK: - Events

    @Test(
        "Check Active User Modal Shown Event Is Sent Along With Number Of Modal Shown",
        arguments: [
            DefaultBrowserPromptType.active(.firstModal),
            .active(.secondModal),
            .active(.subsequentModal)
        ],
        [
            0,
            1,
            2,
            5,
            15
        ]
    )
    func whenActiveUserModalShownThenActiveModalShownEventIsSent(promptType: DefaultBrowserPromptType, numberOfModalAlreadyShown: Int) async throws {
        // GIVEN
        promptStoreMock.modalShownOccurrences = numberOfModalAlreadyShown
        promptTypeDeciderMock.promptToReturn = promptType
        #expect(!eventMapperMock.didCallFireEvent)
        #expect(eventMapperMock.capturedEvent == nil)

        // WHEN
        _ = sut.getPrompt()

        // THEN
        #expect(eventMapperMock.didCallFireEvent)
        #expect(eventMapperMock.capturedEvent == .activeModalShown(numberOfModalShown: numberOfModalAlreadyShown+1))
    }

    @Test("Check Inactive User Modal Shown Event Is Sent")
    func whenInactiveUserModalShownThenInactiveModalShownEventIsSent() {
        // GIVEN
        promptTypeDeciderMock.promptToReturn = .inactive
        #expect(!eventMapperMock.didCallFireEvent)
        #expect(eventMapperMock.capturedEvent == nil)

        // WHEN
        _ = sut.getPrompt()

        // THEN
        #expect(eventMapperMock.didCallFireEvent)
        #expect(eventMapperMock.capturedEvent == .inactiveModalShown)
    }

    @Test(
        "Check Active User Modal Actioned Event is Sent Along With Number Of Modal Shown",
          arguments: [
              0,
              1,
              2,
              5,
              15
          ]
    )
    func whenSetDefaultBrowserActionForActiveUserModalThenActiveModalActionedEventIsSent(numberOfModalAlreadyShown: Int) {
        // GIVEN
        promptStoreMock.modalShownOccurrences = numberOfModalAlreadyShown
        #expect(!eventMapperMock.didCallFireEvent)
        #expect(eventMapperMock.capturedEvent == nil)

        // WHEN
        sut.setDefaultBrowserAction(forPrompt: .activeUserModal)

        // THEN
        #expect(eventMapperMock.didCallFireEvent)
        #expect(eventMapperMock.capturedEvent == .activeModalActioned(numberOfModalShown: numberOfModalAlreadyShown))
    }

    @Test("Check Inactive User Modal Actioned Event is Sent")
    func whenSetDefaultBrowserActionForInactiveUserModalThenInactiveModalActionedEventIsSent() {
        // GIVEN
        #expect(!eventMapperMock.didCallFireEvent)
        #expect(eventMapperMock.capturedEvent == nil)

        // WHEN
        sut.setDefaultBrowserAction(forPrompt: .inactiveUserModal)

        // THEN
        #expect(eventMapperMock.didCallFireEvent)
        #expect(eventMapperMock.capturedEvent == .inactiveModalActioned)
    }

    @Test(
        "Check Active Modal Dismissed Event Is Sent Correctly For Active Modal",
        arguments: [
            false,
            true
        ]
    )
    func whenDismissActionForActiveUserModalThenActiveModalDismissedEventIsSent(shouldDismissPromptPermanently: Bool) {
        // GIVEN
        let expectedEvent: DefaultBrowserPromptEvent = shouldDismissPromptPermanently ? .activeModalDismissedPermanently : .activeModalDismissed
        #expect(!eventMapperMock.didCallFireEvent)
        #expect(eventMapperMock.capturedEvent == nil)

        // WHEN
        sut.dismissAction(forPrompt: .activeUserModal, shouldDismissPromptPermanently: shouldDismissPromptPermanently)

        // THEN
        #expect(eventMapperMock.didCallFireEvent)
        #expect(eventMapperMock.capturedEvent == expectedEvent)
    }

    @Test(
        "Check Inactive User Modal Dismissed Event Is Sent Correctly For Inactive Modal",
        arguments: [
            false,
            true
        ]
    )
    func whenDismissActionIsCalledForInactiveUserModalThenInactiveModalDismissedEventIsSent(shouldDismissPromptPermanently: Bool) {
        // GIVEN
        #expect(!eventMapperMock.didCallFireEvent)
        #expect(eventMapperMock.capturedEvent == nil)

        // WHEN
        sut.dismissAction(forPrompt: .inactiveUserModal, shouldDismissPromptPermanently: shouldDismissPromptPermanently)

        // THEN
        #expect(eventMapperMock.didCallFireEvent)
        #expect(eventMapperMock.capturedEvent == .inactiveModalDismissed)
    }

    @Test("Check Inactive User Modal More Protection Event Is Sent Correctly For Inactive Modal")
    func whenMoreProtectionActionIsCalledForInactiveUserModalThenMoreProtectionActionEventIsSent() {
        // GIVEN
        #expect(!eventMapperMock.didCallFireEvent)
        #expect(eventMapperMock.capturedEvent == nil)

        // WHEN
        sut.moreProtectionsAction()

        // THEN
        #expect(eventMapperMock.didCallFireEvent)
        #expect(eventMapperMock.capturedEvent == .inactiveModalMoreProtectionsAction)
    }

}

private extension DefaultBrowserPromptType {

    var isActiveModal: Bool {
        switch self {
        case .active:
            return true
        case .inactive:
            return false
        }
    }

}
