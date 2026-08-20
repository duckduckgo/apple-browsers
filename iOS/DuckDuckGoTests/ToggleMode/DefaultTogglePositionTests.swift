//
//  DefaultTogglePositionTests.swift
//  DuckDuckGoTests
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
import AIChat
import PersistenceTestingUtils
@testable import Core
@testable import DuckDuckGo

// MARK: - TextEntryMode Display Gating

final class TextEntryModeDisplayTests: XCTestCase {

    func testAIChatFallsBackToSearchWhenSearchInputDisabled() {
        XCTAssertEqual(TextEntryMode.aiChat.displayed(isAIChatSearchInputEnabled: false), .search)
    }

    func testAIChatPreservedWhenSearchInputEnabled() {
        XCTAssertEqual(TextEntryMode.aiChat.displayed(isAIChatSearchInputEnabled: true), .aiChat)
    }

    func testSearchAlwaysPreserved() {
        XCTAssertEqual(TextEntryMode.search.displayed(isAIChatSearchInputEnabled: true), .search)
        XCTAssertEqual(TextEntryMode.search.displayed(isAIChatSearchInputEnabled: false), .search)
    }
}

// MARK: - DefaultOmnibarMode Resolution

final class DefaultOmnibarModeResolutionTests: XCTestCase {

    func testSearchModeAlwaysResolvesToSearch() {
        let result = DefaultOmnibarMode.search.resolvedTextEntryMode { .aiChat }
        XCTAssertEqual(result, .search)
    }

    func testDuckAIModeAlwaysResolvesToAIChat() {
        let result = DefaultOmnibarMode.duckAI.resolvedTextEntryMode { .search }
        XCTAssertEqual(result, .aiChat)
    }

    func testLastUsedModeResolvesToStoredValue() {
        let resultAI = DefaultOmnibarMode.lastUsed.resolvedTextEntryMode { .aiChat }
        XCTAssertEqual(resultAI, .aiChat)

        let resultSearch = DefaultOmnibarMode.lastUsed.resolvedTextEntryMode { .search }
        XCTAssertEqual(resultSearch, .search)
    }

    func testLastUsedModeDefaultsToSearchWhenNil() {
        let result = DefaultOmnibarMode.lastUsed.resolvedTextEntryMode { nil }
        XCTAssertEqual(result, .search)
    }
}

// MARK: - ToggleModeStorage

final class ToggleModeStorageTests: XCTestCase {

    func testSaveAndRestore() {
        let store = MockKeyValueStore()
        let sut = ToggleModeStorage(store: store)

        sut.save(.aiChat)
        XCTAssertEqual(sut.restore(), .aiChat)

        sut.save(.search)
        XCTAssertEqual(sut.restore(), .search)
    }

    func testRestoreReturnsNilWhenEmpty() {
        let store = MockKeyValueStore()
        let sut = ToggleModeStorage(store: store)

        XCTAssertNil(sut.restore())
    }
}
