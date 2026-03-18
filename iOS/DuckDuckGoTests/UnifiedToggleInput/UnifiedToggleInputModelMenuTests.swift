//
//  UnifiedToggleInputModelMenuTests.swift
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

final class UnifiedToggleInputModelMenuTests: XCTestCase {

    private let freeModel = AIChatModel(id: "gpt-4o-mini", name: "GPT-4o mini", provider: .openAI, supportsImageUpload: false, entityHasAccess: true, accessTier: ["free"])
    private let freeModel2 = AIChatModel(id: "claude-3-haiku", name: "Claude 3 Haiku", provider: .anthropic, supportsImageUpload: false, entityHasAccess: true, accessTier: ["free"])
    private let premiumModel = AIChatModel(id: "gpt-5", name: "GPT-5", provider: .openAI, supportsImageUpload: true, entityHasAccess: false, accessTier: ["plus", "pro"])
    private let premiumModel2 = AIChatModel(id: "claude-opus", name: "Claude Opus", provider: .anthropic, supportsImageUpload: true, entityHasAccess: false, accessTier: ["plus", "pro"])

    // MARK: - Free User: Section Structure

    func test_freeUser_allAccessible_producesSingleSection() {
        let menu = buildFreeMenu(models: [freeModel, freeModel2], selectedId: "gpt-4o-mini")

        XCTAssertEqual(menu.sections.count, 1)
        XCTAssertEqual(menu.sections[0].items.count, 2)
    }

    func test_freeUser_mixedAccess_producesTwoSections() {
        let menu = buildFreeMenu(models: [freeModel, premiumModel], selectedId: "gpt-4o-mini")

        XCTAssertEqual(menu.sections.count, 2)
    }

    func test_freeUser_allPremium_producesTwoSections() {
        let menu = buildFreeMenu(models: [premiumModel, premiumModel2], selectedId: "")

        XCTAssertEqual(menu.sections.count, 2)
        XCTAssertTrue(menu.sections[0].items.isEmpty)
        XCTAssertEqual(menu.sections[1].items.count, 2)
    }

    // MARK: - Free User: Section Ordering

    func test_freeUser_topAnchored_accessibleSectionFirst() {
        let menu = buildFreeMenu(models: [freeModel, premiumModel], selectedId: "gpt-4o-mini")

        XCTAssertEqual(menu.sections[0].title, "")
        XCTAssertEqual(menu.sections[0].items[0].modelId, "gpt-4o-mini")
        XCTAssertEqual(menu.sections[1].title, "Advanced")
        XCTAssertEqual(menu.sections[1].items[0].modelId, "gpt-5")
    }

    func test_freeUser_bottomAnchored_reversesSectionOrder() {
        let menu = buildFreeMenu(models: [freeModel, premiumModel], selectedId: "gpt-4o-mini", isBottomAnchored: true)

        XCTAssertEqual(menu.sections[0].title, "Advanced")
        XCTAssertEqual(menu.sections[0].items[0].modelId, "gpt-5")
        XCTAssertEqual(menu.sections[1].title, "")
        XCTAssertEqual(menu.sections[1].items[0].modelId, "gpt-4o-mini")
    }

    // MARK: - Free User: Item Properties

    func test_freeUser_accessibleItems_areNotDisabled() {
        let menu = buildFreeMenu(models: [freeModel], selectedId: "")

        XCTAssertFalse(menu.sections[0].items[0].isDisabled)
    }

    func test_freeUser_premiumItems_areDisabled() {
        let menu = buildFreeMenu(models: [premiumModel], selectedId: "")

        XCTAssertTrue(menu.sections[1].items[0].isDisabled)
    }

    func test_selectedModel_hasIsSelectedTrue() {
        let menu = buildFreeMenu(models: [freeModel, freeModel2], selectedId: "claude-3-haiku")

        XCTAssertFalse(menu.sections[0].items[0].isSelected)
        XCTAssertTrue(menu.sections[0].items[1].isSelected)
    }

    func test_noMatchingSelection_allDeselected() {
        let menu = buildFreeMenu(models: [freeModel, freeModel2], selectedId: "nonexistent")

        XCTAssertTrue(menu.sections[0].items.allSatisfy { !$0.isSelected })
    }

    // MARK: - Item Metadata

    func test_itemPreservesModelMetadata() {
        let menu = buildFreeMenu(models: [freeModel], selectedId: "")

        let item = menu.sections[0].items[0]
        XCTAssertEqual(item.modelId, "gpt-4o-mini")
        XCTAssertEqual(item.name, "GPT-4o mini")
        XCTAssertEqual(item.provider, .openAI)
    }

    // MARK: - Ordering Preserves Model Order

    func test_itemOrderMatchesInputOrder() {
        let menu = buildFreeMenu(models: [freeModel2, freeModel], selectedId: "")

        XCTAssertEqual(menu.sections[0].items[0].modelId, "claude-3-haiku")
        XCTAssertEqual(menu.sections[0].items[1].modelId, "gpt-4o-mini")
    }

    // MARK: - Empty Models

    func test_emptyModels_producesSingleEmptySection() {
        let menu = buildFreeMenu(models: [], selectedId: "")

        XCTAssertEqual(menu.sections.count, 1)
        XCTAssertTrue(menu.sections[0].items.isEmpty)
    }

    // MARK: - Advanced Section Title

