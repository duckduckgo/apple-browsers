//
//  VPNEnabledObserverTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import NetworkExtension
@testable import VPN

final class VPNEnabledObserverTests: XCTestCase {

    // MARK: - Connected Status Tests

    func testIsVPNEnabled_whenConnected_withoutOnDemand_returnsTrue() {
        let result = VPNEnabledObserverThroughSession.isVPNEnabled(
            status: .connected,
            isOnDemandEnabled: false
        )
        XCTAssertTrue(result)
    }

    func testIsVPNEnabled_whenConnected_withOnDemand_returnsTrue() {
        let result = VPNEnabledObserverThroughSession.isVPNEnabled(
            status: .connected,
            isOnDemandEnabled: true
        )
        XCTAssertTrue(result)
    }

    // MARK: - Connecting Status Tests

    func testIsVPNEnabled_whenConnecting_withoutOnDemand_returnsTrue() {
        let result = VPNEnabledObserverThroughSession.isVPNEnabled(
            status: .connecting,
            isOnDemandEnabled: false
        )
        XCTAssertTrue(result)
    }

    // MARK: - Reasserting Status Tests

    func testIsVPNEnabled_whenReasserting_withoutOnDemand_returnsTrue() {
        let result = VPNEnabledObserverThroughSession.isVPNEnabled(
            status: .reasserting,
            isOnDemandEnabled: false
        )
        XCTAssertTrue(result)
    }

    // MARK: - Disconnected with On-Demand Tests

    func testIsVPNEnabled_whenDisconnected_withOnDemand_returnsTrue() {
        let result = VPNEnabledObserverThroughSession.isVPNEnabled(
            status: .disconnected,
            isOnDemandEnabled: true
        )
        XCTAssertTrue(result)
    }

    func testIsVPNEnabled_whenDisconnected_withoutOnDemand_returnsFalse() {
        let result = VPNEnabledObserverThroughSession.isVPNEnabled(
            status: .disconnected,
            isOnDemandEnabled: false
        )
        XCTAssertFalse(result)
    }

    // MARK: - Invalid Status Tests (Edge Case)

    func testIsVPNEnabled_whenInvalid_withOnDemand_returnsFalse() {
        // Edge case: Config deleted but isOnDemandEnabled returns stale true
        let result = VPNEnabledObserverThroughSession.isVPNEnabled(
            status: .invalid,
            isOnDemandEnabled: true
        )
        XCTAssertFalse(result)
    }

    func testIsVPNEnabled_whenInvalid_withoutOnDemand_returnsFalse() {
        let result = VPNEnabledObserverThroughSession.isVPNEnabled(
            status: .invalid,
            isOnDemandEnabled: false
        )
        XCTAssertFalse(result)
    }

    // MARK: - Disconnecting Status Tests

    func testIsVPNEnabled_whenDisconnecting_withOnDemand_returnsTrue() {
        let result = VPNEnabledObserverThroughSession.isVPNEnabled(
            status: .disconnecting,
            isOnDemandEnabled: true
        )
        XCTAssertTrue(result)
    }

    func testIsVPNEnabled_whenDisconnecting_withoutOnDemand_returnsFalse() {
        let result = VPNEnabledObserverThroughSession.isVPNEnabled(
            status: .disconnecting,
            isOnDemandEnabled: false
        )
        XCTAssertFalse(result)
    }
}
