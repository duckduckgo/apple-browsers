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
        static let aiChatOmnibarContainerView = "AIChatOmnibarTextContainerViewController.view"
    }

    private let prompt = "alpha beta gamma delta"
    private var bar: EditingDriver!

    /// The Search/Duck.ai toggle setting is stored in the app defaults, so it is enabled once for the whole class (like the
    /// autocomplete setting of the address bar tests) and every test only has to enter Duck.ai mode.
    override class func setUp() {
        super.setUp()
        enableSearchAndDuckAIToggle()
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()
        bar = try enterDuckAIMode()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        app.terminate()
    }

    private static func enableSearchAndDuckAIToggle() {
        let app = XCUIApplication.setUp()
        app.enforceSingleWindow()
        app.addressBar.typeURL(URL(string: "duck://settings/aichat")!)
        let toggle = app.checkBoxes[XCUIApplication.AccessibilityIdentifiers.showSearchAndDuckAIToggleToggle]
        XCTAssertTrue(toggle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Search/Duck.ai toggle setting should exist")
        if toggle.value as? Bool == false {
            toggle.click()
        }
        XCTAssertEqual(toggle.value as? Bool, true, "Search/Duck.ai toggle should be ON")
        app.terminate()
    }

    /// Switches the address bar to Duck.ai mode with Shift+Enter and replaces the carried over text with the test prompt.
    private func enterDuckAIMode() throws -> EditingDriver {
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

/// The text starts either at the left edge or right after the Duck.ai logo, and the first line is ~17 pt from the top, so the mouse
/// tests use a long first word that any click in the first ~170 pt of the line lands on, and a point on the same line past the end
/// of the text for clicks that must put the caret at the end. (The panel height differs between macOS versions, so nothing
/// below the first line is used.)
extension DuckAIOmnibarEditingTests {

    private enum Points {
        static let onFirstWord: CGFloat = 60
        static let firstLineY: CGFloat = 17
        static let pastTheTextX: CGFloat = 300
    }

    private var mouseText: String { "abcdefghijklmnopqrstuvwxyz second" }

    /// Replaces the text; keys right after Select All can lose the first character, so retry until the text matches.
    /// Reading the text selects everything, so the caret is moved to the start afterwards: the clicks must move it.
    private func typeMouseText() {
        for _ in 0..<3 {
            bar.press(EditingKeys.selectAll)
            bar.type(mouseText)
            guard bar.rawValue == mouseText else { continue }
            bar.moveCaretToStart()
            return
        }
        XCTFail("The Duck.ai text view did not accept the typed text")
    }

    func test_doubleClick_onTheFirstWord_selectsTheWord() {
        typeMouseText()
        bar.doubleClick(bar.point(x: Points.onFirstWord, y: Points.firstLineY))
        XCTAssertEqual(bar.selectedText(), "abcdefghijklmnopqrstuvwxyz")
    }

    func test_click_pastTheTextOnTheFirstLine_putsTheCaretAtTheEnd() {
        typeMouseText()
        bar.click(bar.point(x: Points.pastTheTextX, y: Points.firstLineY))
        bar.type("!")
        XCTAssertEqual(bar.rawValue, mouseText + "!")
    }

    func test_shiftClick_pastTheTextOnTheFirstLine_extendsTheSelectionToTheEnd() {
        typeMouseText()
        bar.shiftClick(bar.point(x: Points.pastTheTextX, y: Points.firstLineY))
        XCTAssertEqual(bar.selectedText(), mouseText)
    }

    func test_drag_fromTheFirstWordPastTheTextEnd_selectsTheTail() {
        typeMouseText()
        bar.drag(from: bar.point(x: Points.onFirstWord, y: Points.firstLineY), to: bar.point(x: Points.pastTheTextX, y: Points.firstLineY))
        let selected = bar.selectedText() ?? ""
        XCTAssertFalse(selected.isEmpty, "Dragging over the text should select something")
        XCTAssertTrue(mouseText.hasSuffix(selected), "The selection must end at the end of the text, got \(selected)")
        XCTAssertNotEqual(selected, mouseText)
    }
}
