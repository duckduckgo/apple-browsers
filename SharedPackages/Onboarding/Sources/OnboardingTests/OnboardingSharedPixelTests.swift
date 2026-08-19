//
//  OnboardingSharedPixelTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import PixelKit
import PixelKitTestingUtilities
@testable import Onboarding

final class OnboardingSharedPixelTests: XCTestCase {

    func testWhenFiringiOSPixelEventThenUsesiOSNamePrefix() throws {
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(platform: .iOS, pixelFiring: pixelFiring)

        pixelHandler.fire(.welcome(.shown))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.namePrefix, "m_ios_")
    }

    func testWhenFiringmacOSPixelEventThenUsesmacOSNamePrefix() throws {
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(platform: .macOS, pixelFiring: pixelFiring)

        pixelHandler.fire(.welcome(.shown))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.namePrefix, "m_mac_")
    }

    func testWhenFiringPixelEventWithNilParametersThenUsesExpectedNameAndStandardParameters() throws {
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(pixelFiring: pixelFiring)

        pixelHandler.fire(.welcome(.shown), source: nil, flow: nil, variant: nil)

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.pixel.name, "onboarding_welcome")
        XCTAssertEqual(event.pixel.parameters?["event"], "shown")
        XCTAssertEqual(event.pixel.standardParameters, [.pixelSource])
        XCTAssertNil(event.additionalParameters?["source"])
        XCTAssertNil(event.additionalParameters?["flow"])
        XCTAssertNil(event.additionalParameters?["variant"])
    }

    func testWhenFiringPixelEventWithAdditionalParametersThenUsesProvidedParameters() throws {
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(pixelFiring: pixelFiring)

        pixelHandler.fire(.searchResults(.shown),
                          source: .duckAICustomProductPage,
                          flow: .duckAI,
                          variant: .duckAISearch)

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.additionalParameters?["source"], "duckai_cpp")
        XCTAssertEqual(event.additionalParameters?["flow"], "duckai")
        XCTAssertEqual(event.additionalParameters?["variant"], "search_plus_duckai-search")
    }

    func testWhenFlowIsTailoredByDownloadReasonThenUsesTailoredByDownloadReasonValue() throws {
        // GIVEN
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(pixelFiring: pixelFiring)

        // WHEN
        pixelHandler.fire(.welcome(.shown),
                          source: .default,
                          flow: .tailoredByDownloadReason,
                          variant: nil)

        // THEN
        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.additionalParameters?["flow"], "tailored_by_download_reason")
    }

    func testWhenVariantIsDownloadReasonThenUsesDownloadReasonValue() throws {
        // GIVEN
        let expectedValues: [OnboardingPixelParameter.Variant: String] = [
            .downloadReasonSearch: "download_reason_search",
            .downloadReasonAIChat: "download_reason_ai-chat",
            .downloadReasonNoAI: "download_reason_no-ai",
            .downloadReasonAdBlocking: "download_reason_ad-blocking"
        ]

        // WHEN
        for (variant, expectedValue) in expectedValues {
            let pixelFiring = PixelKitMock()
            let pixelHandler = makeHandler(pixelFiring: pixelFiring)

            pixelHandler.fire(.welcome(.shown),
                              source: .default,
                              flow: .tailoredByDownloadReason,
                              variant: variant)

            // THEN
            let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
            XCTAssertEqual(event.additionalParameters?["variant"], expectedValue, "Failed for variant \(variant)")
        }
    }

    func testWhenVariantInitFromDownloadReasonThenMapsToExpectedVariant() {
        // GIVEN
        let expectedMappings: [OnboardingDownloadReason: OnboardingPixelParameter.Variant] = [
            .browserPrivately: .downloadReasonSearch,
            .privateAIChat: .downloadReasonAIChat,
            .noAI: .downloadReasonNoAI,
            .blockAds: .downloadReasonAdBlocking
        ]

        // WHEN
        for (reason, expectedVariant) in expectedMappings {
            // THEN
            XCTAssertEqual(OnboardingPixelParameter.Variant(reason), expectedVariant, "Failed for reason \(reason)")
        }
    }

    func testWhenFiringPixelEventThenFrequencyIsUniqueByNameAndParameters() throws {
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(pixelFiring: pixelFiring)

        pixelHandler.fire(.welcome(.shown))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.frequency, .uniqueByNameAndParameters)
    }

    func testWhenEventTypeHasNoValueThenValueParameterIsOmitted() throws {
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(pixelFiring: pixelFiring)

        pixelHandler.fire(.welcome(.shown))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertNil(event.pixel.parameters?["value"])
    }

    func testWhenEngagementEventClickedThenUsesEngagementValue() throws {
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(pixelFiring: pixelFiring)

        pixelHandler.fire(.welcome(.clicked(.engage)))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.pixel.parameters?["value"], "engage")
    }

    func testWhenChromeExtensionInstallClickedEngageThenUsesExpectedNameAndParameters() throws {
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(pixelFiring: pixelFiring)

        pixelHandler.fire(.chromeExtensionInstall(.clicked(.engage)))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.pixel.name, "onboarding_chrome-extension-install")
        XCTAssertEqual(event.pixel.parameters?["event"], "clicked")
        XCTAssertEqual(event.pixel.parameters?["value"], "engage")
    }

    func testWhenSearchExperienceEventClickedThenUsesSearchExperienceValue() throws {
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(pixelFiring: pixelFiring)

        pixelHandler.fire(.searchExperience(.clicked(.searchPlusDuckAI)))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.pixel.parameters?["value"], "search_plus_duckai")
    }

    func testWhenSuggestedOrCustomEventClickedThenUsesSuggestedOrCustomValue() throws {
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(pixelFiring: pixelFiring)

        pixelHandler.fire(.search(.clicked(.suggested)))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.pixel.parameters?["value"], "suggested")
    }

    func testWhenSuggestedOrCustomToggleEventClickedThenUsesSuggestedOrCustomValue() throws {
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(pixelFiring: pixelFiring)

        pixelHandler.fire(.searchChatToggle(.clicked(.suggestedChat)))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.pixel.parameters?["value"], "suggested_chat")
    }

    func testWhenCustomizeEventClickedWithValuesThenUsesValues() throws {
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(pixelFiring: pixelFiring)

        pixelHandler.fire(.customization(.clicked([.bookmarksBar, .restoreSession])))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.pixel.parameters?["value"], "bookmarks_bar,restore_session")
    }

    func testWhenCustomizeEventClickedWithNoValuesThenUsesDismiss() throws {
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(pixelFiring: pixelFiring)

        pixelHandler.fire(.customization(.clicked([])))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.pixel.parameters?["value"], "dismiss")
    }

    func testWhenInstallTypeIsProvidedThenInstallTypeParameterIsIncluded() throws {
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(installTypeProvider: { .newInstall }, pixelFiring: pixelFiring)

        pixelHandler.fire(.welcome(.shown))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.additionalParameters?["installType"], "new")
    }

    func testWhenInstallTypeIsNotProvidedThenInstallTypeParameterIsOmitted() throws {
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(installTypeProvider: { nil }, pixelFiring: pixelFiring)

        pixelHandler.fire(.welcome(.shown))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertNil(event.additionalParameters?["installType"])
    }

    func testWhenInstallTypeProviderResultChangesThenSubsequentFiresUseUpdatedInstallTypeParameter() throws {
        let pixelFiring = PixelKitMock()
        var isReinstall = false
        let pixelHandler = makeHandler(installTypeProvider: { isReinstall ? .reinstall : .newInstall }, pixelFiring: pixelFiring)

        pixelHandler.fire(.welcome(.shown))
        let first = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(first.additionalParameters?["installType"], "new")

        isReinstall = true
        pixelHandler.fire(.welcome(.shown))
        let second = try XCTUnwrap(pixelFiring.actualFireCalls.last)
        XCTAssertEqual(second.additionalParameters?["installType"], "reinstall")
    }

    func testWhenDaysSinceInstallIsZeroThenDaysSinceInstallBucketIsZero() throws {
        let pixelFiring = PixelKitMock()
        let currentDate = Date()
        let pixelHandler = makeHandler(
            installDateProvider: { currentDate.daysAgo(0) },
            currentDateProvider: { currentDate },
            pixelFiring: pixelFiring)

        pixelHandler.fire(.welcome(.shown))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.additionalParameters?["daysSinceInstall"], "0")
    }

    func testWhenDaysSinceInstallIsOneToThreeThenDaysSinceInstallBucketIsOneToThree() throws {
        let currentDate = Date()
        for daysAgo in [1, 3] {
            let pixelFiring = PixelKitMock()
            let pixelHandler = makeHandler(
                installDateProvider: { currentDate.daysAgo(daysAgo) },
                currentDateProvider: { currentDate },
                pixelFiring: pixelFiring)

            pixelHandler.fire(.welcome(.shown))

            let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
            XCTAssertEqual(event.additionalParameters?["daysSinceInstall"], "1-3", "Failed for day \(daysAgo)")
        }
    }

    func testWhenDaysSinceInstallIsFourToTenThenDaysSinceInstallBucketIsFourToTen() throws {
        let currentDate = Date()
        for daysAgo in [4, 10] {
            let pixelFiring = PixelKitMock()
            let pixelHandler = makeHandler(
                installDateProvider: { currentDate.daysAgo(daysAgo) },
                currentDateProvider: { currentDate },
                pixelFiring: pixelFiring)

            pixelHandler.fire(.welcome(.shown))

            let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
            XCTAssertEqual(event.additionalParameters?["daysSinceInstall"], "4-10", "Failed for day \(daysAgo)")
        }
    }

    func testWhenDaysSinceInstallIsElevenToTwentyEightThenDaysSinceInstallBucketIsElevenToTwentyEight() throws {
        let currentDate = Date()
        for daysAgo in [11, 28] {
            let pixelFiring = PixelKitMock()
            let pixelHandler = makeHandler(
                installDateProvider: { currentDate.daysAgo(daysAgo) },
                currentDateProvider: { currentDate },
                pixelFiring: pixelFiring)

            pixelHandler.fire(.welcome(.shown))

            let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
            XCTAssertEqual(event.additionalParameters?["daysSinceInstall"], "11-28", "Failed for day \(daysAgo)")
        }
    }

    func testWhenDaysSinceInstallIsTwentyNineOrMoreThenDaysSinceInstallBucketIsTwentyEightPlus() throws {
        let currentDate = Date()
        for daysAgo in [29, 100] {
            let pixelFiring = PixelKitMock()
            let pixelHandler = makeHandler(
                installDateProvider: { currentDate.daysAgo(daysAgo) },
                currentDateProvider: { currentDate },
                pixelFiring: pixelFiring)

            pixelHandler.fire(.welcome(.shown))

            let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
            XCTAssertEqual(event.additionalParameters?["daysSinceInstall"], "28+", "Failed for day \(daysAgo)")
        }
    }

    func testWhenDaysSinceInstallIsNegativeThenDaysSinceInstallParameterIsOmitted() throws {
        let pixelFiring = PixelKitMock()
        let currentDate = Date()
        let pixelHandler = makeHandler(
            installDateProvider: { currentDate.daysAgo(-1) },
            currentDateProvider: { currentDate },
            pixelFiring: pixelFiring)

        pixelHandler.fire(.welcome(.shown))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertNil(event.additionalParameters?["daysSinceInstall"])
    }

    func testWhenAppIconColorClickedThenUsesColorValue() throws {
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(pixelFiring: pixelFiring)

        pixelHandler.fire(.appIconColor(.clicked(.purple)))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.pixel.parameters?["value"], "purple")
    }

    func testWhenAddressBarPositionClickedThenUsesPositionValue() throws {
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(pixelFiring: pixelFiring)

        pixelHandler.fire(.addressBarPosition(.clicked(.bottom)))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.pixel.parameters?["value"], "bottom")
    }

    // MARK: - Segmented onboarding (download-reason) events

    func testWhenSegmentedOnboardingImpressionThenUsesExpectedNameAndNoValue() throws {
        // GIVEN
        let cases: [(OnboardingSharedPixelEvent, String)] = [
            (.downloadChoice(.shown), "onboarding_download-choice"),
            (.preferencesSerp(.shown), "onboarding_preferences_serp"),
            (.preferencesAIModel(.shown), "onboarding_preferences_ai-model"),
            (.preferencesAIToggleMode(.shown), "onboarding_preferences_ai-toggle-mode"),
            (.preferencesAISearch(.shown), "onboarding_preferences_ai-search"),
            (.preferencesDuckAI(.shown), "onboarding_preferences_duck-ai"),
            (.preferencesAdBlocking(.shown), "onboarding_preferences_ad-blocking")
        ]

        for (pixelEvent, expectedName) in cases {
            let pixelFiring = PixelKitMock()
            let pixelHandler = makeHandler(pixelFiring: pixelFiring)

            // WHEN
            pixelHandler.fire(pixelEvent)

            // THEN
            let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
            XCTAssertEqual(event.pixel.name, expectedName, "Failed for \(expectedName)")
            XCTAssertEqual(event.pixel.parameters?["event"], "shown", "Failed for \(expectedName)")
            XCTAssertNil(event.pixel.parameters?["value"], "Failed for \(expectedName)")
        }
    }

    func testWhenDownloadChoiceClickedThenUsesReasonValue() throws {
        // GIVEN
        let expectedValues: [OnboardingSharedPixelEvent.DownloadChoiceEvent.Value: String] = [
            .search: "search",
            .aiChat: "ai-chat",
            .noAI: "no-ai",
            .adBlocking: "ad-blocking"
        ]

        for (value, expectedValue) in expectedValues {
            let pixelFiring = PixelKitMock()
            let pixelHandler = makeHandler(pixelFiring: pixelFiring)

            // WHEN
            pixelHandler.fire(.downloadChoice(.clicked(value)))

            // THEN
            let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
            XCTAssertEqual(event.pixel.name, "onboarding_download-choice")
            XCTAssertEqual(event.pixel.parameters?["event"], "clicked")
            XCTAssertEqual(event.pixel.parameters?["value"], expectedValue, "Failed for \(value)")
        }
    }

    func testWhenPreferencesSerpClickedThenSendsToggleParametersAndNoValue() throws {
        // GIVEN
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(pixelFiring: pixelFiring)

        // WHEN
        pixelHandler.fire(.preferencesSerp(.clicked(recentlyVisitedSitesEnabled: true, safeSearchEnabled: false)))

        // THEN
        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.pixel.name, "onboarding_preferences_serp")
        XCTAssertEqual(event.pixel.parameters?["event"], "clicked")
        XCTAssertNil(event.pixel.parameters?["value"])
        XCTAssertEqual(event.pixel.parameters?["recently_visited_sites_enabled"], "true")
        XCTAssertEqual(event.pixel.parameters?["safe_search_enabled"], "false")
    }

    func testWhenPreferencesAISearchClickedThenSendsToggleParametersAndNoValue() throws {
        // GIVEN
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(pixelFiring: pixelFiring)

        // WHEN
        pixelHandler.fire(.preferencesAISearch(.clicked(searchAssistEnabled: false, aiGeneratedImagesEnabled: true)))

        // THEN
        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.pixel.name, "onboarding_preferences_ai-search")
        XCTAssertEqual(event.pixel.parameters?["event"], "clicked")
        XCTAssertNil(event.pixel.parameters?["value"])
        XCTAssertEqual(event.pixel.parameters?["search_assist_enabled"], "false")
        XCTAssertEqual(event.pixel.parameters?["ai_generated_images_enabled"], "true")
    }

    func testWhenPreferencesAdBlockingClickedThenSendsToggleParametersAndNoValue() throws {
        // GIVEN
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(pixelFiring: pixelFiring)

        // WHEN
        pixelHandler.fire(.preferencesAdBlocking(.clicked(youTubeAdBlockingEnabled: true, cookiePopUpProtectionEnabled: true, popUpsWithoutOptOutsEnabled: false)))

        // THEN
        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.pixel.name, "onboarding_preferences_ad-blocking")
        XCTAssertEqual(event.pixel.parameters?["event"], "clicked")
        XCTAssertNil(event.pixel.parameters?["value"])
        XCTAssertEqual(event.pixel.parameters?["youtube_ad_blocking_enabled"], "true")
        XCTAssertEqual(event.pixel.parameters?["cookie_popup_protection_enabled"], "true")
        XCTAssertEqual(event.pixel.parameters?["popups_without_optouts_enabled"], "false")
    }

    func testWhenPreferencesAIModelClickedThenUsesModelValue() throws {
        // GIVEN
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(pixelFiring: pixelFiring)

        // WHEN
        pixelHandler.fire(.preferencesAIModel(.clicked(model: "claude")))

        // THEN
        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.pixel.name, "onboarding_preferences_ai-model")
        XCTAssertEqual(event.pixel.parameters?["event"], "clicked")
        XCTAssertEqual(event.pixel.parameters?["value"], "claude")
    }

    func testWhenPreferencesAIToggleModeClickedThenUsesEnabledValue() throws {
        for (enabled, expectedValue) in [(true, "true"), (false, "false")] {
            // GIVEN
            let pixelFiring = PixelKitMock()
            let pixelHandler = makeHandler(pixelFiring: pixelFiring)

            // WHEN
            pixelHandler.fire(.preferencesAIToggleMode(.clicked(openNewTabsWithAIChat: enabled)))

            // THEN
            let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
            XCTAssertEqual(event.pixel.name, "onboarding_preferences_ai-toggle-mode")
            XCTAssertEqual(event.pixel.parameters?["value"], expectedValue, "Failed for \(enabled)")
        }
    }

    func testWhenPreferencesDuckAIClickedThenUsesOnOffValue() throws {
        // GIVEN
        let expectedValues: [OnboardingSharedPixelEvent.DuckAIEvent.Value: String] = [
            .on: "on",
            .off: "off"
        ]

        for (value, expectedValue) in expectedValues {
            let pixelFiring = PixelKitMock()
            let pixelHandler = makeHandler(pixelFiring: pixelFiring)

            // WHEN
            pixelHandler.fire(.preferencesDuckAI(.clicked(value)))

            // THEN
            let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
            XCTAssertEqual(event.pixel.name, "onboarding_preferences_duck-ai")
            XCTAssertEqual(event.pixel.parameters?["value"], expectedValue, "Failed for \(value)")
        }
    }

    func testWhenEndTryDuckAIEventThenUsesExpectedNameAndValue() throws {
        // GIVEN
        let cases: [(OnboardingSharedPixelEvent, String, String?)] = [
            (.endTryDuckAI(.shown), "shown", nil),
            (.endTryDuckAI(.clicked(.engage)), "clicked", "engage"),
            (.endTryDuckAI(.clicked(.dismiss)), "clicked", "dismiss")
        ]

        for (pixelEvent, expectedEvent, expectedValue) in cases {
            let pixelFiring = PixelKitMock()
            let pixelHandler = makeHandler(pixelFiring: pixelFiring)

            // WHEN
            pixelHandler.fire(pixelEvent)

            // THEN
            let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
            XCTAssertEqual(event.pixel.name, "onboarding_end-try-duckai")
            XCTAssertEqual(event.pixel.parameters?["event"], expectedEvent, "Failed for \(pixelEvent)")
            XCTAssertEqual(event.pixel.parameters?["value"], expectedValue, "Failed for \(pixelEvent)")
        }
    }
}

private extension OnboardingSharedPixelHandling {
    func fire(_ event: OnboardingSharedPixelEvent) {
        fire(event, source: nil, flow: nil, variant: nil)
    }
}

private extension OnboardingSharedPixelTests {
    func makeHandler(platform: OnboardingSharedPixelHandler.Platform = .macOS,
                     installTypeProvider: @escaping () -> OnboardingSharedPixelHandler.InstallType? = { nil },
                     installDateProvider: @escaping () -> Date? = { nil },
                     currentDateProvider: @escaping () -> Date = { Date() },
                     pixelFiring: PixelFiring? = nil) -> OnboardingSharedPixelHandler {
        OnboardingSharedPixelHandler(platform: platform,
                                     installTypeProvider: installTypeProvider,
                                     installDateProvider: installDateProvider,
                                     currentDateProvider: currentDateProvider,
                                     pixelFiring: pixelFiring)
    }
}
