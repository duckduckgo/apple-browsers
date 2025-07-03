//
//  SubscriptionOnWakeEntitlementCheckerTests.swift
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
import Combine
import Foundation
@testable import Subscription
import SubscriptionTestingUtilities

@MainActor
final class SubscriptionOnWakeEntitlementCheckerTests: XCTestCase {

    struct EntitlementStatusCallback {
        let feature: Entitlement.ProductName
        let hasEntitlement: Bool
    }

    var subscriptionManager: SubscriptionManagerMockV2!
    var wakePublisher: PassthroughSubject<Void, Never>!
    var statusCallbacks: [EntitlementStatusCallback]!
    var cancellables: Set<AnyCancellable>!

    override func setUpWithError() throws {
        subscriptionManager = SubscriptionManagerMockV2()
        wakePublisher = PassthroughSubject<Void, Never>()
        statusCallbacks = []
        cancellables = Set<AnyCancellable>()
    }

    override func tearDownWithError() throws {
        subscriptionManager = nil
        wakePublisher = nil
        statusCallbacks = nil
        cancellables = nil
    }

    // MARK: - Initialization Tests

    func testInitializationWithMultipleFeatures() {
        let features: [Entitlement.ProductName] = [.networkProtection, .dataBrokerProtection]
        
        let checker = SubscriptionOnWakeEntitlementChecker(
            subscriptionManager: subscriptionManager,
            features: features,
            onEntitlementStatus: { feature, hasEntitlement in
                self.statusCallbacks.append(EntitlementStatusCallback(feature: feature, hasEntitlement: hasEntitlement))
            },
            wakeNotificationPublisher: wakePublisher.eraseToAnyPublisher()
        )
        
        XCTAssertNotNil(checker)
        XCTAssertTrue(statusCallbacks.isEmpty, "Should not trigger callbacks during initialization")
    }



    // MARK: - Wake Notification Tests

    func testWakeNotificationTriggersEntitlementCheck() async throws {
        // Mock that user has network protection entitlement
        subscriptionManager.resultFeatures = [
            SubscriptionFeatureV2(entitlement: .networkProtection, isAvailableForUser: true)
        ]
        
        let expectation = expectation(description: "onEntitlementStatus called")
        
        let checker = SubscriptionOnWakeEntitlementChecker(
            subscriptionManager: subscriptionManager,
            features: [.networkProtection],
            onEntitlementStatus: { feature, hasEntitlement in
                self.statusCallbacks.append(EntitlementStatusCallback(feature: feature, hasEntitlement: hasEntitlement))
                expectation.fulfill()
            },
            wakeNotificationPublisher: wakePublisher.eraseToAnyPublisher()
        )
        
        // Send wake notification
        wakePublisher.send(())
        
        // Wait for callback
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertEqual(statusCallbacks.count, 1, "Should receive one callback")
        XCTAssertEqual(statusCallbacks[0].feature, .networkProtection, "Should check network protection feature")
        XCTAssertEqual(statusCallbacks[0].hasEntitlement, true, "Should report entitlement status")
        
        // Keep checker alive
        _ = checker
    }

    func testWakeNotificationWithMultipleFeatures() async throws {
        // Mock that user has both network protection and data broker protection entitlements
        subscriptionManager.resultFeatures = [
            SubscriptionFeatureV2(entitlement: .networkProtection, isAvailableForUser: true),
            SubscriptionFeatureV2(entitlement: .dataBrokerProtection, isAvailableForUser: true)
        ]
        let features: [Entitlement.ProductName] = [.networkProtection, .dataBrokerProtection]
        
        let expectation = expectation(description: "onEntitlementStatus called for multiple features")
        expectation.expectedFulfillmentCount = 2
        
        let checker = SubscriptionOnWakeEntitlementChecker(
            subscriptionManager: subscriptionManager,
            features: features,
            onEntitlementStatus: { feature, hasEntitlement in
                self.statusCallbacks.append(EntitlementStatusCallback(feature: feature, hasEntitlement: hasEntitlement))
                expectation.fulfill()
            },
            wakeNotificationPublisher: wakePublisher.eraseToAnyPublisher()
        )
        
        // Send wake notification
        wakePublisher.send(())
        
        // Wait for both callbacks
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertEqual(statusCallbacks.count, 2, "Should receive callback for each feature")
        
        let checkedFeatures = Set(statusCallbacks.map { $0.feature })
        XCTAssertEqual(checkedFeatures, Set(features), "Should check all requested features")
        
        // All should report true based on mock setup
        XCTAssertTrue(statusCallbacks.allSatisfy { $0.hasEntitlement }, "All features should report true")
        
        // Keep checker alive
        _ = checker
    }

