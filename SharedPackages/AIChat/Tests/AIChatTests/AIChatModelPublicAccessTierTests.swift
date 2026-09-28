//
//  AIChatModelPublicAccessTierTests.swift
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
import XCTest

final class AIChatModelPublicAccessTierTests: XCTestCase {

    // MARK: - lowestPublicAccessTier

    func testWhenAccessTierContainsFree_ThenLowestPublicAccessTierIsFree() {
        let model = makeModel(accessTier: ["free", "plus", "pro"])

        XCTAssertEqual(model.lowestPublicAccessTier, .free)
    }

    func testWhenAccessTierContainsOnlyPlusAndPro_ThenLowestPublicAccessTierIsPlus() {
        let model = makeModel(accessTier: ["plus", "pro"])

        XCTAssertEqual(model.lowestPublicAccessTier, .plus)
    }

    func testWhenAccessTierContainsOnlyPro_ThenLowestPublicAccessTierIsPro() {
        let model = makeModel(accessTier: ["pro"])

        XCTAssertEqual(model.lowestPublicAccessTier, .pro)
    }

    func testWhenAccessTierContainsOnlyInternal_ThenLowestPublicAccessTierIsNil() {
        // "internal" isn't a publicly-marketed tier — a model gated to only internal testers
        // has no public tier to badge/upsell against.
        let model = makeModel(accessTier: ["internal"])

        XCTAssertNil(model.lowestPublicAccessTier)
    }

    func testWhenAccessTierIsEmpty_ThenLowestPublicAccessTierIsNil() {
        let model = makeModel(accessTier: [])

        XCTAssertNil(model.lowestPublicAccessTier)
    }

    // MARK: - lowestPublicAccessTier(for effort:)

    func testWhenEffortIsAccessible_ThenLowestPublicAccessTierForEffortIsNil() {
        let model = makeModel(
            accessTier: ["free", "plus", "pro"],
            supportedReasoningEffort: [.none],
            reasoningEffortAccess: [
                AIChatReasoningEffortAccess(effort: .none, accessTier: ["free", "plus", "pro"], entityHasAccess: true)
            ]
        )

        XCTAssertNil(model.lowestPublicAccessTier(for: .none))
    }

    func testWhenEffortIsGatedToPlusAndPro_ThenLowestPublicAccessTierForEffortIsPlus() {
        let model = makeModel(
            accessTier: ["free", "plus", "pro"],
            supportedReasoningEffort: [.medium],
            reasoningEffortAccess: [
                AIChatReasoningEffortAccess(effort: .medium, accessTier: ["plus", "pro"], entityHasAccess: false)
            ]
        )

        XCTAssertEqual(model.lowestPublicAccessTier(for: .medium), .plus)
    }

    func testWhenEffortIsGatedToProOnly_ThenLowestPublicAccessTierForEffortIsPro() {
        let model = makeModel(
            accessTier: ["free", "plus", "pro"],
            supportedReasoningEffort: [.medium],
            reasoningEffortAccess: [
                AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro"], entityHasAccess: false)
            ]
        )

        XCTAssertEqual(model.lowestPublicAccessTier(for: .medium), .pro)
    }

    func testWhenReasoningEffortAccessIsAbsent_ThenLowestPublicAccessTierForEffortIsNil() {
        // Graceful degradation: no per-effort gating metadata means nothing is gated.
        let model = makeModel(accessTier: ["free"], supportedReasoningEffort: [.medium], reasoningEffortAccess: nil)

        XCTAssertNil(model.lowestPublicAccessTier(for: .medium))
    }

    // MARK: - AIChatUserTier.upgradeFlow(for:)

    func testWhenFreeUserRequiresPlus_ThenFlowIsPurchase() {
        XCTAssertEqual(AIChatUserTier.free.upgradeFlow(for: .plus), .purchase)
    }

    func testWhenFreeUserRequiresPro_ThenFlowIsPurchase() {
        XCTAssertEqual(AIChatUserTier.free.upgradeFlow(for: .pro), .purchase)
    }

    func testWhenPlusUserRequiresPro_ThenFlowIsUpgrade() {
        XCTAssertEqual(AIChatUserTier.plus.upgradeFlow(for: .pro), .upgrade)
    }

    func testWhenPlusUserRequiresPlus_ThenFlowIsNone() {
        // Already satisfies the requirement — shouldn't normally be reached by a real caller
        // (they'd have found the selection accessible already), but must resolve to no flow.
        XCTAssertEqual(AIChatUserTier.plus.upgradeFlow(for: .plus), .none)
    }

    func testWhenProUserRequiresAnyTier_ThenFlowIsNone() {
        XCTAssertEqual(AIChatUserTier.pro.upgradeFlow(for: .free), .none)
        XCTAssertEqual(AIChatUserTier.pro.upgradeFlow(for: .plus), .none)
        XCTAssertEqual(AIChatUserTier.pro.upgradeFlow(for: .pro), .none)
    }

    func testWhenInternalUserRequiresAnyTier_ThenFlowIsNone() {
        XCTAssertEqual(AIChatUserTier.internal.upgradeFlow(for: .free), .none)
        XCTAssertEqual(AIChatUserTier.internal.upgradeFlow(for: .plus), .none)
        XCTAssertEqual(AIChatUserTier.internal.upgradeFlow(for: .pro), .none)
    }

    func testWhenFreeUserRequiresFree_ThenFlowIsNone() {
        XCTAssertEqual(AIChatUserTier.free.upgradeFlow(for: .free), .none)
    }
}

private extension AIChatModelPublicAccessTierTests {
    func makeModel(
        accessTier: [String],
        supportedReasoningEffort: [AIChatReasoningEffort] = [],
        reasoningEffortAccess: [AIChatReasoningEffortAccess]? = nil
    ) -> AIChatModel {
        AIChatModel(
            id: "test-model",
            name: "Test Model",
            provider: .openAI,
            supportsImageUpload: false,
            entityHasAccess: true,
            accessTier: accessTier,
            supportedReasoningEffort: supportedReasoningEffort,
            reasoningEffortAccess: reasoningEffortAccess
        )
    }
}
