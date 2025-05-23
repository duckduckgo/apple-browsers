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

import Testing
import FeatureFlags
@testable import DuckDuckGo_Privacy_Browser

final class DefaultBrowserAndDockPromptTypeDeciderTests {
    private var featureFlaggerMock: MockDefaultBrowserAndDockPromptFeatureFlagger!
    private var storeMock: MockDefaultBrowserAndDockPromptStore!
    private var timeTraveller: TimeTraveller!
    private var sut: DefaultBrowserAndDockPromptTypeDecider!

    init() {
        featureFlaggerMock = MockDefaultBrowserAndDockPromptFeatureFlagger()
        storeMock = MockDefaultBrowserAndDockPromptStore()
        timeTraveller = TimeTraveller()
    }

    func makeSUT(installDate: Date? = nil) {
        sut = DefaultBrowserAndDockPromptTypeDecider(
            featureFlagger: featureFlaggerMock,
            store: storeMock,
            installDateProvider: { installDate },
            dateProvider: timeTraveller.getDate
        )
    }

    @Test("Return Nil Prompt when Feature Is Disabled")
    func checkPromptIsNilWhenFeatureFlagIsDisabled() {
        // GIVEN
        featureFlaggerMock.isDefaultBrowserAndDockPromptFeatureEnabled = false
        makeSUT()

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
        #expect(result == .popover)
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
        #expect(result == .banner)
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
        #expect(result == .banner)
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

    @Test("Check Right Prompts Are Presented")
    func checkRightPromptsArePresented() {

        func advanceInTimeAndAssertPrompt(days: Int, expectedResult: DefaultBrowserAndDockPromptPresentationType?) {
            timeTraveller.advanceBy(.days(days))
            let result = sut.promptType()
            #expect(result == expectedResult)
        }

        // GIVEN
        featureFlaggerMock.firstPopoverDelayDays = 10
        featureFlaggerMock.bannerAfterPopoverDelayDays = 20
        featureFlaggerMock.bannerRepeatIntervalDays = 30
        let installDate = Date(timeIntervalSince1970: 1747699200) // 20 May 2025 12:00:00 AM
        makeSUT(installDate: installDate)
        timeTraveller.setNowDate(installDate)

        // THEN prompt is nil as installation date and now are same day.
        #expect(sut.promptType() == nil)

        // We advance 10 days. The timing condition to see the popover is satisfied.
        advanceInTimeAndAssertPrompt(days: 10, expectedResult: .popover)
        // Save the popover shown date
        storeMock.popoverShownDate = timeTraveller.getDate().timeIntervalSince1970

        // We advance 10 days. The timing condition to see the banner is not satisfied as it'll show 20 days after the popover has been shown.
        advanceInTimeAndAssertPrompt(days: 10, expectedResult: nil)

        // We advance other 10 days. The timing condition to see the banner is satisfied. The banner is shown.
        advanceInTimeAndAssertPrompt(days: 10, expectedResult: .banner)
        // Save the banner shown date
        storeMock.bannerShownDate = timeTraveller.getDate().timeIntervalSince1970

        // We advance 20 days. The timing condition to see the banner again is not satisfied as it'll show 30 days after the first banner has been shown.
        advanceInTimeAndAssertPrompt(days: 20, expectedResult: nil)

        // We advance other 10 days. The timing condition to see the banner is satisfied. The banner is shown.
        advanceInTimeAndAssertPrompt(days: 10, expectedResult: .banner)
        // Save last shown banner date
        storeMock.bannerShownDate = timeTraveller.getDate().timeIntervalSince1970

        // At this point we simulate the user has permanently dismissed the banner.
        storeMock.isBannerPermanentlyDismissed = true

        // We advance another 40 days. No prompt should be returned.
        advanceInTimeAndAssertPrompt(days: 40, expectedResult: nil)
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
