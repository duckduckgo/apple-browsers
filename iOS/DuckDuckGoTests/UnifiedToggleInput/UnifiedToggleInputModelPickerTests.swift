//
//  UnifiedToggleInputModelPickerTests.swift
//  DuckDuckGoTests
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

final class UnifiedToggleInputModelPickerTests: XCTestCase {

    func testWhenModelsHaveMixedAccessThenContentGroupsThemByCurrentAccess() {
        let content = makeContent(models: [
            makeModel(id: "free", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "plus", entityHasAccess: false, accessTier: ["plus", "pro"]),
            makeModel(id: "pro", entityHasAccess: false, accessTier: ["pro"]),
        ])

        XCTAssertEqual(content.availableItems.map(\.id), ["free"])
        XCTAssertEqual(content.gatedItems.map(\.id), ["plus", "pro"])
    }

    func testWhenAvailableModelsHaveRecommendationLabelsThenContentGroupsThemInBackendOrder() {
        let content = makeContent(models: [
            makeModel(id: "without-1", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "with-1", entityHasAccess: true, accessTier: ["free"], label: .everydayUse),
            makeModel(id: "unknown", entityHasAccess: true, accessTier: ["free"], label: .unknown("FUTURE_LABEL")),
            makeModel(id: "without-2", entityHasAccess: true, accessTier: ["free"]),
        ])

        XCTAssertEqual(content.itemsWithRecommendationLabel.map(\.id), ["with-1", "unknown"])
        XCTAssertEqual(content.itemsWithoutRecommendationLabel.map(\.id), ["without-1", "without-2"])
        XCTAssertEqual(content.availableItems.map(\.id), ["with-1", "unknown", "without-1", "without-2"])
        XCTAssertNil(content.itemsWithRecommendationLabel.last?.subtitle)
    }

    func testWhenAvailableModelsHaveAndDoNotHaveRecommendationLabelsThenContentShowsSeparatorForEveryUserTier() {
        let models = [
            makeModel(id: "with", entityHasAccess: true, accessTier: ["free", "plus", "pro", "internal"], label: .everydayUse),
            makeModel(id: "without", entityHasAccess: true, accessTier: ["free", "plus", "pro", "internal"]),
        ]

        for userTier in [AIChatUserTier.free, .plus, .pro, .internal] {
            XCTAssertTrue(makeContent(models: models, userTier: userTier).showsAvailableItemsSeparator)
        }
    }

    func testWhenOnlyOneAvailableGroupExistsThenContentDoesNotShowAvailableSeparator() {
        let onlyLabeled = makeContent(models: [
            makeModel(id: "with", entityHasAccess: true, accessTier: ["free"], label: .everydayUse),
        ])
        let onlyUnlabeled = makeContent(models: [
            makeModel(id: "without", entityHasAccess: true, accessTier: ["free"]),
        ])

        XCTAssertFalse(onlyLabeled.showsAvailableItemsSeparator)
        XCTAssertFalse(onlyUnlabeled.showsAvailableItemsSeparator)
    }

    func testWhenAvailableModelHasLabelThenContentIncludesLocalizedSubtitle() {
        let content = makeContent(models: [
            makeModel(
                id: "free",
                entityHasAccess: true,
                accessTier: ["free"],
                label: .everydayUse
            ),
        ])

        XCTAssertEqual(content.availableItems.first?.subtitle, AIChatModelLabel.everydayUse.localizedText)
    }

    func testModelNameSeparatesEmphasizedFirstComponentFromRemainingName() {
        let content = makeContent(models: [
            makeModel(
                id: "claude-haiku",
                name: "Claude Haiku 4.5",
                entityHasAccess: true,
                accessTier: ["free"]
            ),
        ])

        XCTAssertEqual(content.availableItems.first?.emphasizedName, "Claude")
        XCTAssertEqual(content.availableItems.first?.remainingName, " Haiku 4.5")
    }

    func testSingleComponentModelNameIsFullyEmphasized() {
        let content = makeContent(models: [
            makeModel(id: "gpt-5", name: "GPT-5", entityHasAccess: true, accessTier: ["free"]),
        ])

        XCTAssertEqual(content.availableItems.first?.emphasizedName, "GPT-5")
        XCTAssertEqual(content.availableItems.first?.remainingName, "")
    }

