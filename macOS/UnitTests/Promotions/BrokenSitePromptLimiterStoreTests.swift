//
//  BrokenSitePromptLimiterStoreTests.swift
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

@_spi(Testing) import Persistence
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class BrokenSitePromptLimiterStoreTests: XCTestCase {

    private static let legacyShownDateKey = "brokenSitePrompt.last-broken-site-toast-shown-date"
    private static let legacyStreakKey = "brokenSitePrompt.toast-dismiss-streak-counter"

    private var keyValueStore: InMemoryKeyValueStore!

    override func setUp() {
        super.setUp()
        keyValueStore = InMemoryKeyValueStore()
    }

    override func tearDown() {
        keyValueStore = nil
        super.tearDown()
    }

    private func makeSUT() -> BrokenSitePromptLimiterStore {
        BrokenSitePromptLimiterStore(storage: KeyedStorage(storage: keyValueStore))
    }

    func testWhenNoStoredValuesThenDefaultsAreReturned() {
        let sut = makeSUT()

        XCTAssertEqual(sut.lastToastShownDate, .distantPast)
        XCTAssertEqual(sut.toastDismissStreakCounter, 0)
    }

    func testWhenValuesWrittenThenTheyRoundTrip() {
        let sut = makeSUT()
        let shownDate = Date(timeIntervalSince1970: 1_700_000_000)

        sut.lastToastShownDate = shownDate
        sut.toastDismissStreakCounter = 2

        XCTAssertEqual(makeSUT().lastToastShownDate, shownDate)
        XCTAssertEqual(makeSUT().toastDismissStreakCounter, 2)
    }

    /// Users upgrading mid-cooldown must keep their shipped values, or the prompt re-shows early.
    func testWhenLegacyKeysPresentThenValuesAreMigratedAndLegacyKeysRemoved() {
        let shownDate = Date(timeIntervalSince1970: 1_700_000_000)
        keyValueStore.set(shownDate, forKey: Self.legacyShownDateKey)
        keyValueStore.set(2, forKey: Self.legacyStreakKey)

        let sut = makeSUT()

        XCTAssertEqual(sut.lastToastShownDate, shownDate)
        XCTAssertEqual(sut.toastDismissStreakCounter, 2)
        XCTAssertNil(keyValueStore.object(forKey: Self.legacyShownDateKey))
        XCTAssertNil(keyValueStore.object(forKey: Self.legacyStreakKey))
    }
}
