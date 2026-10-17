//
//  AddressBarMouseSelectionTests.swift
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

/// Selecting address bar text with the mouse: double click (word), triple click (everything), drag, Shift+click and clicks on or
/// after the “ – Search with DuckDuckGo” / “ – Visit …” suffix, which must never be selected.
///
/// The texts are short so the positions in points from the left edge of the field stay valid for any window width:
/// the text starts at the left edge, ends at ~70 pt and the suffix covers roughly 80–230 pt.
class AddressBarMouseSelectionTests: UITestCase {

    private let query = "alpha beta"
    private let shortURL = "https://a.io/x"
    private var bar: EditingDriver!

    private enum Points {
        static let firstWord: CGFloat = 20
        static let secondWord: CGFloat = 58
        static let textStart: CGFloat = 1
        static let onSuffix: CGFloat = 150
        /// Empty field area after the suffix (the field is much wider; the buttons at its right edge are avoided)
        static let afterEverything: CGFloat = 330
    }

    override class func setUp() {
        super.setUp()
        UITests.setAutocompleteToggleBeforeTestcaseRuns(false) // We don't want changes in the address bar that we don't create
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()
        bar = EditingDriver(element: app.addressBar)
    }

    private func typeQuery() {
        bar.type(query)
        XCTAssertTrue(bar.rawValue.contains(EditingDriver.suffixSeparator), "The ‘Search with DuckDuckGo’ suffix should be displayed")
    }

    private func typeURL() throws {
        bar.element.typeURL(try XCTUnwrap(URL(string: shortURL)), pressingEnter: false)
        XCTAssertTrue(bar.rawValue.contains(EditingDriver.suffixSeparator), "The ‘Visit …’ suffix should be displayed")
    }

    // MARK: - Words and everything

    func test_doubleClick_onTheFirstWord_selectsTheWord() {
        typeQuery()
        bar.doubleClick(bar.point(x: Points.firstWord))
        XCTAssertEqual(bar.selectedText(), "alpha")
    }

    func test_doubleClick_onTheSecondWord_selectsTheWordWithoutTheSuffix() {
        typeQuery()
        bar.doubleClick(bar.point(x: Points.secondWord))
        XCTAssertEqual(bar.selectedText(), "beta")
    }

    func test_tripleClick_selectsTheWholeQueryWithoutTheSuffix() throws {
        typeQuery()
        try bar.tripleClick(bar.point(x: Points.firstWord))
        XCTAssertEqual(bar.selectedText(), query)
    }

    func test_tripleClick_selectsTheWholeURLWithoutTheSuffix() throws {
        try typeURL()
        try bar.tripleClick(bar.point(x: Points.firstWord))
        XCTAssertEqual(bar.selectedText(), shortURL)
    }

    func test_doubleClick_onTheURLScheme_selectsTheWord() throws {
        try typeURL()
        bar.doubleClick(bar.point(x: Points.firstWord))
        XCTAssertEqual(bar.selectedText(), "https")
    }

    // MARK: - Clicks on and after the suffix

    func test_click_afterTheText_putsTheCaretBeforeTheSuffix() {
        typeQuery()
        bar.click(bar.point(x: Points.afterEverything))
        bar.type("!")
        XCTAssertEqual(bar.value, query + "!")
        XCTAssertTrue(bar.rawValue.contains(EditingDriver.suffixSeparator))
    }

    func test_click_onTheSuffix_putsTheCaretBeforeTheSuffix() {
        typeQuery()
        bar.click(bar.point(x: Points.onSuffix))
        bar.type("!")
        XCTAssertEqual(bar.value, query + "!")
    }

    func test_click_onTheURLSuffix_putsTheCaretBeforeTheSuffix() throws {
        try typeURL()
        bar.click(bar.point(x: Points.onSuffix))
        bar.type("!")
        XCTAssertEqual(bar.value, shortURL + "!")
    }

    func test_doubleClick_onTheSuffix_doesNotSelectTheSuffix() {
        typeQuery()
        let before = bar.rawValue
        bar.doubleClick(bar.point(x: Points.onSuffix))
        let selected = bar.selectedText()
        XCTAssertTrue(bar.selectionExcludesSuffix(selected), "The suffix must not be selected, got \(selected ?? "nil")")
        XCTAssertFalse((selected ?? "").contains("Search"), "A suffix word must not be selected, got \(selected ?? "nil")")
        XCTAssertEqual(bar.rawValue, before)
    }

