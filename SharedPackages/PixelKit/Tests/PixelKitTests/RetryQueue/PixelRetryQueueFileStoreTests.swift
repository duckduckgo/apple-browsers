//
//  PixelRetryQueueFileStoreTests.swift
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
@testable import PixelKit

final class PixelRetryQueueFileStoreTests: XCTestCase {

    private var storageURL: URL!
    private var store: PixelRetryQueueFileStore!

    override func setUp() {
        super.setUp()
        let directory = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString.appending(".json")
        storageURL = directory.appendingPathComponent(fileName)
        store = PixelRetryQueueFileStore(fileName: fileName, storageDirectory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storageURL)
        super.tearDown()
    }

    private func item(named name: String) -> PixelRetryQueueItem {
        PixelRetryQueueItem(pixelName: name,
                            headers: [:],
                            parameters: ["p": name],
                            allowedQueryReservedCharacters: nil,
                            timestamp: Date())
    }

    func testWhenStoringItem_ThenItCanBeReadBack() throws {
        let item = item(named: "test")
        try store.append([item])
        XCTAssertEqual(try store.storedItems(), [item])
    }

    func testWhenStoringMultipleItems_ThenTheyAreReadBackInOrder() throws {
        let items = [item(named: "a"), item(named: "b"), item(named: "c")]
        try store.append(items)
        XCTAssertEqual(try store.storedItems(), items)
    }

    func testWhenAppendingPastTheLimitIncrementally_ThenOldestAreDropped() throws {
        let limit = PixelRetryQueueFileStore.Constants.itemCountLimit
        for index in 1...(limit + 50) {
            try store.append([item(named: "pixel\(index)")])
        }
        let stored = try store.storedItems()
        XCTAssertEqual(stored.count, limit)
        XCTAssertEqual(stored.first?.pixelName, "pixel51")
        XCTAssertEqual(stored.last?.pixelName, "pixel\(limit + 50)")
    }

    func testWhenAppendingPastTheLimitInOneBatch_ThenOldestAreDropped() throws {
        let limit = PixelRetryQueueFileStore.Constants.itemCountLimit
        let items = (1...(limit + 50)).map { item(named: "pixel\($0)") }
        try store.append(items)
        let stored = try store.storedItems()
        XCTAssertEqual(stored.count, limit)
        XCTAssertEqual(stored.first?.pixelName, "pixel51")
        XCTAssertEqual(stored.last?.pixelName, "pixel\(limit + 50)")
    }

    func testWhenRemovingFromEmptyStore_ThenNothingHappens() throws {
        try store.remove(itemsWithIDs: [UUID()])
        XCTAssertEqual(try store.storedItems(), [])
    }

    func testWhenRemovingNonMatchingID_ThenItemIsRetained() throws {
        let item = item(named: "test")
        try store.append([item])
        try store.remove(itemsWithIDs: [UUID()])
        XCTAssertEqual(try store.storedItems(), [item])
    }

    func testWhenRemovingMatchingID_ThenItemIsRemoved() throws {
        let item = item(named: "test")
        try store.append([item])
        try store.remove(itemsWithIDs: [item.id])
        XCTAssertEqual(try store.storedItems(), [])
    }
}
