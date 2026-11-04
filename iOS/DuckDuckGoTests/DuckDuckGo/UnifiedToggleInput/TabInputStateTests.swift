//
//  TabInputStateTests.swift
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

final class TabInputStateTests: XCTestCase {

    func test_default_isEmpty() {
        let sut = TabInputState()
        XCTAssertEqual(sut.text, "")
        XCTAssertEqual(sut.toggleMode, .search)
        XCTAssertTrue(sut.attachments.isEmpty)
        XCTAssertNil(sut.selectedModelID)
        XCTAssertNil(sut.selectedReasoningMode)
        XCTAssertNil(sut.selectedTool)
        XCTAssertFalse(sut.isModelPickerForcedVisible)
    }

    func test_equatable_sameValues_areEqual() {
        let a = TabInputState(text: "hi", toggleMode: .aiChat)
        let b = TabInputState(text: "hi", toggleMode: .aiChat)
        XCTAssertEqual(a, b)
    }

    func test_equatable_differingText_areNotEqual() {
        let a = TabInputState(text: "a")
        let b = TabInputState(text: "b")
        XCTAssertNotEqual(a, b)
    }
}
