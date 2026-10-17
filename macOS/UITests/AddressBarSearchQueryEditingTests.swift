//
//  AddressBarSearchQueryEditingTests.swift
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

/// Selection, caret movement and delete patterns of the address bar when it contains a search query,
/// i.e. when it shows the “ – Search with DuckDuckGo” suffix.
class AddressBarSearchQueryEditingTests: UITestCase {

    private let query = "alpha beta gamma"
    private var bar: EditingDriver!

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
        bar.type(query)
        XCTAssertTrue(bar.rawValue.contains(EditingDriver.suffixSeparator), "The ‘Search with DuckDuckGo’ suffix should be displayed")
    }

    func test_suffix_isShownAfterTheQuery() throws {
        XCTAssertEqual(bar.value, query)
        XCTAssertNotEqual(bar.rawValue, query, "The ‘Search with DuckDuckGo’ suffix should be displayed")
    }

    // MARK: - Selection

    func test_selectAll_selectsTheQueryWithoutTheSuffix() {
        bar.press(EditingKeys.selectAll)
        XCTAssertEqual(bar.selectedText(), query)
    }

    func test_cmdShiftLeft_fromEnd_andCmdShiftRight_fromStart_selectTheQueryWithoutTheSuffix() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.cmdShiftLeft)
        XCTAssertEqual(bar.selectedText(), query)
        bar.moveCaretToStart()
        bar.press(EditingKeys.cmdShiftRight)
        XCTAssertEqual(bar.selectedText(), query)
    }

    func test_optShiftLeft_fromEnd_selectsWordsBackwards() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.optShiftLeft)
        XCTAssertEqual(bar.selectedText(), "gamma")
        bar.press(EditingKeys.optShiftLeft)
        XCTAssertEqual(bar.selectedText(), "beta gamma")
        bar.press(EditingKeys.optShiftLeft, times: 3)
        XCTAssertEqual(bar.selectedText(), query)
    }

    func test_optShiftRight_fromStart_selectsWordsForwards_andStopsBeforeTheSuffix() {
        bar.moveCaretToStart()
        bar.press(EditingKeys.optShiftRight)
        XCTAssertEqual(bar.selectedText(), "alpha")
        bar.press(EditingKeys.optShiftRight, times: 5)
        XCTAssertEqual(bar.selectedText(), query)
    }

    func test_selectionTowardsTheSuffix_fromEnd_selectsNothing() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.shiftRight)
        XCTAssertNil(bar.selectedText())
        bar.press(EditingKeys.optShiftRight)
        XCTAssertNil(bar.selectedText())
        bar.press(EditingKeys.cmdShiftRight)
        XCTAssertNil(bar.selectedText())
    }

    func test_optShiftLeft_afterSelectAll_contractsFromTheRight() {
        bar.press(EditingKeys.selectAll)
        bar.press(EditingKeys.optShiftLeft)
        XCTAssertEqual(bar.selectedText(), "alpha beta ")
    }

    func test_optShiftRight_afterCmdShiftLeft_contractsFromTheLeft() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.cmdShiftLeft)
        bar.press(EditingKeys.optShiftRight)
        XCTAssertEqual(bar.selectedText(), " beta gamma")
    }

    func test_shiftLeft_fromEnd_selectsCharacters() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.shiftLeft, times: 5)
        XCTAssertEqual(bar.selectedText(), "gamma")
    }

    // MARK: - Delete

    func test_forwardDelete_atTheEnd_doesNotDeleteTheSuffix() {
        bar.moveCaretToEnd()
        let before = bar.rawValue
        bar.press([EditingKeys.forwardDelete, EditingKeys.optForwardDelete, EditingKeys.cmdForwardDelete, EditingKeys.ctrlD, EditingKeys.ctrlK])
        XCTAssertEqual(bar.rawValue, before)
    }

    func test_optDelete_atTheEnd_deletesTheLastWord() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.optDelete)
        XCTAssertEqual(bar.value, "alpha beta ")
    }

    func test_backspace_atTheEnd_deletesOneCharacter() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.fnDelete)
        XCTAssertEqual(bar.value, "alpha beta gamm")
        bar.press(EditingKeys.ctrlH)
        XCTAssertEqual(bar.value, "alpha beta gam")
    }

    func test_cmdDelete_atTheEnd_deletesTheWholeQuery() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.cmdDelete)
        XCTAssertEqual(bar.value, "")
    }

    func test_cmdDelete_fromMiddle_deletesToTheStart() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.cmdDelete)
        XCTAssertEqual(bar.value, "beta gamma")
    }

    func test_forwardDelete_fromMiddle_deletesTowardsTheEnd() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.forwardDelete)
        XCTAssertEqual(bar.value, "alpha eta gamma")
        bar.press(EditingKeys.optForwardDelete)
        XCTAssertEqual(bar.value, "alpha  gamma")
        bar.press(EditingKeys.cmdForwardDelete)
        XCTAssertEqual(bar.value, "alpha ")
    }

    func test_optForwardDelete_atTheStart_deletesTheFirstWord() {
        bar.moveCaretToStart()
        bar.press(EditingKeys.optForwardDelete)
        XCTAssertEqual(bar.value, " beta gamma")
    }

    func test_backspace_atTheStart_deletesNothing() {
        bar.moveCaretToStart()
        bar.press([EditingKeys.backspace, EditingKeys.optDelete, EditingKeys.cmdDelete])
        XCTAssertEqual(bar.value, query)
    }

    func test_backspace_afterSelectAll_clearsTheAddressBar() {
        bar.press(EditingKeys.selectAll)
        bar.press(EditingKeys.backspace)
        XCTAssertEqual(bar.rawValue, "", "The suffix must go away together with the query")
    }

    func test_optDelete_afterOptShiftLeft_deletesOnlyTheSelectedWords() {
        bar.moveCaretToEnd()
        bar.press(repeated(EditingKeys.optShiftLeft, 2))
        bar.press(EditingKeys.optDelete)
        XCTAssertEqual(bar.value, "alpha ")
    }

    // MARK: - Caret movement to the string bounds

    func test_typing_afterCmdRight_insertsBeforeTheSuffix() {
        bar.moveCaretToEnd()
        bar.type("!")
        XCTAssertEqual(bar.value, query + "!")
    }

    func test_typing_afterOptRightPastTheEnd_insertsBeforeTheSuffix() {
        bar.moveCaretToStart()
        bar.press(EditingKeys.optRight, times: 5)
        bar.type("!")
        XCTAssertEqual(bar.value, query + "!")
    }

    func test_typing_afterRightArrow_overSelectAll_insertsBeforeTheSuffix() {
        bar.press(EditingKeys.selectAll)
        bar.press(EditingKeys.right)
        bar.type("!")
        XCTAssertEqual(bar.value, query + "!")
    }

    func test_typing_afterLeftArrow_overSelectAll_insertsAtTheStart() {
        bar.press(EditingKeys.selectAll)
        bar.press(EditingKeys.left)
        bar.type("!")
        XCTAssertEqual(bar.value, "!" + query)
    }

    func test_ctrlA_andCtrlE_moveTheCaretToTheBounds() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.ctrlA)
        bar.type("<")
        bar.press(EditingKeys.ctrlE)
        bar.type(">")
        XCTAssertEqual(bar.value, "<" + query + ">")
    }

    private func repeated(_ key: EditingKey, _ times: Int) -> [EditingKey] {
        Array(repeating: key, count: times)
    }
}