    func testWakeNotificationWithDifferentEntitlementStates() async throws {
        // Mock that user has only network protection entitlement, not data broker protection
        subscriptionManager.resultFeatures = [
            SubscriptionFeatureV2(entitlement: .networkProtection, isAvailableForUser: true)
            // Deliberately omitting .dataBrokerProtection
        ]
        
        let features: [Entitlement.ProductName] = [.networkProtection, .dataBrokerProtection]
        
        let expectation = expectation(description: "onEntitlementStatus called for both features")
        expectation.expectedFulfillmentCount = 2
        
        let checker = SubscriptionOnWakeEntitlementChecker(
            subscriptionManager: subscriptionManager,
            features: features,
            onEntitlementStatus: { feature, hasEntitlement in
                self.statusCallbacks.append(EntitlementStatusCallback(feature: feature, hasEntitlement: hasEntitlement))
                expectation.fulfill()
            },
            wakeNotificationPublisher: wakePublisher.eraseToAnyPublisher()
        )
        
        // Send wake notification
        wakePublisher.send(())
        
        // Wait for both callbacks
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertEqual(statusCallbacks.count, 2, "Should receive callback for each feature")
        
        // Find the callbacks for each feature
        let netpCallback = statusCallbacks.first { $0.feature == .networkProtection }
        let dbpCallback = statusCallbacks.first { $0.feature == .dataBrokerProtection }
        
        XCTAssertNotNil(netpCallback)
        XCTAssertNotNil(dbpCallback)
        XCTAssertTrue(netpCallback!.hasEntitlement, "Network protection should have entitlement")
        XCTAssertFalse(dbpCallback!.hasEntitlement, "Data broker protection should not have entitlement")
        
        // Keep checker alive
        _ = checker
    }

    // MARK: - Multiple Wake Notifications Tests

    func testMultipleWakeNotifications() async throws {
        // Mock that user has network protection entitlement
        subscriptionManager.resultFeatures = [
            SubscriptionFeatureV2(entitlement: .networkProtection, isAvailableForUser: true)
        ]
        
        let firstWakeExpectation = expectation(description: "First wake notification callback")
        let secondWakeExpectation = expectation(description: "Second wake notification callback")
        var callbackCount = 0
        
        let checker = SubscriptionOnWakeEntitlementChecker(
            subscriptionManager: subscriptionManager,
            features: [.networkProtection],
            onEntitlementStatus: { feature, hasEntitlement in
                self.statusCallbacks.append(EntitlementStatusCallback(feature: feature, hasEntitlement: hasEntitlement))
                callbackCount += 1
                if callbackCount == 1 {
                    firstWakeExpectation.fulfill()
                } else if callbackCount == 2 {
                    secondWakeExpectation.fulfill()
                }
            },
            wakeNotificationPublisher: wakePublisher.eraseToAnyPublisher()
        )
        
        // Send first wake notification
        wakePublisher.send(())
        await fulfillment(of: [firstWakeExpectation], timeout: 1.0)
        
        XCTAssertEqual(statusCallbacks.count, 1, "Should receive one callback after first wake")
        
        // Send second wake notification
        wakePublisher.send(())
        await fulfillment(of: [secondWakeExpectation], timeout: 1.0)
        
        XCTAssertEqual(statusCallbacks.count, 2, "Should receive another callback after second wake")
        
        // Both should report the same status since mock always returns true
        XCTAssertTrue(statusCallbacks.allSatisfy { $0.hasEntitlement }, "Both callbacks should report entitlement")
        
        // Keep checker alive
        _ = checker
    }

    func testStatelessBehavior() async throws {
        // Start with entitlement
        subscriptionManager.resultFeatures = [
            SubscriptionFeatureV2(entitlement: .networkProtection, isAvailableForUser: true)
        ]
        
        let firstWakeExpectation = expectation(description: "First wake callback")
        let secondWakeExpectation = expectation(description: "Second wake callback")
        let thirdWakeExpectation = expectation(description: "Third wake callback")
        var callbackCount = 0
        
        let checker = SubscriptionOnWakeEntitlementChecker(
            subscriptionManager: subscriptionManager,
            features: [.networkProtection],
            onEntitlementStatus: { feature, hasEntitlement in
                self.statusCallbacks.append(EntitlementStatusCallback(feature: feature, hasEntitlement: hasEntitlement))
                callbackCount += 1
                if callbackCount == 1 {
                    firstWakeExpectation.fulfill()
                } else if callbackCount == 2 {
                    secondWakeExpectation.fulfill()
                } else if callbackCount == 3 {
                    thirdWakeExpectation.fulfill()
                }
            },
            wakeNotificationPublisher: wakePublisher.eraseToAnyPublisher()
        )
        
        // First wake - has entitlement
        wakePublisher.send(())
        await fulfillment(of: [firstWakeExpectation], timeout: 1.0)
        
        XCTAssertEqual(statusCallbacks.count, 1)
        XCTAssertTrue(statusCallbacks[0].hasEntitlement, "First callback should report entitlement")
        
        // Second wake - still has entitlement (no change)
        wakePublisher.send(())
        await fulfillment(of: [secondWakeExpectation], timeout: 1.0)
        
        XCTAssertEqual(statusCallbacks.count, 2, "Should still receive callback even though status hasn't changed")
        XCTAssertTrue(statusCallbacks[1].hasEntitlement, "Second callback should still report entitlement")
        
        // Third wake - now no entitlement (simulate subscription expiry)
        subscriptionManager.resultFeatures = []
        wakePublisher.send(())
        await fulfillment(of: [thirdWakeExpectation], timeout: 1.0)
        
        XCTAssertEqual(statusCallbacks.count, 3, "Should receive callback for changed status")
        XCTAssertFalse(statusCallbacks[2].hasEntitlement, "Third callback should report no entitlement")
        
        // Keep checker alive
        _ = checker
    }

