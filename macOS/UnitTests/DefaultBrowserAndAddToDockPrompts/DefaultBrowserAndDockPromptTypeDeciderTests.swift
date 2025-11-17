//
//  DefaultBrowserAndDockPromptTypeDeciderTests.swift
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

import FeatureFlags
import Foundation
import Testing

@testable import DuckDuckGo_Privacy_Browser

final class DefaultBrowserAndDockPromptTypeDeciderTests {
    private var featureFlaggerMock: MockDefaultBrowserAndDockPromptFeatureFlagger!
    private var storeMock: MockDefaultBrowserAndDockPromptStore!
    private var userActivityProviderMock: MockDefaultBrowserAndDockPromptUserActivityProvider!
    private var timeTraveller: TimeTraveller!
    private var sut: DefaultBrowserAndDockPromptTypeDecider!

    init() {
        featureFlaggerMock = MockDefaultBrowserAndDockPromptFeatureFlagger()
        storeMock = MockDefaultBrowserAndDockPromptStore()
        userActivityProviderMock = MockDefaultBrowserAndDockPromptUserActivityProvider()
        timeTraveller = TimeTraveller()
    }

    func makeSUT(installDate: Date? = nil,
                 activeUserPromptDecider: DefaultBrowserAndDockPromptTypeDeciding? = nil,
                 inactiveUserPromptDecider: DefaultBrowserAndDockPromptTypeDeciding? = nil) {
        sut = DefaultBrowserAndDockPromptTypeDecider(
            featureFlagger: featureFlaggerMock,
            store: storeMock,
            userActivityProvider: userActivityProviderMock,
            activeUserPromptDecider: activeUserPromptDecider,
            inactiveUserPromptDecider: inactiveUserPromptDecider,
            installDateProvider: { installDate },
            dateProvider: timeTraveller.getDate
        )
    }

