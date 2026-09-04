//
//  AppRatingCoordinationCapabilityTests.swift
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

import FeatureFlags_iOS
import Foundation
import Testing
@testable import DuckDuckGo

@Suite("App Rating Prompt - Coordination Capability")
struct AppRatingCoordinationCapabilityTests {

    struct Scenario: Sendable, CustomTestStringConvertible {
        let mode: PromoCoordinationMode
        let isRatingFlagOn: Bool
        let isCoordinationEnabled: Bool

        var testDescription: String {
            "mode: \(mode), ratingFlag: \(isRatingFlagOn) -> \(isCoordinationEnabled)"
        }
    }

    @Test(
        "Coordination requires both the promo queue and the rating prompt flag",
        arguments: [
            Scenario(mode: .coordinated, isRatingFlagOn: true, isCoordinationEnabled: true),
            Scenario(mode: .coordinated, isRatingFlagOn: false, isCoordinationEnabled: false),
            // The case that matters: the rating flag alone must not opt the prompt into a queue
            // that is not coordinating, because the legacy route has no lease for it to hold.
            Scenario(mode: .legacy, isRatingFlagOn: true, isCoordinationEnabled: false),
            Scenario(mode: .legacy, isRatingFlagOn: false, isCoordinationEnabled: false),
        ]
    )
    func coordinationRequiresBothFlags(_ scenario: Scenario) {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = scenario.isRatingFlagOn ? [.appRatingPromptCoordination] : []

        let capability = AppRatingCoordinationCapability.create(
            promoCoordinationMode: scenario.mode,
            featureFlagger: featureFlagger
        )

        #expect(capability.isCoordinationEnabled == scenario.isCoordinationEnabled)
    }

    @Test("The promo presentation flag alone does not enable coordination")
    func promoPresentationFlagAloneDoesNotEnableCoordination() {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.promoPresentationCoordination]

        let capability = AppRatingCoordinationCapability.create(
            promoCoordinationMode: .coordinated,
            featureFlagger: featureFlagger
        )

        #expect(!capability.isCoordinationEnabled)
    }
}
