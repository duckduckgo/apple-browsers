//
//  AIChatModelSectionBuilderTests.swift
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
@testable import AIChat

final class AIChatModelSectionBuilderTests: XCTestCase {

    private let advancedHeader = "Advanced Models"
    private let basicHeader = "Basic Models"

    // MARK: - Free User

    func testWhenFreeUserThenAccessibleModelsInFirstSectionAndPremiumInSecond() {
        let models = [
            makeModel(id: "free-1", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "free-2", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "premium-1", entityHasAccess: false, accessTier: ["plus", "pro"]),
        ]

        let sections = AIChatModelSectionBuilder.buildSections(
            models: models,
            hasActiveSubscription: false,
            advancedSectionHeader: advancedHeader,
            basicSectionHeader: basicHeader
        )

        XCTAssertEqual(sections.count, 2)

        // First section: accessible models, no header
        XCTAssertNil(sections[0].header)
        XCTAssertEqual(sections[0].items.map(\.id), ["free-1", "free-2"])

        // Second section: premium models with header
        XCTAssertEqual(sections[1].header, advancedHeader)
        XCTAssertEqual(sections[1].items.map(\.id), ["premium-1"])
    }

    func testWhenFreeUserHasNoPremiumModelsThenSingleSectionReturned() {
        let models = [
            makeModel(id: "free-1", entityHasAccess: true, accessTier: ["free"]),
        ]

        let sections = AIChatModelSectionBuilder.buildSections(
            models: models,
            hasActiveSubscription: false,
            advancedSectionHeader: advancedHeader,
            basicSectionHeader: basicHeader
        )

        XCTAssertEqual(sections.count, 1)
        XCTAssertNil(sections[0].header)
        XCTAssertEqual(sections[0].items.map(\.id), ["free-1"])
    }

