//
//  UnifiedToggleInputReasoningMenuFactoryTests.swift
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

@MainActor
final class UnifiedToggleInputReasoningMenuFactoryTests: XCTestCase {

    private var sut: UnifiedToggleInputReasoningMenuFactory!

    override func setUp() {
        super.setUp()
        sut = UnifiedToggleInputReasoningMenuFactory(isUpdatedModelPickerEnabled: false)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func testWhenModelDoesNotSupportReasoningPickerThenMenuIsNil() {
        let model = makeReasoningModel(id: "gpt-oss", supportedReasoningEffort: [.low])

        let menu = sut.makeMenu(model: model, selectedMode: nil, userTier: .free) { _ in }

        XCTAssertNil(menu)
    }

    func testMenuListsAvailableModesInFixedOrder() {
        let model = makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.medium, .low, .none])

        let menu = sut.makeMenu(model: model, selectedMode: nil, userTier: .free) { _ in }

        let titles = menu?.children.compactMap { ($0 as? UIAction)?.title }
        XCTAssertEqual(titles, ["Fast", "Reasoning", "Extended Reasoning"])
    }

    func testMenuUsesSingleSelectionOption() {
        let model = makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])

        let menu = sut.makeMenu(model: model, selectedMode: nil, userTier: .free) { _ in }

        XCTAssertTrue(menu?.options.contains(.singleSelection) ?? false)
    }

    func testSelectedModeActionIsMarkedOn() {
        let model = makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])

        let menu = sut.makeMenu(model: model, selectedMode: .reasoning, userTier: .free) { _ in }

        let actions = menu?.children.compactMap { $0 as? UIAction }
        let onAction = actions?.first { $0.state == .on }
        XCTAssertEqual(onAction?.title, "Reasoning")
        XCTAssertEqual(actions?.filter { $0.state == .on }.count, 1)
    }

    func testWhenUpdatedModelPickerIsEnabledThenMenuGroupsGatedModes() throws {
        sut = UnifiedToggleInputReasoningMenuFactory(isUpdatedModelPickerEnabled: true)
        let model = makeModelWithGatedExtendedReasoning()

        let menu = try XCTUnwrap(sut.makeMenu(
            model: model,
            selectedMode: .fast,
            userTier: .free,
            freeTrialEligibility: .unknown,
            onSelect: { _ in }))
        let availableActions = menu.children.compactMap { $0 as? UIAction }
        let gatedSection = try XCTUnwrap(menu.children.compactMap { $0 as? UIMenu }.first)

        XCTAssertEqual(availableActions.map(\.title), ["Fast", "Reasoning"])
        XCTAssertEqual(gatedSection.title, UserText.aiChatModelPickerTryFree)
        XCTAssertEqual(gatedSection.children.compactMap { ($0 as? UIAction)?.title }, ["Extended Reasoning…"])
    }

    func testWhenUpdatedMenuFreeUserIsIneligibleForTrialThenUsesSubscriberExclusiveTitle() throws {
        sut = UnifiedToggleInputReasoningMenuFactory(isUpdatedModelPickerEnabled: true)
        let model = makeModelWithGatedExtendedReasoning()

        let menu = try XCTUnwrap(sut.makeMenu(
            model: model,
            selectedMode: .fast,
            userTier: .free,
            freeTrialEligibility: .ineligible,
            onSelect: { _ in }))
        let gatedSection = try XCTUnwrap(menu.children.compactMap { $0 as? UIMenu }.first)

        XCTAssertEqual(gatedSection.title, UserText.aiChatModelPickerSubscriberExclusive)
    }

    // MARK: - Helpers

    private func makeModelWithGatedExtendedReasoning() -> AIChatModel {
        makeReasoningModel(
            id: "gpt-5.2",
            supportedReasoningEffort: [.none, .low, .medium],
            reasoningEffortAccess: [
                AIChatReasoningEffortAccess(effort: .none, accessTier: ["free"], entityHasAccess: true),
                AIChatReasoningEffortAccess(effort: .low, accessTier: ["free"], entityHasAccess: true),
                AIChatReasoningEffortAccess(effort: .medium, accessTier: ["plus"], entityHasAccess: false)
            ]
        )
    }

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
}
