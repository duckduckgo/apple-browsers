//
//  MultiTabMentionTokenTests.swift
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

import XCTest
@testable import DuckDuckGo

final class MultiTabMentionTokenTests: XCTestCase {
    func testWhenCaretIsInsideMentionThenReturnsOnlyTextThroughCaretWithUTF16Range() throws {
        let text = "\u{1F680} Compare @wikipedia afterwards"
        let expectedRange = (text as NSString).range(of: "@wiki")
        let selection = NSRange(location: NSMaxRange(expectedRange), length: 0)

        let token = try XCTUnwrap(MultiTabMentionToken.token(in: text, selection: selection))

        XCTAssertEqual(token.query, "wiki")
        XCTAssertEqual(token.range, expectedRange)
        XCTAssertEqual((text as NSString).substring(with: token.range), "@wiki")
    }

    func testWhenMentionStartsAtTextOrWhitespaceBoundaryThenReturnsQueryIncludingSpaces() throws {
        for prefix in ["", "Compare ", "Compare\t", "Compare\n"] {
            let text = prefix + "@new york "
            let token = try XCTUnwrap(MultiTabMentionToken.token(
                in: text, selection: NSRange(location: (text as NSString).length, length: 0)), prefix)

            XCTAssertEqual(token.query, "new york ", prefix)
            XCTAssertEqual(token.range, (text as NSString).range(of: "@new york "), prefix)
        }
        XCTAssertEqual(MultiTabMentionToken.token(in: "@", selection: NSRange(location: 1, length: 0))?.query, "")
    }

    func testWhenCaretHasNoValidMentionThenReturnsNil() {
        for text in ["", "ordinary text", "user@example.com", "@wiki\nnext", "@wiki\rnext", "@wiki\u{2028}next"] {
            XCTAssertNil(MultiTabMentionToken.token(
                in: text, selection: NSRange(location: (text as NSString).length, length: 0)), text)
        }
        XCTAssertNil(MultiTabMentionToken.token(in: "@wiki", selection: NSRange(location: 0, length: 0)))
        XCTAssertNil(MultiTabMentionToken.token(in: "@wiki", selection: NSRange(location: 1, length: 4)))
    }
}
