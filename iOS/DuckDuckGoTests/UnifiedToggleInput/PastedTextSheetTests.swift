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

    func testEditableSubtitleGivesTheCompactCountAgainstTheCompactLimit() {
        let en = Locale(identifier: "en_US")
        let rules = PastedTextSheetRules(original: original, mode: .editable(limit: 16_000))

        XCTAssertEqual(rules.subtitle(for: text(1_234), locale: en), .size("1.2k of 16k characters"))
        XCTAssertEqual(rules.subtitle(for: text(850), locale: en), .size("850 of 16k characters"))
        XCTAssertEqual(rules.subtitle(for: text(16_000), locale: en), .size("16k of 16k characters"), "At the limit is not over it")
    }

    func testEditableSubtitleUsesTheLowerLimitTheRestOfThePromptLeaves() {
        let rules = PastedTextSheetRules(original: original, mode: .editable(limit: 4_500))

        XCTAssertEqual(rules.subtitle(for: text(1_234), locale: Locale(identifier: "en_US")), .size("1.2k of 4.5k characters"))
    }

    func testOverLimitSubtitleGivesTheExactCountAgainstTheExactLimit() {
        let rules = PastedTextSheetRules(original: original, mode: .editable(limit: 16_000))

        XCTAssertEqual(rules.subtitle(for: text(16_001)), .overLimit(count: 16_001, limit: 16_000))
        XCTAssertEqual(String(format: UserText.aiChatPromptTooLongCountFormat, 15_487, 16_000), "15487/16000", "No grouping separators, as in the footer")
    }

    func testViewOnlySubtitleGivesTheSizeWithoutALimit() {
        let en = Locale(identifier: "en_US")
        let rules = PastedTextSheetRules(original: original, mode: .viewOnly)

        XCTAssertEqual(rules.subtitle(for: text(1_234), locale: en), .size("1.2k characters"))
        XCTAssertEqual(rules.subtitle(for: text(100_000), locale: en), .size("100k characters"), "View-only is never over a limit")
        XCTAssertEqual(rules.subtitle(for: text(1), locale: en), .size("1 character"))
    }

    func testTitleOffersEditingOnlyWhenTheTextCanChange() {
        XCTAssertEqual(PastedTextSheetRules(original: original, mode: .editable(limit: 100)).title, "Edit Text")
        XCTAssertEqual(PastedTextSheetRules(original: original, mode: .viewOnly).title, "Pasted Text")
    }

    private func text(_ count: Int) -> String { String(repeating: "a", count: count) }

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
