//
//  AppRatingPromptCoordinationPolicyTests.swift
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
import PrivacyConfig
import PrivacyConfigTestsUtils
import Testing
@testable import DuckDuckGo

@Suite("App Rating Prompt - Coordination Policy")
struct AppRatingPromptCoordinationPolicyTests {

    @Test("Coordination follows the rating prompt flag", arguments: [true, false])
    func coordinationFollowsRatingFlag(_ isRatingFlagOn: Bool) {
        let policy = makePolicy(enabledFlags: isRatingFlagOn ? [.appRatingPromptCoordination] : [])

        #expect(policy.isCoordinationEnabled == isRatingFlagOn)
    }


    @Test("The coordination decision is latched at construction")
    func coordinationDecisionIsLatched() {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.appRatingPromptCoordination]
        let policy = AppRatingPromptCoordinationPolicy(
            featureFlagger: featureFlagger,
            privacyConfigurationManager: MockPrivacyConfigurationManager()
        )
        #expect(policy.isCoordinationEnabled)

        featureFlagger.enabledFeatureFlags = []

        // A live read turning false while a slot is held would strand the lease and skip the
        // cooldown, so this stays fixed for the session.
        #expect(policy.isCoordinationEnabled)
    }

    // MARK: - Unredeemed slot cap

    struct MaxUnredeemedSlotsScenario: Sendable, CustomTestStringConvertible {
        let json: String?
        let expected: Int

        var testDescription: String {
            "\(json ?? "no settings") -> \(expected)"
        }
    }

    @Test(
        "The unredeemed slot cap is read from remote config, falling back to the default",
        arguments: [
            MaxUnredeemedSlotsScenario(json: "{\"maxUnredeemedSlots\": 5}", expected: 5),
            // Zero is preserved rather than defaulted: it is how the cap is switched off.
            MaxUnredeemedSlotsScenario(json: "{\"maxUnredeemedSlots\": 0}", expected: 0),
            MaxUnredeemedSlotsScenario(json: nil, expected: 3),
            MaxUnredeemedSlotsScenario(json: "{}", expected: 3),
            MaxUnredeemedSlotsScenario(json: "not json", expected: 3),
            MaxUnredeemedSlotsScenario(json: "{\"maxUnredeemedSlots\": \"5\"}", expected: 3),
        ]
    )
    func maxUnredeemedSlots(_ scenario: MaxUnredeemedSlotsScenario) {
        let policy = makePolicy(enabledFlags: [], json: scenario.json)

        #expect(policy.maxUnredeemedSlots == scenario.expected)
    }

    private func makePolicy(
        enabledFlags: [FeatureFlag],
        json: String? = nil
    ) -> AppRatingPromptCoordinationPolicying {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = enabledFlags

        let config = MockPrivacyConfiguration()
        config.subfeatureSettings = json
        let privacyConfigurationManager = MockPrivacyConfigurationManager()
        privacyConfigurationManager.privacyConfig = config

        return AppRatingPromptCoordinationPolicy(
            featureFlagger: featureFlagger,
            privacyConfigurationManager: privacyConfigurationManager
        )
    }
}
