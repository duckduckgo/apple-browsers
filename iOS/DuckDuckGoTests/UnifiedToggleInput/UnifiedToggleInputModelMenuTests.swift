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
import UIKit
import XCTest
@testable import DuckDuckGo

final class UnifiedToggleInputModelMenuTests: XCTestCase {

    func testWhenFreeTierModelIsPresentThenItAppearsInHeaderlessFreeSection() {
        let menu = buildMenu(models: [
            makeFakeModel(id: "free-model", accessTier: ["free"], hasAccess: true),
        ])

        XCTAssertEqual(menu.sections.count, 1)
        XCTAssertEqual(menu.sections[0].title, "")
        XCTAssertEqual(menu.sections[0].items.map(\.modelId), ["free-model"])
    }

    func testWhenPlusTierModelIsPresentThenItAppearsUnderPlusSection() {
        let menu = buildMenu(models: [
            makeFakeModel(id: "plus-model", accessTier: ["plus"], hasAccess: false),
        ])

        XCTAssertEqual(menu.sections.count, 1)
        XCTAssertEqual(menu.sections[0].title, "Plus")
        XCTAssertEqual(menu.sections[0].items.map(\.modelId), ["plus-model"])
    }

    func testWhenProTierModelIsPresentThenItAppearsUnderProSection() {
        let menu = buildMenu(models: [
            makeFakeModel(id: "pro-model", accessTier: ["pro"], hasAccess: false),
        ])

        XCTAssertEqual(menu.sections.count, 1)
        XCTAssertEqual(menu.sections[0].title, "Pro")
        XCTAssertEqual(menu.sections[0].items.map(\.modelId), ["pro-model"])
    }

    func testWhenModelsContainMultipleTiersThenTheyUseLowestPublicTier() {
        let menu = buildMenu(models: [
            makeFakeModel(id: "free-plus-model", accessTier: ["free", "plus", "pro"], hasAccess: true),
            makeFakeModel(id: "plus-pro-model", accessTier: ["plus", "pro"], hasAccess: false),
            makeFakeModel(id: "pro-internal-model", accessTier: ["pro", "internal"], hasAccess: false),
        ])

        XCTAssertEqual(menu.sections.map(\.title), ["", "Plus", "Pro"])
        XCTAssertEqual(menu.sections[0].items.map(\.modelId), ["free-plus-model"])
        XCTAssertEqual(menu.sections[1].items.map(\.modelId), ["plus-pro-model"])
        XCTAssertEqual(menu.sections[2].items.map(\.modelId), ["pro-internal-model"])
    }

    func testWhenModelsAreGroupedThenInputOrderIsPreservedWithinEachSection() {
        let firstPlus = makeFakeModel(id: "first-plus", accessTier: ["plus"], hasAccess: false)
        let firstFree = makeFakeModel(id: "first-free", accessTier: ["free"], hasAccess: true)
        let firstPro = makeFakeModel(id: "first-pro", accessTier: ["pro"], hasAccess: false)
        let secondPlus = makeFakeModel(id: "second-plus", accessTier: ["plus"], hasAccess: false)
        let secondFree = makeFakeModel(id: "second-free", accessTier: ["free"], hasAccess: true)

        let menu = buildMenu(models: [firstPlus, firstFree, firstPro, secondPlus, secondFree])

        XCTAssertEqual(menu.sections[0].items.map(\.modelId), ["first-free", "second-free"])
        XCTAssertEqual(menu.sections[1].items.map(\.modelId), ["first-plus", "second-plus"])
        XCTAssertEqual(menu.sections[2].items.map(\.modelId), ["first-pro"])
    }

    func testWhenSelectedModelMatchesThenOnlyThatItemIsSelected() {
        let menu = buildMenu(models: [
            makeFakeModel(id: "free-model", accessTier: ["free"], hasAccess: true),
            makeFakeModel(id: "plus-model", accessTier: ["plus"], hasAccess: false),
        ], selectedId: "plus-model")

        XCTAssertFalse(menu.sections[0].items[0].isSelected)
        XCTAssertTrue(menu.sections[1].items[0].isSelected)
    }

    func testWhenFactoryBuildsMenuThenTierActionsAreNotDisabled() {
        let menu = UnifiedToggleInputModelMenuFactory().makeMenu(
            models: [
                makeFakeModel(id: "free-model", accessTier: ["free"], hasAccess: true),
                makeFakeModel(id: "plus-model", accessTier: ["plus"], hasAccess: false),
                makeFakeModel(id: "pro-model", accessTier: ["pro"], hasAccess: false),
            ],
            selectedId: nil,
            plusSectionTitle: "Plus",
            proSectionTitle: "Pro",
            onSelect: { _ in }
        )

        XCTAssertTrue(actions(in: menu).allSatisfy { !$0.attributes.contains(.disabled) })
    }

    // MARK: - Helpers

    private func buildMenu(models: [AIChatModel], selectedId: String? = nil) -> UnifiedToggleInputModelMenu {
        UnifiedToggleInputModelMenu.build(
            models: models,
            selectedId: selectedId,
            plusSectionTitle: "Plus",
            proSectionTitle: "Pro"
        )
    }

    private func actions(in menu: UIMenu) -> [UIAction] {
        menu.children.compactMap { $0 as? UIMenu }.flatMap { section in
            section.children.compactMap { $0 as? UIAction }
        }
    }

    private func makeFakeModel(id: String, name: String? = nil, accessTier: [String], hasAccess: Bool) -> AIChatModel {
        AIChatModel(
            id: id,
            name: name ?? id,
            provider: .openAI,
            supportsImageUpload: false,
            entityHasAccess: hasAccess,
            accessTier: accessTier
        )
    }
}
