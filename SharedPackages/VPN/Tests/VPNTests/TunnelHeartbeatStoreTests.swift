//
//  TunnelHeartbeatStoreTests.swift
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
@testable import VPN

final class TunnelHeartbeatStoreTests: XCTestCase {

    private static let suiteName = "TunnelHeartbeatStoreTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.suiteName)
        defaults = nil
        super.tearDown()
    }

    func testLastHeartbeat_isNilBeforeAnyWrite() {
        let store = TunnelHeartbeatStore(store: defaults)
        XCTAssertNil(store.lastHeartbeat)
    }

    func testRecordHeartbeat_storesGeneratedDate() {
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let store = TunnelHeartbeatStore(store: defaults, dateGenerator: { fixed })

        store.recordHeartbeat()

        XCTAssertEqual(store.lastHeartbeat?.timeIntervalSince1970, fixed.timeIntervalSince1970)
    }

    func testRecordHeartbeat_overwritesPreviousValue() {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = TunnelHeartbeatStore(store: defaults, dateGenerator: { now })

        store.recordHeartbeat()
        now = Date(timeIntervalSince1970: 1_700_000_060)
        store.recordHeartbeat()

        XCTAssertEqual(store.lastHeartbeat?.timeIntervalSince1970, 1_700_000_060)
    }

    func testClear_removesStoredHeartbeat() {
        let store = TunnelHeartbeatStore(store: defaults)
        store.recordHeartbeat()
        XCTAssertNotNil(store.lastHeartbeat)

        store.clear()

        XCTAssertNil(store.lastHeartbeat)
    }

    func testLastHeartbeat_persistsAcrossInstances() {
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let writer = TunnelHeartbeatStore(store: defaults, dateGenerator: { fixed })
        writer.recordHeartbeat()

        let reader = TunnelHeartbeatStore(store: defaults)
        XCTAssertEqual(reader.lastHeartbeat?.timeIntervalSince1970, fixed.timeIntervalSince1970)
    }
}
