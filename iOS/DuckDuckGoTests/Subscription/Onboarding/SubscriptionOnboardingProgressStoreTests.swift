//
//  SubscriptionOnboardingProgressStoreTests.swift
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
import Persistence
import PersistenceTestingUtils
@testable import DuckDuckGo

final class SubscriptionOnboardingProgressStoreTests: XCTestCase {

    private var keyValueStore: InMemoryThrowingKeyValueStore!
    private var sut: SubscriptionOnboardingProgressStore!

    override func setUp() {
        super.setUp()
        keyValueStore = InMemoryThrowingKeyValueStore()
        sut = SubscriptionOnboardingProgressStore(keyValueStore: keyValueStore)
    }

    override func tearDown() {
        keyValueStore = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Completed items

    func testWhenNothingIsStoredThenNoItemsAreComplete() {
        XCTAssertTrue(sut.completedItems.isEmpty)
    }

    func testWhenItemsAreStoredThenTheyRoundTrip() {
        sut.completedItems = [.vpn, .duckAI]

        XCTAssertEqual(SubscriptionOnboardingProgressStore(keyValueStore: keyValueStore).completedItems,
                       [.vpn, .duckAI])
    }

    func testWhenMarkingCompleteThenTheItemIsAddedWithoutDisturbingTheOthers() {
        sut.completedItems = [.vpn]

        sut.markComplete(.idtr)

        XCTAssertEqual(sut.completedItems, [.vpn, .idtr])
    }

    func testWhenMarkingTheSameItemTwiceThenTheSetIsUnchanged() {
        sut.markComplete(.vpn)
        sut.markComplete(.vpn)

        XCTAssertEqual(sut.completedItems, [.vpn])
    }

    func testWhenStoredValueContainsAnUnknownItemThenTheRestSurvive() {
        // A downgrade after a new checklist item ships must not wipe the progress that still makes sense.
        try? keyValueStore.set(["vpn", "teleportation", "pir"],
                               forKey: SubscriptionOnboardingProgressStore.Key.completedItems.rawValue)

        XCTAssertEqual(sut.completedItems, [.vpn, .pir])
    }

    func testWhenStoredValueIsTheWrongTypeThenNoItemsAreComplete() {
        try? keyValueStore.set(42, forKey: SubscriptionOnboardingProgressStore.Key.completedItems.rawValue)

        XCTAssertTrue(sut.completedItems.isEmpty)
    }

    // MARK: - Card first shown

    func testWhenCardHasNeverBeenShownThenTheDateIsNil() {
        XCTAssertNil(sut.cardFirstShownDate)
    }

    func testWhenRecordingFirstShownThenTheDateIsStored() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        sut.recordCardFirstShownIfNeeded(now: now)

        XCTAssertEqual(sut.cardFirstShownDate, now)
    }

    func testWhenRecordingFirstShownAgainThenTheOriginalDateIsKept() {
        // The 14-day window is anchored to the first display; a later one must not extend it.
        let first = Date(timeIntervalSince1970: 1_000_000)
        let later = Date(timeIntervalSince1970: 2_000_000)

        sut.recordCardFirstShownIfNeeded(now: first)
        sut.recordCardFirstShownIfNeeded(now: later)

        XCTAssertEqual(sut.cardFirstShownDate, first)
    }

    func testWhenClearingFirstShownThenItIsRemoved() {
        sut.recordCardFirstShownIfNeeded(now: Date())

        sut.cardFirstShownDate = nil

        XCTAssertNil(sut.cardFirstShownDate)
    }
}
