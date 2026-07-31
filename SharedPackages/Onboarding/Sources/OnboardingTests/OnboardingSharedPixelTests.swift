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
