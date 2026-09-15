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
@_spi(Testing) import PixelKit
import PrivacyConfig
import PixelExperimentKit
@testable import DuckDuckGo

final class OnboardingPixelReporterTests: XCTestCase {
    private static let suiteName = "testing_onboarding_pixel_store"
    private var sut: OnboardingPixelReporter!
    private var pixelKitMock: PixelKitMock!
    private var statisticsStoreMock: MockStatisticsStore!
    private var now: Date!
    private var userDefaultsMock: UserDefaults!
    private var sharedPixelHandlerMock: MockOnboardingSharedPixelHandling!
    private var sharedPixelsStorageMock: (any KeyedStoring<OnboardingSharedPixelsKeys>)!

    override func setUpWithError() throws {
        pixelKitMock = PixelKitMock()
        statisticsStoreMock = MockStatisticsStore()
        statisticsStoreMock.atb = "TESTATB"
        now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        userDefaultsMock = UserDefaults(suiteName: Self.suiteName)
        sharedPixelHandlerMock = MockOnboardingSharedPixelHandling()
        initSharedPixelsStorageMock()
        MockExperimentPixelFiring.reset()
        sut = OnboardingPixelReporter(pixelFiring: pixelKitMock, statisticsStore: statisticsStoreMock, calendar: calendar, dateProvider: { self.now }, userDefaults: userDefaultsMock, sharedPixelHandler: sharedPixelHandlerMock, sharedPixelsStorage: sharedPixelsStorageMock, downloadReasonExperimentMetric: OnboardingDownloadReasonExperimentMetric(experimentPixelFiring: MockExperimentPixelFiring.self))
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        pixelKitMock = nil
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
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial }))
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.additionalParameters ?? [:], [:])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureOnboardingIntroImpression()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, "m_preonboarding_intro_shown_unique")
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.additionalParameters ?? [:], [:])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.welcome(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureSkipOnboardingCTAIsCalledThenLegacySkipPressedAndWelcomeDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroSkipOnboardingCTAPressed
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.additionalParameters ?? [:], [:])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureSkipOnboardingCTAAction()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, "m_preonboarding_skip-onboarding-pressed")
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.additionalParameters ?? [:], [:])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.welcome(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureConfirmSkipOnboardingCTAIsCalledThenLegacyConfirmSkipPressedAndSkipOnboardingEngageSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroConfirmSkipOnboardingCTAPressed
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.additionalParameters ?? [:], [:])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureConfirmSkipOnboardingCTAAction()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, "m_preonboarding_confirm-skip-onboarding-pressed")
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.additionalParameters ?? [:], [:])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.skipOnboarding(.clicked(.engage))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureCancelSkipOnboardingCTAIsCalledThenLegacyResumePressedAndSkipOnboardingDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroResumeOnboardingCTAPressed
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.additionalParameters ?? [:], [:])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureResumeOnboardingCTAAction()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, "m_preonboarding_resume-onboarding-pressed")
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.additionalParameters ?? [:], [:])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.skipOnboarding(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureBrowserComparisonImpressionThenLegacyComparisonChartShownUniqueAndSetDefaultShownSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroComparisonChartShownUnique
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial }))
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.additionalParameters ?? [:], [:])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureSetDefaultBrowserImpression()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, "m_preonboarding_comparison_chart_shown_unique")
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.additionalParameters ?? [:], [:])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.setDefault(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertNotNil(sharedPixelHandlerMock.receivedVariant)
    }

    func testWhenMeasureChooseBrowserCTAActionThenLegacyChooseBrowserPressedAndSetDefaultEngageSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroChooseBrowserCTAPressed
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.additionalParameters ?? [:], [:])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureChooseBrowserCTAAction()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, "m_preonboarding_choose_browser_pressed")
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.additionalParameters ?? [:], [:])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.setDefault(.clicked(.engage))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertNotNil(sharedPixelHandlerMock.receivedVariant)
    }

    func testWhenMeasureAiComparisonImpressionThenAiComparisonShownSharedPixelFires() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })

        // WHEN
        sut.measureAiIntroImpression()

        // THEN
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.aiIntro(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureAiComparisonCTAActionThenAiComparisonEngageSharedPixelFires() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })

        // WHEN
        sut.measureAiIntroCTAAction()

        // THEN
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.aiIntro(.clicked(.engage))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureStartOnboardingCTAActionThenWelcomeEngageSharedPixelFires() {
        // GIVEN
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })

        // WHEN
        sut.measureStartOnboardingCTAAction()

        // THEN
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })

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
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.pixel.name, expectedPixel.name)
    }

    func testWhenMeasureAutoRestoreOnboardingSkipCTAActionThenLegacySkipTappedUniquePixelFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.syncAutoRestoreOnboardingSkipTappedUnique

        // WHEN
        sut.measureAutoRestoreOnboardingSkipCTAAction()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.pixel.name, expectedPixel.name)
    }

    func testWhenMeasureAutoRestoreOnboardingPromptShownThenLegacyPixelFiresWithoutSharedPixels() {
        // GIVEN
        let expectedPixel = Pixel.Event.syncAutoRestoreOnboardingPromptShownUnique
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureAutoRestoreOnboardingPromptShown()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.pixel.name, expectedPixel.name)
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
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial }))
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.additionalParameters ?? [:], [:])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureCustomSearch()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, "m_onboarding_search_custom_unique")
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.additionalParameters ?? [:], [:])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.search(.clicked(.custom))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureCustomSiteIsCalledThenLegacySiteCustomUniqueAndVisitSiteCustomSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingContextualSiteCustomUnique
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial }))
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.additionalParameters ?? [:], [:])
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureCustomSite()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, "m_onboarding_visit_site_custom_unique")
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.additionalParameters ?? [:], [:])

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.visitSite(.clicked(.custom))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureSecondVisitIsCalledAndStoreDoesNotContainPixelThenPixelIsNotFired() {
        // GIVEN
        XCTAssertNil(userDefaultsMock.value(forKey: "com.duckduckgo.ios.site-visited"))
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial }))
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.additionalParameters ?? [:], [:])

        // WHEN
        sut.measureSecondSiteVisit()

        // THEN
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial }))
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.additionalParameters ?? [:], [:])
    }

    func testWhenMeasureSecondVisitIsCalledThenFiresOnlyOnSecondTime() {
        // GIVEN
        let key = "com.duckduckgo.ios.site-visited"
        userDefaultsMock.set(true, forKey: key)
        XCTAssertTrue(userDefaultsMock.bool(forKey: key))
        let expectedPixel = Pixel.Event.onboardingContextualSecondSiteVisitUnique
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial }))
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.additionalParameters ?? [:], [:])

        // WHEN
        sut.measureSecondSiteVisit()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, "m_second_sitevisit_unique")
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.additionalParameters ?? [:], [:])
    }

    func testWhenMeasurePrivacyDashboardOpenedForFirstTimeThenPrivacyDashboardFirstTimeOpenedPixelFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.privacyDashboardFirstTimeOpenedUnique
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial }))

        // WHEN
        sut.measurePrivacyDashboardOpenedForFirstTime()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, "m_privacy_dashboard_first_time_used_unique")
    }

    func testWhenMeasurePrivacyDashboardOpenedForFirstTimeThenFromOnboardingParameterIsSetToTrue() {
        // GIVEN
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.additionalParameters ?? [:], [:])

        // WHEN
        sut.measurePrivacyDashboardOpenedForFirstTime()

        // THEN
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.additionalParameters?["from_onboarding"], "true")
    }

    func testWhenMeasurePrivacyDashboardOpenedForFirstTimeThenDaysSinceInstallParameterIsSet() {
        // GIVEN
        let installDate = Date(timeIntervalSince1970: 1722348000) // 30th July 2024 GMT
        now = Date(timeIntervalSince1970: 1722607200) // 1st August 2024 GMT
        statisticsStoreMock.installDate = installDate
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.additionalParameters ?? [:], [:])

        // WHEN
        sut.measurePrivacyDashboardOpenedForFirstTime()

        // THEN
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.additionalParameters?["daysSinceInstall"], "3")
    }

    // MARK: - Dax Dialogs

    func testWhenMeasureScreenImpressionIsCalledThenLegacyUniquePixelFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.daxDialogsSerpUnique
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial }))

        // WHEN
        sut.measureScreenImpression(event: expectedPixel)

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertTrue(sharedPixelHandlerMock.eventsFired.isEmpty)
    }

    func testWhenMeasureScreenImpressionWithDuckAIFireDialogEventThenLegacyFireDialogShownUniqueFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingDuckAIFireDialogShownUnique
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureScreenImpression(event: expectedPixel)

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.pixel.name, expectedPixel.name)
        XCTAssertTrue(sharedPixelHandlerMock.eventsFired.isEmpty)
    }

    func testWhenMeasureScreenImpressionWithFireEducationEventThenLegacyFireEducationUniqueFiresWithoutSharedPixels() {
        // GIVEN
        let expectedPixel = Pixel.Event.daxDialogsFireEducationShownUnique
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureScreenImpression(event: expectedPixel)

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.pixel.name, expectedPixel.name)
        XCTAssertTrue(sharedPixelHandlerMock.eventsFired.isEmpty)
    }

    func testWhenMeasureScreenImpressionIsCalledWithSharedOnboardingPixelThenSharedPixelFires() {
        // GIVEN
        XCTAssertTrue(sharedPixelHandlerMock.eventsFired.isEmpty)

        // WHEN
        sut.measureScreenImpression(.searchResults(.shown))

        // THEN
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.searchResults(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureEndOfJourneyDialogCTAActionIsCalledThenLegacyEndOfJourneyDismissedAndEndEngageSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.daxDialogsEndOfJourneyDismissed
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureEndOfJourneyDialogCTAAction()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)

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
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
    }

    func testWhenMeasureDuckAIFinalDialogImpressionThenLegacyFinalDialogShownUniquePixelFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingDuckAIFinalDialogShownUnique

        // WHEN
        sut.measureDuckAIFinalDialogImpression()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.pixel.name, expectedPixel.name)
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
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.pixel.name, Pixel.Event.onboardingIntroDuckAIToggleImpressionUnique.name)
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
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureTrySearchDialogNewTabDismissButtonTapped()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.search(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureTryVisitSiteDialogNewTabDismissButtonTappedThenLegacyDismissTappedAndVisitSiteDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingTryVisitSiteDialogNewTabDismissButtonTapped
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureTryVisitSiteDialogNewTabDismissButtonTapped()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.visitSite(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureTryVisitSiteDialogDismissButtonTappedThenLegacyDismissTappedAndVisitSiteDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingTryVisitSiteDialogDismissButtonTapped
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureTryVisitSiteDialogDismissButtonTapped()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.visitSite(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureSearchResultDialogDismissButtonTappedThenLegacyDismissTappedAndSearchResultsDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingSearchResultDialogDismissButtonTapped
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureSearchResultDialogDismissButtonTapped()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.searchResults(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureTrackersDialogDismissButtonTappedThenLegacyDismissTappedAndTrackersBlockedDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingTrackersDialogDismissButtonTapped
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureTrackersDialogDismissButtonTapped()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.trackersBlocked(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureFireDialogDismissButtonTappedThenLegacyDismissTappedAndFireButtonDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingFireDialogDismissButtonTapped
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureFireDialogDismissButtonTapped()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.fireButton(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureEndOfJourneyDialogNewTabDismissButtonTappedThenLegacyDismissTappedAndEndDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingEndOfJourneyDialogNewTabDismissButtonTapped
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureEndOfJourneyDialogNewTabDismissButtonTapped()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.end(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureEndOfJourneyDialogDismissButtonTappedThenLegacyDismissTappedAndEndDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingEndOfJourneyDialogDismissButtonTapped
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureEndOfJourneyDialogDismissButtonTapped()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.end(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureSubscriptionPromoDialogNewTabDismissButtonTappedThenLegacyDismissTappedAndSubscriptionPromoDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingSubscriptionDialogDismissButtonTapped
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureSubscriptionDialogNewTabDismissButtonTapped()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.subscriptionPromo(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    // MARK: - Onboarding Intro Highglights Experiment

    func testWhenMeasureChooseAppIconImpressionIsCalledThenLegacyChooseIconImpressionUniqueAndAppIconColorShownSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroChooseAppIconImpressionUnique
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureChooseAppIconImpression()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.appIconColor(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureChooseNonDefaultAppIconIsCalledThenLegacyChooseCustomIconColorPressedAndAppIconColorClickedSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroChooseCustomAppIconColorCTAPressed
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureChooseAppIconColor(.green)

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)

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
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.appIconColor(.clicked(.red))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureAddressBarPositionSelectionImpressionIsCalledThenLegacyChooseAddressBarImpressionUniqueAndAddressBarPositionShownSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroChooseAddressBarImpressionUnique
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureAddressBarPositionSelectionImpression()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.addressBarPosition(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureChooseBottomAddressBarPositionIsCalledThenLegacyBottomAddressBarSelectedAndAddressBarBottomSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroBottomAddressBarSelected
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureChooseAddressBarPosition(.bottom)

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)

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
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.addressBarPosition(.clicked(.top))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    // MARK: Add To Dock Experiment

    func testWhenMeasureAddToDockPromoImpressionsIsCalledThenLegacyPromoImpressionsUniqueAndAddToDockShownSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingAddToDockPromoImpressionsUnique
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureAddToDockPromoImpression()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.addToDock(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureAddToDockPromoShowTutorialCTAActionIsCalledThenLegacyShowTutorialTappedAndAddToDockEngageSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingAddToDockPromoShowTutorialCTATapped
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureAddToDockPromoShowTutorialCTAAction()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.addToDock(.clicked(.engage))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureAddToDockPromoDismissCTAActionThenLegacyPromoDismissTappedAndAddToDockDismissSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingAddToDockPromoDismissCTATapped
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureAddToDockPromoDismissCTAAction()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.addToDock(.clicked(.dismiss))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureAddToDockTutorialDismissCTAActionIsCalledThenonboardingAddToDockTutorialDismissCTAPixelFires() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingAddToDockTutorialDismissCTATapped
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureAddToDockTutorialDismissCTAAction()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)
        XCTAssertTrue(sharedPixelHandlerMock.eventsFired.isEmpty)
    }

    // MARK: - Search Experience Selection

    func testWhenMeasureSearchExperienceSelectionImpressionIsCalledThenLegacyChooseSearchExperienceImpressionUniqueAndSearchExperienceShownSharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroChooseSearchExperienceImpressionUnique
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureSearchExperienceSelectionImpression()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .legacyInitial })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .legacyInitial })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.searchExperience(.shown)])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureChooseAIChatIsCalledThenLegacyAIChatSelectedAndSearchExperienceSearchPlusDuckAISharedPixelsFire() {
        // GIVEN
        let expectedPixel = Pixel.Event.onboardingIntroAIChatSelected
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureChooseAIChat()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)

        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [.searchExperience(.clicked(.searchPlusDuckAI))])
        XCTAssertEqual(sharedPixelHandlerMock.receivedSource, .duckAICustomProductPage)
        XCTAssertEqual(sharedPixelHandlerMock.receivedFlow, .duckAI)
        XCTAssertEqual(sharedPixelHandlerMock.receivedVariant, .duckAISearch)
    }

    func testWhenMeasureChooseSearchOnlyIsCalledThenLegacySearchOnlySelectedAndSearchExperienceSearchOnlySharedPixelsFire() {
        // GIVEN
        sharedPixelsStorageMock.onboardingVariant = nil
        let expectedPixel = Pixel.Event.onboardingIntroSearchOnlySelected
        XCTAssertFalse(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertNil(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard }))
        XCTAssertEqual(sharedPixelHandlerMock.eventsFired, [])

        // WHEN
        sut.measureChooseSearchOnly()

        // THEN
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.frequency == .standard })
        XCTAssertEqual(pixelKitMock.actualFireCalls.last(where: { $0.frequency == .standard })?.pixel.name, expectedPixel.name)
        XCTAssertEqual(expectedPixel.name, expectedPixel.name)

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
