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

    func testWhenFreeModelsAreBuiltThenExistingRecommendedOrderIsUsed() {
        let content = makeContent(models: [
            makeModel(id: "mistral", name: "Mistral Small", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "mini", name: "GPT-5 mini", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "nano", name: "GPT-5 nano", entityHasAccess: true, accessTier: ["free"]),
        ])

        XCTAssertEqual(content.availableItems.map(\.id), ["nano", "mini", "mistral"])
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
        XCTAssertEqual(content.gatedItems.first?.emphasizedName, "")
        XCTAssertEqual(content.gatedItems.first?.remainingName, "Claude Sonnet 4.6")
    }

    func testWhenFreeUserHasGatedPlusModelThenContentOffersPurchase() {
        let content = makeContent(models: [
            makeModel(id: "plus", entityHasAccess: false, accessTier: ["plus", "pro"]),
        ], userTier: .free)

        XCTAssertEqual(content.callToAction?.title, UserText.aiChatModelPickerTryForFree)
        XCTAssertEqual(content.callToAction?.requiredTier, .plus)
    }

    func testWhenPlusUserHasGatedProModelThenContentOffersUpgrade() {
        let content = makeContent(models: [
            makeModel(id: "pro", entityHasAccess: false, accessTier: ["pro"]),
        ], userTier: .plus)

        XCTAssertEqual(content.callToAction?.title, UserText.aiChatModelPickerUpgrade)
        XCTAssertEqual(content.callToAction?.requiredTier, .pro)
    }

    func testWhenNoSubscriptionChangeCanUnlockGatedModelsThenContentHasNoCallToAction() {
        let content = makeContent(models: [
            makeModel(id: "pro", entityHasAccess: false, accessTier: ["pro"]),
        ], userTier: .pro)

        XCTAssertNil(content.callToAction)
    }

    func testPreferredHeightUsesRowKindsAndGatedSectionChrome() {
        let content = makeContent(models: [
            makeModel(id: "standard", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "subtitle", entityHasAccess: true, accessTier: ["free"], label: .everydayUse),
            makeModel(id: "gated", entityHasAccess: false, accessTier: ["plus"]),
        ])

        XCTAssertEqual(content.preferredHeight, 216)
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