// MARK: - Remaining positions and the suffix

extension AddressBarSearchQueryEditingTests {

    func test_optShiftLeft_atTheStart_selectsNothing() {
        bar.moveCaretToStart()
        bar.press(EditingKeys.optShiftLeft)
        XCTAssertNil(bar.selectedText())
    }

    func test_shiftLeft_andShiftRight_fromMiddle_selectOneCharacter() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.shiftRight)
        XCTAssertEqual(bar.selectedText(), "b")
        bar.press(EditingKeys.left)
        bar.press(EditingKeys.shiftLeft)
        XCTAssertEqual(bar.selectedText(), " ")
    }

    func test_cmdShiftLeft_andCmdShiftRight_fromMiddle_selectToTheBounds() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.cmdShiftLeft)
        XCTAssertEqual(bar.selectedText(), "alpha ")
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.cmdShiftRight)
        XCTAssertEqual(bar.selectedText(), "beta gamma", "The suffix must not be selected")
    }

    func test_optDelete_fromMiddle_deletesThePreviousWord() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.optDelete)
        XCTAssertEqual(bar.value, "beta gamma")
    }

    func test_backspace_fromMiddle_deletesOneCharacterBack() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.fnDelete)
        XCTAssertEqual(bar.value, "alphabeta gamma")
    }

    func test_cmdDelete_andCmdForwardDelete_withSelection_deleteOnlyTheSelection() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.optShiftRight)
        bar.press(EditingKeys.cmdDelete)
        XCTAssertEqual(bar.value, "alpha  gamma")
    }

    /// Every way of selecting towards the end of the text must stop before the “ – Search with DuckDuckGo” suffix.
    func test_suffix_isNeverSelectedByTheKeyboard() {
        bar.moveCaretToEnd()
        let keys = [EditingKeys.shiftRight, EditingKeys.optShiftRight, EditingKeys.cmdShiftRight]
        for key in keys {
            bar.press(key)
            XCTAssertNil(bar.selectedText(), "Selecting towards the suffix must select nothing")
        }
        bar.press(EditingKeys.selectAll)
        let selected = bar.selectedText()
        XCTAssertTrue(bar.selectionExcludesSuffix(selected), "Select All must not include the suffix, got \(selected ?? "nil")")
        XCTAssertEqual(selected, query)
        bar.press(EditingKeys.ctrlE)
        bar.type("!")
        XCTAssertEqual(bar.value, query + "!")
        XCTAssertTrue(bar.rawValue.contains(EditingDriver.suffixSeparator), "The suffix must still be there")
    }
}
