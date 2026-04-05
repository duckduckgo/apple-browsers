//
//  ConnectionFailureLoopDetectorTests.swift
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

final class ConnectionFailureLoopDetectorTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ConnectionFailureLoopDetectorTests")!
        defaults.removePersistentDomain(forName: "ConnectionFailureLoopDetectorTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "ConnectionFailureLoopDetectorTests")
        defaults = nil
        super.tearDown()
    }

    // MARK: - Feature Flag Off

    func testWhenFeatureDisabled_connectionFailed_returnsFalse() {
        let detector = ConnectionFailureLoopDetector(store: defaults, isFeatureEnabled: false)

        for _ in 1...5 {
            XCTAssertFalse(detector.connectionFailed(isOnDemand: true))
        }
        XCTAssertFalse(detector.connectionLoopDetected)
    }

    func testWhenFeatureDisabled_noStateWrittenToDefaults() {
        let detector = ConnectionFailureLoopDetector(store: defaults, isFeatureEnabled: false)

        _ = detector.connectionFailed(isOnDemand: true)
        _ = detector.connectionFailed(isOnDemand: true)
        _ = detector.connectionFailed(isOnDemand: true)

        XCTAssertEqual(defaults.integer(forKey: ConnectionFailureLoopDetector.Keys.consecutiveFailureCount), 0)
    }

    // MARK: - Threshold Detection

    func testThirdConsecutiveOnDemandFailure_returnsTrue() {
        let detector = ConnectionFailureLoopDetector(store: defaults, isFeatureEnabled: true)

        XCTAssertFalse(detector.connectionFailed(isOnDemand: true))
        XCTAssertFalse(detector.connectionFailed(isOnDemand: true))
        XCTAssertTrue(detector.connectionFailed(isOnDemand: true))
    }

    func testConnectionLoopDetected_isFalseAtThreshold() {
        let detector = ConnectionFailureLoopDetector(store: defaults, isFeatureEnabled: true)

        _ = detector.connectionFailed(isOnDemand: true)
        _ = detector.connectionFailed(isOnDemand: true)
        _ = detector.connectionFailed(isOnDemand: true)

        XCTAssertFalse(detector.connectionLoopDetected)
    }

    func testConnectionLoopDetected_isTrueAfterThreshold() {
        let detector = ConnectionFailureLoopDetector(store: defaults, isFeatureEnabled: true)

        _ = detector.connectionFailed(isOnDemand: true)
        _ = detector.connectionFailed(isOnDemand: true)
        _ = detector.connectionFailed(isOnDemand: true)
        _ = detector.connectionFailed(isOnDemand: true)

        XCTAssertTrue(detector.connectionLoopDetected)
    }

    func testAfterLoopDetected_subsequentFailures_returnFalse() {
        let detector = ConnectionFailureLoopDetector(store: defaults, isFeatureEnabled: true)

        _ = detector.connectionFailed(isOnDemand: true)
        _ = detector.connectionFailed(isOnDemand: true)
        _ = detector.connectionFailed(isOnDemand: true) // triggers

        XCTAssertFalse(detector.connectionFailed(isOnDemand: true))
        XCTAssertFalse(detector.connectionFailed(isOnDemand: true))
        XCTAssertTrue(detector.connectionLoopDetected)
    }

    // MARK: - Reset via Success

    func testConnectionSucceeded_resetsLoopState() {
        let detector = ConnectionFailureLoopDetector(store: defaults, isFeatureEnabled: true)

        _ = detector.connectionFailed(isOnDemand: true)
        _ = detector.connectionFailed(isOnDemand: true)
        _ = detector.connectionFailed(isOnDemand: true)
        _ = detector.connectionFailed(isOnDemand: true)
        XCTAssertTrue(detector.connectionLoopDetected)

        detector.connectionSucceeded()

        XCTAssertFalse(detector.connectionLoopDetected)
        XCTAssertFalse(detector.connectionFailed(isOnDemand: true))
    }

    // MARK: - Reset via Manual Disable

    func testReset_clearsLoopState() {
        let detector = ConnectionFailureLoopDetector(store: defaults, isFeatureEnabled: true)

        _ = detector.connectionFailed(isOnDemand: true)
        _ = detector.connectionFailed(isOnDemand: true)
        _ = detector.connectionFailed(isOnDemand: true)
        _ = detector.connectionFailed(isOnDemand: true)
        XCTAssertTrue(detector.connectionLoopDetected)

        detector.reset()

        XCTAssertFalse(detector.connectionLoopDetected)
        XCTAssertFalse(detector.connectionFailed(isOnDemand: true))
    }

    // MARK: - Reset via Non-On-Demand Failure

    func testNonOnDemandFailure_resetsLoopState() {
        let detector = ConnectionFailureLoopDetector(store: defaults, isFeatureEnabled: true)

        _ = detector.connectionFailed(isOnDemand: true)
        _ = detector.connectionFailed(isOnDemand: true)
        _ = detector.connectionFailed(isOnDemand: true)
        _ = detector.connectionFailed(isOnDemand: true)
        XCTAssertTrue(detector.connectionLoopDetected)

        XCTAssertFalse(detector.connectionFailed(isOnDemand: false))
        XCTAssertFalse(detector.connectionLoopDetected)
    }

    func testNonOnDemandFailure_preventsLoopDetection() {
        let detector = ConnectionFailureLoopDetector(store: defaults, isFeatureEnabled: true)

        _ = detector.connectionFailed(isOnDemand: true)
        _ = detector.connectionFailed(isOnDemand: true)
        _ = detector.connectionFailed(isOnDemand: false) // resets

        XCTAssertFalse(detector.connectionFailed(isOnDemand: true)) // count=1 again
        XCTAssertFalse(detector.connectionLoopDetected)
    }

    // MARK: - Persistence Across Instances

    func testLoopState_persistsAcrossInstances() {
        let detector1 = ConnectionFailureLoopDetector(store: defaults, isFeatureEnabled: true)

        _ = detector1.connectionFailed(isOnDemand: true)
        _ = detector1.connectionFailed(isOnDemand: true)
        _ = detector1.connectionFailed(isOnDemand: true)
        _ = detector1.connectionFailed(isOnDemand: true)
        XCTAssertTrue(detector1.connectionLoopDetected)

        let detector2 = ConnectionFailureLoopDetector(store: defaults, isFeatureEnabled: true)
        XCTAssertTrue(detector2.connectionLoopDetected)
    }

    func testFailureCount_persistsAcrossInstances() {
        let detector1 = ConnectionFailureLoopDetector(store: defaults, isFeatureEnabled: true)

        _ = detector1.connectionFailed(isOnDemand: true)
        _ = detector1.connectionFailed(isOnDemand: true)

        let detector2 = ConnectionFailureLoopDetector(store: defaults, isFeatureEnabled: true)
        XCTAssertTrue(detector2.connectionFailed(isOnDemand: true)) // 3rd failure triggers
        XCTAssertFalse(detector2.connectionLoopDetected) // but suppression doesn't start until 4th
    }
}
