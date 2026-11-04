//
//  SuggestionListKeyboardSelectionTests.swift
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

final class SuggestionListKeyboardSelectionTests: XCTestCase {

    func testWhenNoSelectionAndNextThenFirstItemIsSelected() {
        XCTAssertEqual(SuggestionListKeyboardSelection.next(after: nil, in: [1, 2, 3]), 1)
    }

    func testWhenNextFromMiddleThenAdvancesByOne() {
        XCTAssertEqual(SuggestionListKeyboardSelection.next(after: 2, in: [1, 2, 3]), 3)
    }

    func testWhenNextAtLastThenClampsToLast() {
        XCTAssertEqual(SuggestionListKeyboardSelection.next(after: 3, in: [1, 2, 3]), 3)
    }

    func testWhenNextOnEmptyListThenReturnsNil() {
        XCTAssertNil(SuggestionListKeyboardSelection.next(after: nil, in: [Int]()))
    }

    func testWhenNextFromSelectionNotInListThenSelectionIsUnchanged() {
        XCTAssertEqual(SuggestionListKeyboardSelection.next(after: 99, in: [1, 2, 3]), 99)
    }

    func testWhenNoSelectionAndPreviousThenStaysUnselected() {
        XCTAssertNil(SuggestionListKeyboardSelection.previous(before: nil, in: [1, 2, 3]))
    }

    func testWhenPreviousFromMiddleThenRetreatsByOne() {
        XCTAssertEqual(SuggestionListKeyboardSelection.previous(before: 2, in: [1, 2, 3]), 1)
    }

    func testWhenPreviousAtFirstThenClampsToFirst() {
        XCTAssertEqual(SuggestionListKeyboardSelection.previous(before: 1, in: [1, 2, 3]), 1)
    }

    func testWhenPreviousFromSelectionNotInListThenSelectionIsUnchanged() {
        XCTAssertEqual(SuggestionListKeyboardSelection.previous(before: 99, in: [1, 2, 3]), 99)
    }

}
