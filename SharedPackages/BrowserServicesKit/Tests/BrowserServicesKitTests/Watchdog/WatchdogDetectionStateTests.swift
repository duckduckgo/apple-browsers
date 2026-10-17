//
//  WatchdogDetectionStateTests.swift
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
@testable import BrowserServicesKit

final class WatchdogDetectionStateTests: XCTestCase {

    private let settings = WatchdogSettings(
        checkInterval: 0.5,
        minimumHangDuration: 2.0,
        maximumHangDuration: 5.0,
        requiredRecoveryHeartbeats: 3,
        timeoutRepeatCooldown: 60.0
    )

    private func nextState(
        _ current: WatchdogDetectionState,
        sinceLastHeartbeat: TimeInterval,
        sinceHangStarted: TimeInterval
    ) -> WatchdogDetectionState {
        .nextState(currentState: current, settings: settings, secondsSinceLastHeartbeat: sinceLastHeartbeat, secondsSinceHangStarted: sinceHangStarted)
    }

    // MARK: - Boundary Conditions

    func testStayInCurrentStateAtThresholdBoundaries() {
        XCTAssertEqual(nextState(.responsive, sinceLastHeartbeat: 1.0, sinceHangStarted: 0), .responsive)
        XCTAssertEqual(nextState(.responsive, sinceLastHeartbeat: settings.minimumHangDuration, sinceHangStarted: 0), .responsive)
        XCTAssertEqual(nextState(.hanging, sinceLastHeartbeat: 5.0, sinceHangStarted: settings.maximumHangDuration), .hanging)
        XCTAssertEqual(nextState(.timeout, sinceLastHeartbeat: 6.0, sinceHangStarted: 10), .timeout)
    }

    // MARK: - Full Lifecycle: Hang -> Recovery -> Responsive

    func testHangRecoveryCycle() {
        var state = nextState(.responsive, sinceLastHeartbeat: 3.0, sinceHangStarted: 0)
        XCTAssertEqual(state, .hanging)

        state = nextState(state, sinceLastHeartbeat: 0.5, sinceHangStarted: 4.0)
        XCTAssertEqual(state, .recovery(after: .hanging, heartbeatCount: 0))

        for _ in 0...settings.requiredRecoveryHeartbeats {
            state = nextState(state, sinceLastHeartbeat: 0.3, sinceHangStarted: 4.0)
        }
        XCTAssertEqual(state, .recovered(after: .hanging))

        state = nextState(state, sinceLastHeartbeat: 0.3, sinceHangStarted: 4.0)
        XCTAssertEqual(state, .responsive)
    }

    // MARK: - Full Lifecycle: Hang -> Timeout -> Recovery -> Responsive

    func testTimeoutRecoveryCycle() {
        var state = nextState(.responsive, sinceLastHeartbeat: 3.0, sinceHangStarted: 0)
        XCTAssertEqual(state, .hanging)

        state = nextState(state, sinceLastHeartbeat: 6.0, sinceHangStarted: 6.0)
        XCTAssertEqual(state, .timeout)

        state = nextState(state, sinceLastHeartbeat: 0.5, sinceHangStarted: 7.0)
        XCTAssertEqual(state, .recovery(after: .timeout, heartbeatCount: 0))

        for _ in 0...settings.requiredRecoveryHeartbeats {
            state = nextState(state, sinceLastHeartbeat: 0.3, sinceHangStarted: 7.0)
        }
        XCTAssertEqual(state, .recovered(after: .timeout))

        state = nextState(state, sinceLastHeartbeat: 0.3, sinceHangStarted: 7.0)
        XCTAssertEqual(state, .responsive)
    }

    // MARK: - Recovery Interruption

    func testRecoveryAfterHangingReentersHanging() {
        let state = nextState(.recovery(after: .hanging, heartbeatCount: 2), sinceLastHeartbeat: 3.0, sinceHangStarted: 4.0)
        XCTAssertEqual(state, .hanging)
    }

    func testRecoveryAfterTimeoutResetsCountInstead() {
        let state = nextState(.recovery(after: .timeout, heartbeatCount: 2), sinceLastHeartbeat: 3.0, sinceHangStarted: 11.0)
        XCTAssertEqual(state, .recovery(after: .timeout, heartbeatCount: 0))
    }
}
