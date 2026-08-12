//
//  SubscriptionOnboardingInstrumentationTests.swift
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

import XCTest
import PixelKit
import PixelKitTestingUtilities
@testable import DuckDuckGo

@MainActor
final class SubscriptionOnboardingInstrumentationTests: XCTestCase {

    private var pixelFiring: PixelKitMock!

    private var fired: [SubscriptionPixel] { pixelFiring.actualFireCalls.compactMap { $0.pixel as? SubscriptionPixel } }

    override func setUp() {
        super.setUp()
        pixelFiring = PixelKitMock()
    }

    override func tearDown() {
        pixelFiring = nil
        super.tearDown()
    }

    private func makeInstrumentation(entryPoint: SubscriptionOnboardingEntryPoint = .postCheckout,
                                     isDuckAIEnabled: Bool = true) -> SubscriptionOnboardingInstrumentation {
        SubscriptionOnboardingInstrumentation(entryPoint: entryPoint,
                                             isDuckAIEnabled: { isDuckAIEnabled },
                                             pixelFiring: pixelFiring)
    }

    // MARK: - Step names

    func testWhenEverySectionIsNamedThenTheNamesAreTheAgreedVocabulary() {
        XCTAssertEqual(SubscriptionOnboardingSection.allCases.map(\.pixelStepName),
                       ["intro", "features_summary", "vpn", "vpn_widget", "idtr", "duck_ai", "completion", "pir"])
    }

    func testWhenEntryPointsAreNamedThenTheyMatchThePixelValues() {
        XCTAssertEqual(SubscriptionOnboardingEntryPoint.postCheckout.pixelValue, "post_checkout")
        XCTAssertEqual(SubscriptionOnboardingEntryPoint.subscriptionSettings.pixelValue, "subscription_settings")
    }

    // MARK: - Names on the wire

    /// The step belongs in the name, which is what the definitions' `keyPattern` matches against.
    func testWhenAStepIsReportedThenTheNameCarriesTheEventAndStep() {
        let sut = makeInstrumentation()

        sut.stepShown(.vpnActivation)
        sut.stepCompleted(.duckAI)
        sut.stepSkipped(.vpnActivation)

        XCTAssertEqual(fired.map(\.name), ["subscription_onboarding_step_shown_vpn",
                                           "subscription_onboarding_step_completed_duck_ai",
                                           "subscription_onboarding_step_skipped_vpn"])
    }

    func testWhenTheFlowStartsThenTheDenominatorIsReported() {
        let sut = makeInstrumentation()

        sut.flowStarted()

        XCTAssertEqual(fired.map(\.name), ["subscription_onboarding_flow_started"])
    }

    // MARK: - Parameters

    func testWhenTheFlowStartsThenTheEntryPointAndDuckAIStateAreParameters() {
        let sut = makeInstrumentation(entryPoint: .subscriptionSettings, isDuckAIEnabled: false)

        sut.flowStarted()

        XCTAssertEqual(fired.first?.parameters?["entry_point"], "subscription_settings")
        XCTAssertEqual(fired.first?.parameters?["duck_ai_enabled"], "false")
    }

    func testWhenDuckAIIsEnabledThenTheFlowStartReportsItAsSuch() {
        let sut = makeInstrumentation(isDuckAIEnabled: true)

        sut.flowStarted()

        XCTAssertEqual(fired.first?.parameters?["duck_ai_enabled"], "true")
    }

    /// Without this the two entry points share every step pixel, and neither population can be read.
    func testWhenAStepIsReportedThenTheEntryPointIsAParameter() {
        let sut = makeInstrumentation(entryPoint: .postCheckout)

        sut.stepShown(.idtr)

        XCTAssertEqual(fired.first?.parameters?["entry_point"], "post_checkout")
    }
}
