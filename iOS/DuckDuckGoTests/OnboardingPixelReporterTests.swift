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
import Persistence
import PersistenceTestingUtils
import PixelKit
import PixelKitTestingUtilities
import PrivacyConfig
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
        sut = OnboardingPixelReporter(pixel: OnboardingPixelFireMock.self, uniquePixel: OnboardingUniquePixelFireMock.self, experimentPixel: OnboardingExperimentPixelFireMock.self, statisticsStore: statisticsStoreMock, calendar: calendar, dateProvider: { self.now }, userDefaults: userDefaultsMock, sharedPixelHandler: sharedPixelHandlerMock, sharedPixelsStorage: sharedPixelsStorageMock)
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        OnboardingPixelFireMock.tearDown()
        OnboardingUniquePixelFireMock.tearDown()
        OnboardingExperimentPixelFireMock.tearDown()
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
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
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
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
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
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
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
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
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
        sut.measureBrowserComparisonImpression()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(expectedPixel.name, "m_preonboarding_comparison_chart_shown_unique")
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedParams, [:])
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedIncludeParameters, [.appVersion])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.setDefault(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
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
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
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
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
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
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
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
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
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

    func testWhenMeasureScreenImpressionWithDuckAIFireDialogEventThenLegacyFireDialogShownUniqueAndExperimentPixelsFireWithoutSharedPixels() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingDuckAIExperimentFireDialogShownUnique
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureScreenImpression(event: expectedPixel)

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(OnboardingExperimentPixelFireMock.firedMetrics.count, 2)
        XCTAssertTrue(OnboardingExperimentPixelFireMock.firedMetrics.allSatisfy {
            $0.subfeatureID == AIChatSubfeature.onboardingDuckAIQueryTrackersDemoExperiment.rawValue
                && $0.metric == "screen-impression"
                && $0.value == "fire-dialog"
        })
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

    func testWhenMeasureDuckAIExperimentFireButtonCTAActionThenLegacyCTAPressedAndExperimentPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingDuckAIExperimentFireButtonCTAPressed
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureDuckAIExperimentFireButtonCTAAction()

        // THEN
        XCTAssertTrue(OnboardingPixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingPixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(OnboardingExperimentPixelFireMock.firedMetrics.count, 2)
        XCTAssertTrue(OnboardingExperimentPixelFireMock.firedMetrics.allSatisfy {
            $0.subfeatureID == AIChatSubfeature.onboardingDuckAIQueryTrackersDemoExperiment.rawValue
                && $0.metric == "cta-pressed"
                && $0.value == "fire-button-pressed"
        })
    }

    func testWhenMeasureDuckAIExperimentFinalDialogImpressionThenLegacyFinalDialogShownUniqueAndExperimentPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingDuckAIExperimentFinalDialogShownUnique

        // WHEN
        sut.measureDuckAIExperimentFinalDialogImpression()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, expectedPixel)
        XCTAssertEqual(OnboardingExperimentPixelFireMock.firedMetrics.count, 2)
        XCTAssertTrue(OnboardingExperimentPixelFireMock.firedMetrics.allSatisfy {
            $0.subfeatureID == AIChatSubfeature.onboardingDuckAIQueryTrackersDemoExperiment.rawValue
                && $0.metric == "screen-impression"
                && $0.value == "final-dialog"
        })
    }

    func testWhenMeasureDuckAIExperimentFinalDialogCTAActionThenEndEngageSharedPixelFires() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureDuckAIExperimentFinalDialogCTAAction()

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.end(.clicked(.engage))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    // MARK: - Duck AI query experiment (linear onboarding)

    func testWhenMeasureDuckAIQueryExperimentSelectionImpressionThenLegacyToggleImpressionUniqueExperimentAndSearchShownSharedPixelsFire() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureDuckAIQueryExperimentSelectionImpression()

        // THEN
        XCTAssertTrue(OnboardingUniquePixelFireMock.didCallFire)
        XCTAssertEqual(OnboardingUniquePixelFireMock.capturedPixelEvent, .onboardingIntroDuckAIExperimentToggleImpressionUnique)
        XCTAssertEqual(OnboardingExperimentPixelFireMock.firedMetrics.count, 2)
        XCTAssertTrue(OnboardingExperimentPixelFireMock.firedMetrics.allSatisfy {
            $0.subfeatureID == AIChatSubfeature.onboardingDuckAIQueryTrackersDemoExperiment.rawValue
                && $0.metric == "screen-impression"
                && $0.value == "toggle-screen"
        })

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.searchChatToggle(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
    }

    func testWhenMeasureDuckAIQueryExperimentQuerySubmissionWithCustomPromptThenSearchCustomSharedPixelFiresAndVariantIsPersisted() {
        // GIVEN
        sharedPixelsStorageMock.onboardingVariant = nil
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureDuckAIQueryExperimentQuerySubmission(selection: .search, promptSource: .custom)

        // THEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.searchChatToggle(.clicked(.customSearch))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
        XCTAssertEqual(sharedPixelsStorageMock.onboardingVariant, .duckAISearch)
    }

    func testWhenMeasureDuckAIQueryExperimentQuerySubmissionWithSuggestedPromptThenSearchSuggestedSharedPixelFiresAndVariantIsPersisted() {
        // GIVEN
        sharedPixelsStorageMock.onboardingVariant = nil
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureDuckAIQueryExperimentQuerySubmission(selection: .duckAI, promptSource: .option1)

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
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
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
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
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
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
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
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
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
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
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
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
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
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
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
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
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
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
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
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
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
        XCTAssertNil(sharedPixelHandlerMock.receivedVariant)
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
