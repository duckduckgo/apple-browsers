//
//  AIChatMentionTokenDetectorTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

final class AIChatMentionTokenDetectorTests: XCTestCase {

    // MARK: - Caret at end of token

    func testEmptyInputCaretZero_ThenNoToken() {
        XCTAssertNil(AIChatMentionTokenDetector.token(in: "", caret: 0))
    }

    func testLoneAtSign_CaretAtEnd_ThenEmptyQueryTokenAtStart() {
        let token = AIChatMentionTokenDetector.token(in: "@", caret: 1)
        XCTAssertEqual(token, AIChatMentionToken(range: NSRange(location: 0, length: 1), query: ""))
    }

    func testAtSignFollowedByQuery_CaretAtEnd_ThenQueryReturned() {
        let token = AIChatMentionTokenDetector.token(in: "@foo", caret: 4)
        XCTAssertEqual(token, AIChatMentionToken(range: NSRange(location: 0, length: 4), query: "foo"))
    }

    func testAtSignAfterSpace_CaretAtEnd_ThenTokenStartsAtAt() {
        // "summarize @goo" — caret at end (14)
        let token = AIChatMentionTokenDetector.token(in: "summarize @goo", caret: 14)
        XCTAssertEqual(token, AIChatMentionToken(range: NSRange(location: 10, length: 4), query: "goo"))
    }

    // MARK: - Caret elsewhere

    func testCaretInsideToken_ThenQueryIsPrefixUpToCaret() {
        // "@google" — caret after "@goo" (position 4)
        let token = AIChatMentionTokenDetector.token(in: "@google", caret: 4)
        XCTAssertEqual(token, AIChatMentionToken(range: NSRange(location: 0, length: 4), query: "goo"))
    }

    func testCaretBeforeAt_ThenNoToken() {
        // "abc @goo" — caret right before the `@` at position 4
        XCTAssertNil(AIChatMentionTokenDetector.token(in: "abc @goo", caret: 4))
    }

    func testCaretPastTokenAfterWhitespace_ThenTokenIncludesSpaces() {
        // "@goo bar|" — caret at 8. Per multi-word support: whitespace inside the token
        // doesn't end it; the token extends from `@` all the way to the caret.
        let token = AIChatMentionTokenDetector.token(in: "@goo bar", caret: 8)
        XCTAssertEqual(token, AIChatMentionToken(range: NSRange(location: 0, length: 8), query: "goo bar"))
    }

    func testMultiWordQuery_AcrossMultipleSpaces() {
        let token = AIChatMentionTokenDetector.token(in: "@apple plus settings", caret: 20)
        XCTAssertEqual(token, AIChatMentionToken(range: NSRange(location: 0, length: 20), query: "apple plus settings"))
    }

    func testMultiWordQuery_AfterLeadingPrompt() {
        let token = AIChatMentionTokenDetector.token(in: "summarize @apple plus", caret: 21)
        XCTAssertEqual(token, AIChatMentionToken(range: NSRange(location: 10, length: 11), query: "apple plus"))
    }

    func testTokenStopsAtNewline() {
        // Newline terminates the token — the `@` on the previous line is not the active
        // trigger for a caret on a later line.
        XCTAssertNil(AIChatMentionTokenDetector.token(in: "@goo\nbar", caret: 8))
    }

    func testMultiWordQueryAfterNewline() {
        // A new `@`-token on the second line works just like one at start-of-input.
        let token = AIChatMentionTokenDetector.token(in: "first line\n@goo plus", caret: 20)
        XCTAssertEqual(token, AIChatMentionToken(range: NSRange(location: 11, length: 9), query: "goo plus"))
    }

    // MARK: - Not preceded by whitespace

    func testAtSignAfterLetter_ThenNoToken() {
        // Classic email — should NOT trigger.
        XCTAssertNil(AIChatMentionTokenDetector.token(in: "foo@bar.com", caret: 11))
    }

    func testAtSignAfterPunctuation_ThenNoToken() {
        // Punctuation isn't whitespace — the `@` is mid-word, no trigger.
        XCTAssertNil(AIChatMentionTokenDetector.token(in: "x:@goo", caret: 6))
    }

    // MARK: - Multiple `@` characters

    func testDoubleAtSign_ThenLeftmostIsTrigger_QueryIncludesTrailingAt() {
        // "@@goo" — leftmost `@` at start-of-input wins; second `@` is part of the query.
        let token = AIChatMentionTokenDetector.token(in: "@@goo", caret: 5)
        XCTAssertEqual(token, AIChatMentionToken(range: NSRange(location: 0, length: 5), query: "@goo"))
    }

    func testTwoSeparateAtSignsAcrossWhitespace_ThenSecondIsActiveToken() {
        // "@foo @bar" with caret at end — the second `@bar` is the active token because the
        // caret is inside it; the first `@foo` is already a "completed" token.
        let token = AIChatMentionTokenDetector.token(in: "@foo @bar", caret: 9)
        XCTAssertEqual(token, AIChatMentionToken(range: NSRange(location: 5, length: 4), query: "bar"))
    }

    // MARK: - Whitespace boundary variants

    func testAtSignAfterTab_ThenTriggers() {
        let token = AIChatMentionTokenDetector.token(in: "x\t@y", caret: 4)
        XCTAssertEqual(token, AIChatMentionToken(range: NSRange(location: 2, length: 2), query: "y"))
    }

    func testAtSignAfterNewline_ThenTriggers() {
        let token = AIChatMentionTokenDetector.token(in: "first line\n@goo", caret: 15)
        XCTAssertEqual(token, AIChatMentionToken(range: NSRange(location: 11, length: 4), query: "goo"))
    }

    // MARK: - Token characters

    func testTokenAllowsDigitsDashesAndSlashes() {
        // Tab titles can contain anything-but-whitespace; the filter should pass them through.
        let token = AIChatMentionTokenDetector.token(in: "@docs/foo-2", caret: 11)
        XCTAssertEqual(token, AIChatMentionToken(range: NSRange(location: 0, length: 11), query: "docs/foo-2"))
    }

    // MARK: - Caret bounds

    func testCaretBeforeStart_ThenNoToken() {
        XCTAssertNil(AIChatMentionTokenDetector.token(in: "@foo", caret: -1))
    }

    func testCaretBeyondEnd_ThenNoToken() {
        XCTAssertNil(AIChatMentionTokenDetector.token(in: "@foo", caret: 100))
    }
}