    // MARK: - Error Handling Tests

    func testNoEntitlementReporting() async throws {
        // Test that checker correctly reports false when user has no entitlements
        subscriptionManager.resultFeatures = [] // No entitlements
        
        let expectation = expectation(description: "onEntitlementStatus called for no entitlement")
        
        let checker = SubscriptionOnWakeEntitlementChecker(
            subscriptionManager: subscriptionManager,
            features: [.networkProtection],
            onEntitlementStatus: { feature, hasEntitlement in
                self.statusCallbacks.append(EntitlementStatusCallback(feature: feature, hasEntitlement: hasEntitlement))
                expectation.fulfill()
            },
            wakeNotificationPublisher: wakePublisher.eraseToAnyPublisher()
        )
        
        // Send wake notification
        wakePublisher.send(())
        
        // Wait for callback
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // Should receive callback with false entitlement status
        XCTAssertEqual(statusCallbacks.count, 1, "Should receive callback")
        XCTAssertEqual(statusCallbacks[0].feature, .networkProtection, "Should check network protection feature")
        XCTAssertFalse(statusCallbacks[0].hasEntitlement, "Should report no entitlement")
        
        // Keep checker alive until end of test
        _ = checker
    }

    // MARK: - Memory Management Tests

    func testWeakSelfInCallback() async throws {
        // Mock that user has network protection entitlement
        subscriptionManager.resultFeatures = [
            SubscriptionFeatureV2(entitlement: .networkProtection, isAvailableForUser: true)
        ]
        
        let firstCallbackExpectation = expectation(description: "First callback received")
        
        var checker: SubscriptionOnWakeEntitlementChecker? = SubscriptionOnWakeEntitlementChecker(
            subscriptionManager: subscriptionManager,
            features: [.networkProtection],
            onEntitlementStatus: { [weak self] feature, hasEntitlement in
                self?.statusCallbacks.append(EntitlementStatusCallback(feature: feature, hasEntitlement: hasEntitlement))
                firstCallbackExpectation.fulfill()
            },
            wakeNotificationPublisher: wakePublisher.eraseToAnyPublisher()
        )
        
        // Send wake notification while checker exists
        wakePublisher.send(())
        await fulfillment(of: [firstCallbackExpectation], timeout: 1.0)
        
        XCTAssertEqual(statusCallbacks.count, 1, "Should receive callback while checker exists")
        
        // Release checker
        _ = checker // Silence warning about unused variable
        checker = nil
        
        // Send another wake notification after checker is released
        wakePublisher.send(())
        
        // Wait a bit for any potential callbacks (but shouldn't get any)
        try await Task.sleep(for: .milliseconds(100))
        
        XCTAssertEqual(statusCallbacks.count, 1, "Should not receive callback after checker is deallocated")
    }

    func testPublisherCleanup() {
        weak var checkerRef: SubscriptionOnWakeEntitlementChecker?
        
        autoreleasepool {
            let checker = SubscriptionOnWakeEntitlementChecker(
                subscriptionManager: subscriptionManager,
                features: [.networkProtection],
                onEntitlementStatus: { feature, hasEntitlement in
                    self.statusCallbacks.append(EntitlementStatusCallback(feature: feature, hasEntitlement: hasEntitlement))
                },
                wakeNotificationPublisher: wakePublisher.eraseToAnyPublisher()
            )
            checkerRef = checker
        }
        
        XCTAssertNil(checkerRef, "Checker should be deallocated when no strong references exist")
    }
}

// MARK: - Test Helpers

private enum TestError: Error {
    case mockError
} 
