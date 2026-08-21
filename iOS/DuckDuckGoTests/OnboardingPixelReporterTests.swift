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
import Onboarding
@_spi(Testing) import Persistence
import PrivacyConfig
import PixelExperimentKit
@testable import DuckDuckGo

final class OnboardingPixelReporterTests: XCTestCase {
    private static let suiteName = "testing_onboarding_pixel_store"
    private var sut: OnboardingPixelReporter!
    private var statisticsStoreMock: MockStatisticsStore!
    private var now: Date!
    private var userDefaultsMock: UserDefaults!
    private var sharedPixelHandlerMock: MockOnboardingSharedPixelHandling!
    private var sharedPixelsStorageMock: (any KeyedStoring<OnboardingSharedPixelsKeys>)!

    override func setUpWithError() throws {
        statisticsStoreMock = MockStatisticsStore()
        statisticsStoreMock.atb = "TESTATB"
        now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        userDefaultsMock = UserDefaults(suiteName: Self.suiteName)
        sharedPixelHandlerMock = MockOnboardingSharedPixelHandling()
        initSharedPixelsStorageMock()
        MockExperimentPixelFiring.reset()
        sut = OnboardingPixelReporter(pixel: OnboardingPixelFireMock.self, uniquePixel: OnboardingUniquePixelFireMock.self, statisticsStore: statisticsStoreMock, calendar: calendar, dateProvider: { self.now }, userDefaults: userDefaultsMock, sharedPixelHandler: sharedPixelHandlerMock, sharedPixelsStorage: sharedPixelsStorageMock, downloadReasonExperimentMetric: OnboardingDownloadReasonExperimentMetric(experimentPixelFiring: MockExperimentPixelFiring.self))
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        OnboardingPixelFireMock.tearDown()
        OnboardingUniquePixelFireMock.tearDown()
        sharedPixelsStorageMock = nil
        sharedPixelHandlerMock = nil
        statisticsStoreMock = nil
        now = nil
        userDefaultsMock.removePersistentDomain(forName: Self.suiteName)
        userDefaultsMock = nil
        sut = nil
        try super.tearDownWithError()
    }

    private func initSharedPixelsStorageMock() {
        let mockStore = InMemoryKeyValueStore()
        sharedPixelsStorageMock = mockStore.keyedStoring()
        sharedPixelsStorageMock.onboardingSource = .duckAICustomProductPage
        sharedPixelsStorageMock.onboardingFlow = .duckAI
        sharedPixelsStorageMock.onboardingVariant = .duckAISearch
    }

