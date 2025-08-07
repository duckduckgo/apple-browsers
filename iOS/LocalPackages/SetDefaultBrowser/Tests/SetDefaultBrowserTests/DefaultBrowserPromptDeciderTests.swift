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

    @Test("Check No Modal Is Presented When Prompt Is Permanently Dismissed")
    func checkPromptIsNilWhenPromptIsPermanentlyDismissed() {
        // GIVEN
        featureFlaggerMock.isDefaultBrowserPromptsForActiveUsersFeatureEnabled = true
        featureFlaggerMock.isDefaultBrowserPromptsForInactiveUsersFeatureEnabled = true
        storeMock.isPromptPermanentlyDismissed = true
        makeSUT()
        #expect(!userTypeProviderMock.didCallCurrentUserType)

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == nil)
        #expect(!userTypeProviderMock.didCallCurrentUserType)
    }

    @Test("Check No Modal Is Presented If A modal Has Already Been Shown In The Same Day")
    func checkNoModalIsNotPresentedWhenAModalHasAlreadyBeenShownInTheSameDay() {
        // GIVEN
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: false)
        let installDate = Date(timeIntervalSince1970: 1750739150) // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        let today = Date(timeIntervalSince1970: 1750739150) // Wednesday, 6 August 2025 8:01:24 AM
        storeMock.lastModalShownDate = today.timeIntervalSince1970
        makeSUT(installDate: installDate)
        dateProviderMock.setNowDate(today)

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == nil)
    }

    @Test("Check Inactive User Modal Has Priority Over Active User Modal")
    func checkInactiveUserModalIsCheckedBeforeActiveUser() {
        // GIVEN
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: false)
        let inactiveUserPromptDecider = MockDefaultBrowserPromptTypeDecider()
        inactiveUserPromptDecider.promptToReturn = .inactive
        let activeUserPromptDecider = MockDefaultBrowserPromptTypeDecider()
        activeUserPromptDecider.promptToReturn = .active(.firstModal)
        let installDate = Date(timeIntervalSince1970: 1750739150) // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        sut = DefaultBrowserPromptTypeDecider(
            featureFlagger: featureFlaggerMock,
            store: storeMock,
            activeUserPromptDecider: activeUserPromptDecider,
            inactiveUserPromptDecider: inactiveUserPromptDecider,
            defaultBrowserManager: defaultBrowserManagerMock,
            installDateProvider: { installDate },
            dateProvider: dateProviderMock.getDate
        )

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == .inactive)
    }

    @Test("Check Active User Modal Is Checked If Inactive User Modal Is Nil")
    func checkActiveUserModalIsReturnedWhenInactiveUserModalIsNil() {
        // GIVEN
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: false)
        let inactiveUserPromptDecider = MockDefaultBrowserPromptTypeDecider()
        inactiveUserPromptDecider.promptToReturn = nil
        let activeUserPromptDecider = MockDefaultBrowserPromptTypeDecider()
        activeUserPromptDecider.promptToReturn = .active(.firstModal)
        let installDate = Date(timeIntervalSince1970: 1750739150) // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        sut = DefaultBrowserPromptTypeDecider(
            featureFlagger: featureFlaggerMock,
            store: storeMock,
            activeUserPromptDecider: activeUserPromptDecider,
            inactiveUserPromptDecider: inactiveUserPromptDecider,
            defaultBrowserManager: defaultBrowserManagerMock,
            installDateProvider: { installDate },
            dateProvider: dateProviderMock.getDate
        )

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == .active(.firstModal))
    }

    @Test("Check Return Nil Modal If Inactive And Active Modals Are Nil")
    func checkModalIsNilWhenInactiveAndActiveUserModalIsNil() {
        // GIVEN
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: false)
        let inactiveUserPromptDecider = MockDefaultBrowserPromptTypeDecider()
        inactiveUserPromptDecider.promptToReturn = nil
        let activeUserPromptDecider = MockDefaultBrowserPromptTypeDecider()
        activeUserPromptDecider.promptToReturn = nil
        let installDate = Date(timeIntervalSince1970: 1750739150) // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        sut = DefaultBrowserPromptTypeDecider(
            featureFlagger: featureFlaggerMock,
            store: storeMock,
            activeUserPromptDecider: activeUserPromptDecider,
            inactiveUserPromptDecider: inactiveUserPromptDecider,
            defaultBrowserManager: defaultBrowserManagerMock,
            installDateProvider: { installDate },
            dateProvider: dateProviderMock.getDate
        )

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == nil)
    }

    @Test("Check Return Nil Modal If Inactive Should Be Prompted But Browser Already Is Default")
    func checkModalIsNilWhenInactiveModalShouldBePromptedButBrowserAlreadyIsDefault() {
        // GIVEN
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: true)
        let inactiveUserPromptDecider = MockDefaultBrowserPromptTypeDecider()
        inactiveUserPromptDecider.promptToReturn = .inactive
        let activeUserPromptDecider = MockDefaultBrowserPromptTypeDecider()
        activeUserPromptDecider.promptToReturn = .active(.firstModal)
        let installDate = Date(timeIntervalSince1970: 1750739150) // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        sut = DefaultBrowserPromptTypeDecider(
            featureFlagger: featureFlaggerMock,
            store: storeMock,
            activeUserPromptDecider: activeUserPromptDecider,
            inactiveUserPromptDecider: inactiveUserPromptDecider,
            defaultBrowserManager: defaultBrowserManagerMock,
            installDateProvider: { installDate },
            dateProvider: dateProviderMock.getDate
        )

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == nil)
    }

    @Test("Check Return Nil Modal If Active Should Be Prompted But Browser Already Is Default",
          arguments: [
            DefaultBrowserPromptType.active(.firstModal),
            .active(.secondModal),
            .active(.subsequentModal)
          ]
    )
    func checkModalIsNilWhenInactiveAndActiveUserModalIsNil(_ promptType: DefaultBrowserPromptType) {
        // GIVEN
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: true)
        let inactiveUserPromptDecider = MockDefaultBrowserPromptTypeDecider()
        inactiveUserPromptDecider.promptToReturn = nil
        let activeUserPromptDecider = MockDefaultBrowserPromptTypeDecider()
        activeUserPromptDecider.promptToReturn = promptType
        let installDate = Date(timeIntervalSince1970: 1750739150) // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        sut = DefaultBrowserPromptTypeDecider(
            featureFlagger: featureFlaggerMock,
            store: storeMock,
            activeUserPromptDecider: activeUserPromptDecider,
            inactiveUserPromptDecider: inactiveUserPromptDecider,
            defaultBrowserManager: defaultBrowserManagerMock,
            installDateProvider: { installDate },
            dateProvider: dateProviderMock.getDate
        )

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == nil)
    }

    @Test(
        "Check Full Flow Correctness Of Modal For New and Returning Active User",
        arguments: [
            DefaultBrowserPromptUserType.new,
                .returning
        ]
    )
    func checkFullFlowCorrectnessForNewAndReturningUser(userType: DefaultBrowserPromptUserType) {
        // GIVEN
        featureFlaggerMock.firstActiveModalDelayDays = 1
        featureFlaggerMock.secondActiveModalDelayDays = 4
        featureFlaggerMock.subsequentActiveModalRepeatIntervalDays = 14
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
        #expect(sut.promptType() == .active(.firstModal))
        storeMock.lastModalShownDate = dateProviderMock.getDate().timeIntervalSince1970
        storeMock.modalShownOccurrences = 1

        // Active days after first modal < 4. Do not show any modal.
        dateProviderMock.advanceBy(.days(3))
        userActivityProviderMock.numberOfActiveDaysPassed = 3
        #expect(sut.promptType() == nil)

        // Active days after first modal == 4. Show second modal.
        dateProviderMock.advanceBy(.days(1))
        userActivityProviderMock.numberOfActiveDaysPassed = 4
        #expect(sut.promptType() == .active(.secondModal))
        storeMock.modalShownOccurrences = 2

        // Active days after second modal == 10. Do not show second modal.
        dateProviderMock.advanceBy(.days(10))
        userActivityProviderMock.numberOfActiveDaysPassed = 10
        #expect(sut.promptType() == nil)

        // Active days after second modal == 14. Show subsequent modal.
        dateProviderMock.advanceBy(.days(4))
        userActivityProviderMock.numberOfActiveDaysPassed = 14
        #expect(sut.promptType() == .active(.subsequentModal))
        storeMock.modalShownOccurrences = 3

        // Active days for subsequent modal == 10. Do not show subsequent modal.
        dateProviderMock.advanceBy(.days(10))
        userActivityProviderMock.numberOfActiveDaysPassed = 10
        #expect(sut.promptType() == nil)

        // Active days for subsequent modal == 14. Show subsequent modal.
        dateProviderMock.advanceBy(.days(4))
        userActivityProviderMock.numberOfActiveDaysPassed = 14
        #expect(sut.promptType() == .active(.subsequentModal))
        storeMock.modalShownOccurrences = 4

        // Browser is set to Default and active days for subsequent modal == 14. Do Not show modal.
        dateProviderMock.advanceBy(.days(14))
        userActivityProviderMock.numberOfActiveDaysPassed = 14
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: true)
        #expect(sut.promptType() == nil)
    }

    @Test("Check Full Flow Correctness Of Modal For Existing Active User")
    func checkFullFlowCorrectnessForExistingUser() {
        featureFlaggerMock.firstActiveModalDelayDays = 1
        featureFlaggerMock.secondActiveModalDelayDays = 4
        featureFlaggerMock.subsequentActiveModalRepeatIntervalDays = 14
        userTypeProviderMock.userType = .existing
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
        #expect(sut.promptType() == .active(.firstModal))
        storeMock.lastModalShownDate = dateProviderMock.getDate().timeIntervalSince1970
        storeMock.modalShownOccurrences = 1

        // Active days after first modal < 4. Do not show any modal.
        dateProviderMock.advanceBy(.days(3))
        userActivityProviderMock.numberOfActiveDaysPassed = 3
        #expect(sut.promptType() == nil)

        // Active days after first modal == 4. Do not show second modal for existing user.
        dateProviderMock.advanceBy(.days(1))
        userActivityProviderMock.numberOfActiveDaysPassed = 4
        #expect(sut.promptType() == nil)

        // Active days after second modal == 10. Do not show second modal.
        dateProviderMock.advanceBy(.days(10))
        userActivityProviderMock.numberOfActiveDaysPassed = 10
        #expect(sut.promptType() == nil)

        // Active days after second modal == 14. Show subsequent modal.
        dateProviderMock.advanceBy(.days(4))
        userActivityProviderMock.numberOfActiveDaysPassed = 14
        #expect(sut.promptType() == .active(.subsequentModal))
        storeMock.modalShownOccurrences = 2

        // Active days for subsequent modal == 10. Do not show subsequent modal.
        dateProviderMock.advanceBy(.days(10))
        userActivityProviderMock.numberOfActiveDaysPassed = 10
        #expect(sut.promptType() == nil)

        // Active days for subsequent modal == 14. Show subsequent modal.
        dateProviderMock.advanceBy(.days(4))
        userActivityProviderMock.numberOfActiveDaysPassed = 14
        #expect(sut.promptType() == .active(.subsequentModal))
        storeMock.modalShownOccurrences = 3

        // Browser is set to Default and active days for subsequent modal == 14. Do Not show modal.
        dateProviderMock.advanceBy(.days(14))
        userActivityProviderMock.numberOfActiveDaysPassed = 14
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: true)
        #expect(sut.promptType() == nil)
    }

    @Test("Check Full Flow Correctness Of Modal For Inactive User", arguments: [DefaultBrowserPromptUserType.new, .returning, .existing])
    func checkFullFlowCorrectnessOfModalForInactiveUser(_ userType: DefaultBrowserPromptUserType) async throws {
        // GIVEN
        userTypeProviderMock.userType = userType
        storeMock.hasInactiveModalShown = false
        storeMock.modalShownOccurrences = 3 // Ensure active modal is not shown for this test
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: false)
        let installDate = Date(timeIntervalSince1970: 1750739150) // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        makeSUT(installDate: installDate)
        dateProviderMock.setNowDate(installDate)

        // Install day < 28 day. Then no Modal should show
        #expect(sut.promptType() == nil)

        // Install day == 27 day and number of inactive days passed 6. Do not show modal
        dateProviderMock.advanceBy(.days(27))
        userActivityProviderMock.numberOfInactiveDaysPassed = 6
        #expect(sut.promptType() == nil)

        // Install day == 27 day and number of inactive days passed 7. Show Inactive Modal
        dateProviderMock.advanceBy(.days(1))
        userActivityProviderMock.numberOfInactiveDaysPassed = 7
        #expect(sut.promptType() == .inactive)
        storeMock.hasInactiveModalShown = true

        // Inactive modal already shown, should not show again
        dateProviderMock.advanceBy(.days(1))
        #expect(sut.promptType() == nil)
    }

    @Test("Check Inactive Modal Is Presented First If User Install The App And Become Inactive", arguments: [DefaultBrowserPromptUserType.new, .returning, .existing])
    func checkInactiveModalIsPresentedFirstThenActiveModalIsPresented(_ userType: DefaultBrowserPromptUserType) async throws {
        featureFlaggerMock.firstActiveModalDelayDays = 1
        featureFlaggerMock.secondActiveModalDelayDays = 4
        featureFlaggerMock.subsequentActiveModalRepeatIntervalDays = 14
        userTypeProviderMock.userType = userType
        storeMock.lastModalShownDate = nil
        storeMock.modalShownOccurrences = 0
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: false)
        let installDate = Date(timeIntervalSince1970: 1750739150) // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        makeSUT(installDate: installDate)
        dateProviderMock.setNowDate(installDate)

        // Install day < 1 day. Then no Modal should show
        #expect(sut.promptType() == nil)

        // Install day == 28 day. Show Inactive Modal
        dateProviderMock.advanceBy(.days(28))
        userActivityProviderMock.numberOfInactiveDaysPassed = 28

        #expect(sut.promptType() == .inactive)
        storeMock.lastModalShownDate = dateProviderMock.getDate().timeIntervalSince1970
        storeMock.hasInactiveModalShown = true

        // Active modal should show but a modal has already been presented
        #expect(sut.promptType() == nil)

        // Advance by one day. First modal after should show
        dateProviderMock.advanceBy(.days(1))
        #expect(sut.promptType() == .active(.firstModal))
        storeMock.lastModalShownDate = dateProviderMock.getDate().timeIntervalSince1970
        storeMock.modalShownOccurrences = 1
    }

    @Test("Check Inactive Modal Is Presented If Presenting Active Modal And User Become Inactive", arguments: [DefaultBrowserPromptUserType.new, .returning, .existing])
    func checkInactiveModalIsPresentedAfterActiveModal(_ userType: DefaultBrowserPromptUserType) async throws {
        featureFlaggerMock.firstActiveModalDelayDays = 1
        featureFlaggerMock.secondActiveModalDelayDays = 4
        featureFlaggerMock.subsequentActiveModalRepeatIntervalDays = 14
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
        #expect(sut.promptType() == .active(.firstModal))
        storeMock.lastModalShownDate = dateProviderMock.getDate().timeIntervalSince1970
        storeMock.modalShownOccurrences = 1


        // Install day == 28 day. Show Inactive Modal
        dateProviderMock.advanceBy(.days(28))
        userActivityProviderMock.numberOfInactiveDaysPassed = 28

        #expect(sut.promptType() == .inactive)
        storeMock.lastModalShownDate = dateProviderMock.getDate().timeIntervalSince1970
        storeMock.hasInactiveModalShown = true

        // Active modal should show but a modal has already been presented
        #expect(sut.promptType() == nil)
    }

}
