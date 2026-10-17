//
//  AddressBarEditingPatternsTests.swift
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

/// Selection, caret movement and delete patterns of the address bar when it contains a URL.
///
/// Words in the fixture URL: `https` `duckduckgo` `com` `duckduckgo` `help` `pages` `results` `translation`.
/// Word moves skip separators first and then the word, like macOS text fields do.
class AddressBarUrlEditingTests: UITestCase {

    private let url = "https://duckduckgo.com/duckduckgo-help-pages/results/translation/"
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
        bar.element.typeURL(try XCTUnwrap(URL(string: url)), pressingEnter: false)
    }

    private func repeated(_ key: EditingKey, _ times: Int) -> [EditingKey] {
        Array(repeating: key, count: times)
    }

    // MARK: - Opt+Shift+Left/Right selection by word

    func test_optShiftLeft_fromEnd_selectsWordsBackwards() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.optShiftLeft)
        XCTAssertEqual(bar.selectedText(), "translation/")
        bar.press(EditingKeys.optShiftLeft, times: 2)
        XCTAssertEqual(bar.selectedText(), "pages/results/translation/")
    }

    func test_optShiftLeft_fromEnd_pastTheFirstWord_stopsAtTheStart() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.optShiftLeft, times: 12)
        XCTAssertEqual(bar.selectedText(), url)
    }

    func test_optShiftRight_fromStart_selectsWordsForwards() {
        bar.moveCaretToStart()
        bar.press(EditingKeys.optShiftRight)
        XCTAssertEqual(bar.selectedText(), "https")
        bar.press(EditingKeys.optShiftRight)
        XCTAssertEqual(bar.selectedText(), "https://duckduckgo")
    }

    func test_optShiftRight_fromStart_pastTheLastWord_stopsAtTheEndOfTheURL() {
        bar.moveCaretToStart()
        bar.press(EditingKeys.optShiftRight, times: 12)
        XCTAssertEqual(bar.selectedText(), url, "The address bar suffix must not be selected")
    }

    func test_optShiftLeft_fromMiddle_extendsLeft() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.optShiftLeft)
        XCTAssertEqual(bar.selectedText(), "pages/")
        bar.press(EditingKeys.optShiftLeft)
        XCTAssertEqual(bar.selectedText(), "help-pages/")
    }

    func test_optShiftRight_fromMiddle_extendsRight() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.optShiftRight)
        XCTAssertEqual(bar.selectedText(), "results")
        bar.press(EditingKeys.optShiftRight)
        XCTAssertEqual(bar.selectedText(), "results/translation")
    }

    func test_optShiftRight_afterOptShiftLeft_contractsFromTheLeft() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(repeated(EditingKeys.optShiftLeft, 2))
        bar.press(EditingKeys.optShiftRight)
        XCTAssertEqual(bar.selectedText(), "-pages/")
    }

    func test_optShiftLeft_afterOptShiftRight_contractsFromTheRight_andCollapsesTheSelection() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.optShiftRight)
        bar.press(EditingKeys.optShiftLeft)
        XCTAssertNil(bar.selectedText(), "Contracting a one word selection leaves a caret")
        bar.press(EditingKeys.backspace)
        XCTAssertEqual(bar.value, "https://duckduckgo.com/duckduckgo-help-pagesresults/translation/")
    }

    func test_optShiftLeft_afterOptShiftRight_twoWords_contractsOneWordAtATime() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(repeated(EditingKeys.optShiftRight, 2))
        bar.press(EditingKeys.optShiftLeft)
        XCTAssertEqual(bar.selectedText(), "results/", "The caret moves back to the start of ‘translation’")
    }

    // MARK: - Contracting a select-all selection

    func test_optShiftLeft_afterSelectAll_contractsWordByWord() {
        bar.press(EditingKeys.selectAll)
        bar.press(repeated(EditingKeys.optShiftLeft, 2))
        XCTAssertEqual(bar.selectedText(), "https://duckduckgo.com/duckduckgo-help-pages/")
    }

    func test_optShiftLeft_afterSelectAll_forEveryWord_collapsesToACaret() {
        bar.press(EditingKeys.selectAll)
        bar.press(repeated(EditingKeys.optShiftLeft, 8))
        XCTAssertNil(bar.selectedText())
        bar.press(EditingKeys.backspace)
        XCTAssertEqual(bar.value, url, "Nothing is selected at the start of the URL, so nothing is deleted")
    }

    func test_optShiftRight_afterSelectAll_keepsTheSelection() {
        bar.press(EditingKeys.selectAll)
        bar.press(EditingKeys.optShiftRight)
        XCTAssertEqual(bar.selectedText(), url)
    }

    func test_optShiftRight_afterCmdShiftLeft_contractsFromTheLeftWordByWord() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.cmdShiftLeft)
        bar.press(repeated(EditingKeys.optShiftRight, 2))
        XCTAssertEqual(bar.selectedText(), ".com/duckduckgo-help-pages/results/translation/")
    }

    // MARK: - Cmd+Shift+Left/Right selection to the string bounds

    func test_cmdShiftLeft_selectsToTheStart() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.cmdShiftLeft)
        XCTAssertEqual(bar.selectedText(), "https://duckduckgo.com/duckduckgo-help-pages/")
    }

    func test_cmdShiftRight_selectsToTheEndOfTheURL_notTheSuffix() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.cmdShiftRight)
        XCTAssertEqual(bar.selectedText(), "results/translation/")
    }

    func test_cmdShiftLeft_atTheStart_andCmdShiftRight_atTheEnd_selectNothing() {
        bar.moveCaretToStart()
        bar.press(EditingKeys.cmdShiftLeft)
        XCTAssertNil(bar.selectedText())
        bar.moveCaretToEnd()
        bar.press(EditingKeys.cmdShiftRight)
        XCTAssertNil(bar.selectedText())
    }

    func test_selectAll_selectsTheURLWithoutTheSuffix() {
        bar.press(EditingKeys.selectAll)
        XCTAssertEqual(bar.selectedText(), url)
    }

    // MARK: - Shift+Left/Right selection by character

    func test_shiftLeft_fromEnd_selectsCharacters() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.shiftLeft, times: 3)
        XCTAssertEqual(bar.selectedText(), "on/")
    }

    func test_shiftRight_fromStart_selectsCharacters() {
        bar.moveCaretToStart()
        bar.press(EditingKeys.shiftRight, times: 2)
        XCTAssertEqual(bar.selectedText(), "ht")
    }

    func test_shiftRight_atTheEnd_doesNotSelectTheSuffix() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.shiftRight, times: 3)
        XCTAssertNil(bar.selectedText())
    }

    func test_shiftRight_afterShiftLeft_contractsTheSelection() {
        bar.moveCaretToEnd()
        bar.press(repeated(EditingKeys.shiftLeft, 2))
        bar.press(EditingKeys.shiftRight)
        XCTAssertEqual(bar.selectedText(), "/")
    }

    // MARK: - Backward delete

    func test_backspace_atTheStart_deletesNothing() {
        bar.moveCaretToStart()
        bar.press([EditingKeys.backspace, EditingKeys.fnDelete, EditingKeys.optDelete, EditingKeys.cmdDelete, EditingKeys.ctrlH])
        XCTAssertEqual(bar.value, url)
    }

    func test_backspace_atTheEnd_deletesOneCharacter() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.fnDelete)
        XCTAssertEqual(bar.value, "https://duckduckgo.com/duckduckgo-help-pages/results/translation")
        bar.press(EditingKeys.ctrlH)
        XCTAssertEqual(bar.value, "https://duckduckgo.com/duckduckgo-help-pages/results/translatio")
    }

    func test_optDelete_atTheEnd_deletesTheLastWord() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.optDelete)
        XCTAssertEqual(bar.value, "https://duckduckgo.com/duckduckgo-help-pages/results/")
        bar.press(EditingKeys.optDelete)
        XCTAssertEqual(bar.value, "https://duckduckgo.com/duckduckgo-help-pages/")
    }

    func test_cmdDelete_atTheEnd_deletesEverything() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.cmdDelete)
        XCTAssertEqual(bar.value, "")
    }

    func test_cmdDelete_fromMiddle_deletesToTheStart() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.cmdDelete)
        XCTAssertEqual(bar.value, "results/translation/")
    }

    func test_optDelete_withSelection_deletesOnlyTheSelection() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.optShiftRight)
        bar.press(EditingKeys.optDelete)
        XCTAssertEqual(bar.value, "https://duckduckgo.com/duckduckgo-help-pages//translation/")
    }

    func test_backspace_afterOptShiftLeft_fromMiddle_deletesTheSelectedWords() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(repeated(EditingKeys.optShiftLeft, 2))
        bar.press(EditingKeys.backspace)
        XCTAssertEqual(bar.value, "https://duckduckgo.com/duckduckgo-results/translation/")
    }

    // MARK: - Forward delete

    func test_forwardDelete_atTheEnd_doesNotDeleteTheSuffix() {
        bar.moveCaretToEnd()
        let before = bar.rawValue
        bar.press([EditingKeys.forwardDelete, EditingKeys.optForwardDelete, EditingKeys.cmdForwardDelete, EditingKeys.ctrlD, EditingKeys.ctrlK])
        XCTAssertEqual(bar.rawValue, before)
    }

    func test_forwardDelete_atTheStart_deletesOneCharacter() {
        bar.moveCaretToStart()
        bar.press(EditingKeys.forwardDelete)
        XCTAssertEqual(bar.value, "ttps://duckduckgo.com/duckduckgo-help-pages/results/translation/")
        bar.press(EditingKeys.ctrlD)
        XCTAssertEqual(bar.value, "tps://duckduckgo.com/duckduckgo-help-pages/results/translation/")
    }

    func test_optForwardDelete_atTheStart_deletesTheFirstWord() {
        bar.moveCaretToStart()
        bar.press(EditingKeys.optForwardDelete)
        XCTAssertEqual(bar.value, "://duckduckgo.com/duckduckgo-help-pages/results/translation/")
    }

    func test_cmdForwardDelete_atTheStart_deletesEverything() {
        bar.moveCaretToStart()
        bar.press(EditingKeys.cmdForwardDelete)
        XCTAssertEqual(bar.value, "")
    }

    func test_cmdForwardDelete_fromMiddle_deletesToTheEnd() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.cmdForwardDelete)
        XCTAssertEqual(bar.value, "https://duckduckgo.com/duckduckgo-help-pages/")
    }

    func test_ctrlK_fromMiddle_deletesToTheEnd() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.ctrlK)
        XCTAssertEqual(bar.value, "https://duckduckgo.com/duckduckgo-help-pages/")
    }

    func test_optForwardDelete_withSelection_deletesOnlyTheSelection() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.optShiftRight)
        bar.press(EditingKeys.optForwardDelete)
        XCTAssertEqual(bar.value, "https://duckduckgo.com/duckduckgo-help-pages//translation/")
    }

    // MARK: - Caret movement to the string bounds

    func test_ctrlA_andCtrlE_moveTheCaretToTheBounds() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.ctrlA)
        bar.press(EditingKeys.forwardDelete)
        XCTAssertEqual(bar.value, "ttps://duckduckgo.com/duckduckgo-help-pages/results/translation/")
        bar.press(EditingKeys.ctrlE)
        bar.press(EditingKeys.fnDelete)
        XCTAssertEqual(bar.value, "ttps://duckduckgo.com/duckduckgo-help-pages/results/translation")
    }

    func test_typing_afterCmdRight_insertsBeforeTheSuffix() {
        bar.moveCaretToEnd()
        bar.type("!")
        XCTAssertEqual(bar.value, url + "!")
    }

    func test_optRight_pastTheLastWord_staysBeforeTheSuffix() {
        bar.moveCaretToStart()
        bar.press(EditingKeys.optRight, times: 12)
        bar.type("!")
        XCTAssertEqual(bar.value, url + "!")
    }

    func test_arrowKeys_withSelection_collapseToTheSelectionEdges() {
        bar.press(EditingKeys.selectAll)
        bar.press(EditingKeys.right)
        bar.type("!")
        XCTAssertEqual(bar.value, url + "!")
        bar.press(EditingKeys.selectAll)
        bar.press(EditingKeys.left)
        bar.type("!")
        XCTAssertEqual(bar.value, "!" + url + "!")
    }
}

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
