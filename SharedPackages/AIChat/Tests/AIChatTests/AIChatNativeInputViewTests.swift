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

    func testSubmitButtonUsesMinimumHitTarget() throws {
        sut.frame = CGRect(x: 0, y: 0, width: 320, height: 160)
        sut.text = "Hello"
        sut.layoutIfNeeded()

        let button = try XCTUnwrap(submitButton())
        let frame = button.convert(button.bounds, to: sut)

        XCTAssertEqual(frame.width, 44, accuracy: 0.5)
        XCTAssertEqual(frame.height, 44, accuracy: 0.5)
    }

    // MARK: - Submit Title Tests

    func testWhenASubmitTitleIsSetThenTheButtonShowsItInsteadOfTheArrow() throws {
        sut.text = "Hello"

        sut.submitButtonTitle = "Ask"

        let button = try XCTUnwrap(submitButton())
        XCTAssertEqual(button.title(for: .normal), "Ask")
        XCTAssertNil(button.image(for: .normal))
        XCTAssertEqual(button.accessibilityLabel, "Ask")
        XCTAssertTrue(button.isEnabled)
    }

    func testWhenASubmitTitleIsSetThenTheButtonWidensToFitIt() throws {
        sut.frame = CGRect(x: 0, y: 0, width: 320, height: 160)
        sut.text = "Hello"

        sut.submitButtonTitle = "Ask"
        sut.layoutIfNeeded()

        let button = try XCTUnwrap(submitButton())
        let titleWidth = try XCTUnwrap(button.titleLabel).intrinsicContentSize.width
        XCTAssertGreaterThan(button.bounds.width, titleWidth)
        XCTAssertLessThanOrEqual(button.convert(button.bounds, to: sut).maxX, sut.bounds.maxX)
    }

    func testWhenTheSubmitTitleIsClearedThenTheArrowReturns() throws {
        let container = makeContainer()
        sut.text = "Hello"
        sut.submitButtonTitle = "Ask"
        container.layoutIfNeeded()

        sut.submitButtonTitle = nil
        container.layoutIfNeeded()

        let button = try XCTUnwrap(submitButton())
        XCTAssertNil(button.title(for: .normal))
        XCTAssertNotNil(button.image(for: .normal))
        XCTAssertEqual(button.bounds.width, 44, accuracy: 0.5)
    }

    /// Only the send button carries the title; Return keeps adding new lines to the prompt.
    func testWhenASubmitTitleIsSetThenReturnStillAddsANewLine() {
        sut.submitButtonTitle = "Ask"
        let textView = textViews(in: sut).first

        let allowsEdit = textView.flatMap { $0.delegate?.textView?($0, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementText: "\n") } ?? true

        XCTAssertTrue(allowsEdit)
        XCTAssertTrue(mockDelegate.didTapSubmitCalls.isEmpty)
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

    // MARK: - Append Text Tests

    func testAppendTextToEmptyField() {
        sut.appendText("Summarize this page")

        XCTAssertEqual(sut.text, "Summarize this page")
        XCTAssertEqual(mockDelegate.didChangeTextCalls.last, "Summarize this page")
    }

    func testAppendTextToExistingText() {
        sut.text = "Hello"

        sut.appendText("Summarize this page")

        XCTAssertEqual(sut.text, "Hello Summarize this page")
        XCTAssertEqual(mockDelegate.didChangeTextCalls.last, "Hello Summarize this page")
    }

    // MARK: - Context Chip Duplicate Tests

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

    private func submitButton() -> UIButton? {
        buttons(in: sut).first { $0.accessibilityIdentifier == "AIChatNativeInputView.submitButton" }
    }

    /// Hosts the view the way a screen does, so a later constraint change is laid out again.
    private func makeContainer() -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 160))
        sut.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sut)
        NSLayoutConstraint.activate([
            sut.topAnchor.constraint(equalTo: container.topAnchor),
            sut.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sut.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        container.layoutIfNeeded()
        return container
    }

    private func textViews(in view: UIView) -> [UITextView] {
        view.subviews.flatMap { subview -> [UITextView] in
            (subview as? UITextView).map { [$0] } ?? textViews(in: subview)
        }
    }

    private func buttons(in view: UIView) -> [UIButton] {
        view.subviews.flatMap { subview -> [UIButton] in
            var matches = buttons(in: subview)
            if let button = subview as? UIButton {
                matches.append(button)
            }
            return matches
        }
    }
}
#endif
