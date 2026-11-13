//
//  DuckAIInputFocusTests.swift
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

@MainActor
final class DuckAIInputFocusTests: XCTestCase {

    private var isFocused = false
    private var resignCount = 0
    private var refocusCount = 0
    private var focus: DuckAIInputFocus!

    override func setUp() {
        super.setUp()
        isFocused = false
        resignCount = 0
        refocusCount = 0
        focus = DuckAIInputFocus(
            isFocused: { [unowned self] in isFocused },
            resign: { [unowned self] in
                resignCount += 1
                isFocused = false
            },
            refocus: { [unowned self] in
                refocusCount += 1
                isFocused = true
            }
        )
    }

    func testWhenFocusedInputIsSetAsideThenRestoreGivesFocusBack() {
        isFocused = true

        focus.setAside()
        XCTAssertEqual(resignCount, 1)
        XCTAssertTrue(focus.isSetAside)

        focus.restore()
        XCTAssertEqual(refocusCount, 1)
        XCTAssertFalse(focus.isSetAside)
    }

    func testWhenInputWasNotFocusedThenSetAsideAndRestoreDoNothing() {
        focus.setAside()
        focus.restore()

        XCTAssertEqual(resignCount, 0)
        XCTAssertEqual(refocusCount, 0)
    }

    func testWhenSetAsideFocusIsForgottenThenRestoreDoesNothing() {
        isFocused = true
        focus.setAside()

        focus.forget()
        focus.restore()

        XCTAssertEqual(refocusCount, 0)
    }

    func testWhenRestoredTwiceThenFocusIsGivenBackOnce() {
        isFocused = true
        focus.setAside()

        focus.restore()
        focus.restore()

        XCTAssertEqual(refocusCount, 1)
    }

    func testWhenReleasedThenFocusIsNotRestored() {
        isFocused = true

        focus.release()
        focus.restore()

        XCTAssertEqual(resignCount, 1)
        XCTAssertEqual(refocusCount, 0)
    }

    func testWhenReleasedAfterSetAsideThenEarlierFocusIsDropped() {
        isFocused = true
        focus.setAside()

        focus.release()
        focus.restore()

        XCTAssertEqual(refocusCount, 0)
    }
}
