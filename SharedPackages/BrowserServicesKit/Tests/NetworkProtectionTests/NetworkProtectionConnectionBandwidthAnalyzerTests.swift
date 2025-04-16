//
//  NetworkProtectionConnectionBandwidthAnalyzerTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Foundation
import XCTest
@testable import NetworkProtection
import NetworkProtectionTestUtils

final class NetworkProtectionConnectionBandwidthAnalyzerTests: XCTestCase {

    func testBytesPerSecondCalculationIsCorrect() {
        let deltaSeconds = TimeInterval(5)
        let oldDate = Date()
        let newDate = oldDate.addingTimeInterval(deltaSeconds)
        let oldRx = UInt64(1000)
        let newRx = UInt64(2000)
        let oldTx = UInt64(2000)
        let newTx = UInt64(6000)
        let expectedRx = Double(newRx - oldRx) / deltaSeconds
        let expectedTx = Double(newTx - oldTx) / deltaSeconds

        let oldSnapshot = NetworkProtectionConnectionBandwidthAnalyzer.Snapshot(rxBytes: oldRx, txBytes: oldTx, date: oldDate)
        let newSnapshot = NetworkProtectionConnectionBandwidthAnalyzer.Snapshot(rxBytes: newRx, txBytes: newTx, date: newDate)

        let (rx, tx) = NetworkProtectionConnectionBandwidthAnalyzer.bytesPerSecond(newer: newSnapshot, older: oldSnapshot)

        XCTAssertEqual(rx, expectedRx)
        XCTAssertEqual(tx, expectedTx)
    }

    func testBytesPerSecondNoTimeDelta() {
        let deltaSeconds = TimeInterval(0)
        let oldDate = Date()
        let newDate = oldDate.addingTimeInterval(deltaSeconds)
        let oldRx = UInt64(1000)
        let newRx = UInt64(2000)
        let oldTx = UInt64(2000)
        let newTx = UInt64(6000)
        let expectedRx = Double(0)
        let expectedTx = Double(0)

        let oldSnapshot = NetworkProtectionConnectionBandwidthAnalyzer.Snapshot(rxBytes: oldRx, txBytes: oldTx, date: oldDate)
        let newSnapshot = NetworkProtectionConnectionBandwidthAnalyzer.Snapshot(rxBytes: newRx, txBytes: newTx, date: newDate)

        let (rx, tx) = NetworkProtectionConnectionBandwidthAnalyzer.bytesPerSecond(newer: newSnapshot, older: oldSnapshot)

        XCTAssertEqual(rx, expectedRx)
        XCTAssertEqual(tx, expectedTx)
    }
}
