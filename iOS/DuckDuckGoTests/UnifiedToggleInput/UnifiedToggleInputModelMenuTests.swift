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
import DesignResourcesKitIcons
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
        let menu = UnifiedToggleInputModelMenuFactory(isUpdatedModelPickerEnabled: false).makeMenu(
            models: [
                makeFakeModel(id: "free-model", accessTier: ["free"], hasAccess: true),
                makeFakeModel(id: "plus-model", accessTier: ["plus"], hasAccess: false),
                makeFakeModel(id: "pro-model", accessTier: ["pro"], hasAccess: false),
            ],
            selectedId: nil,
            userTier: .free,
            onSelect: { _ in }
        )

        XCTAssertTrue(actions(in: menu).allSatisfy { !$0.attributes.contains(.disabled) })
    }

    func testWhenFactoryBuildsLegacyMenuThenUpdatedMenuPresentationIsNotApplied() {
        let menu = UnifiedToggleInputModelMenuFactory(isUpdatedModelPickerEnabled: false).makeMenu(
            models: [
                makeFakeModel(id: "free-model", accessTier: ["free"], hasAccess: true, label: .everydayUse),
                makeFakeModel(id: "plus-model", accessTier: ["plus"], hasAccess: false, label: .everydayUse),
                makeFakeModel(id: "pro-model", accessTier: ["pro"], hasAccess: false),
            ],
            selectedId: nil,
            userTier: .free,
            onSelect: { _ in }
        )

        let sections = menu.children.compactMap { $0 as? UIMenu }
        let menuActions = actions(in: menu)
        XCTAssertEqual(sections.map(\.title), ["", "Plus", "Pro"])
        XCTAssertEqual(menuActions.map(\.title), ["free-model", "plus-model", "pro-model"])
        XCTAssertTrue(menuActions.allSatisfy { $0.subtitle == nil })
    }

    // MARK: - Updated Menu

    func testWhenUpdatedMenuHasThreeAvailableAndTwoGatedModelsThenGroupsThemByCurrentAccess() {
        let menu = makeUpdatedMenu(models: [
            makeFakeModel(id: "available-1", accessTier: ["free"], hasAccess: true),
            makeFakeModel(id: "gated-1", accessTier: ["plus", "pro"], hasAccess: false),
            makeFakeModel(id: "available-2", accessTier: ["plus"], hasAccess: true),
            makeFakeModel(id: "gated-2", accessTier: ["pro"], hasAccess: false),
            makeFakeModel(id: "available-3", accessTier: ["pro"], hasAccess: true),
        ])

        let gatedSections = menu.children.compactMap { $0 as? UIMenu }
        XCTAssertEqual(availableActions(in: menu).map(\.title), ["available-1", "available-2", "available-3"])
        XCTAssertEqual(gatedSections.count, 1)
        XCTAssertEqual(gatedSections[0].children.compactMap { $0 as? UIAction }.map(\.title), ["gated-1…", "gated-2…"])
    }

    func testWhenUpdatedMenuAvailableModelsHaveRecommendationLabelsThenOrdersThemFirstInBackendOrder() {
        let menu = makeUpdatedMenu(models: [
            makeFakeModel(id: "without-1", accessTier: ["free"], hasAccess: true),
            makeFakeModel(id: "with-1", accessTier: ["free"], hasAccess: true, label: .everydayUse),
            makeFakeModel(id: "unknown", accessTier: ["free"], hasAccess: true, label: .unknown("FUTURE_LABEL")),
            makeFakeModel(id: "without-2", accessTier: ["free"], hasAccess: true),
        ])

        let actions = availableActions(in: menu)
        XCTAssertEqual(actions.map(\.title), ["with-1", "unknown", "without-1", "without-2"])
        XCTAssertEqual(actions.first?.subtitle, AIChatModelLabel.everydayUse.localizedText)
        XCTAssertNil(actions[1].subtitle)
    }

    func testWhenUpdatedMenuGatedModelsHaveLabelsThenKeepsBackendOrderAndOmitsSubtitles() {
        let menu = makeUpdatedMenu(models: [
            makeFakeModel(id: "gated-without", accessTier: ["plus"], hasAccess: false),
            makeFakeModel(id: "gated-with", accessTier: ["plus"], hasAccess: false, label: .everydayUse),
        ])

        let gatedActions = gatedSection(in: menu)?.children.compactMap { $0 as? UIAction } ?? []
        XCTAssertTrue(availableActions(in: menu).isEmpty)
        XCTAssertEqual(gatedActions.map(\.title), ["gated-without…", "gated-with…"])
        XCTAssertTrue(gatedActions.allSatisfy { $0.subtitle == nil })
    }

    func testWhenUpdatedMenuModelIsAccessibleThenDoesNotAddTierBadgeToTitle() {
        let menu = makeUpdatedMenu(
            models: [makeFakeModel(id: "plus", accessTier: ["plus"], hasAccess: true)],
            userTier: .plus
        )

        XCTAssertEqual(availableActions(in: menu).first?.title, "plus")
    }

    func testWhenUpdatedMenuFreeUserHasGatedModelsThenUsesTryFreeTitle() {
        let menu = makeUpdatedMenu(
            models: [makeFakeModel(id: "plus", accessTier: ["plus"], hasAccess: false)],
            userTier: .free
        )

        XCTAssertEqual(gatedSection(in: menu)?.title, UserText.aiChatModelPickerTryFree)
    }

    func testWhenUpdatedMenuPlusUserHasGatedModelsThenUsesAvailableWithProTitle() {
        let menu = makeUpdatedMenu(
            models: [makeFakeModel(id: "pro", accessTier: ["pro"], hasAccess: false)],
            userTier: .plus
        )

        XCTAssertEqual(gatedSection(in: menu)?.title, UserText.aiChatModelPickerAvailableWithPro)
    }

    func testWhenUpdatedMenuAvailableModelsHaveMixedRecommendationLabelsThenDoesNotAddSectionSeparator() {
        let menu = makeUpdatedMenu(models: [
            makeFakeModel(id: "with", accessTier: ["pro"], hasAccess: true, label: .everydayUse),
            makeFakeModel(id: "without", accessTier: ["pro"], hasAccess: true),
        ], userTier: .pro)

        XCTAssertEqual(menu.children.compactMap { $0 as? UIMenu }.count, 0)
        XCTAssertEqual(availableActions(in: menu).map(\.title), ["with", "without"])
    }

    func testWhenUpdatedMenuModelIsSelectedThenItsActionIsOn() {
        let menu = makeUpdatedMenu(
            models: [
                makeFakeModel(id: "selected", accessTier: ["free"], hasAccess: true),
                makeFakeModel(id: "other", accessTier: ["free"], hasAccess: true),
            ],
            selectedId: "selected"
        )

        XCTAssertEqual(availableActions(in: menu).map(\.state), [.on, .off])
        XCTAssertTrue(menu.options.contains(.singleSelection))
    }

    func testWhenUpdatedMenuModelProviderIsUnknownThenUsesOSSIcon() {
        let menu = makeUpdatedMenu(models: [
            makeFakeModel(id: "unknown", provider: .unknown, accessTier: ["free"], hasAccess: true),
        ])

        XCTAssertEqual(
            availableActions(in: menu).first?.image?.pngData(),
            DesignSystemImages.Glyphs.Size16.aiModelOSS.pngData()
        )
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

    private func makeUpdatedMenu(
        models: [AIChatModel],
        selectedId: String? = nil,
        userTier: AIChatUserTier = .free
    ) -> UIMenu {
        UnifiedToggleInputModelMenuFactory(isUpdatedModelPickerEnabled: true).makeMenu(
            models: models,
            selectedId: selectedId,
            userTier: userTier,
            onSelect: { _ in }
        )
    }

    private func availableActions(in menu: UIMenu) -> [UIAction] {
        menu.children.compactMap { $0 as? UIAction }
    }

    private func gatedSection(in menu: UIMenu) -> UIMenu? {
        menu.children.compactMap { $0 as? UIMenu }.first
    }

    private func makeFakeModel(
        id: String,
        name: String? = nil,
        provider: AIChatModel.ModelProvider = .openAI,
        accessTier: [String],
        hasAccess: Bool,
        label: AIChatModelLabel? = nil
    ) -> AIChatModel {
        AIChatModel(
            id: id,
            name: name ?? id,
            provider: provider,
            supportsImageUpload: false,
            entityHasAccess: hasAccess,
            accessTier: accessTier,
            label: label
        )
    }
}
