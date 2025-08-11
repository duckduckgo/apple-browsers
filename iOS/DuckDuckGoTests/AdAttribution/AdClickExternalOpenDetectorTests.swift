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
        detector.failNavigation(error: NSError(domain: "WebKitErrorDomain", code: 102))
        detector.appDidEnterBackground()

        waitForExpectations(timeout: 1.0)
    }

    func test_invalidSequence_startThenFinishNavigation_doesNotTriggerMitigation() {
        let expectation = self.expectation(description: "Mitigation should not be triggered")
        expectation.isInverted = true
        
        detector.mitigationHandler = {
            expectation.fulfill()
        }

        detector.startNavigation()
        detector.finishNavigation()
        detector.appDidEnterBackground()

        wait(for: [expectation], timeout: 0.5)
    }

    func test_invalidSequence_startThenLeaveApp_doesNotTriggerMitigation() {
        let expectation = self.expectation(description: "Mitigation should not be triggered")
        expectation.isInverted = true
        
        detector.mitigationHandler = {
            expectation.fulfill()
        }

        detector.startNavigation()
        detector.appDidEnterBackground()

        wait(for: [expectation], timeout: 0.5)
    }

    func test_timeout_preventsMitigation() {
        let expectation = self.expectation(description: "Mitigation should NOT be triggered")
        expectation.isInverted = true

        // Use a very short timeout for this test
        detector = AdClickExternalOpenDetector(tabID: testTabID, operationTimeout: .milliseconds(10))
        detector.mitigationHandler = {
            expectation.fulfill()
        }
        detector.startNavigation()
        detector.failNavigation(error: NSError(domain: "WebKitErrorDomain", code: 102))
        // Allow timeout to elapse
        let timeoutExpectation = self.expectation(description: "Timeout elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            timeoutExpectation.fulfill()
        }
        wait(for: [timeoutExpectation], timeout: 0.1)
        detector.appDidEnterBackground()

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
        detector.failNavigation(error: NSError(domain: "WebKitErrorDomain", code: 102))
        detector.appDidEnterBackground()

        waitForExpectations(timeout: 1.0)

        // Try to repeat the same sequence again, should still trigger mitigation
        detector.startNavigation()
        detector.failNavigation(error: NSError(domain: "WebKitErrorDomain", code: 102))
        detector.appDidEnterBackground()

        XCTAssertEqual(triggerCount, 2, "Mitigation should be triggered twice after state reset")
    }
    
    // MARK: - Error Validation Tests
    
    func test_wrongErrorDomain_doesNotTriggerMitigation() {
        let expectation = self.expectation(description: "Mitigation should not be triggered for wrong error domain")
        expectation.isInverted = true
        
        detector.mitigationHandler = {
            expectation.fulfill()
        }
        
        detector.startNavigation()
        detector.failNavigation(error: NSError(domain: "NSURLErrorDomain", code: 102))
        detector.appDidEnterBackground()
        
        wait(for: [expectation], timeout: 0.5)
    }
    
    func test_wrongErrorCode_doesNotTriggerMitigation() {
        let expectation = self.expectation(description: "Mitigation should not be triggered for wrong error code")
        expectation.isInverted = true
        
        detector.mitigationHandler = {
            expectation.fulfill()
        }
        
        detector.startNavigation()
        detector.failNavigation(error: NSError(domain: "WebKitErrorDomain", code: 101))
        detector.appDidEnterBackground()
        
        wait(for: [expectation], timeout: 0.5)
    }
    
    func test_correctWebKitError102_triggersMitigation() {
        let expectation = self.expectation(description: "Mitigation should be triggered for correct WebKit error")
        detector.mitigationHandler = {
            expectation.fulfill()
        }
        
        detector.startNavigation()
        detector.failNavigation(error: NSError(domain: "WebKitErrorDomain", code: 102))
        detector.appDidEnterBackground()
        
        waitForExpectations(timeout: 1.0)
    }
    
    func test_otherWebKitErrorCodes_doNotTriggerMitigation() {
        let otherWebKitErrors = [100, 101, 103, 200, 404, 500]
        
        detector.mitigationHandler = {
            XCTFail("Mitigation should not be triggered for other WebKit error codes")
        }
        
        let expectation = self.expectation(description: "Mitigation should not be triggered for other WebKit error codes")
        expectation.isInverted = true
        
        for errorCode in otherWebKitErrors {
            detector.startNavigation()
            detector.failNavigation(error: NSError(domain: "WebKitErrorDomain", code: errorCode))
            detector.appDidEnterBackground()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - User Interaction Invalidation Tests
    
    func test_userInteractionInvalidation_preventsDetection() {
        let expectation = self.expectation(description: "Mitigation should not be triggered after user interaction invalidation")
        expectation.isInverted = true
        
        detector.mitigationHandler = {
            expectation.fulfill()
        }
        
        detector.startNavigation()
        detector.invalidateForUserInitiated()
        detector.failNavigation(error: NSError(domain: "WebKitErrorDomain", code: 102))
        detector.appDidEnterBackground()
        
        wait(for: [expectation], timeout: 0.5)
    }
    
    func test_userInteractionAfterStart_preventsDetection() {
        let expectation = self.expectation(description: "Mitigation should not be triggered when user interaction occurs after start")
        expectation.isInverted = true
        
        detector.mitigationHandler = {
            expectation.fulfill()
        }

        detector.invalidateForUserInitiated()
        detector.startNavigation() // Try to start again after invalidation
        detector.failNavigation(error: NSError(domain: "WebKitErrorDomain", code: 102))
        detector.appDidEnterBackground()
        
        wait(for: [expectation], timeout: 0.5)
    }
    
    func test_userInteractionResetsState() {

        // User interacts, should reset and skip detection
        detector.invalidateForUserInitiated()
        
        // New navigation should work normally after reset
        detector.mitigationHandler = {
            XCTFail("Mitigation shouldn't be triggered after user interaction reset")
        }
        
        detector.startNavigation()
        detector.failNavigation(error: NSError(domain: "WebKitErrorDomain", code: 102))
        detector.appDidEnterBackground()
    }
    
    func test_userInteractionDuringFailedState_preventsDetection() {
        let expectation = self.expectation(description: "Mitigation should not be triggered when user interaction occurs during failed state")
        expectation.isInverted = true
        
        detector.mitigationHandler = {
            expectation.fulfill()
        }
        
        detector.startNavigation()
        detector.failNavigation(error: NSError(domain: "WebKitErrorDomain", code: 102))
        detector.invalidateForUserInitiated() // User interacts after failure but before background
        detector.appDidEnterBackground()

        wait(for: [expectation], timeout: 0.5)
    }
    
    // MARK: - Edge Case Tests
    
    func test_multipleStartNavigations_resetsState() {
        let expectation = self.expectation(description: "Mitigation should not be triggered after multiple start navigations")
        expectation.isInverted = true
        
        detector.mitigationHandler = {
            expectation.fulfill()
        }
        
        detector.startNavigation()
        detector.startNavigation() // Second start should reset state
        detector.failNavigation(error: NSError(domain: "WebKitErrorDomain", code: 102))
        detector.appDidEnterBackground()
        
        wait(for: [expectation], timeout: 0.5)
    }
    
    func test_backgroundNotificationWithoutSequence_doesNotTriggerMitigation() {
        let expectation = self.expectation(description: "Mitigation should not be triggered by background notification alone")
        expectation.isInverted = true
        
        detector.mitigationHandler = {
            expectation.fulfill()
        }
        
        detector.appDidEnterBackground()
        
        wait(for: [expectation], timeout: 0.5)
    }
    
    func test_finishNavigationAfterStart_resetsState() {
        let expectation = self.expectation(description: "New sequence after finish should work")
        detector.mitigationHandler = {
            expectation.fulfill()
        }
        
        // Start then finish (normal successful navigation)
        detector.startNavigation()
        detector.finishNavigation()
        
        // New malicious sequence should still be detected
        detector.startNavigation()
        detector.failNavigation(error: NSError(domain: "WebKitErrorDomain", code: 102))
        detector.appDidEnterBackground()
        
        waitForExpectations(timeout: 1.0)
    }
    
    func test_errorThenFinishNavigation_resetsState() {
        let expectation = self.expectation(description: "Mitigation should not be triggered when finish navigation comes after error")
        expectation.isInverted = true
        
        detector.mitigationHandler = {
            expectation.fulfill()
        }
        
        detector.startNavigation()
        detector.failNavigation(error: NSError(domain: "WebKitErrorDomain", code: 102))
        detector.finishNavigation() // This should reset the state
        detector.appDidEnterBackground()
        
        wait(for: [expectation], timeout: 0.5)
    }
    
    // MARK: - Timeout Edge Cases
    
    func test_timeoutDuringDifferentStates() {
        let shortTimeout = AdClickExternalOpenDetector(tabID: testTabID, operationTimeout: 0.1)
        
        shortTimeout.mitigationHandler = {
            XCTFail("Mitigation should not be triggered after timeout in any state")
        }
        
        // Test timeout during startNavigation state
        shortTimeout.startNavigation()
        
        let timeoutExpectation = self.expectation(description: "Timeout exceeded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            timeoutExpectation.fulfill()
        }
        wait(for: [timeoutExpectation], timeout: 0.3)
        
        shortTimeout.failNavigation(error: NSError(domain: "WebKitErrorDomain", code: 102))
        detector.appDidEnterBackground()
        
        let finalExpectation = self.expectation(description: "Final check completed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            finalExpectation.fulfill()
        }
        wait(for: [finalExpectation], timeout: 0.2)
    }
}
