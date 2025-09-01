//
//  OnboardingPixelReporterTests.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import XCTest
import Core
@testable import DuckDuckGo

final class OnboardingPixelReporterTests: XCTestCase {
    private static let suiteName = "testing_onboarding_pixel_store"
    private var sut: OnboardingPixelReporter!
    private var statisticsStoreMock: MockStatisticsStore!
    private var now: Date!
    private var userDefaultsMock: UserDefaults!

    override func setUpWithError() throws {
        statisticsStoreMock = MockStatisticsStore()
        statisticsStoreMock.atb = "TESTATB"
        now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        userDefaultsMock = UserDefaults(suiteName: Self.suiteName)
        sut = OnboardingPixelReporter(pixel: OnboardingPixelFireMock.self, uniquePixel: OnboardingUniquePixelFireMock.self, experimentPixel: OnboardingExperimentPixelFireMock.self, statisticsStore: statisticsStoreMock, calendar: calendar, dateProvider: { self.now }, userDefaults: userDefaultsMock)
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        OnboardingPixelFireMock.tearDown()
        OnboardingUniquePixelFireMock.tearDown()
        OnboardingExperimentPixelFireMock.tearDown()
        statisticsStoreMock = nil
        now = nil
        userDefaultsMock.removePersistentDomain(forName: Self.suiteName)
        userDefaultsMock = nil
        sut = nil
        try super.tearDownWithError()
    }