    func test_tripleClick_onTheSuffix_doesNotSelectTheSuffix() throws {
        typeQuery()
        try bar.tripleClick(bar.point(x: Points.onSuffix))
        let selected = bar.selectedText()
        XCTAssertTrue(bar.selectionExcludesSuffix(selected), "The suffix must not be selected, got \(selected ?? "nil")")
        XCTAssertTrue(selected == nil || selected == query, "Only the query can be selected, got \(selected ?? "nil")")
    }

    func test_doubleClick_onTheURLSuffix_doesNotSelectTheSuffix() throws {
        try typeURL()
        bar.doubleClick(bar.point(x: Points.onSuffix))
        let selected = bar.selectedText()
        XCTAssertTrue(bar.selectionExcludesSuffix(selected), "The suffix must not be selected, got \(selected ?? "nil")")
        XCTAssertFalse((selected ?? "").contains("Visit"), "A suffix word must not be selected, got \(selected ?? "nil")")
    }

    // MARK: - Drag and Shift+click

    func test_drag_fromTheStartThroughTheSuffix_selectsOnlyTheQuery() {
        typeQuery()
        bar.drag(from: bar.point(x: Points.textStart), to: bar.point(x: Points.afterEverything))
        let selected = bar.selectedText()
        XCTAssertTrue(bar.selectionExcludesSuffix(selected), "The suffix must not be selected, got \(selected ?? "nil")")
        XCTAssertEqual(selected, query)
    }

    func test_drag_fromTheSuffixBackToTheStart_selectsOnlyTheQuery() {
        typeQuery()
        bar.drag(from: bar.point(x: Points.onSuffix), to: bar.point(x: Points.textStart))
        let selected = bar.selectedText()
        XCTAssertTrue(bar.selectionExcludesSuffix(selected), "The suffix must not be selected, got \(selected ?? "nil")")
        XCTAssertEqual(selected, query)
    }

    func test_drag_throughTheURLAndItsSuffix_selectsOnlyTheURL() throws {
        try typeURL()
        bar.drag(from: bar.point(x: Points.textStart), to: bar.point(x: Points.afterEverything))
        let selected = bar.selectedText()
        XCTAssertTrue(bar.selectionExcludesSuffix(selected), "The suffix must not be selected, got \(selected ?? "nil")")
        XCTAssertEqual(selected, shortURL)
    }

    func test_drag_withinTheText_selectsAPartOfTheQuery() {
        typeQuery()
        bar.drag(from: bar.point(x: Points.textStart), to: bar.point(x: Points.secondWord))
        let selected = bar.selectedText() ?? ""
        XCTAssertFalse(selected.isEmpty, "Dragging over the text should select something")
        XCTAssertTrue(query.hasPrefix(selected), "A prefix of the query is expected, got \(selected)")
        XCTAssertNotEqual(selected, query)
    }

    func test_shiftClick_onTheSuffix_extendsTheSelectionToTheEndOfTheQuery() {
        typeQuery()
        bar.moveCaretToStart()
        bar.shiftClick(bar.point(x: Points.onSuffix))
        let selected = bar.selectedText()
        XCTAssertTrue(bar.selectionExcludesSuffix(selected), "The suffix must not be selected, got \(selected ?? "nil")")
        XCTAssertEqual(selected, query)
    }

    func test_shiftClick_inTheMiddle_extendsTheSelectionFromTheCaret() {
        typeQuery()
        bar.moveCaretToStart()
        bar.shiftClick(bar.point(x: Points.secondWord))
        let selected = bar.selectedText() ?? ""
        XCTAssertFalse(selected.isEmpty, "Shift+click should select from the caret")
        XCTAssertTrue(query.hasPrefix(selected), "A prefix of the query is expected, got \(selected)")
    }

    // MARK: - Combined with the keyboard

    func test_click_inTheMiddle_thenOptShiftRight_selectsTheRestOfTheWord() {
        typeQuery()
        bar.doubleClick(bar.point(x: Points.firstWord))
        bar.press(EditingKeys.right)
        bar.press(EditingKeys.optShiftRight)
        XCTAssertEqual(bar.selectedText(), " beta")
        bar.press(EditingKeys.optShiftRight)
        XCTAssertEqual(bar.selectedText(), " beta", "The suffix must not be selected")
    }
}