    func testWhenGatedModelHasLabelThenContentDoesNotIncludeSubtitle() {
        let content = makeContent(models: [
            makeModel(
                id: "plus",
                name: "Claude Sonnet 4.6",
                entityHasAccess: false,
                accessTier: ["plus"],
                label: .usesLimitsFaster
            ),
        ])

        XCTAssertNil(content.gatedItems.first?.subtitle)
        XCTAssertEqual(content.gatedItems.first?.emphasizedName, "Claude")
        XCTAssertEqual(content.gatedItems.first?.remainingName, " Sonnet 4.6")
    }

    func testWhenGatedModelsHaveLabelsThenContentKeepsBackendOrderAndDoesNotIncludeThemInAvailableGroups() {
        let content = makeContent(models: [
            makeModel(id: "gated-without", entityHasAccess: false, accessTier: ["plus"]),
            makeModel(id: "gated-with", entityHasAccess: false, accessTier: ["plus"], label: .everydayUse),
        ])

        XCTAssertEqual(content.gatedItems.map(\.id), ["gated-without", "gated-with"])
        XCTAssertTrue(content.itemsWithRecommendationLabel.isEmpty)
        XCTAssertTrue(content.itemsWithoutRecommendationLabel.isEmpty)
        XCTAssertTrue(content.gatedItems.allSatisfy { $0.subtitle == nil })
    }

    func testWhenGatedModelRequiresPlusThenContentUsesPlusBadge() {
        let content = makeContent(models: [
            makeModel(id: "plus", entityHasAccess: false, accessTier: ["plus", "pro"]),
        ])

        XCTAssertEqual(content.gatedItems.first?.requiredTierBadgeText, UserText.aiChatPlusModelsSectionHeader.uppercased())
    }

    func testWhenGatedModelRequiresProThenContentUsesProBadge() {
        let content = makeContent(models: [
            makeModel(id: "pro", entityHasAccess: false, accessTier: ["pro"]),
        ])

        XCTAssertEqual(content.gatedItems.first?.requiredTierBadgeText, UserText.aiChatProModelsSectionHeader.uppercased())
    }

    func testWhenModelIsAccessibleThenContentDoesNotIncludeRequiredTierBadge() {
        let content = makeContent(models: [
            makeModel(id: "plus", entityHasAccess: true, accessTier: ["plus"]),
        ], userTier: .plus)

        XCTAssertNil(content.availableItems.first?.requiredTierBadgeText)
    }

    func testWhenFreeUserHasGatedModelsThenContentUsesTryFreeTitle() {
        let content = makeContent(models: [
            makeModel(id: "plus", entityHasAccess: false, accessTier: ["plus"]),
        ], userTier: .free)

        XCTAssertEqual(content.gatedSectionTitle, UserText.aiChatModelPickerTryFree)
    }

    func testWhenPlusUserHasGatedModelsThenContentUsesAvailableWithProTitle() {
        let content = makeContent(models: [
            makeModel(id: "pro", entityHasAccess: false, accessTier: ["pro"]),
        ], userTier: .plus)

        XCTAssertEqual(content.gatedSectionTitle, UserText.aiChatModelPickerAvailableWithPro)
    }

    func testPreferredHeightUsesRowKindsAndGatedSectionChrome() {
        let content = makeContent(models: [
            makeModel(id: "standard", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "subtitle", entityHasAccess: true, accessTier: ["free"], label: .everydayUse),
            makeModel(id: "gated", entityHasAccess: false, accessTier: ["plus"]),
        ])

        XCTAssertEqual(content.preferredHeight, 237)
    }

    func testPreferredHeightIncludesAvailableSeparatorForProUser() {
        let content = makeContent(models: [
            makeModel(id: "with", entityHasAccess: true, accessTier: ["pro"], label: .everydayUse),
            makeModel(id: "without", entityHasAccess: true, accessTier: ["pro"]),
        ], userTier: .pro)

        XCTAssertEqual(content.preferredHeight, 141)
    }

    private func makeContent(
        models: [AIChatModel],
        selectedModelID: String? = nil,
        userTier: AIChatUserTier = .free
    ) -> UnifiedToggleInputModelPickerContent {
        UnifiedToggleInputModelPickerContent(
            models: models,
            selectedModelID: selectedModelID,
            userTier: userTier
        )
    }

    private func makeModel(
        id: String,
        name: String? = nil,
        entityHasAccess: Bool,
        accessTier: [String],
        label: AIChatModelLabel? = nil
    ) -> AIChatModel {
        AIChatModel(
            id: id,
            name: name ?? id,
            provider: .openAI,
            supportsImageUpload: false,
            entityHasAccess: entityHasAccess,
            accessTier: accessTier,
            label: label
        )
    }
}
