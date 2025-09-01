//
//  DefaultBrowserPromptDeciderActiveUserTests.swift
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
@Suite("Set Default Browser - Active User Prompt Decider")
final class DefaultBrowserPromptDeciderActiveUserTests {
    private var featureFlaggerMock = MockDefaultBrowserPromptFeatureFlag()
    private var storeMock = MockDefaultBrowserPromptStore()
    private var userTypeProviderMock = MockDefaultBrowserPromptUserTypeProvider()
    private var userActivityProviderMock = MockDefaultBrowserPromptUserActivityManager()
    private var sut: DefaultBrowserPromptTypeDecider.ActiveUser!

    func makeSUT(numberOfDaysSinceInstall: Int = 0) {
        sut = DefaultBrowserPromptTypeDecider.ActiveUser(
            featureFlagger: featureFlaggerMock,
            store: storeMock,
            userTypeProvider: userTypeProviderMock,
            userActivityProvider: userActivityProviderMock,
            daysSinceInstallProvider: { numberOfDaysSinceInstall },
        )
    }

    @Test("Check No Modal Is Presented When Feature Is Disabled")
    func checkPromptIsNilWhenFeatureFlagIsDisabled() {
        // GIVEN
        featureFlaggerMock.isDefaultBrowserPromptsForActiveUsersFeatureEnabled = false
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
        makeSUT(numberOfDaysSinceInstall: 1)

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == .active(.firstModal))
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
        storeMock.lastModalShownDate = 1750739150 // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        storeMock.modalShownOccurrences = 1
        userTypeProviderMock.userType = userType
        userActivityProviderMock.numberOfActiveDaysPassed = 4
        featureFlaggerMock.secondActiveModalDelayDays = 4
        makeSUT()

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == .active(.secondModal))
    }

    @Test(
        "Check Second Modal is Not Presented For Existing User When First Modal Has Shown And Number Of Active Days Is 4",
        arguments: [
            DefaultBrowserPromptUserType.existing
        ]
    )
    func checkSecondModalIsNotPresentedForExistingUserWhenFirstModalHasShownAndNumberOfActiveDaysIsFour(userType: DefaultBrowserPromptUserType) {
        // GIVEN
        storeMock.lastModalShownDate = 1750739150 // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        storeMock.modalShownOccurrences = 1
        userTypeProviderMock.userType = userType
        userActivityProviderMock.numberOfActiveDaysPassed = 4
        featureFlaggerMock.secondActiveModalDelayDays = 4
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
        storeMock.lastModalShownDate = 1750739150 // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        storeMock.modalShownOccurrences = 2
        userTypeProviderMock.userType = userType
        userActivityProviderMock.numberOfActiveDaysPassed = 14
        featureFlaggerMock.subsequentActiveModalRepeatIntervalDays = 14
        makeSUT()

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == .active(.subsequentModal))
    }

    @Test(
        "Check Subsequent Modal is Presented For Existing User When First Modal Has Shown And Number Of Active Days Is 14",
        arguments: [
            DefaultBrowserPromptUserType.existing,
        ]
    )
    func checkSubsequentModalIsPresentedForExistingUserWhenFirstModalHasShownAndNumberOfActiveDaysIsFourteen(userType: DefaultBrowserPromptUserType) {
        // GIVEN
        storeMock.lastModalShownDate = 1750739150 // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        storeMock.modalShownOccurrences = 1
        userTypeProviderMock.userType = userType
        userActivityProviderMock.numberOfActiveDaysPassed = 14
        featureFlaggerMock.subsequentActiveModalRepeatIntervalDays = 14
        makeSUT()

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == .active(.subsequentModal))
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
        storeMock.lastModalShownDate = 1750739150 // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        storeMock.modalShownOccurrences = numberOfModalShown
        userTypeProviderMock.userType = userType
        userActivityProviderMock.numberOfActiveDaysPassed = 14
        featureFlaggerMock.subsequentActiveModalRepeatIntervalDays = 14
        makeSUT()

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == .active(.subsequentModal))
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
        storeMock.lastModalShownDate = 1750739150 // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        storeMock.modalShownOccurrences = numberOfModalShown
        userTypeProviderMock.userType = userType
        userActivityProviderMock.numberOfActiveDaysPassed = 14
        featureFlaggerMock.subsequentActiveModalRepeatIntervalDays = 14
        makeSUT()

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == .active(.subsequentModal))
    }

    @Test("Check Prompt Is Not Shown If User Type could not be determined")
    func checkPromptIsNotShownIfUserTypeCouldNotBeDetermined() {
        // GIVEN
        storeMock.lastModalShownDate = nil
        storeMock.modalShownOccurrences = 0
        userTypeProviderMock.userType = nil
        makeSUT(numberOfDaysSinceInstall: 1)

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == nil)
    }
}
