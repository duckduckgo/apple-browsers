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

    func testWhenFiringPixelEventThenUsesExpectedName() throws {
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(pixelFiring: pixelFiring)

        pixelHandler.fire(.welcome(.shown))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.pixel.name, "onboarding_welcome")
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

    func testWhenInstallTypeIsProvidedThenItParameterIsIncluded() throws {
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(installType: .newInstall, pixelFiring: pixelFiring)

        pixelHandler.fire(.welcome(.shown))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.additionalParameters?["it"], "new")
    }

    func testWhenInstallTypeIsNotProvidedThenItParameterIsOmitted() throws {
        let pixelFiring = PixelKitMock()
        let pixelHandler = makeHandler(installType: nil, pixelFiring: pixelFiring)

        pixelHandler.fire(.welcome(.shown))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertNil(event.additionalParameters?["it"])
    }

    func testWhenDaysSinceInstallIsInRangeThenDParameterIsIncluded() throws {
        let pixelFiring = PixelKitMock()
        let currentDate = Date()
        let pixelHandler = makeHandler(installDate: currentDate.daysAgo(28), currentDateProvider: { currentDate }, pixelFiring: pixelFiring)

        pixelHandler.fire(.welcome(.shown))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(event.additionalParameters?["d"], "28")
    }

    func testWhenDaysSinceInstallIsOutOfRangeThenDParameterIsOmitted() throws {
        let pixelFiring = PixelKitMock()
        let currentDate = Date()
        let pixelHandler = makeHandler(installDate: currentDate.daysAgo(29), currentDateProvider: { currentDate }, pixelFiring: pixelFiring)

        pixelHandler.fire(.welcome(.shown))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertNil(event.additionalParameters?["d"])
    }

    func testWhenDaysSinceInstallIsNegativeThenDParameterIsOmitted() throws {
        let pixelFiring = PixelKitMock()
        let currentDate = Date()
        let pixelHandler = makeHandler(installDate: currentDate.daysAgo(-1), currentDateProvider: { currentDate }, pixelFiring: pixelFiring)

        pixelHandler.fire(.welcome(.shown))

        let event = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertNil(event.additionalParameters?["d"])
    }
}

private extension OnboardingSharedPixelTests {
    func makeHandler(platform: OnboardingSharedPixelHandler.Platform = .macOS,
                     installType: OnboardingSharedPixelHandler.InstallType? = nil,
                     installDate: Date? = nil,
                     currentDateProvider: @escaping () -> Date = { Date() },
                     pixelFiring: PixelFiring? = nil) -> OnboardingSharedPixelHandler {
        OnboardingSharedPixelHandler(platform: platform,
                                     installType: installType,
                                     installDate: installDate,
                                     currentDateProvider: currentDateProvider,
                                     pixelFiring: pixelFiring)
    }
}
