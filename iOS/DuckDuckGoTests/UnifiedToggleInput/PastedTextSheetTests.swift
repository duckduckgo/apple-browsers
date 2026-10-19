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
