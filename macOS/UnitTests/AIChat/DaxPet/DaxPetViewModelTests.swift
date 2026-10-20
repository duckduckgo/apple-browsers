//
//  DaxPetViewModelTests.swift
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

import AppKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
private final class RecordingDaxPetPromptSubmitter: DaxPetPromptSubmitting {
    var submittedPrompts: [String] = []
    var openDuckAICount = 0
    var onSubmit: (() -> Void)?

    func submit(prompt: String) {
        submittedPrompts.append(prompt)
        onSubmit?()
    }

    func openDuckAI() {
        openDuckAICount += 1
    }
}

@MainActor
final class DaxPetViewModelTests: XCTestCase {

    private var submitter: RecordingDaxPetPromptSubmitter!
    private var model: DaxPetViewModel!

    override func setUp() {
        super.setUp()
        submitter = RecordingDaxPetPromptSubmitter()
        model = DaxPetViewModel(submitter: submitter, character: DaxCharacterView(reduceMotion: { true }))
        model.submissionDelay = 0
    }

    override func tearDown() {
        model = nil
        submitter = nil
        super.tearDown()
    }

    func testWhenDaxIsClickedThenPromptFieldOpensAndAsksForKeyboard() {
        var keyboardRequests = 0
        model.onNeedsKeyboard = { keyboardRequests += 1 }

        model.characterClicked()

        XCTAssertTrue(model.isComposing)
        XCTAssertEqual(model.character.mood, .listening)
        XCTAssertEqual(model.speech, UserText.daxPetGreeting)
        XCTAssertEqual(keyboardRequests, 1)
    }

    func testWhenDaxIsClickedWhileComposingThenPromptFieldCloses() {
        model.characterClicked()
        model.prompt = "draft"

        model.characterClicked()

        XCTAssertFalse(model.isComposing)
        XCTAssertEqual(model.prompt, "")
        XCTAssertEqual(model.character.mood, .idle)
        XCTAssertNil(model.speech)
    }

    func testWhenTypingThenDaxWatchesTheCaretAndStopsTalking() {
        var requestedWidths: [CGFloat] = []
        model.caretLocation = { width in
            requestedWidths.append(width)
            return NSPoint(x: 100 + width, y: 10)
        }
        model.startComposing()

        model.prompt = "Hello"

        XCTAssertNil(model.speech)
        XCTAssertGreaterThan(requestedWidths.last ?? 0, 0)
        XCTAssertEqual(model.character.lookTarget, NSPoint(x: 100 + (requestedWidths.last ?? 0), y: 10))
    }

    func testWhenPromptIsSubmittedThenItIsTrimmedAndHandedToDuckAI() {
        let submitted = expectation(description: "submitted")
        submitter.onSubmit = { submitted.fulfill() }
        model.startComposing()
        model.prompt = "  What's a duck?  \n"

        model.submit()

        XCTAssertFalse(model.isComposing)
        XCTAssertEqual(model.character.mood, .thinking)
        XCTAssertEqual(model.speech, UserText.daxPetThinking)
        wait(for: [submitted], timeout: 1)
        XCTAssertEqual(submitter.submittedPrompts, ["What's a duck?"])
        XCTAssertEqual(model.character.mood, .idle)
        XCTAssertNil(model.speech)
    }

    func testWhenPromptIsBlankThenNothingIsSubmitted() {
        model.startComposing()
        model.prompt = "   "

        model.submit()

        XCTAssertTrue(model.isComposing)
        XCTAssertTrue(submitter.submittedPrompts.isEmpty)
    }

    func testWhenFocusIsLostWithADraftThenTheDraftIsKept() {
        model.startComposing()
        model.prompt = "draft"

        model.keyboardFocusLost()

        XCTAssertTrue(model.isComposing)
        XCTAssertEqual(model.prompt, "draft")
    }

    func testWhenFocusIsLostWithoutADraftThenPromptFieldCloses() {
        model.startComposing()

        model.keyboardFocusLost()

        XCTAssertFalse(model.isComposing)
    }

    func testWhenHiddenThenComposingEndsAndOwnerIsTold() {
        var hideCount = 0
        model.onHide = { hideCount += 1 }
        model.startComposing()

        model.hide()

        XCTAssertFalse(model.isComposing)
        XCTAssertEqual(hideCount, 1)
    }

    func testWhenOpenDuckAIIsTappedThenANewChatOpens() {
        model.openDuckAI()

        XCTAssertEqual(submitter.openDuckAICount, 1)
    }
}
