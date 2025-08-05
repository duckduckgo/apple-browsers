//
//  HotspotDetectionServiceTests.swift
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

import Clocks
import Combine
import Common
import OHHTTPStubs
import OHHTTPStubsSwift
import XCTest
import os.log

@testable import DuckDuckGo_Privacy_Browser

extension Task where Success == Never, Failure == Never {
    static func megaYield() async {
        await Task.yield()
        await Task.yield()
        await Task.yield()
    }
}

@available(macOS 13, *)
@MainActor
final class HotspotDetectionServiceTests: XCTestCase {

    private var service: HotspotDetectionService!
    private var cancellables: Set<AnyCancellable>!
    private var clock: TestClock<Duration>!

    override func setUp() {
        clock = TestClock()
        let sleeper = Sleeper(clock: clock)
        service = HotspotDetectionService(sleeper: sleeper)
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        cancellables?.removeAll()
        service = nil
        clock = nil
        HTTPStubs.removeAllStubs()
    }

    // MARK: - Subscription Tests

    func testWhenNoSubscribers_ServiceStateIsUnknown() {
        XCTAssertEqual(service.currentState, .unknown)
    }

    func testWhenFirstSubscriberAdded_ServiceStartsMonitoring() {
        let expectation = expectation(description: "Service should start monitoring")
        var receivedStates: [HotspotConnectivityState] = []

        // Stub success response
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            expectation.fulfill()
            return HTTPStubsResponse(data: "success".data(using: .utf8)!, statusCode: 200, headers: nil)
        }

        service.statePublisher
            .sink { state in
                receivedStates.append(state)
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(receivedStates.contains(.unknown)) // Initial state
    }

    func testWhenAllSubscribersRemoved_ServiceStopsMonitoringAndResetsToUnknown() async throws {
        var capturedStates: [HotspotConnectivityState] = []
        var subscription: AnyCancellable?

        // Start monitoring and capture state values
        subscription = service.statePublisher.sink { state in
            capturedStates.append(state)
        }

        // Give a brief moment for subscription to register and capture initial state
        await Task.yield()

        // Stop monitoring by canceling subscription
        subscription?.cancel()
        subscription = nil

        // Give a brief moment for the service to process the cancellation
        await Task.yield()

        // Verify service is in unknown state (it starts in unknown and should stay unknown)
        XCTAssertEqual(service.currentState, .unknown, "Service should be in unknown state when no subscribers")
        XCTAssertTrue(capturedStates.contains(.unknown), "Should have captured initial unknown state")
    }

    // MARK: - Network Response Tests

    func testWhenNetworkReturnsSuccess_StateIsConnected() {
        let expectation = expectation(description: "Should detect connected state")
        var finalState: HotspotConnectivityState?

        // Stub success response
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            return HTTPStubsResponse(data: "success".data(using: .utf8)!, statusCode: 200, headers: nil)
        }

        service.statePublisher
            .dropFirst() // Skip initial unknown state
            .sink { state in
                finalState = state
                if state == .connected {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(finalState, .connected)
    }

    func testWhenNetworkReturnsCaptivePortalResponse_StateIsHotspotAuth() {
        let expectation = expectation(description: "Should detect hotspot auth state")
        var finalState: HotspotConnectivityState?

        // Stub captive portal response
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            return HTTPStubsResponse(data: "<html>Captive Portal</html>".data(using: .utf8)!, statusCode: 200, headers: nil)
        }

        service.statePublisher
            .dropFirst() // Skip initial unknown state
            .sink { state in
                finalState = state
                if state == .hotspotAuth {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(finalState, .hotspotAuth)
    }

    func testWhenNetworkRequestFails_StateRemainsUnknownIfPreviouslyUnknown() {
        let expectation = expectation(description: "Should handle network failure")
        var capturedStates: [HotspotConnectivityState] = []

        // Stub network failure
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            expectation.fulfill()
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
            return HTTPStubsResponse(error: error)
        }

        // Subscribe to service and capture all state changes
        service.statePublisher.sink { state in
            capturedStates.append(state)
        }.store(in: &cancellables)

        wait(for: [expectation], timeout: 3.0)

        // Should remain unknown after network failure
        XCTAssertEqual(service.currentState, .unknown)

        // @Published always emits initial value, so we should have captured the .unknown state
        XCTAssertFalse(capturedStates.isEmpty, "Should have captured initial state")
        XCTAssertTrue(capturedStates.allSatisfy { $0 == .unknown }, "All published states should be unknown when network fails")
    }

    func testWhenNetworkFailsAfterBeingConnected_StateChangesToUnknown() async throws {
        var capturedStates: [HotspotConnectivityState] = []

        // First few requests succeed to establish connected state, then return error
        var requestCount = 0
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            requestCount += 1
            if requestCount <= 2 {
                // First 2 requests succeed to establish and maintain connected state
                return HTTPStubsResponse(data: "success".data(using: .utf8)!, statusCode: 200, headers: nil)
            } else {
                // Return a network error that should trigger catch block
                let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: nil)
                return HTTPStubsResponse(error: error)
            }
        }