    func testWhenFreeUserHasOnlyPremiumModelsThenSingleSectionWithHeaderReturned() {
        let models = [
            makeModel(id: "premium-1", entityHasAccess: false, accessTier: ["plus"]),
        ]

        let sections = AIChatModelSectionBuilder.buildSections(
            models: models,
            hasActiveSubscription: false,
            advancedSectionHeader: advancedHeader,
            basicSectionHeader: basicHeader
        )

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].header, advancedHeader)
        XCTAssertEqual(sections[0].items.map(\.id), ["premium-1"])
    }

    // MARK: - Subscribed User

    func testWhenSubscribedUserThenAdvancedModelsFirstAndBasicSecond() {
        let models = [
            makeModel(id: "basic-1", entityHasAccess: true, accessTier: ["free", "plus"]),
            makeModel(id: "advanced-1", entityHasAccess: true, accessTier: ["plus", "pro"]),
            makeModel(id: "advanced-2", entityHasAccess: true, accessTier: ["plus"]),
        ]

        let sections = AIChatModelSectionBuilder.buildSections(
            models: models,
            hasActiveSubscription: true,
            advancedSectionHeader: advancedHeader,
            basicSectionHeader: basicHeader
        )

        XCTAssertEqual(sections.count, 2)

        // First section: advanced models, no header
        XCTAssertNil(sections[0].header)
        XCTAssertEqual(sections[0].items.map(\.id), ["advanced-1", "advanced-2"])

        // Second section: basic models with header
        XCTAssertEqual(sections[1].header, basicHeader)
        XCTAssertEqual(sections[1].items.map(\.id), ["basic-1"])
    }

    func testWhenSubscribedPlusUserThenProOnlyModelsAreHidden() {
        let models = [
            makeModel(id: "basic-1", entityHasAccess: true, accessTier: ["free", "plus"]),
            makeModel(id: "plus-model", entityHasAccess: true, accessTier: ["plus", "pro"]),
            makeModel(id: "pro-only", entityHasAccess: false, accessTier: ["pro"]),
        ]

        let sections = AIChatModelSectionBuilder.buildSections(
            models: models,
            hasActiveSubscription: true,
            advancedSectionHeader: advancedHeader,
            basicSectionHeader: basicHeader
        )

        // pro-only model should be hidden entirely
        let allIds = sections.flatMap { $0.items.map(\.id) }
        XCTAssertFalse(allIds.contains("pro-only"))
        XCTAssertTrue(allIds.contains("plus-model"))
        XCTAssertTrue(allIds.contains("basic-1"))
    }

    func testWhenSubscribedUserHasOnlyBasicModelsThenSingleSectionWithHeaderReturned() {
        let models = [
            makeModel(id: "basic-1", entityHasAccess: true, accessTier: ["free", "plus"]),
        ]

        let sections = AIChatModelSectionBuilder.buildSections(
            models: models,
            hasActiveSubscription: true,
            advancedSectionHeader: advancedHeader,
            basicSectionHeader: basicHeader
        )

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].header, basicHeader)
        XCTAssertEqual(sections[0].items.map(\.id), ["basic-1"])
    }

    // MARK: - Edge Cases

    func testWhenModelsAreEmptyThenEmptySectionsReturned() {
        let freeSections = AIChatModelSectionBuilder.buildSections(
            models: [],
            hasActiveSubscription: false,
            advancedSectionHeader: advancedHeader,
            basicSectionHeader: basicHeader
        )
        XCTAssertTrue(freeSections.isEmpty)

        let subscribedSections = AIChatModelSectionBuilder.buildSections(
            models: [],
            hasActiveSubscription: true,
            advancedSectionHeader: advancedHeader,
            basicSectionHeader: basicHeader
        )
        XCTAssertTrue(subscribedSections.isEmpty)
    }

    func testWhenBuildingSectionsThenModelOrderIsPreserved() {
        let models = [
            makeModel(id: "z-model", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "a-model", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "m-model", entityHasAccess: true, accessTier: ["free"]),
        ]

        let sections = AIChatModelSectionBuilder.buildSections(
            models: models,
            hasActiveSubscription: false,
            advancedSectionHeader: advancedHeader,
            basicSectionHeader: basicHeader
        )

        XCTAssertEqual(sections[0].items.map(\.id), ["z-model", "a-model", "m-model"])
    }

    // MARK: - Ordering (PoC recommended-first)

    func testWhenFreeUserThenNanoMiniAndHaikuAreHoistedInThatOrderRestKeepAPIOrder() {
        let models = [
            makeModel(id: "mistral", name: "Mistral Large", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "nano", name: "GPT-5 nano", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "opus", name: "Claude Opus", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "mini", name: "GPT-5 mini", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "haiku", name: "Claude Haiku", entityHasAccess: true, accessTier: ["free"]),
        ]

        let ordered = AIChatModelSectionBuilder.orderedAccessibleModels(models, userTier: .free)

        XCTAssertEqual(ordered.map(\.id), ["nano", "mini", "haiku", "mistral", "opus"])
    }

    func testWhenPlusUserThenFullGPTAndSonnetAreHoistedAndMiniNanoStayInRest() {
        let models = [
            makeModel(id: "gptmini", name: "GPT-5 mini", entityHasAccess: true, accessTier: ["free", "plus"]),
            makeModel(id: "gpt5", name: "GPT-5", entityHasAccess: true, accessTier: ["free", "plus"]),
            makeModel(id: "sonnet", name: "Claude Sonnet", entityHasAccess: true, accessTier: ["free", "plus"]),
            makeModel(id: "opus", name: "Claude Opus", entityHasAccess: true, accessTier: ["free", "plus"]),
            makeModel(id: "gptnano", name: "GPT-5 nano", entityHasAccess: true, accessTier: ["free", "plus"]),
        ]

        let ordered = AIChatModelSectionBuilder.orderedAccessibleModels(models, userTier: .plus)

        // isFullGPT excludes the mini/nano variants, so plain "GPT-5" leads, then Sonnet.
        XCTAssertEqual(ordered.map(\.id), ["gpt5", "sonnet", "gptmini", "opus", "gptnano"])
    }

    func testWhenProUserThenFullGPTAndOpusAreHoisted() {
        let models = [
            makeModel(id: "opus", name: "Claude Opus", entityHasAccess: true, accessTier: ["pro"]),
            makeModel(id: "gpt5", name: "GPT-5", entityHasAccess: true, accessTier: ["pro"]),
            makeModel(id: "sonnet", name: "Claude Sonnet", entityHasAccess: true, accessTier: ["pro"]),
        ]

        let ordered = AIChatModelSectionBuilder.orderedAccessibleModels(models, userTier: .pro)

        XCTAssertEqual(ordered.map(\.id), ["gpt5", "opus", "sonnet"])
    }

    func testWhenInternalUserThenUsesSamePlusMatchers() {
        let models = [
            makeModel(id: "sonnet", name: "Claude Sonnet", entityHasAccess: true, accessTier: ["internal"]),
            makeModel(id: "gpt5", name: "GPT-5", entityHasAccess: true, accessTier: ["internal"]),
        ]

        let ordered = AIChatModelSectionBuilder.orderedAccessibleModels(models, userTier: .`internal`)

        XCTAssertEqual(ordered.map(\.id), ["gpt5", "sonnet"])
    }

    func testWhenNoModelMatchesThenOriginalOrderIsPreserved() {
        let models = [
            makeModel(id: "mistral", name: "Mistral Large", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "cohere", name: "Cohere Command", entityHasAccess: true, accessTier: ["free"]),
        ]

        let ordered = AIChatModelSectionBuilder.orderedAccessibleModels(models, userTier: .free)

        XCTAssertEqual(ordered.map(\.id), ["mistral", "cohere"])
    }

    func testWhenTwoModelsMatchAMatcherThenOnlyTheFirstIsHoisted() {
        let models = [
            makeModel(id: "plain", name: "Plain One", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "nano-a", name: "GPT nano A", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "nano-b", name: "GPT nano B", entityHasAccess: true, accessTier: ["free"]),
        ]

        let ordered = AIChatModelSectionBuilder.orderedAccessibleModels(models, userTier: .free)

        // Only the first nano match is hoisted; the second keeps its place in the remainder.
        XCTAssertEqual(ordered.map(\.id), ["nano-a", "plain", "nano-b"])
    }

    func testWhenModelsAreEmptyThenOrderingReturnsEmpty() {
        XCTAssertTrue(AIChatModelSectionBuilder.orderedAccessibleModels([], userTier: .free).isEmpty)
    }

    // MARK: - Helpers

    private func makeModel(
        id: String,
        name: String? = nil,
        entityHasAccess: Bool,
        accessTier: [String]
    ) -> AIChatModel {
        AIChatModel(
            id: id,
            name: name ?? id,
            shortName: id,
            provider: .openAI,
            supportsImageUpload: false,
            entityHasAccess: entityHasAccess,
            accessTier: accessTier
        )
    }
}
