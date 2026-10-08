//
//  DuckAiTermsOfServicePixelTests.swift
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

import AIChat
@_spi(Testing) import PixelKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

/// The event → pixel mapping: each group lands on its own series, under the complete `_macos` name.
final class DuckAiTermsOfServicePixelTests: XCTestCase {

    private var pixelFiring: PixelKitMock!
    private var sut: DuckAiTermsOfServicePixelAdapter!

    override func setUp() {
        super.setUp()
        pixelFiring = PixelKitMock()
        sut = DuckAiTermsOfServicePixelAdapter(surface: .addressBar, pixelFiring: pixelFiring)
    }

    override func tearDown() {
        pixelFiring = nil
        sut = nil
        super.tearDown()
    }

    private var firedNames: [String] { pixelFiring.actualFireCalls.map(\.pixel.name) }

    func testWhenSessionsStartThenEachGroupReportsItsOwnSeries() {
        sut.fire(.sessionStarted(.shown))
        sut.fire(.sessionStarted(.notShown))

        XCTAssertEqual(pixelFiring.actualFireCalls, [
            .init(pixel: DuckAiTermsOfServicePixel.shown(surface: .addressBar), frequency: .dailyAndCount),
            .init(pixel: DuckAiTermsOfServicePixel.notShown(surface: .addressBar), frequency: .dailyAndCount)
        ])
        XCTAssertEqual(firedNames, ["aichat_terms_of_service_shown_macos", "aichat_terms_of_service_not_shown_macos"])
    }

    func testWhenAPromptIsSubmittedThenItReportsTheSendMethodAndSurface() {
        sut.fire(.promptSubmitted(.shown, .ask))
        sut.fire(.promptSubmitted(.notShown, .return))

        XCTAssertEqual(firedNames, ["aichat_terms_of_service_shown_prompt_submitted_macos",
                                    "aichat_terms_of_service_not_shown_prompt_submitted_macos"])
        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.parameters), [
            ["surface": "address_bar", "send_method": "ask"],
            ["surface": "address_bar", "send_method": "return"]
        ])
    }

    func testWhenASessionIsAbandonedOrTheLinkTappedThenEachHasItsOwnName() {
        sut.fire(.abandoned(.shown))
        sut.fire(.abandoned(.notShown))
        sut.fire(.linkTapped)

        XCTAssertEqual(firedNames, ["aichat_terms_of_service_shown_abandoned_macos",
                                    "aichat_terms_of_service_not_shown_abandoned_macos",
                                    "aichat_terms_of_service_link_tapped_macos"])
    }

    func testWhenAcceptedInTheNativeInputThenItReportsTheSurface() {
        let promptBar = DuckAiTermsOfServicePixelAdapter(surface: .promptBar, pixelFiring: pixelFiring)

        promptBar.fire(.accepted(.nativeInput, isNativeDisclaimerEnabled: true))

        XCTAssertEqual(firedNames, ["aichat_terms_of_service_accepted_macos"])
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.pixel.parameters,
                       ["surface": "prompt_bar", "source": "native_input", "native_disclaimer": "enabled"])
    }

    func testWhenAcceptedOnTheWebThenNoSurfaceIsSent() {
        let web = DuckAiTermsOfServicePixelAdapter(surface: nil, pixelFiring: pixelFiring)

        web.fire(.accepted(.web, isNativeDisclaimerEnabled: false))

        XCTAssertEqual(pixelFiring.actualFireCalls.first?.pixel.parameters,
                       ["source": "web", "native_disclaimer": "disabled"])
    }

    /// Only the web's acceptance comes without a native surface.
    func testWhenASessionEventHasNoSurfaceThenNothingIsReported() {
        let web = DuckAiTermsOfServicePixelAdapter(surface: nil, pixelFiring: pixelFiring)

        web.fire(.sessionStarted(.notShown))

        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    func testWhenFiredThenTheNameIsNotPrefixed() {
        sut.fire(.linkTapped)

        XCTAssertEqual(pixelFiring.actualFireCalls.first?.pixel.namePrefix, PixelKitNamePrefix.none)
    }
}