    func testWhenMeasureOnboardingIntroImpressionThenLegacyIntroShownUniqueAndWelcomeShownPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroShownUnique
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureOnboardingIntroImpression()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, "m_preonboarding_intro_shown_unique")
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.welcome(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureSkipOnboardingCTAIsCalledThenLegacySkipPressedAndWelcomeDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroSkipOnboardingCTAPressed
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureSkipOnboardingCTAAction()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, "m_preonboarding_skip-onboarding-pressed")
        XCTAssertEqual(OnboardingPixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.welcome(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureConfirmSkipOnboardingCTAIsCalledThenLegacyConfirmSkipPressedAndSkipOnboardingEngageSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroConfirmSkipOnboardingCTAPressed
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureConfirmSkipOnboardingCTAAction()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, "m_preonboarding_confirm-skip-onboarding-pressed")
        XCTAssertEqual(OnboardingPixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.skipOnboarding(.clicked(.engage))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureCancelSkipOnboardingCTAIsCalledThenLegacyResumePressedAndSkipOnboardingDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroResumeOnboardingCTAPressed
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureResumeOnboardingCTAAction()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, "m_preonboarding_resume-onboarding-pressed")
        XCTAssertEqual(OnboardingPixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.skipOnboarding(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureBrowserComparisonImpressionThenLegacyComparisonChartShownUniqueAndSetDefaultShownSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroComparisonChartShownUnique
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureSetDefaultBrowserImpression()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, "m_preonboarding_comparison_chart_shown_unique")
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.setDefault(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertNotNil(sharedPixelHandlerMock.receivedVariant)
    }

    func testWhenMeasureChooseBrowserCTAActionThenLegacyChooseBrowserPressedAndSetDefaultEngageSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroChooseBrowserCTAPressed
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureChooseBrowserCTAAction()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, "m_preonboarding_choose_browser_pressed")
        XCTAssertEqual(OnboardingPixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.setDefault(.clicked(.engage))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertNotNil(sharedPixelHandlerMock.receivedVariant)
    }

    func testWhenMeasureAiComparisonImpressionThenAiComparisonShownSharedPixelFires() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)

        // WHEN
        sut.measureAiIntroImpression()

        // THEN
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.aiIntro(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureAiComparisonCTAActionThenAiComparisonEngageSharedPixelFires() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)

        // WHEN
        sut.measureAiIntroCTAAction()

        // THEN
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.aiIntro(.clicked(.engage))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureStartOnboardingCTAActionThenWelcomeEngageSharedPixelFires() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)

        // WHEN
        sut.measureStartOnboardingCTAAction()

        // THEN
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.welcome(.clicked(.engage))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureAutoRestoreOnboardingRestoreCTAActionThenLegacyRestoreTappedUniquePixelFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.syncAutoRestoreOnboardingRestoreTappedUnique

        // WHEN
        sut.measureAutoRestoreOnboardingRestoreCTAAction()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
    }

    func testWhenMeasureAutoRestoreOnboardingSkipCTAActionThenLegacySkipTappedUniquePixelFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.syncAutoRestoreOnboardingSkipTappedUnique

        // WHEN
        sut.measureAutoRestoreOnboardingSkipCTAAction()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
    }

    func testWhenMeasureAutoRestoreOnboardingPromptShownThenLegacyPixelFiresWithoutSharedPixels() {
        // GIVEN
        let expectedPixel = Pixel.Event.syncAutoRestoreOnboardingPromptShownUnique
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureAutoRestoreOnboardingPromptShown()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertTrue(sharedPixelHandlerMock.eventsFired.isEmpty)
    }

    func testWhenMeasureSkipOnboardingScreenImpressionThenSkipOnboardingShownSharedPixelFires() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureSkipOnboardingScreenImpression()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.skipOnboarding(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureSetDefaultBrowserSkippedThenSetDefaultDismissSharedPixelFires() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureSetDefaultBrowserSkipped()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.setDefault(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertNotNil(sharedPixelHandlerMock.receivedVariant)
    }

    // MARK: - Custom Interactions

    func testWhenMeasureCustomSearchIsCalledThenLegacySearchCustomUniqueAndSearchCustomSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingContextualSearchCustomUnique
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureCustomSearch()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, "m_onboarding_search_custom_unique")
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.search(.clicked(.custom))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureCustomSiteIsCalledThenLegacySiteCustomUniqueAndVisitSiteCustomSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingContextualSiteCustomUnique
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureCustomSite()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, "m_onboarding_visit_site_custom_unique")
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.visitSite(.clicked(.custom))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
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

    func testWhenMeasureScreenImpressionIsCalledThenLegacyUniquePixelFires() {
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
        XCTAssertTrue(sharedPixelHandlerMock.eventsFired.isEmpty)
    }

    func testWhenMeasureScreenImpressionWithDuckAIFireDialogEventThenLegacyFireDialogShownUniqueFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingDuckAIFireDialogShownUnique
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureScreenImpression(event: expectedPixel)

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertTrue(sharedPixelHandlerMock.eventsFired.isEmpty)
    }

    func testWhenMeasureScreenImpressionWithFireEducationEventThenLegacyFireEducationUniqueFiresWithoutSharedPixels() {
        // GIVEN
        let expectedPixel = Pixel.Event.daxDialogsFireEducationShownUnique
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureScreenImpression(event: expectedPixel)

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertTrue(sharedPixelHandlerMock.eventsFired.isEmpty)
    }

    func testWhenMeasureScreenImpressionIsCalledWithSharedOnboardingPixelThenSharedPixelFires() {
        // GIVEN
        XCTAssertTrue(sharedPixelHandlerMock.eventsFired.isEmpty)

        // WHEN
        sut.measureScreenImpression(.searchResults(.shown))

        // THEN
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.searchResults(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureEndOfJourneyDialogCTAActionIsCalledThenLegacyEndOfJourneyDismissedAndEndEngageSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.daxDialogsEndOfJourneyDismissed
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureEndOfJourneyDialogCTAAction()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.end(.clicked(.engage))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureSearchResultsDialogGotItActionThenSearchResultsEngageSharedPixelFires() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureSearchResultsDialogGotItAction()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.searchResults(.clicked(.engage))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureTrackersDialogGotItActionThenTrackersBlockedEngageSharedPixelFires() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureTrackersDialogGotItAction()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.trackersBlocked(.clicked(.engage))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureSubscriptionPromoDialogShownThenSubscriptionPromoShownSharedPixelFires() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureSubscriptionPromoDialogShown()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.subscriptionPromo(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureSubscriptionPromoEngageCTAActionThenSubscriptionPromoEngageSharedPixelFires() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureSubscriptionPromoEngageCTAAction()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.subscriptionPromo(.clicked(.engage))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureFireButtonOnboardingDeleteConfirmedThenFireButtonEngageSharedPixelFires() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureFireButtonOnboardingDeleteConfirmed()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.fireButton(.clicked(.engage))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureFireButtonOnboardingDismissButtonTappedThenFireButtonDismissSharedPixelFires() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureFireButtonOnboardingDismissButtonTapped()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.fireButton(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureTrySearchDialogSuggestedSearchTappedThenSearchSuggestedSharedPixelFires() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureTrySearchDialogSuggestedSearchTapped()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.search(.clicked(.suggested))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureDuckAIFireButtonCTAActionThenLegacyCTAPressedPixelFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingDuckAIFireButtonCTAPressed
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureDuckAIFireButtonCTAAction()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
    }

    func testWhenMeasureDuckAIFinalDialogImpressionThenLegacyFinalDialogShownUniquePixelFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingDuckAIFinalDialogShownUnique

        // WHEN
        sut.measureDuckAIFinalDialogImpression()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
    }

    func testWhenMeasureDuckAIFinalDialogCTAActionThenEndEngageSharedPixelFires() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureDuckAIFinalDialogCTAAction()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.end(.clicked(.engage))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    // MARK: - Duck AI query selection (linear onboarding)

    func testWhenMeasureDuckAIQuerySelectionImpressionThenLegacyToggleImpressionUniqueAndSearchShownSharedPixelsFire() {
        // GIVEN — the toggle is the branching point; it fires before a variant is set.
        sharedPixelsStorageMock.onboardingVariant = nil
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureDuckAIQuerySelectionImpression()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, .onboardingIntroDuckAIToggleImpressionUnique)
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.searchChatToggle(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
    }

    func testWhenMeasureDuckAIQuerySubmissionWithCustomPromptThenSearchCustomSharedPixelFiresAndVariantIsPersisted() {
        // GIVEN
        sharedPixelsStorageMock.onboardingVariant = nil
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureDuckAIQuerySubmission(selection: .search, promptSource: .custom)

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.searchChatToggle(.clicked(.customSearch))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
        XCTAssertEqual(sharedPixelsStorageMock.onboardingVariant, .duckAISearch)
    }

    func testWhenMeasureDuckAIQuerySubmissionWithSuggestedPromptThenSearchSuggestedSharedPixelFiresAndVariantIsPersisted() {
        // GIVEN
        sharedPixelsStorageMock.onboardingVariant = nil
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureDuckAIQuerySubmission(selection: .duckAI, promptSource: .option1)

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.searchChatToggle(.clicked(.suggestedChat))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
        XCTAssertEqual(sharedPixelsStorageMock.onboardingVariant, .duckAIChat)
    }

    // MARK: - Manual Dismiss

    func testWhenMeasureTrySearchDialogNewTabDismissButtonTappedThenLegacyDismissTappedAndSearchDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingTrySearchDialogNewTabDismissButtonTapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureTrySearchDialogNewTabDismissButtonTapped()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.search(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureTryVisitSiteDialogNewTabDismissButtonTappedThenLegacyDismissTappedAndVisitSiteDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingTryVisitSiteDialogNewTabDismissButtonTapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureTryVisitSiteDialogNewTabDismissButtonTapped()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.visitSite(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureTryVisitSiteDialogDismissButtonTappedThenLegacyDismissTappedAndVisitSiteDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingTryVisitSiteDialogDismissButtonTapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureTryVisitSiteDialogDismissButtonTapped()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.visitSite(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureSearchResultDialogDismissButtonTappedThenLegacyDismissTappedAndSearchResultsDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingSearchResultDialogDismissButtonTapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureSearchResultDialogDismissButtonTapped()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.searchResults(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureTrackersDialogDismissButtonTappedThenLegacyDismissTappedAndTrackersBlockedDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingTrackersDialogDismissButtonTapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureTrackersDialogDismissButtonTapped()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.trackersBlocked(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureFireDialogDismissButtonTappedThenLegacyDismissTappedAndFireButtonDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingFireDialogDismissButtonTapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureFireDialogDismissButtonTapped()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.fireButton(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureEndOfJourneyDialogNewTabDismissButtonTappedThenLegacyDismissTappedAndEndDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingEndOfJourneyDialogNewTabDismissButtonTapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureEndOfJourneyDialogNewTabDismissButtonTapped()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.end(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureEndOfJourneyDialogDismissButtonTappedThenLegacyDismissTappedAndEndDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingEndOfJourneyDialogDismissButtonTapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureEndOfJourneyDialogDismissButtonTapped()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.end(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureSubscriptionPromoDialogNewTabDismissButtonTappedThenLegacyDismissTappedAndSubscriptionPromoDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingSubscriptionDialogDismissButtonTapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureSubscriptionDialogNewTabDismissButtonTapped()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.subscriptionPromo(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    // MARK: - Onboarding Intro Highglights Experiment

    func testWhenMeasureChooseAppIconImpressionIsCalledThenLegacyChooseIconImpressionUniqueAndAppIconColorShownSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroChooseAppIconImpressionUnique
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureChooseAppIconImpression()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.appIconColor(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureChooseNonDefaultAppIconIsCalledThenLegacyChooseCustomIconColorPressedAndAppIconColorClickedSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroChooseCustomAppIconColorCTAPressed
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureChooseAppIconColor(.green)

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.appIconColor(.clicked(.green))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureChooseDefaultAppIconIsCalledThenOnlySharedOnboardingPixelFires() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureChooseAppIconColor(.defaultAppIcon)

        // THEN
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.appIconColor(.clicked(.red))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureAddressBarPositionSelectionImpressionIsCalledThenLegacyChooseAddressBarImpressionUniqueAndAddressBarPositionShownSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroChooseAddressBarImpressionUnique
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureAddressBarPositionSelectionImpression()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.addressBarPosition(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureChooseBottomAddressBarPositionIsCalledThenLegacyBottomAddressBarSelectedAndAddressBarBottomSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroBottomAddressBarSelected
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureChooseAddressBarPosition(.bottom)

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.addressBarPosition(.clicked(.bottom))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureChooseTopAddressBarPositionIsCalledThenOnlySharedOnboardingPixelFires() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureChooseAddressBarPosition(.top)

        // THEN
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.addressBarPosition(.clicked(.top))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    // MARK: Add To Dock Experiment

    func testWhenMeasureAddToDockPromoImpressionsIsCalledThenLegacyPromoImpressionsUniqueAndAddToDockShownSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingAddToDockPromoImpressionsUnique
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureAddToDockPromoImpression()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.addToDock(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureAddToDockPromoShowTutorialCTAActionIsCalledThenLegacyShowTutorialTappedAndAddToDockEngageSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingAddToDockPromoShowTutorialCTATapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureAddToDockPromoShowTutorialCTAAction()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.addToDock(.clicked(.engage))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureAddToDockPromoDismissCTAActionThenLegacyPromoDismissTappedAndAddToDockDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingAddToDockPromoDismissCTATapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureAddToDockPromoDismissCTAAction()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.addToDock(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureAddToDockTutorialDismissCTAActionIsCalledThenonboardingAddToDockTutorialDismissCTAPixelFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingAddToDockTutorialDismissCTATapped
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureAddToDockTutorialDismissCTAAction()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])
        XCTAssertTrue(sharedPixelHandlerMock.eventsFired.isEmpty)
    }

    // MARK: - Search Experience Selection

    func testWhenMeasureSearchExperienceSelectionImpressionIsCalledThenLegacyChooseSearchExperienceImpressionUniqueAndSearchExperienceShownSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroChooseSearchExperienceImpressionUnique
        XCTAssertFalse(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertNil(OnboardingUniquePixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureSearchExperienceSelectionImpression()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.searchExperience(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureChooseAIChatIsCalledThenLegacyAIChatSelectedAndSearchExperienceSearchPlusDuckAISharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroAIChatSelected
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureChooseAIChat()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.searchExperience(.clicked(.searchPlusDuckAI))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureChooseSearchOnlyIsCalledThenLegacySearchOnlySelectedAndSearchExperienceSearchOnlySharedPixelsFire() {
        // GIVEN
        sharedPixelsStorageMock.onboardingVariant = nil
        let expectedPixel = Pixel.Event.onboardingIntroSearchOnlySelected
        XCTAssertFalse(OnboardingPixelFireMock.didCallFire)
        XCTAssertNil(OnboardingPixelFireMock.capturedPixelEvent)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureChooseSearchOnly()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertEqual(OnboardingPixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.searchExperience(.clicked(.searchOnly))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
    }

    func testWhenMeasureTryVisitSiteDialogSuggestedSiteTappedThenVisitSiteSuggestedSharedPixelFires() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureTryVisitSiteDialogSuggestedSiteTapped()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.visitSite(.clicked(.suggested))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    // MARK: - Try Duck.ai End of Journey

    func testWhenMeasureScreenImpressionEndTryDuckAIShownThenSharedPixelFiresWithVariant() {
        // GIVEN
        sharedPixelsStorageMock.onboardingVariant = .downloadReasonSearch

        // WHEN
        sut.measureScreenImpression(.endTryDuckAI(.shown))

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.endTryDuckAI(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .downloadReasonSearch)
    }

    func testWhenMeasureScreenImpressionEndShownThenOnboardingCompletedExperimentMetricFires() {
        // WHEN
        sut.measureScreenImpression(.end(.shown))

        // THEN
        XCTAssertTrue(MockExperimentPixelFiring.firedMetrics.contains("onboarding_completed"))
    }

    func testWhenMeasureScreenImpressionEndTryDuckAIShownThenOnboardingCompletedExperimentMetricFires() {
        // WHEN
        sut.measureScreenImpression(.endTryDuckAI(.shown))

        // THEN
        XCTAssertTrue(MockExperimentPixelFiring.firedMetrics.contains("onboarding_completed"))
    }

    func testWhenMeasureScreenImpressionOtherSharedEventThenOnboardingCompletedExperimentMetricDoesNotFire() {
        // WHEN
        sut.measureScreenImpression(.welcome(.shown))

        // THEN
        XCTAssertFalse(MockExperimentPixelFiring.firedMetrics.contains("onboarding_completed"))
    }

    func testWhenMeasureEndOfJourneyTryDuckAICTAActionThenEndOfJourneyTryDuckAIEngageFires() {
        // WHEN
        sut.measureEndOfJourneyTryDuckAICTAAction()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.endTryDuckAI(.clicked(.engage))])
    }

    func testWhenMeasureEndOfJourneyTryDuckAISkipActionThenEndOfJourneyTryDuckAIDismissFires() {
        // WHEN
        sut.measureEndOfJourneyTryDuckAISkipAction()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.endTryDuckAI(.clicked(.dismiss))])
    }

    // MARK: - Download Reason Segmented Flow

    func testWhenMeasureTailoredStepImpressionsThenCorrectShownPixelsFire() {
        // WHEN
        sut.measureDownloadReasonImpression()
        sut.measureSearchPrivacySettingsImpression()
        sut.measureAIModelImpression()
        sut.measureToggleInputModeImpression()
        sut.measureAISearchSettingsImpression()
        sut.measureKeepDuckAIImpression()
        sut.measureAdBlockingImpression()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [
            .downloadChoice(.shown),
            .preferencesSerp(.shown),
            .preferencesAIModel(.shown),
            .preferencesAIToggleMode(.shown),
            .preferencesAISearch(.shown),
            .preferencesDuckAI(.shown),
            .preferencesAdBlocking(.shown)
        ])
    }

    func testWhenMeasureDownloadReasonImpressionThenNoVariantIsCarried() {
        // GIVEN
        sharedPixelsStorageMock.onboardingVariant = nil

        // WHEN
        sut.measureDownloadReasonImpression()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.downloadChoice(.shown)])
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
    }

    func testWhenMeasureTailoredStepImpressionThenStoredVariantIsCarried() {
        // GIVEN
        sharedPixelsStorageMock.onboardingVariant = .downloadReasonSearch

        // WHEN
        sut.measureSearchPrivacySettingsImpression()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.preferencesSerp(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .downloadReasonSearch)
    }

    func testWhenSegmentedFlowStepFiresThenCarriesTreatmentSourceAndFlow() {
        // GIVEN
        sharedPixelsStorageMock.onboardingSource = .default
        sharedPixelsStorageMock.onboardingFlow = .tailoredByDownloadReason

        // WHEN
        sut.measureDownloadReasonImpression()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .default)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .tailoredByDownloadReason)
    }

    func testWhenMeasureSetDefaultBrowserImpressionThenCarriesStoredDownloadReasonVariant() {
        // GIVEN — a download reason was selected earlier in the tailored flow.
        sharedPixelsStorageMock.onboardingVariant = .downloadReasonAdBlocking

        // WHEN
        sut.measureSetDefaultBrowserImpression()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.setDefault(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .downloadReasonAdBlocking)
    }

    func testWhenMeasureChooseBrowserCTAActionThenCarriesStoredDownloadReasonVariant() {
        // GIVEN — a download reason was selected earlier in the tailored flow.
        sharedPixelsStorageMock.onboardingVariant = .downloadReasonSearch

        // WHEN
        sut.measureChooseBrowserCTAAction()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.setDefault(.clicked(.engage))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .downloadReasonSearch)
    }

    func testWhenMeasureSetDefaultBrowserSkippedThenCarriesStoredDownloadReasonVariant() {
        // GIVEN — a download reason was selected earlier in the tailored flow.
        sharedPixelsStorageMock.onboardingVariant = .downloadReasonNoAI

        // WHEN
        sut.measureSetDefaultBrowserSkipped()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.setDefault(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .downloadReasonNoAI)
    }

    func testWhenMeasureDownloadReasonSelectionThenDownloadChoiceClickedFiresWithMappedReason() {
        // WHEN
        sharedPixelsStorageMock.onboardingVariant = nil // reset the variant before each selection so every choice fires from a clean state
        sut.measureDownloadReasonSelection(.browserPrivately)
        sharedPixelsStorageMock.onboardingVariant = nil
        sut.measureDownloadReasonSelection(.privateAIChat)
        sharedPixelsStorageMock.onboardingVariant = nil
        sut.measureDownloadReasonSelection(.noAI)
        sharedPixelsStorageMock.onboardingVariant = nil
        sut.measureDownloadReasonSelection(.blockAds)

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [
            .downloadChoice(.clicked(.search)),
            .downloadChoice(.clicked(.aiChat)),
            .downloadChoice(.clicked(.noAI)),
            .downloadChoice(.clicked(.adBlocking))
        ])
        // The download-choice pixel itself carries no variant (the variant is set from this choice).
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
    }

    func testWhenMeasureDownloadReasonSelectionThenChosenReasonPersistedAsVariant() {
        let expectedVariants: [(OnboardingDownloadReason, OnboardingPixelParameter.Variant)] = [
            (.browserPrivately, .downloadReasonSearch),
            (.privateAIChat, .downloadReasonAIChat),
            (.noAI, .downloadReasonNoAI),
            (.blockAds, .downloadReasonAdBlocking)
        ]

        for (reason, expectedVariant) in expectedVariants {
            // GIVEN
            sharedPixelsStorageMock.onboardingVariant = nil

            // WHEN
            sut.measureDownloadReasonSelection(reason)

            // THEN
            XCTAssertEqual(sharedPixelsStorageMock.onboardingVariant, expectedVariant, "Failed for reason \(reason)")
        }
    }

    func testWhenVariantAlreadySetThenLaterSelectionDoesNotOverwriteIt() {
        // GIVEN a variant already set (e.g. by the download-reason screen)
        sharedPixelsStorageMock.onboardingVariant = .downloadReasonSearch

        // WHEN a later branching step tries to set another variant
        sut.measureDuckAIQuerySubmission(selection: .duckAI, promptSource: .custom)

        // THEN the first variant wins and is not overwritten
        XCTAssertEqual(sharedPixelsStorageMock.onboardingVariant, .downloadReasonSearch)
    }

    func testWhenMeasureDownloadReasonSelectionThenSelectionExperimentMetricFires() {
        let expectedMetrics: [(OnboardingDownloadReason, String)] = [
            (.browserPrivately, "download_reason_selected_search"),
            (.privateAIChat, "download_reason_selected_ai-chat"),
            (.noAI, "download_reason_selected_no-ai"),
            (.blockAds, "download_reason_selected_ad-blocking")
        ]

        for (reason, expectedMetric) in expectedMetrics {
            // GIVEN
            MockExperimentPixelFiring.reset()

            // WHEN
            sut.measureDownloadReasonSelection(reason)

            // THEN
            XCTAssertTrue(MockExperimentPixelFiring.firedMetrics.contains(expectedMetric), "Failed for reason \(reason)")
        }
    }

    func testWhenMeasureSearchPrivacySettingsSelectionThenSerpClickedFires() {
        // WHEN
        sut.measureSearchPrivacySettingsSelection(recentlyVisitedSitesEnabled: true, safeSearchEnabled: false)

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.preferencesSerp(.clicked(recentlyVisitedSitesEnabled: true, safeSearchEnabled: false))])
    }

    func testWhenMeasureAIModelSelectionThenAIModelClickedFires() {
        // WHEN
        sut.measureAIModelSelection(model: "claude")

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.preferencesAIModel(.clicked(model: "claude"))])
    }

    func testWhenMeasureToggleInputModeSelectionThenToggleModeClickedFires() {
        // WHEN
        sut.measureToggleInputModeSelection(openNewTabsWithAIChat: true)

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.preferencesAIToggleMode(.clicked(openNewTabsWithAIChat: true))])
    }

    func testWhenMeasureAISearchSettingsSelectionThenAISearchClickedFires() {
        // WHEN
        sut.measureAISearchSettingsSelection(searchAssistEnabled: false, aiGeneratedImagesEnabled: true)

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.preferencesAISearch(.clicked(searchAssistEnabled: false, aiGeneratedImagesEnabled: true))])
    }

    func testWhenMeasureKeepDuckAISelectionEnabledThenDuckAIOnClickedFires() {
        // WHEN
        sut.measureKeepDuckAISelection(shouldKeep: true)

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.preferencesDuckAI(.clicked(.on))])
    }

    func testWhenMeasureKeepDuckAISelectionDisabledThenDuckAIOffClickedFires() {
        // WHEN
        sut.measureKeepDuckAISelection(shouldKeep: false)

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.preferencesDuckAI(.clicked(.off))])
    }

    func testWhenMeasureAdBlockingSelectionThenAdBlockingClickedFires() {
        // WHEN
        sut.measureAdBlockingSelection(youTubeAdBlockingEnabled: true, cookiePopUpProtectionEnabled: true, popUpsWithoutOptOutsEnabled: false)

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.preferencesAdBlocking(.clicked(youTubeAdBlockingEnabled: true, cookiePopUpProtectionEnabled: true, popUpsWithoutOptOutsEnabled: false))])
    }

}

private final class MockOnboardingSharedPixelHandling: OnboardingSharedPixelHandling {
    private(set) var eventsFired: [OnboardingSharedPixelEvent] = []
    private(set) var receivedSource: OnboardingPixelParameter.Source?
    private(set) var receivedFlow: OnboardingPixelParameter.Flow?
    private(set) var receivedVariant: OnboardingPixelParameter.Variant?

    func fire(_ event: OnboardingSharedPixelEvent,
              source: OnboardingPixelParameter.Source?,
              flow: OnboardingPixelParameter.Flow?,
              variant: OnboardingPixelParameter.Variant?) {
        eventsFired.append(event)
        receivedSource = source
        receivedFlow = flow
        receivedVariant = variant
    }
}

private enum MockExperimentPixelFiring: ExperimentPixelFiring {
    private(set) static var firedMetrics: [String] = []

    static func fireExperimentPixel(for subfeatureID: SubfeatureID,
                                    metric: String,
                                    conversionWindowDays: ConversionWindow,
                                    value: String) {
        firedMetrics.append(metric)
    }

    static func reset() {
        firedMetrics = []
    }
}
