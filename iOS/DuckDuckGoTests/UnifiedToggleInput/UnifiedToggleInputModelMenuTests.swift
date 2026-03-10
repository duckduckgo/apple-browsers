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

    private let freeModel = AIChatModel(id: "gpt-4o-mini", name: "GPT-4o mini", provider: .openAI, supportsImageUpload: false, entityHasAccess: true)
    private let freeModel2 = AIChatModel(id: "claude-3-haiku", name: "Claude 3 Haiku", provider: .anthropic, supportsImageUpload: false, entityHasAccess: true)
    private let premiumModel = AIChatModel(id: "gpt-5", name: "GPT-5", provider: .openAI, supportsImageUpload: true, entityHasAccess: false)
    private let premiumModel2 = AIChatModel(id: "claude-opus", name: "Claude Opus", provider: .anthropic, supportsImageUpload: true, entityHasAccess: false)

    // MARK: - Section Structure

    func test_allAccessible_producesSingleSection() {
        let menu = UnifiedToggleInputModelMenu.build(
            models: [freeModel, freeModel2],
            selectedId: "gpt-4o-mini",
            isBottomAnchored: false,
            advancedSectionTitle: "Advanced"
        )

        XCTAssertEqual(menu.sections.count, 1)
        XCTAssertEqual(menu.sections[0].items.count, 2)
    }

    func test_mixedAccess_producesTwoSections() {
        let menu = UnifiedToggleInputModelMenu.build(
            models: [freeModel, premiumModel],
            selectedId: "gpt-4o-mini",
            isBottomAnchored: false,
            advancedSectionTitle: "Advanced"
        )

        XCTAssertEqual(menu.sections.count, 2)
    }

    func test_allPremium_producesTwoSections() {
        let menu = UnifiedToggleInputModelMenu.build(
            models: [premiumModel, premiumModel2],
            selectedId: "",
            isBottomAnchored: false,
            advancedSectionTitle: "Advanced"
        )

        XCTAssertEqual(menu.sections.count, 2)
        XCTAssertTrue(menu.sections[0].items.isEmpty)
        XCTAssertEqual(menu.sections[1].items.count, 2)
    }

    // MARK: - Section Ordering

    func test_topAnchored_accessibleSectionFirst() {
        let menu = UnifiedToggleInputModelMenu.build(
            models: [freeModel, premiumModel],
            selectedId: "gpt-4o-mini",
            isBottomAnchored: false,
            advancedSectionTitle: "Advanced"
        )

        XCTAssertEqual(menu.sections[0].title, "")
        XCTAssertEqual(menu.sections[0].items[0].modelId, "gpt-4o-mini")
        XCTAssertEqual(menu.sections[1].title, "Advanced")
        XCTAssertEqual(menu.sections[1].items[0].modelId, "gpt-5")
    }

    func test_bottomAnchored_reversesSectionOrder() {
        let menu = UnifiedToggleInputModelMenu.build(
            models: [freeModel, premiumModel],
            selectedId: "gpt-4o-mini",
            isBottomAnchored: true,
            advancedSectionTitle: "Advanced"
        )

        XCTAssertEqual(menu.sections[0].title, "Advanced")
        XCTAssertEqual(menu.sections[0].items[0].modelId, "gpt-5")
        XCTAssertEqual(menu.sections[1].title, "")
        XCTAssertEqual(menu.sections[1].items[0].modelId, "gpt-4o-mini")
    }

    // MARK: - Item Properties

    func test_accessibleItems_areNotDisabled() {
        let menu = UnifiedToggleInputModelMenu.build(
            models: [freeModel],
            selectedId: "",
            isBottomAnchored: false,
            advancedSectionTitle: "Advanced"
        )

        XCTAssertFalse(menu.sections[0].items[0].isDisabled)
    }

    func test_premiumItems_areDisabled() {
        let menu = UnifiedToggleInputModelMenu.build(
            models: [premiumModel],
            selectedId: "",
            isBottomAnchored: false,
            advancedSectionTitle: "Advanced"
        )

        XCTAssertTrue(menu.sections[1].items[0].isDisabled)
    }

    func test_selectedModel_hasIsSelectedTrue() {
        let menu = UnifiedToggleInputModelMenu.build(
            models: [freeModel, freeModel2],
            selectedId: "claude-3-haiku",
            isBottomAnchored: false,
            advancedSectionTitle: "Advanced"
        )

        XCTAssertFalse(menu.sections[0].items[0].isSelected)
        XCTAssertTrue(menu.sections[0].items[1].isSelected)
    }

    func test_noMatchingSelection_allDeselected() {
        let menu = UnifiedToggleInputModelMenu.build(
            models: [freeModel, freeModel2],
            selectedId: "nonexistent",
            isBottomAnchored: false,
            advancedSectionTitle: "Advanced"
        )

        XCTAssertTrue(menu.sections[0].items.allSatisfy { !$0.isSelected })
    }

    // MARK: - Item Metadata

    func test_itemPreservesModelMetadata() {
        let menu = UnifiedToggleInputModelMenu.build(
            models: [freeModel],
            selectedId: "",
            isBottomAnchored: false,
            advancedSectionTitle: "Advanced"
        )

        let item = menu.sections[0].items[0]
        XCTAssertEqual(item.modelId, "gpt-4o-mini")
        XCTAssertEqual(item.name, "GPT-4o mini")
        XCTAssertEqual(item.provider, .openAI)
    }

    // MARK: - Ordering Preserves Model Order

    func test_itemOrderMatchesInputOrder() {
        let menu = UnifiedToggleInputModelMenu.build(
            models: [freeModel2, freeModel],
            selectedId: "",
            isBottomAnchored: false,
            advancedSectionTitle: "Advanced"
        )

        XCTAssertEqual(menu.sections[0].items[0].modelId, "claude-3-haiku")
        XCTAssertEqual(menu.sections[0].items[1].modelId, "gpt-4o-mini")
    }

    // MARK: - Empty Models

    func test_emptyModels_producesSingleEmptySection() {
        let menu = UnifiedToggleInputModelMenu.build(
            models: [],
            selectedId: "",
            isBottomAnchored: false,
            advancedSectionTitle: "Advanced"
        )

        XCTAssertEqual(menu.sections.count, 1)
        XCTAssertTrue(menu.sections[0].items.isEmpty)
    }

    // MARK: - Advanced Section Title

    func test_advancedSectionUsesProvidedTitle() {
        let menu = UnifiedToggleInputModelMenu.build(
            models: [freeModel, premiumModel],
            selectedId: "",
            isBottomAnchored: false,
            advancedSectionTitle: "Premium Models"
        )

        XCTAssertEqual(menu.sections[1].title, "Premium Models")
    }
}
