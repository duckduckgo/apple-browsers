//
//  AIChatQuickActionChipViewTests.swift
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

final class AIChatQuickActionChipViewTests: XCTestCase {

    // MARK: - Mock Action

    private struct MockQuickAction: AIChatQuickActionType {
        let id: String
        let title: String
        let prompt: String
        let icon: UIImage?

        static let testAction = MockQuickAction(id: "test", title: "Test Action", prompt: "test prompt", icon: nil)
        static let testActionWithIcon = MockQuickAction(
            id: "iconTest",
            title: "Icon Test",
            prompt: "icon prompt",
            icon: UIImage(systemName: "star")
        )
    }

    // MARK: - Properties

    private var sut: AIChatQuickActionChipView!

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        sut = AIChatQuickActionChipView()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Configuration Tests

    func testConfigureWithActionWithoutIcon() {
        // When/Then - should not crash
        sut.configure(with: MockQuickAction.testAction)
        XCTAssertNotNil(sut)
    }

    func testConfigureWithActionWithIcon() {
        // When/Then - should not crash
        sut.configure(with: MockQuickAction.testActionWithIcon)
        XCTAssertNotNil(sut)
    }

    func testReconfigureWithDifferentAction() {
        // Given
        sut.configure(with: MockQuickAction.testAction)

        // When/Then - should not crash
        sut.configure(with: MockQuickAction.testActionWithIcon)
        XCTAssertNotNil(sut)
    }

    // MARK: - Callback Tests

    func testOnTapCallbackCanBeSet() {
        // Given
        var tapCount = 0

        // When
        sut.onTap = {
            tapCount += 1
        }

        // Then
        XCTAssertNotNil(sut.onTap)
        XCTAssertEqual(tapCount, 0) // Not called yet
    }

    func testOnTapCallbackIsCalledOnTap() {
        // Given
        var tapCount = 0
        sut.onTap = {
            tapCount += 1
        }

        // When - simulate tap by calling the handler directly
        sut.onTap?()

        // Then
        XCTAssertEqual(tapCount, 1)
    }

    func testMultipleTapsCallCallbackMultipleTimes() {
        // Given
        var tapCount = 0
        sut.onTap = {
            tapCount += 1
        }

        // When
        sut.onTap?()
        sut.onTap?()
        sut.onTap?()

        // Then
        XCTAssertEqual(tapCount, 3)
    }
}
#endif
