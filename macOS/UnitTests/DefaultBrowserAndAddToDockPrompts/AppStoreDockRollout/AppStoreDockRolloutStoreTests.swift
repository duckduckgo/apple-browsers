//
//  AppStoreDockRolloutStoreTests.swift
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
@_spi(Testing) import Persistence
@_spi(Testing) import PixelKit
@testable import DuckDuckGo_Privacy_Browser

final class AppStoreDockRolloutStoreTests: XCTestCase {

    private typealias Key = AppStoreDockRolloutStore.Key

    private var keyValueStore: MockThrowingKeyValueStore!
    private var pixelFiring: PixelKitMock!
    private var sut: AppStoreDockRolloutStore!

    override func setUp() {
        super.setUp()
        keyValueStore = MockThrowingKeyValueStore()
        pixelFiring = PixelKitMock()
        sut = AppStoreDockRolloutStore(keyValueStore: keyValueStore, pixelFiring: pixelFiring)
    }

    override func tearDown() {
        sut = nil
        pixelFiring = nil
        keyValueStore = nil
        super.tearDown()
    }

    func testWhenPendingCheckSetThenItRoundTrips() {
        let pending = AppStoreDockRolloutPendingCheck(arm: .combined, shownDate: Date(timeIntervalSince1970: 1_000_000))

        sut.pendingCheck = pending

        XCTAssertEqual(sut.pendingCheck, pending)
    }

    func testWhenPendingCheckSetToNilThenKeyIsRemoved() {
        sut.pendingCheck = AppStoreDockRolloutPendingCheck(arm: .setAsDefault, shownDate: Date())

        sut.pendingCheck = nil

        XCTAssertNil(keyValueStore.underlyingDict[Key.pendingCheck])
    }

    func testWhenLastShownPromptIDSetThenItRoundTrips() {
        sut.lastShownPromptID = "combined-banner-1"

        XCTAssertEqual(sut.lastShownPromptID, "combined-banner-1")

        sut.lastShownPromptID = nil

        XCTAssertNil(keyValueStore.underlyingDict[Key.lastShownPromptID])
    }

    func testWhenStoredPendingCheckIsCorruptThenReadsNilFiresReadFailedAndRemovesIt() {
        keyValueStore.underlyingDict[Key.pendingCheck] = Data("not json".utf8)

        XCTAssertNil(sut.pendingCheck)
        assertSingleFailurePixel(named: "app-store-dock-rollout_store_read-failed_macos")
        XCTAssertNil(keyValueStore.underlyingDict[Key.pendingCheck])
    }

    func testWhenStoredLastShownPromptIDHasWrongTypeThenReadsNilFiresReadFailedAndRemovesIt() {
        keyValueStore.underlyingDict[Key.lastShownPromptID] = 1

        XCTAssertNil(sut.lastShownPromptID)
        assertSingleFailurePixel(named: "app-store-dock-rollout_store_read-failed_macos")
        XCTAssertNil(keyValueStore.underlyingDict[Key.lastShownPromptID])
    }

    func testWhenWriteFailsThenWriteFailedPixelFires() {
        keyValueStore.shouldThrowOnSet = true

        sut.pendingCheck = AppStoreDockRolloutPendingCheck(arm: .combined, shownDate: Date())

        assertSingleFailurePixel(named: "app-store-dock-rollout_store_write-failed_macos")
    }

    private func assertSingleFailurePixel(named name: String, file: StaticString = #filePath, line: UInt = #line) {
        let calls = pixelFiring.actualFireCalls
        XCTAssertEqual(calls.count, 1, file: file, line: line)
        XCTAssertEqual(calls.first?.pixel.name, name, file: file, line: line)
        XCTAssertEqual(calls.first?.pixel.namePrefix, PixelKitNamePrefix.none, file: file, line: line)
        XCTAssertNotNil(calls.first?.pixel.error, file: file, line: line)
        XCTAssertEqual(calls.first?.frequency, .dailyAndCount, file: file, line: line)
    }
}
