//
//  DefaultBrowserConfirmationStoreTests.swift
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

final class DefaultBrowserConfirmationStoreTests: XCTestCase {

    private static let key = "default-browser-win-back.pending-confirmation"

    private var keyValueStore: MockThrowingKeyValueStore!
    private var pixelFiring: PixelKitMock!
    private var sut: DefaultBrowserConfirmationStore!

    override func setUp() {
        super.setUp()
        keyValueStore = MockThrowingKeyValueStore()
        pixelFiring = PixelKitMock()
        sut = DefaultBrowserConfirmationStore(source: .winBack, keyValueStore: keyValueStore, pixelFiring: pixelFiring)
    }

    override func tearDown() {
        sut = nil
        pixelFiring = nil
        keyValueStore = nil
        super.tearDown()
    }

    func testWhenPendingConfirmationSetThenItRoundTrips() {
        let pending = DefaultBrowserPendingConfirmation(clickDate: Date(timeIntervalSince1970: 1_000_000), nextCheck: .nextActivation)

        sut.pendingConfirmation = pending

        XCTAssertEqual(sut.pendingConfirmation, pending)
    }

    func testWhenPendingConfirmationSetToNilThenKeyIsRemoved() {
        sut.pendingConfirmation = DefaultBrowserPendingConfirmation(clickDate: Date(), nextCheck: .afterClick)

        sut.pendingConfirmation = nil

        XCTAssertNil(keyValueStore.underlyingDict[Self.key])
    }

    func testWhenStoredValueIsCorruptThenReadsNilFiresReadFailedAndRemovesIt() {
        keyValueStore.underlyingDict[Self.key] = Data("not json".utf8)

        XCTAssertNil(sut.pendingConfirmation)
        assertSingleFailurePixel(named: "default-browser-win-back_pending-confirmation_read-failed_macos")
        XCTAssertNil(keyValueStore.underlyingDict[Self.key])
    }

    func testWhenWriteFailsThenWriteFailedPixelFires() {
        keyValueStore.shouldThrowOnSet = true

        sut.pendingConfirmation = DefaultBrowserPendingConfirmation(clickDate: Date(), nextCheck: .afterClick)

        assertSingleFailurePixel(named: "default-browser-win-back_pending-confirmation_write-failed_macos")
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
