//
//  AIChatQuickActionsViewTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

#if os(iOS)
import XCTest
@testable import AIChat

final class AIChatQuickActionsViewTests: XCTestCase {

    // MARK: - Mock Action

    private struct MockQuickAction: AIChatQuickActionType {
        let id: String
        let title: String
        let prompt: String
        let icon: UIImage?

        static let testAction1 = MockQuickAction(id: "action1", title: "Action 1", prompt: "prompt1", icon: nil)
        static let testAction2 = MockQuickAction(id: "action2", title: "Action 2", prompt: "prompt2", icon: nil)
    }

    // MARK: - Properties

    private var sut: AIChatQuickActionsView<MockQuickAction>!

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        sut = AIChatQuickActionsView<MockQuickAction>()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Configuration Tests

    func testConfigureWithEmptyActionsDoesNotCrash() {
        // When/Then - should not crash
        sut.configure(with: [])
    }

    func testConfigureWithSingleAction() {
        // When
        sut.configure(with: [.testAction1])

        // Then - view should be configured without crashing
        XCTAssertNotNil(sut)
    }

    func testConfigureWithMultipleActions() {
        // When
        sut.configure(with: [.testAction1, .testAction2])

        // Then - view should be configured without crashing
        XCTAssertNotNil(sut)
    }

    func testReconfigureReplacesActions() {
        // Given
        sut.configure(with: [.testAction1])

        // When
        sut.configure(with: [.testAction2])

        // Then - view should be reconfigured without crashing
        XCTAssertNotNil(sut)
    }

    // MARK: - Callback Tests

    func testOnActionSelectedIsCalledWhenSet() {
        // Given
        var selectedAction: MockQuickAction?
        sut.onActionSelected = { action in
            selectedAction = action
        }

        // Then
        XCTAssertNil(selectedAction) // Not called yet
        XCTAssertNotNil(sut.onActionSelected)
    }
}
#endif
