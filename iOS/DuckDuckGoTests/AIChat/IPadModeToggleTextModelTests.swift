//
//  IPadModeToggleTextModelTests.swift
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

import XCTest
@testable import DuckDuckGo

final class IPadModeToggleTextModelTests: XCTestCase {

    private var sut: IPadModeToggleTextModel!

    override func setUp() {
        super.setUp()
        sut = IPadModeToggleTextModel()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testWhenInitializedThenModeIsSearch() {
        XCTAssertEqual(sut.currentMode, .search)
    }

    func testWhenInitializedThenSharedTextIsEmpty() {
        XCTAssertTrue(sut.sharedText.isEmpty)
    }

    func testWhenInitializedThenIsNotTransitioning() {
        XCTAssertFalse(sut.isTransitioning)
    }

    func testWhenInitializedThenShowPlaceholderIsTrue() {
        XCTAssertTrue(sut.showPlaceholder)
    }

    // MARK: - Text Updates

    func testWhenTextUpdatedThenSharedTextReflectsNewValue() {
        sut.updateText("hello world")

        XCTAssertEqual(sut.sharedText, "hello world")
    }

    func testWhenTextUpdatedWithNonEmptyThenShowPlaceholderIsFalse() {
        sut.updateText("query")

        XCTAssertFalse(sut.showPlaceholder)
    }

    func testWhenTextClearedThenShowPlaceholderIsTrue() {
        sut.updateText("query")
        sut.updateText("")

        XCTAssertTrue(sut.showPlaceholder)
    }

    // MARK: - Transition: Search → AI Chat

    func testWhenTransitioningFromSearchToAIChatThenModeChanges() {
        _ = sut.transition(to: .aiChat)

        XCTAssertEqual(sut.currentMode, .aiChat)
    }

    func testWhenTransitioningFromSearchToAIChatThenTextIsPreserved() {
        sut.updateText("my search query")

        let transition = sut.transition(to: .aiChat)

        XCTAssertEqual(transition?.text, "my search query")
    }

    func testWhenTransitioningFromSearchToAIChatThenKeyboardTransferIsNotNeeded() {
        let transition = sut.transition(to: .aiChat)

        XCTAssertEqual(transition?.needsKeyboardTransfer, false)
    }

    func testWhenTransitioningFromSearchToAIChatThenTextSelectionIsNotSuppressed() {
        let transition = sut.transition(to: .aiChat)

        XCTAssertEqual(transition?.suppressTextSelection, false)
    }

    // MARK: - Transition: AI Chat → Search

    func testWhenTransitioningFromAIChatToSearchThenModeChanges() {
        _ = sut.transition(to: .aiChat)

        _ = sut.transition(to: .search)

        XCTAssertEqual(sut.currentMode, .search)
    }

    func testWhenTransitioningFromAIChatToSearchThenTextIsPreserved() {
        _ = sut.transition(to: .aiChat)
        sut.updateText("ask AI something")

        let transition = sut.transition(to: .search)

        XCTAssertEqual(transition?.text, "ask AI something")
    }

    func testWhenTransitioningFromAIChatToSearchThenKeyboardTransferIsNeeded() {
        _ = sut.transition(to: .aiChat)

        let transition = sut.transition(to: .search)

        XCTAssertEqual(transition?.needsKeyboardTransfer, true)
    }

    func testWhenTransitioningFromAIChatToSearchThenTextSelectionIsSuppressed() {
        _ = sut.transition(to: .aiChat)

        let transition = sut.transition(to: .search)

        XCTAssertEqual(transition?.suppressTextSelection, true)
    }

    // MARK: - No-op Transitions

    func testWhenTransitioningToSameModeThenReturnsNil() {
        XCTAssertNil(sut.transition(to: .search))
    }

    func testWhenTransitioningToSameAIChatModeThenReturnsNil() {
        _ = sut.transition(to: .aiChat)

        XCTAssertNil(sut.transition(to: .aiChat))
    }

    func testWhenTransitioningToSameModeThenModeDoesNotChange() {
        let modeBefore = sut.currentMode

        _ = sut.transition(to: .search)

        XCTAssertEqual(sut.currentMode, modeBefore)
    }

    // MARK: - Transition State

    func testWhenBeginTransitionThenIsTransitioningIsTrue() {
        sut.beginTransition()

        XCTAssertTrue(sut.isTransitioning)
    }

    func testWhenEndTransitionThenIsTransitioningIsFalse() {
        sut.beginTransition()
        sut.endTransition()

        XCTAssertFalse(sut.isTransitioning)
    }

    // MARK: - Round-trip Text Preservation

    func testWhenTextIsUpdatedAndModeRoundTrippedThenTextSurvives() {
        sut.updateText("original query")

        _ = sut.transition(to: .aiChat)
        sut.updateText("modified in AI chat")

        let transition = sut.transition(to: .search)

        XCTAssertEqual(transition?.text, "modified in AI chat")
        XCTAssertEqual(sut.sharedText, "modified in AI chat")
    }

    func testWhenMultipleRoundTripsThenTextRemainsConsistent() {
        sut.updateText("start")

        _ = sut.transition(to: .aiChat)
        sut.updateText("round 1")
        _ = sut.transition(to: .search)
        _ = sut.transition(to: .aiChat)
        sut.updateText("round 2")
        let transition = sut.transition(to: .search)

        XCTAssertEqual(transition?.text, "round 2")
    }

    // MARK: - Placeholder Across Mode Changes

    func testWhenTextEmptyAfterModeChangeThenShowPlaceholderIsTrue() {
        sut.updateText("query")
        _ = sut.transition(to: .aiChat)
        sut.updateText("")

        XCTAssertTrue(sut.showPlaceholder)
    }

    func testWhenTextNotEmptyAfterModeChangeThenShowPlaceholderIsFalse() {
        _ = sut.transition(to: .aiChat)
        sut.updateText("hello")

        XCTAssertFalse(sut.showPlaceholder)
    }
}
