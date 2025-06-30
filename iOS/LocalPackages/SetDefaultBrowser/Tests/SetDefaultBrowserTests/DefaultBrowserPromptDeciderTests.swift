//
//  DefaultBrowserPromptDeciderTests.swift
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
import Testing
import SetDefaultBrowserTestSupport
@testable import SetDefaultBrowserCore

@MainActor
@Suite("Set Default Browser - Prompt Decider")
final class DefaultBrowserPromptDeciderTests {
    private var featureFlaggerMock = MockDefaultBrowserPromptFeatureFlag()
    private var storeMock = MockDefaultBrowserPromptStore()
    private var userTypeProviderMock = MockDefaultBrowserPromptUserTypeProvider()
    private var userActivityProviderMock = MockDefaultBrowserPromptUserActivityManager()
    private var defaultBrowserManagerMock = MockDefaultBrowserManager()
    private var dateProviderMock = MockDateProvider()
    private var sut: DefaultBrowserPromptTypeDecider!

    func makeSUT(installDate: Date? = nil) {
        sut = DefaultBrowserPromptTypeDecider(
            featureFlagger: featureFlaggerMock,
            store: storeMock,
            userTypeProvider: userTypeProviderMock,
            userActivityProvider: userActivityProviderMock,
            defaultBrowserManager: defaultBrowserManagerMock,
            installDateProvider: { installDate },
            dateProvider: dateProviderMock.getDate
        )
    }

