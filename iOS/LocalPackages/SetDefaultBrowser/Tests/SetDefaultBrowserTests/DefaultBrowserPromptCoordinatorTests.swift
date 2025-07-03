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
    private var dateProvideMock: MockDateProvider
    private var promptStoreMock: MockDefaultBrowserPromptStore
    private var userActivityManagerMock: MockDefaultBrowserPromptUserActivityManager
    private var promptTypeDeciderMock: MockDefaultBrowserPromptTypeDecider
    private var urlOpenerMock: MockURLOpener
    private var eventMapperMock: MockDefaultBrowserPromptEventMapping<DefaultBrowserPromptEvent>
    private var sut: DefaultBrowserPromptCoordinator!

    init() {
        dateProvideMock = MockDateProvider()
        promptStoreMock = MockDefaultBrowserPromptStore()
        userActivityManagerMock = MockDefaultBrowserPromptUserActivityManager()
        promptTypeDeciderMock = MockDefaultBrowserPromptTypeDecider()
        urlOpenerMock = MockURLOpener()
        eventMapperMock = MockDefaultBrowserPromptEventMapping<DefaultBrowserPromptEvent>()

        sut = DefaultBrowserPromptCoordinator(
            isOnboardingCompleted: { self.isOnboardingCompleted },
            promptStore: promptStoreMock,
            userActivityManager: userActivityManagerMock,
            promptTypeDecider: promptTypeDeciderMock,
            urlOpener: urlOpenerMock,
            eventMapper: eventMapperMock,
            dateProvider: dateProvideMock.getDate
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
            DefaultBrowserPromptType.firstModal,
            .secondModal,
            .subsequentModal
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
            DefaultBrowserPromptType.firstModal,
            .secondModal,
            .subsequentModal
        ]
    )
    func whenPromptIsNotNilThenPromptIsSetSeen(promptType: DefaultBrowserPromptType) {
        // GIVEN
        let now = Date(timeIntervalSince1970: 1750896000) // 26 June 2025 12:00:00 AM GMT
        dateProvideMock.setNowDate(now)
        promptTypeDeciderMock.promptToReturn = promptType
        #expect(promptStoreMock.lastModalShownDate == nil)

        // WHEN
        _ = sut.getPrompt()

        // THEN
        #expect(promptStoreMock.lastModalShownDate == now.timeIntervalSince1970)
    }

    @Test(
        "Check Prompt Occurrence Is Incremented When Prompt Is Not Nil",
        arguments: [
            DefaultBrowserPromptType.firstModal,
            .secondModal,
            .subsequentModal
        ],
        [
            1, 2, 3, 4, 5, 6, 7, 8, 9, 10
        ]
    )
    func whenPromptIsNotNilThenI(promptType: DefaultBrowserPromptType, numberOfModalShown: Int) {
        // GIVEN
        let now = Date(timeIntervalSince1970: 1750896000) // 26 June 2025 12:00:00 AM GMT
        dateProvideMock.setNowDate(now)
        promptTypeDeciderMock.promptToReturn = promptType
        promptStoreMock.modalShownOccurrences = numberOfModalShown

        // WHEN
        _ = sut.getPrompt()

        // THEN
        #expect(promptStoreMock.modalShownOccurrences == numberOfModalShown + 1)
    }

    @Test(
        "Check User Activity Is Reset Once The Prompt Is Shown",
        arguments: [
            DefaultBrowserPromptType.firstModal,
            .secondModal,
            .subsequentModal
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

    @Test("Check Set Default Browser Action Opens Settings URL")
    func whenSetDefaultBrowserActionIsCalledThenSettingsUrlIsOpened() {
        // GIVEN
        #expect(!urlOpenerMock.didCallOpenURL)
        #expect(urlOpenerMock.capturedURL == nil)

        // WHEN
        sut.setDefaultBrowserAction()

        // THEN
        #expect(urlOpenerMock.didCallOpenURL)
        #expect(urlOpenerMock.capturedURL == URL(string: UIApplication.openSettingsURLString))
    }

    @Test(
        "Check Dismiss Action Set Permanently Dismissed Only When Action Is To Dismiss Modal Permanently",
        arguments: [
            false,
            true
        ]
    )
    func whenDismissActionIsCalledThenPermanentlyDismissedIsSetOnlyWhenNeeded(shouldDismissPromptPermanently: Bool) {
        // GIVEN
        #expect(!promptStoreMock.isPromptPermanentlyDismissed)

        // WHEN
        sut.dismissAction(shouldDismissPromptPermanently: shouldDismissPromptPermanently)

        // THEN
        #expect(promptStoreMock.isPromptPermanentlyDismissed == shouldDismissPromptPermanently)
    }

    // MARK: - Events

    @Test(
        "Check Modal Shown Event Is Sent Along With Number Of Modal Shown",
        arguments: [
            DefaultBrowserPromptType.firstModal,
            .secondModal,
            .subsequentModal
        ],
        [
            0,
            1,
            2,
            5,
            15
        ]
    )
    func whenModalShownThenModalShownEventIsSent(promptType: DefaultBrowserPromptType, numberOfModalAlreadyShown: Int) async throws {
        // GIVEN
        promptStoreMock.modalShownOccurrences = numberOfModalAlreadyShown
        promptTypeDeciderMock.promptToReturn = promptType
        #expect(!eventMapperMock.didCallFireEvent)
        #expect(eventMapperMock.capturedEvent == nil)

        // WHEN
        _ = sut.getPrompt()

        // THEN
        #expect(eventMapperMock.didCallFireEvent)
        #expect(eventMapperMock.capturedEvent == .modalShown(numberOfModalShown: numberOfModalAlreadyShown+1))
    }

    @Test(
        "Check Modal Actioned Event is Sent Along With Number Of Modal Shown",
          arguments: [
              0,
              1,
              2,
              5,
              15
          ]
    )
    func whenSetDefaultBrowserActionThenModalActionedEventIsSent(numberOfModalAlreadyShown: Int) {
        // GIVEN
        promptStoreMock.modalShownOccurrences = numberOfModalAlreadyShown
        #expect(!eventMapperMock.didCallFireEvent)
        #expect(eventMapperMock.capturedEvent == nil)

        // WHEN
        sut.setDefaultBrowserAction()

        // THEN
        #expect(eventMapperMock.didCallFireEvent)
        #expect(eventMapperMock.capturedEvent == .modalActioned(numberOfModalShown: numberOfModalAlreadyShown))
    }

    @Test(
        "Check Modal Dismissed Event Is Sent Correctly",
        arguments: [
            false,
            true
        ]
    )
    func whenDismissActionIsCalledThenModalDismissedEventIsSent(shouldDismissPromptPermanently: Bool) {
        // GIVEN
        let expectedEvent: DefaultBrowserPromptEvent = shouldDismissPromptPermanently ? .modalDismissedPermanently : .modalDismissed
        #expect(!eventMapperMock.didCallFireEvent)
        #expect(eventMapperMock.capturedEvent == nil)

        // WHEN
        sut.dismissAction(shouldDismissPromptPermanently: shouldDismissPromptPermanently)

        // THEN
        #expect(eventMapperMock.didCallFireEvent)
        #expect(eventMapperMock.capturedEvent == expectedEvent)
    }

}
