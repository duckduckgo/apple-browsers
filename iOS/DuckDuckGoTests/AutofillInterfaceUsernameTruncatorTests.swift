//
//  AutofillInterfaceUsernameTruncatorTests.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

class AutofillInterfaceUsernameTruncatorTests: XCTestCase {

    func testWhenUsernameIsShorterThanMaxLengthThenNotTruncated() {
        let username = "daxTheDuck"
        let expectedUsername = "daxTheDuck"

        let result = AutofillInterfaceUsernameTruncator.truncateUsername(username, maxLength: 20)
        XCTAssertEqual(expectedUsername, result, "usernames should match")
    }

    func testWhenUsernameIsTheSameLengthAsMaxLengthThenNotTruncated() {
        let username = "daxTheDuck"
        let expectedUsername = "daxTheDuck"

        let result = AutofillInterfaceUsernameTruncator.truncateUsername(username, maxLength: 10)
        XCTAssertEqual(expectedUsername, result, "usernames should match")
    }

    func testWhenUsernameIsLongerThanMaxLengthThenTruncated() {
        let username = "daxTheDuckTheBestDuckYouCouldEverMeet"
        // 19-char prefix + 1-char ellipsis (`…`) = 20 chars (matches maxLength).
        // The previous ASCII `...` ellipsis (3 chars) only allowed a 17-char
        // prefix; the shorter Unicode ellipsis lets us keep two more chars
        // of the original username.
        let expectedUsername = "daxTheDuckTheBestDu…"

        let result = AutofillInterfaceUsernameTruncator.truncateUsername(username, maxLength: 20)
        XCTAssertEqual(expectedUsername, result, "usernames should match")
    }

    func testWhenUsernameIsOneCharacterLongerThanMaxLengthThenTruncated() {
        let username = "daxTheDuck1"
        // 9-char prefix + 1-char ellipsis (`…`) = 10 chars (matches maxLength).
        let expectedUsername = "daxTheDuc…"

        let result = AutofillInterfaceUsernameTruncator.truncateUsername(username, maxLength: 10)
        XCTAssertEqual(expectedUsername, result, "usernames should match")
    }

    func testWhenUsernameIsEmptyThenNotTruncated() {
        let username = ""
        let expectedUsername = ""

        let result = AutofillInterfaceUsernameTruncator.truncateUsername(username, maxLength: 20)
        XCTAssertEqual(expectedUsername, result, "usernames should match")
    }
}
