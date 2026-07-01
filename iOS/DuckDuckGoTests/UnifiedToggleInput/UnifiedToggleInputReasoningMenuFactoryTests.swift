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
        sut = UnifiedToggleInputReasoningMenuFactory()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func testWhenModelDoesNotSupportReasoningPickerThenMenuIsNil() {
        let model = makeReasoningModel(id: "gpt-oss", supportedReasoningEffort: [.low])

        let menu = sut.makeMenu(model: model, selectedMode: nil) { _ in }

        XCTAssertNil(menu)
    }

    func testMenuListsAvailableModesInFixedOrder() {
        let model = makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.medium, .low, .none])

        let menu = sut.makeMenu(model: model, selectedMode: nil) { _ in }

        let titles = menu?.children.compactMap { ($0 as? UIAction)?.title }
        XCTAssertEqual(titles, ["Fast", "Reasoning", "Extended Reasoning"])
    }

    func testMenuUsesSingleSelectionOption() {
        let model = makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])

        let menu = sut.makeMenu(model: model, selectedMode: nil) { _ in }

        XCTAssertTrue(menu?.options.contains(.singleSelection) ?? false)
    }

    func testSelectedModeActionIsMarkedOn() {
        let model = makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])

        let menu = sut.makeMenu(model: model, selectedMode: .reasoning) { _ in }

        let actions = menu?.children.compactMap { $0 as? UIAction }
        let onAction = actions?.first { $0.state == .on }
        XCTAssertEqual(onAction?.title, "Reasoning")
        XCTAssertEqual(actions?.filter { $0.state == .on }.count, 1)
    }

    // MARK: - Helpers

    private func makeReasoningModel(
        id: String,
        supportedReasoningEffort: [AIChatReasoningEffort]
    ) -> AIChatModel {
        AIChatModel(
            id: id,
            name: id,
            shortName: id,
            provider: .openAI,
            supportsImageUpload: false,
            entityHasAccess: true,
            supportedReasoningEffort: supportedReasoningEffort,
            reasoningEffortAccess: nil
        )
    }
}
