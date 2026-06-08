//
//  OrphanProxyDecisionTests.swift
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

import Foundation
@testable import NetworkProtectionProxy
import XCTest

final class OrphanProxyDecisionTests: XCTestCase {

    private let proxyAgeThreshold: TimeInterval = 60
    private let heartbeatAgeThreshold: TimeInterval = 60

    private func decision(
        proxyAge: TimeInterval = 120,
        heartbeatAge: TimeInterval? = 120,
        bypassEnabled: Bool = true,
        isFullBypassEnabled: Bool = false,
        orphanFiredForCurrentEpisode: Bool = false
    ) -> OrphanProxyDecision? {
        OrphanProxyTester.decision(
            proxyAge: proxyAge,
            heartbeatAge: heartbeatAge,
            bypassEnabled: bypassEnabled,
            isFullBypassEnabled: isFullBypassEnabled,
            orphanFiredForCurrentEpisode: orphanFiredForCurrentEpisode,
            proxyAgeThreshold: proxyAgeThreshold,
            heartbeatAgeThreshold: heartbeatAgeThreshold)
    }

    // MARK: - Proxy age gate

    func testReturnsNilWhenProxyTooYoung() {
        XCTAssertNil(decision(proxyAge: 59, heartbeatAge: nil))
    }

    func testEvaluatesWhenProxyAgeExactlyAtThreshold() {
        XCTAssertNotNil(decision(proxyAge: 60, heartbeatAge: nil))
    }

    // MARK: - Fresh heartbeat (tunnel alive)

    func testFreshHeartbeatLiftsBypassAndResetsLatch() {
        let result = decision(
            heartbeatAge: 10,
            isFullBypassEnabled: true,
            orphanFiredForCurrentEpisode: true)

        XCTAssertEqual(result, OrphanProxyDecision(
            isFullBypassEnabled: false,
            orphanFiredForCurrentEpisode: false,
            shouldFirePixel: false))
    }

    func testHeartbeatExactlyAtThresholdIsStale() {
        // Fresh means strictly under the threshold, so an age equal to it is orphaned.
        let result = decision(heartbeatAge: heartbeatAgeThreshold)
        XCTAssertEqual(result?.isFullBypassEnabled, true)
    }

    // MARK: - Stale heartbeat (orphaned)

    func testStaleHeartbeatEngagesBypassAndFires() {
        let result = decision(heartbeatAge: 120, isFullBypassEnabled: false)

        XCTAssertEqual(result, OrphanProxyDecision(
            isFullBypassEnabled: true,
            orphanFiredForCurrentEpisode: true,
            shouldFirePixel: true))
    }

    func testMissingHeartbeatIsTreatedAsOrphaned() {
        let result = decision(heartbeatAge: nil)
        XCTAssertEqual(result?.isFullBypassEnabled, true)
        XCTAssertEqual(result?.shouldFirePixel, true)
    }

    func testPixelFiresOncePerEpisode() {
        let result = decision(
            heartbeatAge: 120,
            isFullBypassEnabled: true,
            orphanFiredForCurrentEpisode: true)

        // Still orphaned: bypass stays engaged, but the pixel does not re-fire.
        XCTAssertEqual(result?.isFullBypassEnabled, true)
        XCTAssertEqual(result?.shouldFirePixel, false)
    }

    // MARK: - Bypass kill switch

    func testBypassKillSwitchOffStillFiresPixelButDoesNotEngageBypass() {
        let result = decision(
            heartbeatAge: 120,
            bypassEnabled: false,
            isFullBypassEnabled: false)

        XCTAssertEqual(result, OrphanProxyDecision(
            isFullBypassEnabled: false,
            orphanFiredForCurrentEpisode: true,
            shouldFirePixel: true))
    }
}