    func testWhenMeasureOnboardingIntroImpressionThenOnboardingIntroShownEventFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroShownUnique
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureOnboardingIntroImpression()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, "m_preonboarding_intro_shown_unique")
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasureSkipOnboardingCTAIsCalledThenSkipOnboardingCTAEventFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroSkipOnboardingCTAPressed
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureSkipOnboardingCTAAction()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, "m_preonboarding_skip-onboarding-pressed")
        XCTAssertEqual(OnboardingPixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasureConfirmSkipOnboardingCTAIsCalledThenConfirmSkipOnboardingCTAEventFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroConfirmSkipOnboardingCTAPressed
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureConfirmSkipOnboardingCTAAction()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, "m_preonboarding_confirm-skip-onboarding-pressed")
        XCTAssertEqual(OnboardingPixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasureCancelSkipOnboardingCTAIsCalledThenResumeOnboardingCTAEventFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroResumeOnboardingCTAPressed
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureResumeOnboardingCTAAction()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, "m_preonboarding_resume-onboarding-pressed")
        XCTAssertEqual(OnboardingPixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasureBrowserComparisonImpressionThenOnboardingIntroComparisonChartShownEventFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroComparisonChartShownUnique
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureBrowserComparisonImpression()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, "m_preonboarding_comparison_chart_shown_unique")
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasureChooseBrowserCTAActionThenOnboardingIntroChooseBrowserCTAPressedEventFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroChooseBrowserCTAPressed
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureChooseBrowserCTAAction()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, "m_preonboarding_choose_browser_pressed")
        XCTAssertEqual(OnboardingPixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    // MARK: - Custom Interactions

    func testWhenMeasureCustomSearchIsCalledThenSearchCustomFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingContextualSearchCustomUnique
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureCustomSearch()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, "m_onboarding_search_custom_unique")
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasureCustomSiteIsCalledThenSiteCustomFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingContextualSiteCustomUnique
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureCustomSite()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, "m_onboarding_visit_site_custom_unique")
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasureSecondVisitIsCalledAndStoreDoesNotContainPixelThenPixelIsNotFired() {
        // GIVEN
        XCTAssertNil(userDefaultsMock.value(forKey: "com.duckduckgo.ios.site-visited"))
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureSecondSiteVisit()

        // THEN
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])
    }

    func testWhenMeasureSecondVisitIsCalledThenFiresOnlyOnSecondTime() {
        // GIVEN
        let key = "com.duckduckgo.ios.site-visited"
        userDefaultsMock.set(true, forKey: key)
        XCTAssertTrue(userDefaultsMock.bool(forKey: key))
        let expectedPixel = Pixel.Event.onboardingContextualSecondSiteVisitUnique
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureSecondSiteVisit()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, "m_second_sitevisit_unique")
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasurePrivacyDashboardOpenedForFirstTimeThenPrivacyDashboardFirstTimeOpenedPixelFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.privacyDashboardFirstTimeOpenedUnique
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measurePrivacyDashboardOpenedForFirstTime()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, "m_privacy_dashboard_first_time_used_unique")
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasurePrivacyDashboardOpenedForFirstTimeThenFromOnboardingParameterIsSetToTrue() {
        // GIVEN
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])

        // WHEN
        sut.measurePrivacyDashboardOpenedForFirstTime()

        // THEN
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams["from_onboarding"], "true")
    }

    func testWhenMeasurePrivacyDashboardOpenedForFirstTimeThenDaysSinceInstallParameterIsSet() {
        // GIVEN
        let installDate = Date(timeIntervalSince1970: 1722348000) // 30th July 2024 GMT
        now = Date(timeIntervalSince1970: 1722607200) // 1st August 2024 GMT
        statisticsStoreMock.installDate = installDate
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])

        // WHEN
        sut.measurePrivacyDashboardOpenedForFirstTime()

        // THEN
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams["daysSinceInstall"], "3")
    }

    // MARK: - Dax Dialogs

    func testWhenMeasureScreenImpressionIsCalledThenPixelFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.daxDialogsSerpUnique
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureScreenImpression(event: expectedPixel)

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenmeasureEndOfJourneyDialogCTAActionIsCalledThenDaxDialogsEndOfJourneyDismissedPixelFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.daxDialogsEndOfJourneyDismissed
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureEndOfJourneyDialogCTAAction()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    // MARK: - Manual Dismiss

    func testWhenMeasureTrySearchDialogNewTabDismissButtonTappedThenPixelIsFired() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingTrySearchDialogNewTabDismissButtonTapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureTrySearchDialogNewTabDismissButtonTapped()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasureTryVisitSiteDialogNewTabDismissButtonTappedThenPixelIsFired() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingTryVisitSiteDialogNewTabDismissButtonTapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureTryVisitSiteDialogNewTabDismissButtonTapped()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasureTryVisitSiteDialogDismissButtonTappedThenPixelIsFired() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingTryVisitSiteDialogDismissButtonTapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureTryVisitSiteDialogDismissButtonTapped()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasureSearchResultDialogDismissButtonTappedThenPixelIsFired() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingSearchResultDialogDismissButtonTapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureSearchResultDialogDismissButtonTapped()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasureTrackersDialogDismissButtonTappedThenPixelIsFired() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingTrackersDialogDismissButtonTapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureTrackersDialogDismissButtonTapped()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasureFireDialogDismissButtonTappedThenPixelIsFired() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingFireDialogDismissButtonTapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureFireDialogDismissButtonTapped()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasureEndOfJourneyDialogNewTabDismissButtonTappedThenPixelIsFired() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingEndOfJourneyDialogNewTabDismissButtonTapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureEndOfJourneyDialogNewTabDismissButtonTapped()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasureEndOfJourneyDialogDismissButtonTappedThenPixelIsFired() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingEndOfJourneyDialogDismissButtonTapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureEndOfJourneyDialogDismissButtonTapped()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasurePrivacyProPromoDialogNewTabDismissButtonTappedThenPixelIsFired() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingPrivacyPromoDialogDismissButtonTapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measurePrivacyPromoDialogNewTabDismissButtonTapped()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    // MARK: - Enqueuing / Dequeuing Pixels

    func testWhenPixelIsFiredAndAndATBIsNotAvailableAndPixelNeedsATBThenEnqueuePixel() throws {
        // GIVEN
        statisticsStoreMock.atb = nil
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])
        XCTAssertTrue(sut.enqueuedPixels.isEmpty)

        // WHEN
        sut.fireTestPixelWithATB(event: .onboardingIntroShownUnique)

        // THEN
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sut.enqueuedPixels.count, 1)
        let enqueuedPixel = try XCTUnwrap(sut.enqueuedPixels.first)
        XCTAssertEqual(enqueuedPixel.event, .onboardingIntroShownUnique)
        XCTAssertTrue(enqueuedPixel.unique)
        XCTAssertTrue(enqueuedPixel.additionalParameters.isEmpty)
        XCTAssertEqual(enqueuedPixel.includedParameters, [.appVersion, .atb])

    }

    func testWhenPixelIsFiredAndAndATBIsNotAvailableAndPixelDoesNotNeedATBThenFirePixel() {
        // GIVEN
        statisticsStoreMock.atb = nil
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])
        XCTAssertTrue(sut.enqueuedPixels.isEmpty)

        // WHEN
        sut.measurePrivacyDashboardOpenedForFirstTime()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, .privacyDashboardFirstTimeOpenedUnique)
        XCTAssertNotNil(OnboardingUniquePixelFireMock.capturedParams)
        XCTAssertNotNil(OnboardingUniquePixelFireMock.capturedIncludeParameters)
        XCTAssertTrue(sut.enqueuedPixels.isEmpty)
    }

    func testWhenFireEnqueuedPixelIsCalledThenFireEnqueuedPixels() {
        // GIVEN
        statisticsStoreMock.atb = nil
        sut.fireTestPixelWithATB(event: .onboardingIntroShownUnique)
        sut.fireTestPixelWithATB(event: .onboardingIntroComparisonChartShownUnique)
        XCTAssertEqual(sut.enqueuedPixels.count, 2)
        XCTAssertTrue(OnboardingUniquePixelFireMock.capturedPixelEventHistory.isEmpty)

        // WHEN
        sut.fireEnqueuedPixelsIfNeeded()

        // THEN
        XCTAssertEqual(sut.enqueuedPixels.count, 0)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEventHistory.count, 2)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEventHistory[0], .onboardingIntroShownUnique)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEventHistory[1], .onboardingIntroComparisonChartShownUnique)
    }

    // MARK: - Onboarding Intro Highglights Experiment

    func testWhenMeasureChooseAppIconImpressionIsCalledThenOnboardingIntroChooseIconImpressionUniquePixelFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroChooseAppIconImpressionUnique
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureChooseAppIconImpression()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasureChooseNonDefaultAppIconIsCalledThenOnboardingIntroChooseCustomIconColorPixelFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroChooseCustomAppIconColorCTAPressed
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureChooseCustomAppIconColor()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasureAddressBarPositionSelectionImpressionIsCalledThenOnboardingIntroChooseAddressBarImpressionUniquePixelFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroChooseAddressBarImpressionUnique
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureAddressBarPositionSelectionImpression()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasureChooseBottomAddressBarPositionIsCalledThenOnboardingIntroBottomAddressBarSelectedFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroBottomAddressBarSelected
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureChooseBottomAddressBarPosition()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    // MARK: Add To Dock Experiment

    func testWhenMeasureAddToDockPromoImpressionsIsCalledThenOnboardingAddToDockPromoImpressionsPixelFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingAddToDockPromoImpressionsUnique
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureAddToDockPromoImpression()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasureAddToDockPromoShowTutorialCTAActionIsCalledThenOnboardingAddToDockPromoShowTutorialCTAPixelFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingAddToDockPromoShowTutorialCTATapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureAddToDockPromoShowTutorialCTAAction()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasureAddToDockPromoDismissCTAActionThenOnboardingAddToDockPromoDismissCTAPixelFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingAddToDockPromoDismissCTATapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureAddToDockPromoDismissCTAAction()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])
    }

    func testWhenMeasureAddToDockTutorialDismissCTAActionIsCalledThenonboardingAddToDockTutorialDismissCTAPixelFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingAddToDockTutorialDismissCTATapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        // WHEN
        sut.measureAddToDockTutorialDismissCTAAction()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])
    }

}