        // Subscribe to service and capture all state changes
        service.statePublisher.sink { state in
            capturedStates.append(state)
        }.store(in: &cancellables)

        // Set expectation BEFORE advancing clock - wait for connected state
        let connectedExpectation = expectation(
            for: NSPredicate { _, _ in
                self.service.currentState == .connected
            },
            evaluatedWith: self,
            handler: nil
        )

        // Advance clock to trigger first network check (should become connected)
        await clock.advance(by: .seconds(5))
        await Task.megaYield(count: 5)

        // Wait for connected state
        await fulfillment(of: [connectedExpectation], timeout: 2.0)
        XCTAssertEqual(service.currentState, .connected)

        // Advance clock to trigger second network check (should succeed)
        await clock.advance(by: .seconds(5))
        await Task.megaYield(count: 5)

        // Set expectation BEFORE advancing clock for the third time - wait for unknown state after failure
        let unknownExpectation = expectation(
            for: NSPredicate { _, _ in
                capturedStates.contains(.connected) && capturedStates.last == .unknown
            },
            evaluatedWith: self,
            handler: nil
        )

        // Advance clock to trigger third network check (should fail and become unknown)
        await clock.advance(by: .seconds(5))
        await Task.megaYield(count: 5)

        // Wait for transition back to unknown
        await fulfillment(of: [unknownExpectation], timeout: 2.0)

