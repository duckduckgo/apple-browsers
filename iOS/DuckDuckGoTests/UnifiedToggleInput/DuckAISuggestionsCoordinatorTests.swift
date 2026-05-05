//
//  DuckAISuggestionsCoordinatorTests.swift
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

final class DuckAISuggestionsCoordinatorTests: XCTestCase {

    func test_hasSettled_returnsFalseWhenOnlyChatHasSettled() {
        XCTAssertFalse(DuckAISuggestionsCoordinator.hasSettled(
            forQuery: "wp", chatLastQuery: "wp", urlLastQuery: nil
        ))
    }

    func test_hasSettled_returnsFalseWhenOnlyURLHasSettled() {
        XCTAssertFalse(DuckAISuggestionsCoordinator.hasSettled(
            forQuery: "wp", chatLastQuery: nil, urlLastQuery: "wp"
        ))
    }

    func test_hasSettled_returnsTrueWhenBothSettledForCurrentQuery() {
        XCTAssertTrue(DuckAISuggestionsCoordinator.hasSettled(
            forQuery: "wp", chatLastQuery: "wp", urlLastQuery: "wp"
        ))
    }

    func test_hasSettled_returnsFalseWhenBothSettledForStaleQuery() {
        XCTAssertFalse(DuckAISuggestionsCoordinator.hasSettled(
            forQuery: "wp", chatLastQuery: "w", urlLastQuery: "w"
        ))
    }
}
