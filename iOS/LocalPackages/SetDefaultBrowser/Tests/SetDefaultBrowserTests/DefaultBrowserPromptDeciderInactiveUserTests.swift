//
//  DefaultBrowserPromptDeciderInactiveUserTests.swift
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
@Suite("Default Browser Prompt - Inactive User Prompt")
struct DefaultBrowserPromptDeciderInactiveUserTests {
    private let featureFlaggerMock = MockDefaultBrowserPromptFeatureFlag()
    private let storeMock = MockDefaultBrowserPromptStore()
    private let userActivityProviderMock = MockDefaultBrowserPromptUserActivityManager()

    func makeSUT(daysSinceInstall: Int) -> DefaultBrowserPromptTypeDecider.InactiveUser {
        DefaultBrowserPromptTypeDecider.InactiveUser(
            featureFlagger: featureFlaggerMock,
            store: storeMock,
            userActivityProvider: userActivityProviderMock,
            daysSinceInstallProvider: { daysSinceInstall }
        )
    }

    @Test("Check Prompt Type Is Nil When It Should Show But Feature Flag Is Off")
    func whenFeatureFlagIsOffThenReturnNil() {
        // GIVEN
        featureFlaggerMock.isDefaultBrowserPromptsForInactiveUsersFeatureEnabled = false
        storeMock.hasInactiveModalShown = false
        userActivityProviderMock.numberOfInactiveDaysPassed = 40
        let numberOfDaysSinceInstall: Int = 30
        let sut = makeSUT(daysSinceInstall: numberOfDaysSinceInstall)

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == nil)
    }

    @Test("Check Prompt Type Is Nil When It Has Already Shown")
    func whenHasInactiveModalShownStoreValueIsTrueThenReturnFalse() {
        // GIVEN
        featureFlaggerMock.isDefaultBrowserPromptsForInactiveUsersFeatureEnabled = true
        storeMock.hasInactiveModalShown = true
        userActivityProviderMock.numberOfInactiveDaysPassed = 40
        let numberOfDaysSinceInstall: Int = 30
        let sut = makeSUT(daysSinceInstall: numberOfDaysSinceInstall)

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == nil)
    }

    @Test("Check Prompt Type Is Nil When Number Of Inactive Days Is Less Than 7")
    func whenNumberOfInactiveDaysIsLessThan7ThenReturnFalse() {
        // GIVEN
        featureFlaggerMock.isDefaultBrowserPromptsForInactiveUsersFeatureEnabled = true
        storeMock.hasInactiveModalShown = false
        userActivityProviderMock.numberOfInactiveDaysPassed = 5
        let numberOfDaysSinceInstall: Int = 30
        let sut = makeSUT(daysSinceInstall: numberOfDaysSinceInstall)

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == nil)
    }

    @Test("Check Prompt Type Is Nil When Number Of Days Since Install Is Less Than 28")
    func whenNumberOfDaysSinceInstallIsLessThan28ThenReturnFalse() {
        // GIVEN
        featureFlaggerMock.isDefaultBrowserPromptsForInactiveUsersFeatureEnabled = true
        storeMock.hasInactiveModalShown = false
        userActivityProviderMock.numberOfInactiveDaysPassed = 10
        let numberOfDaysSinceInstall: Int = 27
        let sut = makeSUT(daysSinceInstall: numberOfDaysSinceInstall)

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == nil)
    }

    @Test("Check Prompt Type Is Inactive When Modal Has Not Shown, Number Of Inactive Days Is Greater Than 7 And Number Of Days Since Install Is Greater Than 28")
    func checkPromptTypeIsInactive() {
        // GIVEN
        featureFlaggerMock.isDefaultBrowserPromptsForInactiveUsersFeatureEnabled = true
        storeMock.hasInactiveModalShown = false
        userActivityProviderMock.numberOfInactiveDaysPassed = 10
        let numberOfDaysSinceInstall: Int = 28
        let sut = makeSUT(daysSinceInstall: numberOfDaysSinceInstall)

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == .inactive)
    }

    @Test("Check Prompt Type Is Inactive When Modal Has Not Shown, Number Of Inactive Days Is Greater Than 7 And Number Of Days Since Install Is Greater Than 28")
    func checkRulesToShowThePromptAreReadFromFeatureFlaggerSettings() {
        // GIVEN
        featureFlaggerMock.isDefaultBrowserPromptsForInactiveUsersFeatureEnabled = true
        featureFlaggerMock.inactiveModalNumberOfInactiveDays = 1
        featureFlaggerMock.inactiveModalNumberOfDaysSinceInstall = 2
        storeMock.hasInactiveModalShown = false
        userActivityProviderMock.numberOfInactiveDaysPassed = 1
        let numberOfDaysSinceInstall: Int = 2
        let sut = makeSUT(daysSinceInstall: numberOfDaysSinceInstall)

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == .inactive)
    }
}
