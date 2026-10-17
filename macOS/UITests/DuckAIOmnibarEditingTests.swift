//
//  DuckAIOmnibarEditingTests.swift
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

/// Selection, caret movement and delete patterns of the Duck.ai mode of the address bar (the omnibar text view).
/// It is a standard text view, so it must behave like any macOS text field: there is no suffix and words are separated by spaces.
class DuckAIOmnibarEditingTests: UITestCase {

    private enum AccessibilityIdentifiers {
        static let showSearchAndDuckAIToggle = "Preferences.AIChat.showSearchAndDuckAIToggleToggle"
        static let aiChatOmnibarContainerView = "AIChatOmnibarTextContainerViewController.view"
    }

    private let prompt = "alpha beta gamma delta"
    private var bar: EditingDriver!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()
        try enableSearchAndDuckAIToggle()
        bar = try enterDuckAIMode()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        app.terminate()
    }

    private func enableSearchAndDuckAIToggle() throws {
        app.addressBar.typeURL(try XCTUnwrap(URL(string: "duck://settings/aichat")))
        let toggle = app.checkBoxes[AccessibilityIdentifiers.showSearchAndDuckAIToggle]
        XCTAssertTrue(toggle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Search/Duck.ai toggle setting should exist")
        if toggle.value as? Bool == false {
            toggle.click()
        }
        XCTAssertEqual(toggle.value as? Bool, true, "Search/Duck.ai toggle should be ON")
        app.typeKey("w", modifierFlags: .command)
    }

    /// Switches the address bar to Duck.ai mode with Shift+Enter and replaces the carried over text with the test prompt.
    private func enterDuckAIMode() throws -> EditingDriver {
        app.openNewTab()
        app.activateAddressBar()
        app.addressBar.typeText("test query")
        app.typeKey(.return, modifierFlags: .shift)

        // The existence check is on the container view because that is the reliably queryable element under XCUI
        let container = app.windows.firstMatch.descendants(matching: .any)[AccessibilityIdentifiers.aiChatOmnibarContainerView]
        XCTAssertTrue(container.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Duck.ai panel should appear")
        // The container hides the text view from the accessibility tree: the keys go to the focused text view through the app
        // and its contents are read by copying.
        let driver = EditingDriver(element: app, readsContentByCopying: true, mouseTarget: container)
        // Keys sent right after the switch can be lost until the text view takes focus: retry replacing the text
        for _ in 0..<3 {
            driver.press(EditingKeys.selectAll)
            driver.type(prompt)
            if driver.rawValue == prompt { return driver }
        }
        XCTFail("The Duck.ai text view did not accept the typed prompt")
        return driver
    }

    private func repeated(_ key: EditingKey, _ times: Int) -> [EditingKey] {
        Array(repeating: key, count: times)
    }

    // MARK: - Opt+Shift+Left/Right selection by word

    func test_optShiftLeft_fromEnd_selectsWordsBackwards() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.optShiftLeft)
        XCTAssertEqual(bar.selectedText(), "delta")
        bar.press(EditingKeys.optShiftLeft)
        XCTAssertEqual(bar.selectedText(), "gamma delta")
        bar.press(EditingKeys.optShiftLeft, times: 5)
        XCTAssertEqual(bar.selectedText(), prompt)
    }

    func test_optShiftRight_fromStart_selectsWordsForwards() {
        bar.moveCaretToStart()
        bar.press(EditingKeys.optShiftRight)
        XCTAssertEqual(bar.selectedText(), "alpha")
        bar.press(EditingKeys.optShiftRight)
        XCTAssertEqual(bar.selectedText(), "alpha beta")
        bar.press(EditingKeys.optShiftRight, times: 5)
        XCTAssertEqual(bar.selectedText(), prompt)
    }

    func test_optShiftLeft_fromMiddle_extendsLeft() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.optShiftLeft)
        XCTAssertEqual(bar.selectedText(), "beta ")
        bar.press(EditingKeys.optShiftLeft)
        XCTAssertEqual(bar.selectedText(), "alpha beta ")
    }

    func test_optShiftRight_fromMiddle_extendsRight() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.optShiftRight)
        XCTAssertEqual(bar.selectedText(), "gamma")
        bar.press(EditingKeys.optShiftRight)
        XCTAssertEqual(bar.selectedText(), "gamma delta")
    }

    func test_optShiftRight_afterOptShiftLeft_contractsFromTheLeft() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(repeated(EditingKeys.optShiftLeft, 2))
        bar.press(EditingKeys.optShiftRight)
        XCTAssertEqual(bar.selectedText(), " beta ")
    }

    func test_optShiftLeft_afterOptShiftRight_contractsFromTheRight_andCollapsesTheSelection() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.optShiftRight)
        bar.press(EditingKeys.optShiftLeft)
        XCTAssertNil(bar.selectedText(), "Contracting a one word selection leaves a caret")
        bar.press(EditingKeys.backspace)
        XCTAssertEqual(bar.rawValue, "alpha betagamma delta")
    }

    // MARK: - Contracting a select-all selection

    /// Unlike the address bar, a plain `NSTextView` keeps its select-all selection anchored at the right end,
    /// so Opt+Shift+Left has nothing to extend and does not contract it. This pins the native behavior.
    func test_optShiftLeft_afterSelectAll_keepsTheSelection() {
        bar.press(EditingKeys.selectAll)
        bar.press(EditingKeys.optShiftLeft)
        XCTAssertEqual(bar.selectedText(), prompt)
    }

    func test_optShiftRight_afterCmdShiftLeft_contractsFromTheLeft() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.cmdShiftLeft)
        bar.press(EditingKeys.optShiftRight)
        XCTAssertEqual(bar.selectedText(), " beta gamma delta")
    }

    // MARK: - Cmd+Shift+Left/Right and Shift+Left/Right selection

    func test_cmdShiftLeft_selectsToTheStart() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.cmdShiftLeft)
        XCTAssertEqual(bar.selectedText(), "alpha beta ")
    }

    func test_cmdShiftRight_selectsToTheEnd() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.cmdShiftRight)
        XCTAssertEqual(bar.selectedText(), "gamma delta")
    }

    func test_shiftLeft_andShiftRight_selectCharacters() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.shiftLeft, times: 5)
        XCTAssertEqual(bar.selectedText(), "delta")
        bar.press(EditingKeys.shiftRight, times: 2)
        XCTAssertEqual(bar.selectedText(), "lta")
    }

    // MARK: - Backward delete

    func test_backspace_atTheStart_deletesNothing() {
        bar.moveCaretToStart()
        bar.press([EditingKeys.backspace, EditingKeys.fnDelete, EditingKeys.optDelete, EditingKeys.cmdDelete, EditingKeys.ctrlH])
        XCTAssertEqual(bar.rawValue, prompt)
    }

    func test_backspace_atTheEnd_deletesOneCharacter() {
        bar.moveCaretToEnd()
        bar.press([EditingKeys.fnDelete, EditingKeys.ctrlH])
        XCTAssertEqual(bar.rawValue, "alpha beta gamma del")
    }

    func test_optDelete_atTheEnd_deletesTheLastWord() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.optDelete)
        XCTAssertEqual(bar.rawValue, "alpha beta gamma ")
    }

    func test_cmdDelete_fromMiddle_deletesToTheStart() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.cmdDelete)
        XCTAssertEqual(bar.rawValue, "gamma delta")
    }

    func test_cmdDelete_atTheEnd_deletesEverything() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.cmdDelete)
        XCTAssertEqual(bar.rawValue, "")
    }

    func test_optDelete_withSelection_deletesOnlyTheSelection() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.optShiftRight)
        bar.press(EditingKeys.optDelete)
        XCTAssertEqual(bar.rawValue, "alpha beta  delta")
    }

    // MARK: - Forward delete

    func test_forwardDelete_atTheEnd_deletesNothing() {
        bar.moveCaretToEnd()
        bar.press([EditingKeys.forwardDelete, EditingKeys.optForwardDelete, EditingKeys.cmdForwardDelete, EditingKeys.ctrlD, EditingKeys.ctrlK])
        XCTAssertEqual(bar.rawValue, prompt)
    }

    func test_forwardDelete_atTheStart_deletesOneCharacter() {
        bar.moveCaretToStart()
        bar.press([EditingKeys.forwardDelete, EditingKeys.ctrlD])
        XCTAssertEqual(bar.rawValue, "pha beta gamma delta")
    }

    func test_optForwardDelete_atTheStart_deletesTheFirstWord() {
        bar.moveCaretToStart()
        bar.press(EditingKeys.optForwardDelete)
        XCTAssertEqual(bar.rawValue, " beta gamma delta")
    }

    func test_ctrlK_fromMiddle_deletesToTheEnd() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.ctrlK)
        XCTAssertEqual(bar.rawValue, "alpha beta ")
    }

    func test_optForwardDelete_withSelection_deletesOnlyTheSelection() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.optShiftRight)
        bar.press(EditingKeys.optForwardDelete)
        XCTAssertEqual(bar.rawValue, "alpha beta  delta")
    }

    // MARK: - Caret movement to the string bounds

    func test_ctrlA_andCtrlE_moveTheCaretToTheBounds() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.ctrlA)
        bar.type("<")
        bar.press(EditingKeys.ctrlE)
        bar.type(">")
        XCTAssertEqual(bar.rawValue, "<" + prompt + ">")
    }

    func test_optRight_pastTheLastWord_staysAtTheEnd() {
        bar.moveCaretToStart()
        bar.press(EditingKeys.optRight, times: 8)
        bar.type("!")
        XCTAssertEqual(bar.rawValue, prompt + "!")
    }

    func test_arrowKeys_withSelection_collapseToTheSelectionEdges() {
        bar.press(EditingKeys.selectAll)
        bar.press(EditingKeys.right)
        bar.type("!")
        XCTAssertEqual(bar.rawValue, prompt + "!")
        bar.press(EditingKeys.selectAll)
        bar.press(EditingKeys.left)
        bar.type("!")
        XCTAssertEqual(bar.rawValue, "!" + prompt + "!")
    }
}

