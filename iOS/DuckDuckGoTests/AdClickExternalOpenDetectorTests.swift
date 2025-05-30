//
//  AdClickExternalOpenDetectorTests.swift
//  DuckDuckGo
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
@testable import DuckDuckGo

final class AdClickExternalOpenDetectorTests: XCTestCase {

    var detector: AdClickExternalOpenDetector!
    let testTabID = "test-tab"

    override func setUp() {
        super.setUp()
        detector = AdClickExternalOpenDetector(tabID: testTabID, operationTimeout: .seconds(1))
    }

    override func tearDown() {
        detector = nil
        super.tearDown()
    }

    func test_validMitigationSequence_triggersMitigationHandler() {
        let expectation = self.expectation(description: "Mitigation should be triggered")
        detector.mitigationHandler = {
            expectation.fulfill()
        }

        detector.startNavigation()
        detector.failNavigation()
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        waitForExpectations(timeout: 1.0)
    }

    func test_invalidSequence_startThenFinishNavigation_doesNotTriggerMitigation() {
        detector.mitigationHandler = {
            XCTFail("Mitigation should not be triggered")
        }

        detector.startNavigation()
        detector.finishNavigation()
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        // Small delay to allow any async events to fire
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    func test_invalidSequence_startThenLeaveApp_doesNotTriggerMitigation() {
        detector.mitigationHandler = {
            XCTFail("Mitigation should not be triggered")
        }

        detector.startNavigation()
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    func test_timeout_preventsMitigation() {
        let expectation = self.expectation(description: "Mitigation should NOT be triggered")
        expectation.isInverted = true

        detector.mitigationHandler = {
            expectation.fulfill()
        }

        detector.startNavigation()

        // Artificially simulate timeout
        sleep(2) // Exceeds operation timeout
        detector.failNavigation()
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        wait(for: [expectation], timeout: 1.0)
    }

    func test_stateResetsAfterMitigation() {
        let expectation = self.expectation(description: "Mitigation triggered and state reset")

        var triggerCount = 0
        detector.mitigationHandler = {
            triggerCount += 1
            if triggerCount == 1 {
                expectation.fulfill()
            }
        }

        detector.startNavigation()
        detector.failNavigation()
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        waitForExpectations(timeout: 1.0)

        // Try to repeat the same sequence again, should still trigger mitigation
        detector.startNavigation()
        detector.failNavigation()
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertEqual(triggerCount, 2, "Mitigation should be triggered twice after state reset")
    }
}