    @Test("Check No Modal Is Presented When Feature Is Disabled")
    func checkPromptIsNilWhenFeatureFlagIsDisabled() {
        // GIVEN
        featureFlaggerMock.isDefaultBrowserPromptsFeatureEnabled = false
        makeSUT()
        #expect(!userTypeProviderMock.didCallCurrentUserType)

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == nil)
        #expect(!userTypeProviderMock.didCallCurrentUserType)
    }

    @Test("Check No Modal Is Presented When Prompt Is Permanently Dismissed")
    func checkPromptIsNilWhenPromptIsPermanentlyDismissed() {
        // GIVEN
        featureFlaggerMock.isDefaultBrowserPromptsFeatureEnabled = true
        storeMock.isPromptPermanentlyDismissed = true
        makeSUT()
        #expect(!userTypeProviderMock.didCallCurrentUserType)

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == nil)
        #expect(!userTypeProviderMock.didCallCurrentUserType)
    }

    @Test(
        "Check First Modal is Presented When No Modal Have Shown And Installation Date Is >= 1 day",
        arguments: [
            DefaultBrowserPromptUserType.new,
            .returning,
            .existing,
        ],
        [
            1, 10, 15
        ]
    )
    func checkFirstPromptIsPresentedForEveryTypeOfUserWhenNoModalHaveShownAndInstallationDateIsGreaterThanOneDay(userType: DefaultBrowserPromptUserType, daysSinceInstall: Int) {
        // GIVEN
        storeMock.lastModalShownDate = nil
        storeMock.modalShownOccurrences = 0
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: false)
        let installDate = Date(timeIntervalSince1970: 1750739150) // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        makeSUT(installDate: installDate)
        dateProviderMock.setNowDate(installDate)
        dateProviderMock.advanceBy(.days(daysSinceInstall))

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == .firstModal)
    }

    @Test(
        "Check Second Modal is Presented For New or Returning User When First Modal Has Shown And Number Of Active Days Is 4",
        arguments: [
            DefaultBrowserPromptUserType.new,
            .returning,
        ]
    )
    func checkSecondModalIsPresentedForNewAndReturningUserWhenFirstModalHasShownAndNumberOfActiveDaysIsFour(userType: DefaultBrowserPromptUserType) {
        // GIVEN
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: false)
        storeMock.lastModalShownDate = 1750739150 // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        storeMock.modalShownOccurrences = 1
        userTypeProviderMock.userType = userType
        userActivityProviderMock.numberOfActiveDaysPassed = 4
        featureFlaggerMock.secondModalDelayDays = 4
        makeSUT()

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == .secondModal)
    }

    @Test(
        "Check Second Modal is Not Presented For Existing User When First Modal Has Shown And Number Of Active Days Is 4",
        arguments: [
            DefaultBrowserPromptUserType.existing
        ]
    )
    func checkSecondModalIsNotPresentedForExistingUserWhenFirstModalHasShownAndNumberOfActiveDaysIsFour(userType: DefaultBrowserPromptUserType) {
        // GIVEN
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: false)
        storeMock.lastModalShownDate = 1750739150 // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        storeMock.modalShownOccurrences = 1
        userTypeProviderMock.userType = userType
        userActivityProviderMock.numberOfActiveDaysPassed = 4
        featureFlaggerMock.secondModalDelayDays = 4
        makeSUT()

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == nil)
    }

    @Test(
        "Check Subsequent Modal is Presented For New or Returning User When Second Modal Has Shown And Number Of Active Days Is 14",
        arguments: [
            DefaultBrowserPromptUserType.new,
            .returning,
        ]
    )
    func checkSubsequentModalIsPresentedForNewAndReturningUserWhenSecondModalHasShownAndNumberOfActiveDaysIsFourteen(userType: DefaultBrowserPromptUserType) {
        // GIVEN
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: false)
        storeMock.lastModalShownDate = 1750739150 // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        storeMock.modalShownOccurrences = 2
        userTypeProviderMock.userType = userType
        userActivityProviderMock.numberOfActiveDaysPassed = 14
        featureFlaggerMock.subsequentModalRepeatIntervalDays = 14
        makeSUT()

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == .subsequentModal)
    }

    @Test(
        "Check Subsequent Modal is Presented For Existing User When First Modal Has Shown And Number Of Active Days Is 14",
        arguments: [
            DefaultBrowserPromptUserType.existing,
        ]
    )
    func checkSubsequentModalIsPresentedForExistingUserWhenFirstModalHasShownAndNumberOfActiveDaysIsFourteen(userType: DefaultBrowserPromptUserType) {
        // GIVEN
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: false)
        storeMock.lastModalShownDate = 1750739150 // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        storeMock.modalShownOccurrences = 1
        userTypeProviderMock.userType = userType
        userActivityProviderMock.numberOfActiveDaysPassed = 14
        featureFlaggerMock.subsequentModalRepeatIntervalDays = 14
        makeSUT()

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == .subsequentModal)
    }

    @Test(
        "Check Subsequent Modal is Presented For New Or Returning User When Last Modal Has Shown And Number Of Active Days Is 14",
        arguments: [
            DefaultBrowserPromptUserType.new,
            .returning,
        ],
        [
            2, 3, 4, 5, 6, 7, 8, 9, 10
        ]
    )
    func checkSubsequentModalIsPresentedForNewOrReturningUserWhenLastModalHasShownAndNumberOfActiveDaysIsFourteen(userType: DefaultBrowserPromptUserType, numberOfModalShown: Int) {
        // GIVEN
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: false)
        storeMock.lastModalShownDate = 1750739150 // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        storeMock.modalShownOccurrences = numberOfModalShown
        userTypeProviderMock.userType = userType
        userActivityProviderMock.numberOfActiveDaysPassed = 14
        featureFlaggerMock.subsequentModalRepeatIntervalDays = 14
        makeSUT()

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == .subsequentModal)
    }

    @Test(
        "Check Subsequent Modal is Presented For Existing User When Last Modal Has Shown And Number Of Active Days Is 14",
        arguments: [
            DefaultBrowserPromptUserType.existing,
        ],
        [
            2, 3, 4, 5, 6, 7, 8, 9, 10
        ]
    )
    func checkSubsequentModalIsPresentedForExistingUserWhenLastModalHasShownAndNumberOfActiveDaysIsFourteen(userType: DefaultBrowserPromptUserType, numberOfModalShown: Int) {
        // GIVEN
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: false)
        storeMock.lastModalShownDate = 1750739150 // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        storeMock.modalShownOccurrences = numberOfModalShown
        userTypeProviderMock.userType = userType
        userActivityProviderMock.numberOfActiveDaysPassed = 14
        featureFlaggerMock.subsequentModalRepeatIntervalDays = 14
        makeSUT()

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == .subsequentModal)
    }

    @Test("Check Prompt Is Not Shown If User Type could not be determined")
    func checkPromptIsNotShownIfUserTypeCouldNotBeDetermined() {
        // GIVEN
        storeMock.lastModalShownDate = nil
        storeMock.modalShownOccurrences = 0
        userTypeProviderMock.userType = nil
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: false)
        let installDate = Date(timeIntervalSince1970: 1750739150) // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        makeSUT(installDate: installDate)
        dateProviderMock.setNowDate(installDate)
        dateProviderMock.advanceBy(.days(2))

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == nil)
    }

    @Test(
        "Check Full Flow Correctness For New and Returning User",
        arguments: [
            DefaultBrowserPromptUserType.new,
                .returning
        ]
    )
    func checkFullFlowCorrectnessForNewAndReturningUser(userType: DefaultBrowserPromptUserType) {
        // GIVEN
        featureFlaggerMock.firstModalDelayDays = 1
        featureFlaggerMock.secondModalDelayDays = 4
        featureFlaggerMock.subsequentModalRepeatIntervalDays = 14
        userTypeProviderMock.userType = userType
        storeMock.lastModalShownDate = nil
        storeMock.modalShownOccurrences = 0
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: false)
        let installDate = Date(timeIntervalSince1970: 1750739150) // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        makeSUT(installDate: installDate)
        dateProviderMock.setNowDate(installDate)

        // Install day < 1 day. Then no Modal should show
        #expect(sut.promptType() == nil)

        // Install day == 1 day. Show First Modal
        dateProviderMock.advanceBy(.days(1))
        #expect(sut.promptType() == .firstModal)
        storeMock.lastModalShownDate = dateProviderMock.getDate().timeIntervalSince1970
        storeMock.modalShownOccurrences = 1

        // Active days after first modal < 4. Do not show any modal.
        userActivityProviderMock.numberOfActiveDaysPassed = 3
        #expect(sut.promptType() == nil)

        // Active days after first modal == 4. Show second modal.
        userActivityProviderMock.numberOfActiveDaysPassed = 4
        #expect(sut.promptType() == .secondModal)
        storeMock.modalShownOccurrences = 2

        // Active days after second modal == 10. Do not show second modal.
        userActivityProviderMock.numberOfActiveDaysPassed = 10
        #expect(sut.promptType() == nil)

        // Active days after second modal == 14. Show subsequent modal.
        userActivityProviderMock.numberOfActiveDaysPassed = 14
        #expect(sut.promptType() == .subsequentModal)
        storeMock.modalShownOccurrences = 3

        // Active days for subsequent modal == 10. Do not show subsequent modal.
        userActivityProviderMock.numberOfActiveDaysPassed = 10
        #expect(sut.promptType() == nil)

        // Active days for subsequent modal == 14. Show subsequent modal.
        userActivityProviderMock.numberOfActiveDaysPassed = 14
        #expect(sut.promptType() == .subsequentModal)
        storeMock.modalShownOccurrences = 4

        // Browser is set to Default and active days for subsequent modal == 14. Do Not show modal.
        userActivityProviderMock.numberOfActiveDaysPassed = 14
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: true)
        #expect(sut.promptType() == nil)
    }

    @Test("Check Full Flow Correctness For Existing User", arguments: [DefaultBrowserPromptUserType.existing])
    func checkFullFlowCorrectnessForExistingUser(userType: DefaultBrowserPromptUserType) {
        featureFlaggerMock.firstModalDelayDays = 1
        featureFlaggerMock.secondModalDelayDays = 4
        featureFlaggerMock.subsequentModalRepeatIntervalDays = 14
        userTypeProviderMock.userType = userType
        storeMock.lastModalShownDate = nil
        storeMock.modalShownOccurrences = 0
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: false)
        let installDate = Date(timeIntervalSince1970: 1750739150) // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        makeSUT(installDate: installDate)
        dateProviderMock.setNowDate(installDate)

        // Install day < 1 day. Then no Modal should show
        #expect(sut.promptType() == nil)

        // Install day == 1 day. Show First Modal
        dateProviderMock.advanceBy(.days(1))
        #expect(sut.promptType() == .firstModal)
        storeMock.lastModalShownDate = dateProviderMock.getDate().timeIntervalSince1970
        storeMock.modalShownOccurrences = 1

        // Active days after first modal < 4. Do not show any modal.
        userActivityProviderMock.numberOfActiveDaysPassed = 3
        #expect(sut.promptType() == nil)

        // Active days after first modal == 4. Do not show second modal for existing user.
        userActivityProviderMock.numberOfActiveDaysPassed = 4
        #expect(sut.promptType() == nil)

        // Active days after second modal == 10. Do not show second modal.
        userActivityProviderMock.numberOfActiveDaysPassed = 10
        #expect(sut.promptType() == nil)

        // Active days after second modal == 14. Show subsequent modal.
        userActivityProviderMock.numberOfActiveDaysPassed = 14
        #expect(sut.promptType() == .subsequentModal)
        storeMock.modalShownOccurrences = 2

        // Active days for subsequent modal == 10. Do not show subsequent modal.
        userActivityProviderMock.numberOfActiveDaysPassed = 10
        #expect(sut.promptType() == nil)

        // Active days for subsequent modal == 14. Show subsequent modal.
        userActivityProviderMock.numberOfActiveDaysPassed = 14
        #expect(sut.promptType() == .subsequentModal)
        storeMock.modalShownOccurrences = 3

        // Browser is set to Default and active days for subsequent modal == 14. Do Not show modal.
        userActivityProviderMock.numberOfActiveDaysPassed = 14
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: true)
        #expect(sut.promptType() == nil)
    }

}