// MARK: - Remaining positions

extension DuckAIOmnibarEditingTests {

    func test_optShiftLeft_atTheStart_selectsNothing() {
        bar.moveCaretToStart()
        bar.press(EditingKeys.optShiftLeft)
        XCTAssertNil(bar.selectedText())
    }

    func test_optShiftRight_atTheEnd_selectsNothing() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.optShiftRight)
        XCTAssertNil(bar.selectedText())
    }

    func test_shiftLeft_andShiftRight_fromMiddle_selectOneCharacter() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.shiftRight)
        XCTAssertEqual(bar.selectedText(), "g")
        bar.press(EditingKeys.left)
        bar.press(EditingKeys.shiftLeft)
        XCTAssertEqual(bar.selectedText(), " ")
    }

    func test_cmdShiftLeft_fromEnd_andCmdShiftRight_fromStart_selectEverything() {
        bar.moveCaretToEnd()
        bar.press(EditingKeys.cmdShiftLeft)
        XCTAssertEqual(bar.selectedText(), prompt)
        bar.moveCaretToStart()
        bar.press(EditingKeys.cmdShiftRight)
        XCTAssertEqual(bar.selectedText(), prompt)
    }

    func test_optDelete_fromMiddle_deletesThePreviousWord() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.optDelete)
        XCTAssertEqual(bar.rawValue, "alpha gamma delta")
    }

    func test_optForwardDelete_fromMiddle_deletesTheNextWord() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.optForwardDelete)
        XCTAssertEqual(bar.rawValue, "alpha beta  delta")
    }

    func test_backspace_fromMiddle_deletesOneCharacterBack() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press([EditingKeys.fnDelete, EditingKeys.ctrlH])
        XCTAssertEqual(bar.rawValue, "alpha bet" + "gamma delta")
    }

    func test_forwardDelete_fromMiddle_deletesOneCharacterForward() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press([EditingKeys.forwardDelete, EditingKeys.ctrlD])
        XCTAssertEqual(bar.rawValue, "alpha beta mma delta")
    }

    func test_cmdDelete_andCmdForwardDelete_withSelection_deleteOnlyTheSelection() {
        bar.moveCaretTwoWordsFromEnd()
        bar.press(EditingKeys.optShiftRight)
        bar.press(EditingKeys.cmdDelete)
        XCTAssertEqual(bar.rawValue, "alpha beta  delta")
    }
}

