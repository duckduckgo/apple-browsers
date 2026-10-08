//
//  DuckAiTermsOfServicePixelAdapterTests.swift
//  DuckDuckGo
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
@testable import DuckDuckGo

final class DuckAiTermsOfServicePixelAdapterTests: XCTestCase {

    private var pixelKitMock: PixelKitMock!
    private var surface: UnifiedToggleInputPixelSurface?
    private var sut: DuckAiTermsOfServicePixelAdapter!

    override func setUp() {
        super.setUp()
        pixelKitMock = PixelKitMock()
        surface = .addressBar
        sut = DuckAiTermsOfServicePixelAdapter(firing: UTIPixelFiring(pixelKit: { [unowned self] in pixelKitMock }),
                                               surface: { [unowned self] in surface })
    }

    override func tearDown() {
        sut = nil
        pixelKitMock = nil
        super.tearDown()
    }

    func testWhenEachSessionEventFiresThenItIsReportedUnderItsGroupsName() {
        sut.fire(.sessionStarted(.shown))
        sut.fire(.promptSubmitted(.shown, .ask))
        sut.fire(.abandoned(.shown))
        sut.fire(.sessionStarted(.notShown))
        sut.fire(.promptSubmitted(.notShown, .voice))
        sut.fire(.abandoned(.notShown))
        sut.fire(.linkTapped)

        XCTAssertEqual(firedNames, ["aichat_terms_of_service_shown",
                                    "aichat_terms_of_service_shown_prompt_submitted",
                                    "aichat_terms_of_service_shown_abandoned",
                                    "aichat_terms_of_service_not_shown",
                                    "aichat_terms_of_service_not_shown_prompt_submitted",
                                    "aichat_terms_of_service_not_shown_abandoned",
                                    "aichat_terms_of_service_link_tapped"])
        XCTAssertTrue(pixelKitMock.actualFireCalls.allSatisfy { $0.frequency == .dailyAndCount })
    }

    func testWhenAPromptIsSubmittedThenTheSurfaceAndSendMethodAreReported() {
        surface = .contextualChat

        sut.fire(.promptSubmitted(.notShown, .quickAction))

        XCTAssertEqual(lastParameters, ["surface": "contextual_chat", "send_method": "quick_action"])
    }

    func testWhenAcceptedInTheNativeInputThenTheSurfaceIsReported() {
        surface = .duckAI

        sut.fire(.accepted(.nativeInput, isNativeDisclaimerEnabled: true))

        XCTAssertEqual(firedNames, ["aichat_terms_of_service_accepted"])
        XCTAssertEqual(lastParameters, ["surface": "duck_ai", "source": "native_input", "native_disclaimer": "enabled"])
    }

    /// The web app has no native surface.
    func testWhenAcceptedOnTheWebThenNoSurfaceIsReported() {
        surface = nil

        sut.fire(.accepted(.web, isNativeDisclaimerEnabled: false))

        XCTAssertEqual(lastParameters, ["source": "web", "native_disclaimer": "disabled"])
    }

    func testWhenASessionEventHasNoSurfaceThenNothingIsReported() {
        surface = nil

        sut.fire(.sessionStarted(.notShown))

        XCTAssertTrue(pixelKitMock.actualFireCalls.isEmpty)
    }

    func testWhenSendMethodsAreMappedThenEachTriggerKeepsItsMeaning() {
        XCTAssertEqual(DuckAiTermsOfServiceSendMethod(trigger: .sendButton), .ask)
        XCTAssertEqual(DuckAiTermsOfServiceSendMethod(trigger: .textEntry), .return)
        XCTAssertEqual(DuckAiTermsOfServiceSendMethod(trigger: .programmatic), .quickAction)
        XCTAssertEqual(DuckAiTermsOfServiceSendMethod(sentWithAsk: true), .ask)
        XCTAssertEqual(DuckAiTermsOfServiceSendMethod(sentWithAsk: false), .return)
    }

    private var firedNames: [String] {
        pixelKitMock.actualFireCalls.map(\.pixel.name)
    }

    private var lastParameters: [String: String]? {
        pixelKitMock.actualFireCalls.last?.pixel.parameters
    }
}