    @Test("Return Nil Prompt when Features Are Disabled")
    func checkPromptIsNilWhenFeatureFlagsAreDisabled() {
        // GIVEN
        featureFlaggerMock.isDefaultBrowserAndDockPromptForActiveUsersFeatureEnabled = false
        featureFlaggerMock.isDefaultBrowserAndDockPromptForInactiveUsersFeatureEnabled = false
        makeSUT()

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == nil)
    }

    @Test("Check Return Nil Prompt If Banner Prompt Is Permanently Dismissed")
    func checkPromptIsNilWhenBannerPromptPermanentlyDismissed() {
        // GIVEN
        storeMock.isBannerPermanentlyDismissed = true
        let activeUserDecider = MockDefaultBrowserAndDockPromptTypeDecider()
        activeUserDecider.promptTypeToReturn = .active(.popover)
        let inactiveUserDecider = MockDefaultBrowserAndDockPromptTypeDecider()
        inactiveUserDecider.promptTypeToReturn = .inactive
        makeSUT(activeUserPromptDecider: activeUserDecider,
                inactiveUserPromptDecider: inactiveUserDecider)

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == nil)
    }

    @Test("Check Return Nil Prompt If Prompt Has Been Shown Today")
    func checkPromptIsNilWhenPromptAlreadyShownToday() {
        // GIVEN
        storeMock.popoverShownDate = timeTraveller.getDate().timeIntervalSince1970
        let activeUserDecider = MockDefaultBrowserAndDockPromptTypeDecider()
        activeUserDecider.promptTypeToReturn = .active(.banner)
        let inactiveUserDecider = MockDefaultBrowserAndDockPromptTypeDecider()
        inactiveUserDecider.promptTypeToReturn = .inactive
        makeSUT(activeUserPromptDecider: activeUserDecider,
                inactiveUserPromptDecider: inactiveUserDecider)

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == nil)
    }

    @Test("Check Inactive User Prompt Has Priority Over Active User Prompt")
    func checkInactivePromptHasPriorityOverActivePrompt() {
        // GIVEN
        let activeUserDecider = MockDefaultBrowserAndDockPromptTypeDecider()
        activeUserDecider.promptTypeToReturn = .active(.popover)
        let inactiveUserDecider = MockDefaultBrowserAndDockPromptTypeDecider()
        inactiveUserDecider.promptTypeToReturn = .inactive
        makeSUT(activeUserPromptDecider: activeUserDecider,
                inactiveUserPromptDecider: inactiveUserDecider)

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == .inactive)
    }

    @Test("Check Active User Prompt Is Returned If Inactive User Prompt Is Nil")
    func checkActiveUserPromptIsReturnedWhenInactiveUserPromptIsNil() {
        // GIVEN
        let activeUserDecider = MockDefaultBrowserAndDockPromptTypeDecider()
        activeUserDecider.promptTypeToReturn = .active(.popover)
        let inactiveUserDecider = MockDefaultBrowserAndDockPromptTypeDecider()
        inactiveUserDecider.promptTypeToReturn = nil
        makeSUT(activeUserPromptDecider: activeUserDecider,
                inactiveUserPromptDecider: inactiveUserDecider)

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == .active(.popover))
    }

    @Test("Check Return Nil Prompt If Inactive And Active Prompts Are Nil")
    func checkPromptIsNilWhenInactiveAndActiveUserPromptIsNil() {
        // GIVEN
        let activeUserDecider = MockDefaultBrowserAndDockPromptTypeDecider()
        activeUserDecider.promptTypeToReturn = nil
        let inactiveUserDecider = MockDefaultBrowserAndDockPromptTypeDecider()
        inactiveUserDecider.promptTypeToReturn = nil
        makeSUT(activeUserPromptDecider: activeUserDecider,
                inactiveUserPromptDecider: inactiveUserDecider)

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == nil)
    }

    @Test("Check Popover Is Returned When Popover Has Not Been Seen And Install Date is >= 14 days")
    func checkPromptIsPopoverWhenPopoverHasNotBeenSeenAndInstallationDateConditionIsSatisfied() {
        // GIVEN
        storeMock.popoverShownDate = nil
        featureFlaggerMock.firstPopoverDelayDays = 14
        let installDate = Date(timeIntervalSince1970: 1747699200) // 20 May 2025 12:00:00 AM
        makeSUT(installDate: installDate)
        timeTraveller.setNowDate(installDate)

        // WHEN
        var result = sut.promptType()

        // THEN
        #expect(result == nil)

        // ADVANCE IN TIME 14 DAYS
        timeTraveller.advanceBy(.days(14))

        // WHEN
        result = sut.promptType()

        // THEN
        #expect(result == .active(.popover))
    }

    @Test("Check Banner Is Returned When Popover Was Seen at least 14 days ago")
    func checkPromptIsBannerWhenBannerHasNotBeenSeenAndPopoverDelayIsSatisfied() {
        // GIVEN
        featureFlaggerMock.bannerAfterPopoverDelayDays = 14
        let popoverSeenDate = Date(timeIntervalSince1970: 1747699200) // 20 May 2025 12:00:00 AM
        storeMock.popoverShownDate = popoverSeenDate.timeIntervalSince1970
        timeTraveller.setNowDate(popoverSeenDate)
        makeSUT()

        // WHEN
        var result = sut.promptType()

        // THEN
        #expect(result == nil)

        // ADVANCE IN TIME 14 DAYS
        timeTraveller.advanceBy(.days(14))

        // WHEN
        result = sut.promptType()

        // THEN
        #expect(result == .active(.banner))
    }

    @Test("Check Banner Is Returned When Last Banner Was Seen at least 14 days ago")
    func checkPromptIsBannerWhenBannerHasBeenSeenAndBannerRepaeatIntervalConditionIsSatisfied() {
        // GIVEN
        featureFlaggerMock.bannerRepeatIntervalDays = 14
        let bannerSeenDate = Date(timeIntervalSince1970: 1747699200) // 20 May 2025 12:00:00 AM
        storeMock.popoverShownDate = bannerSeenDate.addingTimeInterval(-.days(5)).timeIntervalSince1970 // Not important what value is stored for this test.
        storeMock.bannerShownDate = bannerSeenDate.timeIntervalSince1970
        timeTraveller.setNowDate(bannerSeenDate)
        makeSUT()

        // WHEN
        var result = sut.promptType()

        // THEN
        #expect(result == nil)

        // ADVANCE IN TIME 14 DAYS
        timeTraveller.advanceBy(.days(14))

        // WHEN
        result = sut.promptType()

        // THEN
        #expect(result == .active(.banner))
    }

    @Test("Check Banner Is Not Shown Again When Timing Condition Is Satisfied But Banner Is Permanently Dismissed")
    func checkPromptIsNilWhenBannerIsPermanentlyDismissed() {
        // GIVEN
        storeMock.isBannerPermanentlyDismissed = true
        featureFlaggerMock.bannerRepeatIntervalDays = 14
        let bannerSeenDate = Date(timeIntervalSince1970: 1747699200) // 20 May 2025 12:00:00 AM
        storeMock.popoverShownDate = bannerSeenDate.addingTimeInterval(-.days(5)).timeIntervalSince1970 // Not important what value is stored for this test.
        storeMock.bannerShownDate = bannerSeenDate.timeIntervalSince1970
        timeTraveller.advanceBy(.days(14))
        makeSUT()

        // WHEN
        let result = sut.promptType()

        // THEN
        #expect(result == nil)
    }

    @Test("Check Inactive is Returned When Modal Has Not Been Seen, Install Date is >= 28 Days Ago, and User Inactivity is >= 7 Days")
    func checkPromptIsInactiveUserModalWhenConditionsAreSatisfied() {
        // GIVEN
        storeMock.inactiveUserModalShownDate = nil
        featureFlaggerMock.inactiveModalNumberOfDaysSinceInstall = 28
        featureFlaggerMock.inactiveModalNumberOfInactiveDays = 7
        userActivityProviderMock.inactiveDaysToReturn = 0
        let installDate = Date(timeIntervalSince1970: 1747699200) // 20 May 2025 12:00:00 AM
        timeTraveller.setNowDate(installDate)
        let activeUserDecider = MockDefaultBrowserAndDockPromptTypeDecider()
        activeUserDecider.promptTypeToReturn = nil
        makeSUT(installDate: installDate,
                activeUserPromptDecider: activeUserDecider)

        // WHEN
        var result = sut.promptType()

        // THEN
        #expect(result == nil)

        // ADVANCE IN TIME 28 DAYS, WITH 7 DAYS OF INACTIVITY
        timeTraveller.advanceBy(.days(28))
        userActivityProviderMock.inactiveDaysToReturn = 7

        // WHEN
        result = sut.promptType()

        // THEN
        #expect(result == .inactive)
    }

    @Test("Check Inactive is Not Returned When Install Date is < 28 Days Ago")
    func checkPromptIsInactiveUserModalWhenInstallDateConditionIsNotSatisfied() {
        // GIVEN
        featureFlaggerMock.inactiveModalNumberOfDaysSinceInstall = 28
        featureFlaggerMock.inactiveModalNumberOfInactiveDays = 7
        userActivityProviderMock.inactiveDaysToReturn = 0
        let installDate = Date(timeIntervalSince1970: 1747699200) // 20 May 2025 12:00:00 AM
        timeTraveller.setNowDate(installDate)
        let activeUserDecider = MockDefaultBrowserAndDockPromptTypeDecider()
        activeUserDecider.promptTypeToReturn = nil
        makeSUT(installDate: installDate,
                activeUserPromptDecider: activeUserDecider)

        // WHEN
        var result = sut.promptType()

        // THEN
        #expect(result == nil)

        // ADVANCE IN TIME 8 DAYS, WITH 7 DAYS OF INACTIVITY
        timeTraveller.advanceBy(.days(8))
        userActivityProviderMock.inactiveDaysToReturn = 7

        // WHEN
        result = sut.promptType()

        // THEN
        #expect(result == nil)
    }

    @Test("Check Inactive is Not Returned When Inactivity is < 7 Days")
    func checkPromptIsInactiveUserModalWhenInactivityConditionIsNotSatisfied() {
        // GIVEN
        storeMock.inactiveUserModalShownDate = nil
        featureFlaggerMock.inactiveModalNumberOfDaysSinceInstall = 28
        featureFlaggerMock.inactiveModalNumberOfInactiveDays = 7
        userActivityProviderMock.inactiveDaysToReturn = 0
        let installDate = Date(timeIntervalSince1970: 1747699200) // 20 May 2025 12:00:00 AM
        timeTraveller.setNowDate(installDate)
        let activeUserDecider = MockDefaultBrowserAndDockPromptTypeDecider()
        activeUserDecider.promptTypeToReturn = nil
        makeSUT(installDate: installDate,
                activeUserPromptDecider: activeUserDecider)

        // WHEN
        var result = sut.promptType()

        // THEN
        #expect(result == nil)

        // ADVANCE IN TIME 28 DAYS, WITH 6 DAYS OF INACTIVITY
        timeTraveller.advanceBy(.days(28))
        userActivityProviderMock.inactiveDaysToReturn = 6

        // WHEN
        result = sut.promptType()

        // THEN
        #expect(result == nil)
    }

    @Test("Check Inactive is Not Returned When It Was Already Shown")
    func checkPromptIsInactiveUserModalWhenAlreadySeen() {
        // GIVEN
        storeMock.inactiveUserModalShownDate = nil
        featureFlaggerMock.inactiveModalNumberOfDaysSinceInstall = 28
        featureFlaggerMock.inactiveModalNumberOfInactiveDays = 7
        userActivityProviderMock.inactiveDaysToReturn = 0
        let installDate = Date(timeIntervalSince1970: 1747699200) // 20 May 2025 12:00:00 AM
        let activeUserDecider = MockDefaultBrowserAndDockPromptTypeDecider()
        activeUserDecider.promptTypeToReturn = nil
        makeSUT(installDate: installDate,
                activeUserPromptDecider: activeUserDecider)

        // ADVANCE IN TIME 30 DAYS AND MARK PROMPT AS SHOWN
        let inactivePromptShown = installDate.advanced(by: .days(30))
        storeMock.inactiveUserModalShownDate = inactivePromptShown.timeIntervalSince1970
        timeTraveller.setNowDate(inactivePromptShown)

        // WHEN
        var result = sut.promptType()

        // THEN
        #expect(result == nil)

        // ADVANCE IN TIME 8 DAYS, WITH 7 DAYS OF INACTIVITY
        timeTraveller.advanceBy(.days(8))
        userActivityProviderMock.inactiveDaysToReturn = 7

        // WHEN
        result = sut.promptType()

        // THEN
        #expect(result == nil)
    }

    @Test("Check Full Flow Correctness Of Modal For Existing Active User")
    func checkFullFlowCorrectnessForExistingUser() {

        func advanceInTimeAndAssertPrompt(days: Int, expectedResult: DefaultBrowserAndDockPromptPresentationType?) {
            timeTraveller.advanceBy(.days(days))
            let result = sut.promptType()
            #expect(result == expectedResult)
        }

        // GIVEN
        featureFlaggerMock.firstPopoverDelayDays = 10
        featureFlaggerMock.bannerAfterPopoverDelayDays = 20
        featureFlaggerMock.bannerRepeatIntervalDays = 30
        userActivityProviderMock.inactiveDaysToReturn = 0
        let installDate = Date(timeIntervalSince1970: 1747699200) // 20 May 2025 12:00:00 AM
        makeSUT(installDate: installDate)
        timeTraveller.setNowDate(installDate)

        // THEN prompt is nil as installation date and now are same day.
        #expect(sut.promptType() == nil)

        // We advance 10 days. The timing condition to see the popover is satisfied.
        advanceInTimeAndAssertPrompt(days: 10, expectedResult: .active(.popover))
        // Save the popover shown date
        storeMock.popoverShownDate = timeTraveller.getDate().timeIntervalSince1970

        // We advance 10 days. The timing condition to see the banner is not satisfied as it'll show 20 days after the popover has been shown.
        advanceInTimeAndAssertPrompt(days: 10, expectedResult: nil)

        // We advance other 10 days. The timing condition to see the banner is satisfied. The banner is shown.
        advanceInTimeAndAssertPrompt(days: 10, expectedResult: .active(.banner))
        // Save the banner shown date
        storeMock.bannerShownDate = timeTraveller.getDate().timeIntervalSince1970

        // We advance 20 days. The timing condition to see the banner again is not satisfied as it'll show 30 days after the first banner has been shown.
        advanceInTimeAndAssertPrompt(days: 20, expectedResult: nil)

        // We advance other 10 days. The timing condition to see the banner is satisfied. The banner is shown.
        advanceInTimeAndAssertPrompt(days: 10, expectedResult: .active(.banner))
        // Save last shown banner date
        storeMock.bannerShownDate = timeTraveller.getDate().timeIntervalSince1970

        // At this point we simulate the user has permanently dismissed the banner.
        storeMock.isBannerPermanentlyDismissed = true

        // We advance another 40 days. No prompt should be returned.
        advanceInTimeAndAssertPrompt(days: 40, expectedResult: nil)
    }

    @Test("Check Full Flow Correctness Of Modal For Inactive User")
    func checkFullFlowCorrectnessOfModalForInactiveUser() async throws {
        // GIVEN
        storeMock.inactiveUserModalShownDate = nil
        featureFlaggerMock.inactiveModalNumberOfDaysSinceInstall = 30
        featureFlaggerMock.inactiveModalNumberOfInactiveDays = 10
        let activeUserDecider = MockDefaultBrowserAndDockPromptTypeDecider()
        activeUserDecider.promptTypeToReturn = nil // Ensure active modal is not shown for this test
        let installDate = Date(timeIntervalSince1970: 1747699200) // 20 May 2025 12:00:00 AM
        timeTraveller.setNowDate(installDate)
        makeSUT(installDate: installDate,
                activeUserPromptDecider: activeUserDecider)

        // Install day < 30 day. Then no Modal should show
        #expect(sut.promptType() == nil)

        // Install day == 29 days ago and number of inactive days = 9. Do not show modal
        timeTraveller.advanceBy(.days(29))
        userActivityProviderMock.inactiveDaysToReturn = 9
        #expect(sut.promptType() == nil)

        // Install day == 30 days ago and number of inactive days passed 10. Show Inactive Modal
        timeTraveller.advanceBy(.days(1))
        userActivityProviderMock.inactiveDaysToReturn = 10
        #expect(sut.promptType() == .inactive)
        storeMock.inactiveUserModalShownDate = timeTraveller.getDate().timeIntervalSince1970

        // Inactive modal already shown, should not show again
        timeTraveller.advanceBy(.days(1))
        #expect(sut.promptType() == nil)
    }

    @Test("Check Inactive Modal Is Presented First If User Install The App And Become Inactive")
    func checkInactiveModalIsPresentedFirstThenActiveModalIsPresented() async throws {
        featureFlaggerMock.firstPopoverDelayDays = 10
        featureFlaggerMock.bannerAfterPopoverDelayDays = 20
        featureFlaggerMock.bannerRepeatIntervalDays = 30
        featureFlaggerMock.inactiveModalNumberOfDaysSinceInstall = 30
        featureFlaggerMock.inactiveModalNumberOfInactiveDays = 10
        userActivityProviderMock.inactiveDaysToReturn = 0
        let installDate = Date(timeIntervalSince1970: 1750739150) // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        makeSUT(installDate: installDate)
        timeTraveller.setNowDate(installDate)

        // Install day < 1 day. Then no Modal should show
        #expect(sut.promptType() == nil)

        // Install day == 30 day. Show Inactive Modal
        timeTraveller.advanceBy(.days(30))
        userActivityProviderMock.inactiveDaysToReturn = 29

        #expect(sut.promptType() == .inactive)
        storeMock.inactiveUserModalShownDate = timeTraveller.getDate().timeIntervalSince1970

        // Active modal should show but a modal has already been presented
        #expect(sut.promptType() == nil)

        // Advance by one day. Popover should show
        timeTraveller.advanceBy(.days(1))
        #expect(sut.promptType() == .active(.popover))
    }

    @Test("Check Inactive Modal Is Presented If Presenting Active Modal And User Become Inactive")
    func checkInactiveModalIsPresentedAfterActiveModal() async throws {
        featureFlaggerMock.firstPopoverDelayDays = 10
        featureFlaggerMock.bannerAfterPopoverDelayDays = 20
        featureFlaggerMock.bannerRepeatIntervalDays = 30
        featureFlaggerMock.inactiveModalNumberOfDaysSinceInstall = 30
        featureFlaggerMock.inactiveModalNumberOfInactiveDays = 10
        userActivityProviderMock.inactiveDaysToReturn = 0
        let installDate = Date(timeIntervalSince1970: 1750739150) // Tuesday, 24 June 2025 12:00:00 AM (GMT)
        makeSUT(installDate: installDate)
        timeTraveller.setNowDate(installDate)

        // Install day < 1 day. Then no Modal should show
        #expect(sut.promptType() == nil)

        // Install day == 10 days. Show popover
        timeTraveller.advanceBy(.days(10))
        #expect(sut.promptType() == .active(.popover))
        storeMock.popoverShownDate = timeTraveller.getDate().timeIntervalSince1970

        // Install day == 30 day. Show Inactive Modal
        timeTraveller.advanceBy(.days(20))
        userActivityProviderMock.inactiveDaysToReturn = 29

        #expect(sut.promptType() == .inactive)
        storeMock.inactiveUserModalShownDate = timeTraveller.getDate().timeIntervalSince1970

        // Active modal should show but a modal has already been presented
        #expect(sut.promptType() == nil)
    }

}

final class TimeTraveller {
    private var date: Date

    init(date: Date = Date()) {
        self.date = date
    }

    func setNowDate(_ date: Date) {
        self.date = date
    }

    func advanceBy(_ timeInterval: TimeInterval) {
        date.addTimeInterval(timeInterval)
    }

    func getDate() -> Date {
        date
    }
}