// MARK: - Mouse selection

extension DuckAIOmnibarEditingTests {

    private enum Points {
        static let firstWord: CGFloat = 40
        static let textLineY: CGFloat = 28
        static let afterText: CGFloat = -20
        static let belowText: CGFloat = -15
    }

    func test_doubleClick_onTheFirstWord_selectsTheWord() {
        bar.doubleClick(bar.point(x: Points.firstWord, y: Points.textLineY))
        XCTAssertEqual(bar.selectedText(), "alpha")
    }

    func test_tripleClick_selectsTheWholePrompt() {
        bar.tripleClick(bar.point(x: Points.firstWord, y: Points.textLineY))
        XCTAssertEqual(bar.selectedText(), prompt)
    }

    func test_click_belowTheText_putsTheCaretAtTheEnd() {
        bar.click(bar.point(x: Points.afterText, y: Points.belowText))
        bar.type("!")
        XCTAssertEqual(bar.rawValue, prompt + "!")
    }

    func test_drag_acrossTheText_selectsEverything() {
        bar.drag(from: bar.point(x: 12, y: Points.textLineY), to: bar.point(x: Points.afterText, y: Points.belowText))
        XCTAssertEqual(bar.selectedText(), prompt)
    }

    func test_shiftClick_afterTheText_extendsTheSelectionToTheEnd() {
        bar.moveCaretToStart()
        bar.shiftClick(bar.point(x: Points.afterText, y: Points.belowText))
        XCTAssertEqual(bar.selectedText(), prompt)
    }
}
