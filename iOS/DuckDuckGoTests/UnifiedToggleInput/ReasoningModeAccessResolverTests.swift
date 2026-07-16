//
//  ReasoningModeAccessResolverTests.swift
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
import XCTest
@testable import DuckDuckGo

final class ReasoningModeAccessResolverTests: XCTestCase {

    private var sut: ReasoningModeAccessResolver!

    override func setUp() {
        super.setUp()
        sut = ReasoningModeAccessResolver()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - requiredPublicTier

    func testWhenModeIsAccessibleThenRequiredPublicTierIsNil() {
        let model = makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])

        XCTAssertNil(sut.requiredPublicTier(for: .reasoning, model: model))
    }

    func testWhenModelDoesNotSupportModeThenRequiredPublicTierIsNil() {
        // Single accessible mode (.fast) — .extendedReasoning has no backing effort.
        let model = makeReasoningModel(id: "gpt-oss", supportedReasoningEffort: [.none])

        XCTAssertNil(sut.requiredPublicTier(for: .extendedReasoning, model: model))
    }

    func testWhenExtendedReasoningEffortGatedForPlusThenRequiredPublicTierIsPro() {
        let model = makeReasoningModel(
            id: "gpt-5.2",
            supportedReasoningEffort: [.none, .low, .medium],
            reasoningEffortAccess: gpt52MediumGatedForPlus()
        )

        XCTAssertEqual(sut.requiredPublicTier(for: .extendedReasoning, model: model), .pro)
    }

    // MARK: - canSelect(modeRequiring:userTier:)

    func testCanSelectFreeTierAlwaysTrue() {
        XCTAssertTrue(sut.canSelect(modeRequiring: .free, userTier: .free))
        XCTAssertTrue(sut.canSelect(modeRequiring: .free, userTier: .plus))
        XCTAssertTrue(sut.canSelect(modeRequiring: .free, userTier: .pro))
        XCTAssertTrue(sut.canSelect(modeRequiring: .free, userTier: .internal))
    }

    func testCanSelectPlusRequiresNonFreeUser() {
        XCTAssertFalse(sut.canSelect(modeRequiring: .plus, userTier: .free))
        XCTAssertTrue(sut.canSelect(modeRequiring: .plus, userTier: .plus))
        XCTAssertTrue(sut.canSelect(modeRequiring: .plus, userTier: .pro))
        XCTAssertTrue(sut.canSelect(modeRequiring: .plus, userTier: .internal))
    }

    func testCanSelectProRequiresProOrInternal() {
        XCTAssertFalse(sut.canSelect(modeRequiring: .pro, userTier: .free))
        XCTAssertFalse(sut.canSelect(modeRequiring: .pro, userTier: .plus))
        XCTAssertTrue(sut.canSelect(modeRequiring: .pro, userTier: .pro))
        XCTAssertTrue(sut.canSelect(modeRequiring: .pro, userTier: .internal))
    }

    // MARK: - Helpers

    private func makeReasoningModel(
        id: String,
        supportedReasoningEffort: [AIChatReasoningEffort],
        reasoningEffortAccess: [AIChatReasoningEffortAccess]? = nil
    ) -> AIChatModel {
        AIChatModel(
            id: id,
            name: id,
            shortName: id,
            provider: .openAI,
            supportsImageUpload: false,
            entityHasAccess: true,
            supportedReasoningEffort: supportedReasoningEffort,
            reasoningEffortAccess: reasoningEffortAccess
        )
    }

    private func gpt52MediumGatedForPlus() -> [AIChatReasoningEffortAccess] {
        [
            AIChatReasoningEffortAccess(effort: .none, accessTier: ["plus", "pro", "internal"], entityHasAccess: true),
            AIChatReasoningEffortAccess(effort: .low, accessTier: ["plus", "pro", "internal"], entityHasAccess: true),
            AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro", "internal"], entityHasAccess: false)
        ]
    }
}
