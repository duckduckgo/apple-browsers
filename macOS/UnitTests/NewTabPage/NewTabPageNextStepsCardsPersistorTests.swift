//
//  NewTabPageNextStepsCardsPersistorTests.swift
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

import NewTabPage
import PersistenceTestingUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class NewTabPageNextStepsCardsPersistorTests: XCTestCase {
    private var keyValueStore: MockKeyValueFileStore!
    private var persistor: NewTabPageNextStepsCardsPersistor!

    override func setUp() async throws {
        try await super.setUp()
        keyValueStore = try MockKeyValueFileStore()
        persistor = NewTabPageNextStepsCardsPersistor(keyValueStore: keyValueStore)
    }

    override func tearDown() {
        keyValueStore = nil
        persistor = nil
    }

    // MARK: - Default Values Tests

    func testWhenNoValuesAreStoredThenTimesShownReturnsZero() {
        XCTAssertEqual(persistor.timesShown(for: .defaultApp), 0)
        XCTAssertEqual(persistor.timesShown(for: .addAppToDockMac), 0)
        XCTAssertEqual(persistor.timesShown(for: .duckplayer), 0)
        XCTAssertEqual(persistor.timesShown(for: .emailProtection), 0)
        XCTAssertEqual(persistor.timesShown(for: .bringStuff), 0)
        XCTAssertEqual(persistor.timesShown(for: .subscription), 0)
    }

    func testWhenNoValuesAreStoredThenTimesDismissedReturnsZero() {
        XCTAssertEqual(persistor.timesDismissed(for: .defaultApp), 0)
        XCTAssertEqual(persistor.timesDismissed(for: .addAppToDockMac), 0)
        XCTAssertEqual(persistor.timesDismissed(for: .duckplayer), 0)
        XCTAssertEqual(persistor.timesDismissed(for: .emailProtection), 0)
        XCTAssertEqual(persistor.timesDismissed(for: .bringStuff), 0)
        XCTAssertEqual(persistor.timesDismissed(for: .subscription), 0)
    }

    // MARK: - Times Shown Tests

    func testWhenTimesShownIsSetThenValueIsStored() throws {
        persistor.setTimesShown(5, for: .defaultApp)
        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.defaultApp.card.times.shown") as? Int, 5)

        persistor.setTimesShown(10, for: .duckplayer)
        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.duckplayer.card.times.shown") as? Int, 10)
    }

    func testWhenTimesShownIsRetrievedThenStoredValueIsReturned() throws {
        try keyValueStore.set(3, forKey: "new.tab.page.next.steps.emailProtection.card.times.shown")
        XCTAssertEqual(persistor.timesShown(for: .emailProtection), 3)

        try keyValueStore.set(7, forKey: "new.tab.page.next.steps.bringStuff.card.times.shown")
        XCTAssertEqual(persistor.timesShown(for: .bringStuff), 7)
    }

    func testWhenTimesShownIsIncrementedThenValueIncreasesByOne() throws {
        persistor.setTimesShown(2, for: .subscription)
        persistor.incrementTimesShown(for: .subscription)
        XCTAssertEqual(persistor.timesShown(for: .subscription), 3)
        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.subscription.card.times.shown") as? Int, 3)
    }

    func testWhenTimesShownIsIncrementedMultipleTimesThenValueIncreasesCorrectly() throws {
        persistor.incrementTimesShown(for: .addAppToDockMac)
        XCTAssertEqual(persistor.timesShown(for: .addAppToDockMac), 1)

        persistor.incrementTimesShown(for: .addAppToDockMac)
        XCTAssertEqual(persistor.timesShown(for: .addAppToDockMac), 2)

        persistor.incrementTimesShown(for: .addAppToDockMac)
        XCTAssertEqual(persistor.timesShown(for: .addAppToDockMac), 3)
        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.addAppToDockMac.card.times.shown") as? Int, 3)
    }

    // MARK: - Times Dismissed Tests

    func testWhenTimesDismissedIsSetThenValueIsStored() throws {
        persistor.setTimesDismissed(2, for: .defaultApp)
        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.defaultApp.card.times.dismissed") as? Int, 2)

        persistor.setTimesDismissed(4, for: .emailProtection)
        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.emailProtection.card.times.dismissed") as? Int, 4)
    }

    func testWhenTimesDismissedIsRetrievedThenStoredValueIsReturned() throws {
        try keyValueStore.set(1, forKey: "new.tab.page.next.steps.duckplayer.card.times.dismissed")
        XCTAssertEqual(persistor.timesDismissed(for: .duckplayer), 1)

        try keyValueStore.set(6, forKey: "new.tab.page.next.steps.bringStuff.card.times.dismissed")
        XCTAssertEqual(persistor.timesDismissed(for: .bringStuff), 6)
    }

    func testWhenTimesDismissedIsIncrementedThenValueIncreasesByOne() throws {
        persistor.setTimesDismissed(1, for: .subscription)
        persistor.incrementTimesDismissed(for: .subscription)
        XCTAssertEqual(persistor.timesDismissed(for: .subscription), 2)
        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.subscription.card.times.dismissed") as? Int, 2)
    }

    func testWhenTimesDismissedIsIncrementedMultipleTimesThenValueIncreasesCorrectly() throws {
        persistor.incrementTimesDismissed(for: .defaultApp)
        XCTAssertEqual(persistor.timesDismissed(for: .defaultApp), 1)

        persistor.incrementTimesDismissed(for: .defaultApp)
        XCTAssertEqual(persistor.timesDismissed(for: .defaultApp), 2)

        persistor.incrementTimesDismissed(for: .defaultApp)
        XCTAssertEqual(persistor.timesDismissed(for: .defaultApp), 3)
        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.defaultApp.card.times.dismissed") as? Int, 3)
    }

    // MARK: - Key Generation Tests

    func testWhenCardIsDefaultAppThenKeysAreGeneratedCorrectly() throws {
        persistor.setTimesShown(1, for: .defaultApp)
        persistor.setTimesDismissed(1, for: .defaultApp)

        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.defaultApp.card.times.shown") as? Int, 1)
        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.defaultApp.card.times.dismissed") as? Int, 1)
    }

    func testWhenCardIsAddAppToDockMacThenKeysAreGeneratedCorrectly() throws {
        persistor.setTimesShown(2, for: .addAppToDockMac)
        persistor.setTimesDismissed(2, for: .addAppToDockMac)

        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.addAppToDockMac.card.times.shown") as? Int, 2)
        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.addAppToDockMac.card.times.dismissed") as? Int, 2)
    }

    func testWhenCardIsDuckplayerThenKeysAreGeneratedCorrectly() throws {
        persistor.setTimesShown(3, for: .duckplayer)
        persistor.setTimesDismissed(3, for: .duckplayer)

        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.duckplayer.card.times.shown") as? Int, 3)
        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.duckplayer.card.times.dismissed") as? Int, 3)
    }

    func testWhenCardIsEmailProtectionThenKeysAreGeneratedCorrectly() throws {
        persistor.setTimesShown(4, for: .emailProtection)
        persistor.setTimesDismissed(4, for: .emailProtection)

        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.emailProtection.card.times.shown") as? Int, 4)
        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.emailProtection.card.times.dismissed") as? Int, 4)
    }

    func testWhenCardIsBringStuffThenKeysAreGeneratedCorrectly() throws {
        persistor.setTimesShown(5, for: .bringStuff)
        persistor.setTimesDismissed(5, for: .bringStuff)

        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.bringStuff.card.times.shown") as? Int, 5)
        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.bringStuff.card.times.dismissed") as? Int, 5)
    }

    func testWhenCardIsSubscriptionThenKeysAreGeneratedCorrectly() throws {
        persistor.setTimesShown(6, for: .subscription)
        persistor.setTimesDismissed(6, for: .subscription)

        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.subscription.card.times.shown") as? Int, 6)
        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.subscription.card.times.dismissed") as? Int, 6)
    }

    // MARK: - Ordered Card IDs Tests

    func testWhenNoOrderIsStoredThenOrderedCardIDsReturnsNil() {
        XCTAssertNil(persistor.orderedCardIDs)
    }

    func testWhenOrderedCardIDsIsSetThenRawValueIsStored() throws {
        let cardOrder: [NewTabPageDataModel.CardID] = [.defaultApp, .emailProtection, .duckplayer]
        persistor.orderedCardIDs = cardOrder
        let stored = try keyValueStore.object(forKey: "new.tab.page.next.steps.card.order") as? [String]
        XCTAssertEqual(stored, cardOrder.map { $0.rawValue })
    }

    func testWhenOrderedCardIDsIsRetrievedThenStoredValueIsReturned() throws {
        let cardOrder: [NewTabPageDataModel.CardID] = [.sync, .bringStuff, .subscription]
        try keyValueStore.set(cardOrder.map { $0.rawValue }, forKey: "new.tab.page.next.steps.card.order")
        XCTAssertEqual(persistor.orderedCardIDs, cardOrder)
    }

    // MARK: - First Card Level Tests

    func testWhenNoLevelIsStoredThenFirstCardLevelReturnsLevel1() {
        XCTAssertEqual(persistor.firstCardLevel, .level1)
    }

    func testWhenFirstCardLevelIsSetThenRawValueIsStored() throws {
        let level: NewTabPageDataModel.CardLevel = .level2
        persistor.firstCardLevel = level
        let stored = try keyValueStore.object(forKey: "new.tab.page.next.steps.first.card.level") as? Int
        XCTAssertEqual(stored, level.rawValue)
    }

    func testWhenFirstCardLevelIsRetrievedThenStoredValueIsReturned() throws {
        let level: NewTabPageDataModel.CardLevel = .level2
        try keyValueStore.set(level.rawValue, forKey: "new.tab.page.next.steps.first.card.level")
        XCTAssertEqual(persistor.firstCardLevel, level)
    }

    // MARK: - First Session Tests

    func testIsFirstSessionReturnsTrueByDefault() {
        XCTAssertTrue(persistor.isFirstSession)
    }

    func testWhenIsFirstSessionIsSetThenValueIsStored() throws {
        persistor.isFirstSession = false
        XCTAssertEqual(try keyValueStore.object(forKey: "new.tab.page.next.steps.is.first.session") as? Bool, false)
    }

    func testWhenIsFirstSessionIsRetrievedThenStoredValueIsReturned() throws {
        try keyValueStore.set(false, forKey: "new.tab.page.next.steps.is.first.session")
        XCTAssertEqual(persistor.isFirstSession, false)
    }

    // MARK: - Clear Method Tests

    func testWhenClearIsCalledThenAllCardDataIsRemoved() throws {
        // Set values for all cards
        for card in NewTabPageDataModel.CardID.allCases {
            persistor.setTimesShown(10, for: card)
            persistor.setTimesDismissed(5, for: card)
        }

        // Verify values are stored
        for card in NewTabPageDataModel.CardID.allCases {
            XCTAssertEqual(persistor.timesShown(for: card), 10)
            XCTAssertEqual(persistor.timesDismissed(for: card), 5)
        }

        // Clear all data
        persistor.clear()

        // Verify all values are removed
        for card in NewTabPageDataModel.CardID.allCases {
            XCTAssertEqual(persistor.timesShown(for: card), 0)
            XCTAssertEqual(persistor.timesDismissed(for: card), 0)
        }
    }

    func testWhenClearIsCalledThenShownValuesAreRemoved() throws {
        persistor.setTimesShown(7, for: .defaultApp)
        persistor.setTimesShown(8, for: .duckplayer)
        persistor.setTimesShown(9, for: .emailProtection)

        persistor.clear()

        XCTAssertEqual(persistor.timesShown(for: .defaultApp), 0)
        XCTAssertEqual(persistor.timesShown(for: .duckplayer), 0)
        XCTAssertEqual(persistor.timesShown(for: .emailProtection), 0)
    }

    func testWhenClearIsCalledThenDismissedValuesAreRemoved() throws {
        persistor.setTimesDismissed(3, for: .bringStuff)
        persistor.setTimesDismissed(4, for: .subscription)
        persistor.setTimesDismissed(5, for: .addAppToDockMac)

        persistor.clear()

        XCTAssertEqual(persistor.timesDismissed(for: .bringStuff), 0)
        XCTAssertEqual(persistor.timesDismissed(for: .subscription), 0)
        XCTAssertEqual(persistor.timesDismissed(for: .addAppToDockMac), 0)
    }

    func testWhenClearIsCalledThenOrderedCardIDsIsRemoved() throws {
        let cardOrder: [NewTabPageDataModel.CardID] = [.defaultApp, .emailProtection, .duckplayer]
        persistor.orderedCardIDs = cardOrder
        XCTAssertNotNil(persistor.orderedCardIDs)

        persistor.clear()

        XCTAssertNil(persistor.orderedCardIDs)
        let stored = try? keyValueStore.object(forKey: "new.tab.page.next.steps.card.order") as? [NewTabPageDataModel.CardID]
        XCTAssertNil(stored)
    }

    func testWhenClearIsCalledThenFirstCardLevelIsRemoved() throws {
        persistor.firstCardLevel = .level2
        XCTAssertEqual(persistor.firstCardLevel, .level2)

        persistor.clear()

        XCTAssertEqual(persistor.firstCardLevel, .level1)
        let stored = try? keyValueStore.object(forKey: "new.tab.page.next.steps.first.card.level") as? NewTabPageDataModel.CardLevel
        XCTAssertNil(stored)
    }
}