        // Verify the state transition sequence and final state
        XCTAssertEqual(service.currentState, .unknown, "Service should be unknown after network error from connected state")
        XCTAssertTrue(capturedStates.contains(.connected), "Should have been connected at some point")
        XCTAssertEqual(capturedStates.last, .unknown, "Final state should be unknown")
    }

    // MARK: - State Change Tests

    func testWhenStateChanges_OnlyChangesArePublished() async throws {
        // Track network requests to ensure they're happening
        var requestCount = 0

        // Capture all published states to verify sequence
        var publishedStates: [HotspotConnectivityState] = []

        // Stub consistent success response
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            requestCount += 1
            return HTTPStubsResponse(data: "success".data(using: .utf8)!, statusCode: 200, headers: nil)
        }

        // Subscribe to service and capture all published states
        service.statePublisher.sink { state in
            publishedStates.append(state)
        }.store(in: &cancellables)

        // Set expectation for first state change to .connected
        let firstStateChangeExpectation = expectation(
            for: NSPredicate { _, _ in
                publishedStates.contains(.connected)
            },
            evaluatedWith: self,
            handler: nil
        )

        // Advance clock to trigger first network check
        await clock.advance(by: .seconds(5))
        await Task.megaYield(count: 5)

        // Wait for first state change to .connected
        await fulfillment(of: [firstStateChangeExpectation], timeout: 2.0)

        // Should be connected after first check and have made at least one request
        XCTAssertGreaterThan(requestCount, 0, "At least one network request should have been made")
        XCTAssertEqual(service.currentState, .connected)
        XCTAssertTrue(publishedStates.contains(.connected), "Connected state should have been published")

        let requestCountAfterFirst = requestCount
        let publishedStatesCountAfterFirst = publishedStates.count

        // Set expectation for additional network requests (but NO new state publications)
        let additionalRequestExpectation = expectation(
            for: NSPredicate { _, _ in requestCount > requestCountAfterFirst },
            evaluatedWith: self,
            handler: nil
        )

        // Advance clock multiple times to trigger more checks
        await clock.advance(by: .seconds(5))
        await Task.megaYield(count: 5)
        await clock.advance(by: .seconds(5))
        await Task.megaYield(count: 5)

        // Wait for additional network requests to be made
        await fulfillment(of: [additionalRequestExpectation], timeout: 2.0)

        // Should have made additional requests but NO additional state publications (no duplicates)
        XCTAssertEqual(service.currentState, .connected)
        XCTAssertGreaterThan(requestCount, requestCountAfterFirst, "Additional network requests should have been made")
        XCTAssertEqual(publishedStates.count, publishedStatesCountAfterFirst, "No duplicate state should have been published")

        // Verify the published states sequence contains only unique changes
        let uniqueStates = Array(NSOrderedSet(array: publishedStates)) as! [HotspotConnectivityState]
        XCTAssertEqual(publishedStates.count, uniqueStates.count, "All published states should be unique (no duplicates)")
    }

    // MARK: - Multiple Subscribers Tests

    func testWhenMultipleSubscribers_ServiceRunsOnce() async throws {
        var requestCount = 0
        var firstSubscriberStates: [HotspotConnectivityState] = []
        var secondSubscriberStates: [HotspotConnectivityState] = []

        // Stub and count requests
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            requestCount += 1
            return HTTPStubsResponse(data: "success".data(using: .utf8)!, statusCode: 200, headers: nil)
        }

        // First subscriber - capture all received states
        service.statePublisher.sink { state in
            firstSubscriberStates.append(state)
        }.store(in: &cancellables)

        // Second subscriber - capture all received states  
        service.statePublisher.sink { state in
            secondSubscriberStates.append(state)
        }.store(in: &cancellables)

        // Set expectation BEFORE advancing clock
        let stateChangeExpectation = expectation(
            for: NSPredicate { _, _ in
                self.service.currentState == .connected
            },
            evaluatedWith: self,
            handler: nil
        )

        // Advance clock to trigger network check
        await clock.advance(by: .seconds(5))
        await Task.megaYield(count: 5)

        // Wait for state change
        await fulfillment(of: [stateChangeExpectation], timeout: 2.0)

        // Both subscribers should receive the same sequence of states
        XCTAssertGreaterThan(requestCount, 0, "Should have made network requests")
        XCTAssertEqual(service.currentState, .connected)
        XCTAssertEqual(firstSubscriberStates, secondSubscriberStates, "Both subscribers should receive identical state sequences")
        XCTAssertTrue(firstSubscriberStates.contains(.connected), "Should have received connected state")
    }

    // MARK: - HTTP Response Variations

    func testWhenResponseIs200ButNotSuccess_StateIsHotspotAuth() {
        let expectation = expectation(description: "Should detect hotspot auth for non-success 200 response")
        var finalState: HotspotConnectivityState?

        // Stub 200 response with non-success content
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            return HTTPStubsResponse(data: "redirect".data(using: .utf8)!, statusCode: 200, headers: nil)
        }

        service.statePublisher
            .dropFirst()
            .sink { state in
                finalState = state
                if state == .hotspotAuth {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(finalState, .hotspotAuth)
    }

    func testWhenResponseIsNon200_StateRemainsUnchanged() {
        let expectation = expectation(description: "Should handle non-200 response")
        var capturedStates: [HotspotConnectivityState] = []

        // Stub 404 response
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            expectation.fulfill()
            return HTTPStubsResponse(data: Data(), statusCode: 404, headers: nil)
        }

        // Subscribe to service and capture all state changes (including initial state)
        service.statePublisher.sink { state in
            capturedStates.append(state)
        }.store(in: &cancellables)

        wait(for: [expectation], timeout: 3.0)

        // Should remain unknown for non-200 responses
        XCTAssertEqual(service.currentState, .unknown)

        // @Published always emits initial value, so we should have captured the .unknown state
        XCTAssertFalse(capturedStates.isEmpty, "Should have captured initial state")
        XCTAssertTrue(capturedStates.allSatisfy { $0 == .unknown }, "All published states should remain unknown for non-200 responses")
    }
}
