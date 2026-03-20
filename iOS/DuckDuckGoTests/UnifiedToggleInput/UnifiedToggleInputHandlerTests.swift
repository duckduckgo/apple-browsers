//
//  UnifiedToggleInputHandlerTests.swift
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

import Combine
import XCTest

@testable import DuckDuckGo

final class UnifiedToggleInputHandlerTests: XCTestCase {

    private var sut: UnifiedToggleInputHandler!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        sut = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
    }

    override func tearDown() {
        cancellables.removeAll()
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func test_initialState_textIsEmpty() {
        XCTAssertEqual(sut.currentText, "")
    }

    func test_initialState_toggleIsAIChat() {
        XCTAssertEqual(sut.currentToggleState, .aiChat)
    }

    func test_initialState_voiceDisabled_buttonStateIsNoButtons() {
        XCTAssertEqual(sut.buttonState, .noButtons)
    }

    func test_initialState_voiceEnabled_buttonStateIsVoiceOnly() {
        sut = UnifiedToggleInputHandler(isVoiceSearchEnabled: true)
        XCTAssertEqual(sut.buttonState, .voiceOnly)
    }

    func test_initialState_fixedProperties() {
        XCTAssertFalse(sut.isUsingFadeOutAnimation)
        XCTAssertFalse(sut.isTopBarPosition)
        XCTAssertFalse(sut.isUsingExpandedBottomBarHeight)
        XCTAssertFalse(sut.isCurrentTextValidURL)
    }

    // MARK: - updateCurrentText

    func test_updateCurrentText_setsCurrentText() {
        sut.updateCurrentText("hello")
        XCTAssertEqual(sut.currentText, "hello")
    }

    func test_updateCurrentText_nonEmpty_buttonStateIsClearOnly() {
        sut.updateCurrentText("hello")
        XCTAssertEqual(sut.buttonState, .clearOnly)
    }

    func test_updateCurrentText_emptyWithVoiceDisabled_buttonStateIsNoButtons() {
        sut.updateCurrentText("hello")
        sut.updateCurrentText("")
        XCTAssertEqual(sut.buttonState, .noButtons)
    }

    func test_updateCurrentText_emptyWithVoiceEnabled_buttonStateIsVoiceOnly() {
        sut.isVoiceSearchEnabled = true
        sut.updateCurrentText("hello")
        sut.updateCurrentText("")
        XCTAssertEqual(sut.buttonState, .voiceOnly)
    }

    func test_updateCurrentText_publishesChange() {
        let expectation = expectation(description: "currentTextPublisher fires")
        sut.currentTextPublisher
            .dropFirst()
            .sink { text in
                XCTAssertEqual(text, "world")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        sut.updateCurrentText("world")
        waitForExpectations(timeout: 1)
    }

    // MARK: - clearText

    func test_clearText_emptiesCurrentText() {
        sut.updateCurrentText("hello")
        sut.clearText()
        XCTAssertEqual(sut.currentText, "")
    }

    func test_clearText_withVoiceEnabled_resetsButtonStateToVoiceOnly() {
        sut.isVoiceSearchEnabled = true
        sut.updateCurrentText("hello")
        sut.clearText()
        XCTAssertEqual(sut.buttonState, .voiceOnly)
    }

    // MARK: - submitText

    func test_submitText_withContent_firesPublisher() {
        let expectation = expectation(description: "textSubmissionPublisher fires")
        sut.textSubmissionPublisher
            .sink { submission in
                XCTAssertEqual(submission.text, "hello")
                XCTAssertEqual(submission.mode, .aiChat)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        sut.submitText("hello")
        waitForExpectations(timeout: 1)
    }

    func test_submitText_trimsWhitespace() {
        let expectation = expectation(description: "trimmed text submitted")
        sut.textSubmissionPublisher
            .sink { submission in
                XCTAssertEqual(submission.text, "hello")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        sut.submitText("  hello  ")
        waitForExpectations(timeout: 1)
    }

    func test_submitText_emptyString_doesNotFirePublisher() {
        var fired = false
        sut.textSubmissionPublisher
            .sink { _ in fired = true }
            .store(in: &cancellables)

        sut.submitText("")
        sut.submitText("   ")

        XCTAssertFalse(fired)
    }

    func test_submitText_usesCurrentToggleMode() {
        let expectation = expectation(description: "mode in submission matches toggle")
        sut.setToggleState(.search)

        sut.textSubmissionPublisher
            .sink { submission in
                XCTAssertEqual(submission.mode, .search)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        sut.submitText("query")
        waitForExpectations(timeout: 1)
    }

    // MARK: - setToggleState

    func test_setToggleState_updatesCurrentToggleState() {
        sut.setToggleState(.search)
        XCTAssertEqual(sut.currentToggleState, .search)

        sut.setToggleState(.aiChat)
        XCTAssertEqual(sut.currentToggleState, .aiChat)
    }

    func test_setToggleState_publishesChange() {
        let expectation = expectation(description: "toggleStatePublisher fires")
        sut.toggleStatePublisher
            .dropFirst()
            .sink { mode in
                XCTAssertEqual(mode, .search)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        sut.setToggleState(.search)
        waitForExpectations(timeout: 1)
    }

    // MARK: - isVoiceSearchEnabled

    func test_setVoiceEnabled_withEmptyText_updatesButtonStateToVoiceOnly() {
        sut.isVoiceSearchEnabled = true
        XCTAssertEqual(sut.buttonState, .voiceOnly)
    }

    func test_setVoiceDisabled_withEmptyText_updatesButtonStateToNoButtons() {
        sut.isVoiceSearchEnabled = true
        sut.isVoiceSearchEnabled = false
        XCTAssertEqual(sut.buttonState, .noButtons)
    }

    func test_setVoiceEnabled_withExistingText_doesNotOverrideClearButton() {
        sut.updateCurrentText("hello")
        sut.isVoiceSearchEnabled = true
        XCTAssertEqual(sut.buttonState, .clearOnly)
    }

    // MARK: - microphoneButtonTapped

    func test_microphoneButtonTapped_firesPublisher() {
        let expectation = expectation(description: "microphoneButtonTappedPublisher fires")
        sut.microphoneButtonTappedPublisher
            .sink { expectation.fulfill() }
            .store(in: &cancellables)

        sut.microphoneButtonTapped()
        waitForExpectations(timeout: 1)
    }

    // MARK: - updateBarPosition

    func test_updateBarPosition_doesNotChangeConstants() {
        sut.updateBarPosition(isTop: true)
        XCTAssertFalse(sut.isTopBarPosition)

        sut.updateBarPosition(isTop: false)
        XCTAssertFalse(sut.isTopBarPosition)
    }

    // MARK: - Stop Generating Button State

    func test_isGenerating_collapsed_aiChat_showsStopGeneratingOnly() {
        sut.isGenerating = true
        XCTAssertEqual(sut.buttonState, .stopGeneratingOnly)
    }

    func test_isGenerating_collapsed_toggleDisabled_showsStopGeneratingAndSearchGoTo() {
        sut.isToggleEnabled = false
        sut.isGenerating = true
        XCTAssertEqual(sut.buttonState, .stopGeneratingAndSearchGoTo)
    }

    func test_isGenerating_expanded_doesNotShowStopInCollapsedBar() {
        sut.isExpanded = true
        sut.isGenerating = true
        XCTAssertEqual(sut.buttonState, .noButtons)
    }

    func test_isGenerating_searchMode_doesNotShowStop() {
        sut.setToggleState(.search)
        sut.isGenerating = true
        XCTAssertEqual(sut.buttonState, .noButtons)
    }

    func test_isGenerating_withText_stopOutranksClear() {
        sut.updateCurrentText("hello")
        sut.isGenerating = true
        XCTAssertEqual(sut.buttonState, .stopGeneratingOnly)
    }

    func test_isGenerating_false_restoresNormalState() {
        sut.isGenerating = true
        XCTAssertEqual(sut.buttonState, .stopGeneratingOnly)
        sut.isGenerating = false
        XCTAssertEqual(sut.buttonState, .noButtons)
    }

    func test_isGenerating_false_withText_showsClear() {
        sut.updateCurrentText("hello")
        sut.isGenerating = true
        XCTAssertEqual(sut.buttonState, .stopGeneratingOnly)
        sut.isGenerating = false
        XCTAssertEqual(sut.buttonState, .clearOnly)
    }

    // MARK: - Stop Generating Publisher

    func test_stopGeneratingButtonTapped_firesPublisher() {
        let expectation = expectation(description: "stopGeneratingButtonTappedPublisher fires")
        sut.stopGeneratingButtonTappedPublisher
            .sink { expectation.fulfill() }
            .store(in: &cancellables)

        sut.stopGeneratingButtonTapped()
        waitForExpectations(timeout: 1)
    }
}
