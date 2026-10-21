//
//  PastedTextSheetTests.swift
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

import AIChat
import SwiftUI
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class PastedTextSheetTests: XCTestCase {

    private let original = AIChatPastedText(content: "original text")

    func testSaveIsOffWhenBlankOrOverTheLimitAndOnOtherwise() {
        let rules = PastedTextSheetRules(original: original, mode: .editable(limit: 10))

        XCTAssertFalse(rules.canSave(""))
        XCTAssertFalse(rules.canSave(" \n\t"))
        XCTAssertFalse(rules.canSave("12345678901"))
        XCTAssertTrue(rules.canSave("1234567890"))
    }

    func testSaveIsNeverOfferedInViewOnlyMode() {
        let rules = PastedTextSheetRules(original: original, mode: .viewOnly)

        XCTAssertFalse(rules.canSave("fine"))
        XCTAssertFalse(rules.isOverLimit(String(repeating: "a", count: 100_000)))
    }

    func testSavingIdenticalContentIsUnchangedAndAnEditIsANewValue() {
        let rules = PastedTextSheetRules(original: original, mode: .editable(limit: 100))

        XCTAssertEqual(rules.outcome(savingText: "original text"), .unchanged)
        guard case .saved(let edited) = rules.outcome(savingText: "edited") else { return XCTFail("Expected a saved outcome") }
        XCTAssertEqual(edited.content, "edited")
        XCTAssertNotEqual(edited.id, original.id, "A new id so id-based draft equality sees the edit")
    }

    func testEditableSheetOpensWithTheKeyboardAndViewOnlyDoesNot() {
        let paste = AIChatPastedText(content: "pasted")
        XCTAssertTrue(PastedTextSheetRules(original: paste, mode: .editable(limit: 100)).opensWithKeyboard)
        XCTAssertFalse(PastedTextSheetRules(original: paste, mode: .viewOnly).opensWithKeyboard)
    }

    func testViewOnlySheetShowsTheFullTextInAScrollableReadOnlyViewAndEditableKeepsTheEditor() throws {
        let content = String(repeating: "line\n", count: 2_000)
        let viewOnly = try textView(hosting: .viewOnly, content: content)
        XCTAssertFalse(viewOnly.isEditable)
        XCTAssertTrue(viewOnly.isScrollEnabled, "Reading past the first screen needs scrolling")
        XCTAssertTrue(viewOnly.isSelectable)
        XCTAssertEqual(viewOnly.text, content)

        let editable = try textView(hosting: .editable(limit: 100_000), content: content)
        XCTAssertTrue(editable.isEditable)
        XCTAssertEqual(editable.text, content)
    }

    private func textView(hosting mode: PastedTextSheetMode, content: String) throws -> UITextView {
        let view = PastedTextSheetView(pastedText: AIChatPastedText(content: content), mode: mode, onSave: { _ in }, onCancel: {})
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        return try XCTUnwrap(firstDescendant(of: UITextView.self, in: controller.view), "The sheet shows its text in a UITextView")
    }

    private func firstDescendant<T: UIView>(of type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { self.firstDescendant(of: type, in: $0) }.first
    }

    func testCountIsUTF16() {
        let rules = PastedTextSheetRules(original: original, mode: .editable(limit: 100))

        XCTAssertEqual(rules.count(of: "😀"), 2)
    }

    func testHostingControllerReportsOneOutcomeHoweverItCloses() {
        var outcomes: [PastedTextSheetOutcome] = []
        let view = PastedTextSheetView(pastedText: original, mode: .editable(limit: 100), onSave: { _ in }, onCancel: {})
        let controller = PastedTextSheetHostingController(rootView: view) { outcomes.append($0) }

        controller.finish(.saved(AIChatPastedText(content: "edited")))
        controller.viewDidDisappear(false)

        XCTAssertEqual(outcomes.count, 1)
        guard case .saved(let saved) = outcomes.first else { return XCTFail("Expected the saved outcome to win") }
        XCTAssertEqual(saved.content, "edited")
    }

    func testHostingControllerReportsUnchangedWhenDismissedWithoutSaving() {
        var outcomes: [PastedTextSheetOutcome] = []
        let view = PastedTextSheetView(pastedText: original, mode: .editable(limit: 100), onSave: { _ in }, onCancel: {})
        let controller = PastedTextSheetHostingController(rootView: view) { outcomes.append($0) }

        controller.viewDidDisappear(false)
        controller.viewDidDisappear(false)

        XCTAssertEqual(outcomes, [.unchanged])
    }

    func testCharacterCountStringsReadNaturally() {
        XCTAssertEqual(UserText.aiChatPastedTextCharacterCount(1), "1 character")
        XCTAssertEqual(UserText.aiChatPastedTextCharacterCount(2), "2 characters")
        XCTAssertEqual(UserText.aiChatPastedTextOverLimitCount(count: 16800, limit: 16000), "16800/16000 characters", "No grouping separators, as in the footer")
    }

    func testPresenterPresentsFromTheTopmostControllerAboveTheHost() {
        let host = UIViewController()
        let presented = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.present(presented, animated: false)

        XCTAssertTrue(PastedTextSheetPresenter.topmost(from: host) === presented)
    }
}