    func test_advancedSectionUsesProvidedTitle() {
        let menu = UnifiedToggleInputModelMenu.build(
            models: [freeModel, premiumModel],
            selectedId: "",
            isBottomAnchored: false,
            hasActiveSubscription: false,
            advancedSectionTitle: "Premium Models",
            basicSectionTitle: "Basic"
        )

        XCTAssertEqual(menu.sections[1].title, "Premium Models")
    }

    // MARK: - Subscribed User: Section Layout

    func test_subscribedUser_splitsIntoAdvancedAndBasicSections() {
        let subscribedPremium = AIChatModel(id: "gpt-5", name: "GPT-5", provider: .openAI, supportsImageUpload: true, entityHasAccess: true, accessTier: ["plus", "pro"])
        let menu = buildSubscribedMenu(models: [subscribedPremium, freeModel], selectedId: "gpt-5")

        XCTAssertEqual(menu.sections.count, 2)
        XCTAssertEqual(menu.sections[0].title, "Advanced")
        XCTAssertEqual(menu.sections[0].items[0].modelId, "gpt-5")
        XCTAssertEqual(menu.sections[1].title, "Basic")
        XCTAssertEqual(menu.sections[1].items[0].modelId, "gpt-4o-mini")
    }

    func test_subscribedUser_allAccessibleItems_enabled() {
        let subscribedPremium = AIChatModel(id: "gpt-5", name: "GPT-5", provider: .openAI, supportsImageUpload: true, entityHasAccess: true, accessTier: ["plus", "pro"])
        let menu = buildSubscribedMenu(models: [subscribedPremium, freeModel], selectedId: "gpt-5")

        XCTAssertTrue(menu.sections.flatMap(\.items).allSatisfy { !$0.isDisabled })
    }

    func test_subscribedUser_bottomAnchored_reversesSections() {
        let subscribedPremium = AIChatModel(id: "gpt-5", name: "GPT-5", provider: .openAI, supportsImageUpload: true, entityHasAccess: true, accessTier: ["plus", "pro"])
        let menu = buildSubscribedMenu(models: [subscribedPremium, freeModel], selectedId: "gpt-5", isBottomAnchored: true)

        XCTAssertEqual(menu.sections[0].title, "Basic")
        XCTAssertEqual(menu.sections[1].title, "Advanced")
    }

    func test_subscribedUser_allBasicModels_singleSection() {
        let menu = buildSubscribedMenu(models: [freeModel, freeModel2], selectedId: "gpt-4o-mini")

        XCTAssertEqual(menu.sections.count, 1)
        XCTAssertEqual(menu.sections[0].title, "Basic")
    }

    func test_subscribedUser_allAdvancedModels_singleSection() {
        let subscribedPremium = AIChatModel(id: "gpt-5", name: "GPT-5", provider: .openAI, supportsImageUpload: true, entityHasAccess: true, accessTier: ["plus", "pro"])
        let subscribedPremium2 = AIChatModel(id: "claude-opus", name: "Claude Opus", provider: .anthropic, supportsImageUpload: true, entityHasAccess: true, accessTier: ["plus", "pro"])
        let menu = buildSubscribedMenu(models: [subscribedPremium, subscribedPremium2], selectedId: "gpt-5")

        XCTAssertEqual(menu.sections.count, 1)
        XCTAssertEqual(menu.sections[0].title, "Advanced")
    }

    func test_subscribedUser_advancedSectionUsesCorrectTitle() {
        let subscribedPremium = AIChatModel(id: "gpt-5", name: "GPT-5", provider: .openAI, supportsImageUpload: true, entityHasAccess: true, accessTier: ["plus", "pro"])
        let menu = buildSubscribedMenu(models: [subscribedPremium, freeModel], selectedId: "gpt-5")

        XCTAssertEqual(menu.sections[0].title, "Advanced")
        XCTAssertNotEqual(menu.sections[0].title, "Advanced Models - DuckDuckGo subscription")
    }

    func test_subscribedUser_proOnlyModel_disabledForPlusUser() {
        let proOnly = AIChatModel(id: "gpt-5-ultra", name: "GPT-5 Ultra", provider: .openAI, supportsImageUpload: true, entityHasAccess: false, accessTier: ["pro"])
        let menu = buildSubscribedMenu(models: [proOnly, freeModel], selectedId: "gpt-4o-mini")

        let advancedSection = menu.sections.first(where: { $0.title == "Advanced" })!
        XCTAssertTrue(advancedSection.items[0].isDisabled)
    }

    // MARK: - Helpers

    private func buildFreeMenu(models: [AIChatModel], selectedId: String, isBottomAnchored: Bool = false) -> UnifiedToggleInputModelMenu {
        UnifiedToggleInputModelMenu.build(
            models: models,
            selectedId: selectedId,
            isBottomAnchored: isBottomAnchored,
            hasActiveSubscription: false,
            advancedSectionTitle: "Advanced",
            basicSectionTitle: "Basic"
        )
    }

    private func buildSubscribedMenu(models: [AIChatModel], selectedId: String, isBottomAnchored: Bool = false) -> UnifiedToggleInputModelMenu {
        UnifiedToggleInputModelMenu.build(
            models: models,
            selectedId: selectedId,
            isBottomAnchored: isBottomAnchored,
            hasActiveSubscription: true,
            advancedSectionTitle: "Advanced",
            basicSectionTitle: "Basic"
        )
    }
}
