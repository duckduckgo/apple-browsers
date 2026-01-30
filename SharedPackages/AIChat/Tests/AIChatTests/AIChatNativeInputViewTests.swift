//
//  AIChatNativeInputViewTests.swift
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

final class AIChatNativeInputViewTests: XCTestCase {

    // MARK: - Mock Delegate

    private final class MockDelegate: AIChatNativeInputViewDelegate {
        var didChangeTextCalls: [String] = []
        var didTapSubmitCalls: [String] = []
        var didTapVoiceCount = 0
        var didTapClearCount = 0
        var didRemoveContextChipCount = 0

        func nativeInputViewDidChangeText(_ view: AIChatNativeInputView, text: String) {
            didChangeTextCalls.append(text)
        }

        func nativeInputViewDidTapSubmit(_ view: AIChatNativeInputView, text: String) {
            didTapSubmitCalls.append(text)
        }

        func nativeInputViewDidTapVoice(_ view: AIChatNativeInputView) {
            didTapVoiceCount += 1
        }

        func nativeInputViewDidTapClear(_ view: AIChatNativeInputView) {
            didTapClearCount += 1
        }

        func nativeInputViewDidRemoveContextChip(_ view: AIChatNativeInputView) {
            didRemoveContextChipCount += 1
        }

        func nativeInputViewNeedsLayout(_ view: AIChatNativeInputView) {
            // No-op for tests
        }
    }

    // MARK: - Properties

    private var sut: AIChatNativeInputView!
    private var mockDelegate: MockDelegate!

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        sut = AIChatNativeInputView()
        mockDelegate = MockDelegate()
        sut.delegate = mockDelegate
    }

    override func tearDown() {
        sut = nil
        mockDelegate = nil
        super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialTextIsEmpty() {
        XCTAssertEqual(sut.text, "")
    }

    func testInitialPlaceholderIsEmpty() {
        XCTAssertEqual(sut.placeholder, "")
    }

    func testVoiceButtonEnabledByDefault() {
        XCTAssertTrue(sut.isVoiceButtonEnabled)
    }

    // MARK: - Text Property Tests

    func testSettingTextUpdatesValue() {
        // When
        sut.text = "Hello"

        // Then
        XCTAssertEqual(sut.text, "Hello")
    }

    func testSettingTextToEmptyWorks() {
        // Given
        sut.text = "Hello"

        // When
        sut.text = ""

        // Then
        XCTAssertEqual(sut.text, "")
    }

    // MARK: - Placeholder Tests

    func testSettingPlaceholderUpdatesValue() {
        // When
        sut.placeholder = "Ask privately..."

        // Then
        XCTAssertEqual(sut.placeholder, "Ask privately...")
    }

    // MARK: - Voice Button State Tests

    func testDisablingVoiceButtonUpdatesState() {
        // When
        sut.isVoiceButtonEnabled = false

        // Then
        XCTAssertFalse(sut.isVoiceButtonEnabled)
    }

    // MARK: - Context Chip Tests

    func testContextChipNotVisibleInitially() {
        XCTAssertFalse(sut.isContextChipVisible)
    }

    func testShowContextChipSetsVisibility() {
        // Given
        let chipView = UIView()

        // When
        sut.showContextChip(chipView)

        // Then
        XCTAssertTrue(sut.isContextChipVisible)
    }

    func testHideContextChipClearsVisibility() {
        // Given
        let chipView = UIView()
        sut.showContextChip(chipView)

        // When
        sut.hideContextChip()

        // Then
        XCTAssertFalse(sut.isContextChipVisible)
    }

    func testHideContextChipNotifiesDelegate() {
        // Given
        let chipView = UIView()
        sut.showContextChip(chipView)

        // When
        sut.hideContextChip()

        // Then
        XCTAssertEqual(mockDelegate.didRemoveContextChipCount, 1)
    }

    func testShowContextChipTwiceDoesNotDuplicate() {
        // Given
        let chipView1 = UIView()
        let chipView2 = UIView()
        sut.showContextChip(chipView1)

        // When
        sut.showContextChip(chipView2)

        // Then - second show is ignored while first is visible
        XCTAssertTrue(sut.isContextChipVisible)
    }
}
#endif
