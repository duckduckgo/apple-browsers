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

    var subscriptionManager: SubscriptionManagerMockV2!
    var wakePublisher: PassthroughSubject<Notification, Never>!
    var statusCallbacks: [(Entitlement.ProductName, Bool)]!
    var cancellables: Set<AnyCancellable>!

    override func setUpWithError() throws {
        subscriptionManager = SubscriptionManagerMockV2()
        wakePublisher = PassthroughSubject<Notification, Never>()
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
                self.statusCallbacks.append((feature, hasEntitlement))
            },
            wakeNotificationPublisher: wakePublisher.eraseToAnyPublisher()
        )
        
        XCTAssertNotNil(checker)
        XCTAssertTrue(statusCallbacks.isEmpty, "Should not trigger callbacks during initialization")
    }

    func testConvenienceInitializationWithSingleFeature() {
        let checker = SubscriptionOnWakeEntitlementChecker(
            subscriptionManager: subscriptionManager,
            feature: .networkProtection,
            onEntitlementStatus: { feature, hasEntitlement in
                self.statusCallbacks.append((feature, hasEntitlement))
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
        
        let checker = SubscriptionOnWakeEntitlementChecker(
            subscriptionManager: subscriptionManager,
            feature: .networkProtection,
            onEntitlementStatus: { feature, hasEntitlement in
                self.statusCallbacks.append((feature, hasEntitlement))
            },
            wakeNotificationPublisher: wakePublisher.eraseToAnyPublisher()
        )
        
        // Send wake notification
        let notification = Notification(name: Notification.Name("test.wake"))
        wakePublisher.send(notification)
        
        // Wait for async processing
        try await Task.sleep(for: .milliseconds(50))
        
        XCTAssertEqual(statusCallbacks.count, 1, "Should receive one callback")
        XCTAssertEqual(statusCallbacks[0].0, .networkProtection, "Should check network protection feature")
        XCTAssertEqual(statusCallbacks[0].1, true, "Should report entitlement status")
    }

    func testWakeNotificationWithMultipleFeatures() async throws {
        // Mock that user has both network protection and data broker protection entitlements
        subscriptionManager.resultFeatures = [
            SubscriptionFeatureV2(entitlement: .networkProtection, isAvailableForUser: true),
            SubscriptionFeatureV2(entitlement: .dataBrokerProtection, isAvailableForUser: true)
        ]
        let features: [Entitlement.ProductName] = [.networkProtection, .dataBrokerProtection]
        
        let checker = SubscriptionOnWakeEntitlementChecker(
            subscriptionManager: subscriptionManager,
            features: features,
            onEntitlementStatus: { feature, hasEntitlement in
                self.statusCallbacks.append((feature, hasEntitlement))
            },
            wakeNotificationPublisher: wakePublisher.eraseToAnyPublisher()
        )
        
        // Send wake notification
        let notification = Notification(name: Notification.Name("test.wake"))
        wakePublisher.send(notification)
        
        // Wait for async processing
        try await Task.sleep(for: .milliseconds(50))
        
        XCTAssertEqual(statusCallbacks.count, 2, "Should receive callback for each feature")
        
        let checkedFeatures = Set(statusCallbacks.map { $0.0 })
        XCTAssertEqual(checkedFeatures, Set(features), "Should check all requested features")
        
        // All should report true based on mock setup
        XCTAssertTrue(statusCallbacks.allSatisfy { $0.1 }, "All features should report true")
    }

    func testWakeNotificationWithDifferentEntitlementStates() async throws {
        // Mock that user has only network protection entitlement, not data broker protection
        subscriptionManager.resultFeatures = [
            SubscriptionFeatureV2(entitlement: .networkProtection, isAvailableForUser: true)
            // Deliberately omitting .dataBrokerProtection
        ]
        
        let features: [Entitlement.ProductName] = [.networkProtection, .dataBrokerProtection]
        
        let checker = SubscriptionOnWakeEntitlementChecker(
            subscriptionManager: subscriptionManager,
            features: features,
            onEntitlementStatus: { feature, hasEntitlement in
                self.statusCallbacks.append((feature, hasEntitlement))
            },
            wakeNotificationPublisher: wakePublisher.eraseToAnyPublisher()
        )
        
        // Send wake notification
        let notification = Notification(name: Notification.Name("test.wake"))
        wakePublisher.send(notification)
        
        // Wait for async processing
        try await Task.sleep(for: .milliseconds(50))
        
        XCTAssertEqual(statusCallbacks.count, 2, "Should receive callback for each feature")
        
        // Find the callbacks for each feature
        let netpCallback = statusCallbacks.first { $0.0 == .networkProtection }
        let dbpCallback = statusCallbacks.first { $0.0 == .dataBrokerProtection }
        
        XCTAssertNotNil(netpCallback)
        XCTAssertNotNil(dbpCallback)
        XCTAssertTrue(netpCallback!.1, "Network protection should have entitlement")
        XCTAssertFalse(dbpCallback!.1, "Data broker protection should not have entitlement")
    }

    // MARK: - Multiple Wake Notifications Tests

    func testMultipleWakeNotifications() async throws {
        // Mock that user has network protection entitlement
        subscriptionManager.resultFeatures = [
            SubscriptionFeatureV2(entitlement: .networkProtection, isAvailableForUser: true)
        ]
        
        let checker = SubscriptionOnWakeEntitlementChecker(
            subscriptionManager: subscriptionManager,
            feature: .networkProtection,
            onEntitlementStatus: { feature, hasEntitlement in
                self.statusCallbacks.append((feature, hasEntitlement))
            },
            wakeNotificationPublisher: wakePublisher.eraseToAnyPublisher()
        )
        
        // Send first wake notification
        let notification1 = Notification(name: Notification.Name("test.wake1"))
        wakePublisher.send(notification1)
        try await Task.sleep(for: .milliseconds(50))
        
        XCTAssertEqual(statusCallbacks.count, 1, "Should receive one callback after first wake")
        
        // Send second wake notification
        let notification2 = Notification(name: Notification.Name("test.wake2"))
        wakePublisher.send(notification2)
        try await Task.sleep(for: .milliseconds(50))
        
        XCTAssertEqual(statusCallbacks.count, 2, "Should receive another callback after second wake")
        
        // Both should report the same status since mock always returns true
        XCTAssertTrue(statusCallbacks.allSatisfy { $0.1 }, "Both callbacks should report entitlement")
    }

    func testStatelessBehavior() async throws {
        // Start with entitlement
        subscriptionManager.resultFeatures = [
            SubscriptionFeatureV2(entitlement: .networkProtection, isAvailableForUser: true)
        ]
        
        let checker = SubscriptionOnWakeEntitlementChecker(
            subscriptionManager: subscriptionManager,
            feature: .networkProtection,
            onEntitlementStatus: { feature, hasEntitlement in
                self.statusCallbacks.append((feature, hasEntitlement))
            },
            wakeNotificationPublisher: wakePublisher.eraseToAnyPublisher()
        )
        
        // First wake - has entitlement
        let notification1 = Notification(name: Notification.Name("test.wake1"))
        wakePublisher.send(notification1)
        try await Task.sleep(for: .milliseconds(50))
        
        XCTAssertEqual(statusCallbacks.count, 1)
        XCTAssertTrue(statusCallbacks[0].1, "First callback should report entitlement")
        
        // Second wake - still has entitlement (no change)
        let notification2 = Notification(name: Notification.Name("test.wake2"))
        wakePublisher.send(notification2)
        try await Task.sleep(for: .milliseconds(50))
        
        XCTAssertEqual(statusCallbacks.count, 2, "Should still receive callback even though status hasn't changed")
        XCTAssertTrue(statusCallbacks[1].1, "Second callback should still report entitlement")
        
        // Third wake - now no entitlement (simulate subscription expiry)
        subscriptionManager.resultFeatures = []
        let notification3 = Notification(name: Notification.Name("test.wake3"))
        wakePublisher.send(notification3)
        try await Task.sleep(for: .milliseconds(50))
        
        XCTAssertEqual(statusCallbacks.count, 3, "Should receive callback for changed status")
        XCTAssertFalse(statusCallbacks[2].1, "Third callback should report no entitlement")
    }

    // MARK: - Error Handling Tests

    func testNoEntitlementReporting() async throws {
        // Test that checker correctly reports false when user has no entitlements
        subscriptionManager.resultFeatures = [] // No entitlements
        
        let checker = SubscriptionOnWakeEntitlementChecker(
            subscriptionManager: subscriptionManager,
            feature: .networkProtection,
            onEntitlementStatus: { feature, hasEntitlement in
                self.statusCallbacks.append((feature, hasEntitlement))
            },
            wakeNotificationPublisher: wakePublisher.eraseToAnyPublisher()
        )
        
        // Send wake notification
        let notification = Notification(name: Notification.Name("test.wake"))
        wakePublisher.send(notification)
        
        // Wait for async processing
        try await Task.sleep(for: .milliseconds(50))
        
        // Should receive callback with false entitlement status
        XCTAssertEqual(statusCallbacks.count, 1, "Should receive callback")
        XCTAssertEqual(statusCallbacks[0].0, .networkProtection, "Should check network protection feature")
        XCTAssertFalse(statusCallbacks[0].1, "Should report no entitlement")
        
        // Keep checker alive until end of test
        _ = checker
    }

    // MARK: - Memory Management Tests

    func testWeakSelfInCallback() async throws {
        // Mock that user has network protection entitlement
        subscriptionManager.resultFeatures = [
            SubscriptionFeatureV2(entitlement: .networkProtection, isAvailableForUser: true)
        ]
        
        var checker: SubscriptionOnWakeEntitlementChecker? = SubscriptionOnWakeEntitlementChecker(
            subscriptionManager: subscriptionManager,
            feature: .networkProtection,
            onEntitlementStatus: { [weak self] feature, hasEntitlement in
                self?.statusCallbacks.append((feature, hasEntitlement))
            },
            wakeNotificationPublisher: wakePublisher.eraseToAnyPublisher()
        )
        
        // Send wake notification while checker exists
        let notification1 = Notification(name: Notification.Name("test.wake1"))
        wakePublisher.send(notification1)
        try await Task.sleep(for: .milliseconds(50))
        
        XCTAssertEqual(statusCallbacks.count, 1, "Should receive callback while checker exists")
        
        // Release checker
        checker = nil
        
        // Send another wake notification after checker is released
        let notification2 = Notification(name: Notification.Name("test.wake2"))
        wakePublisher.send(notification2)
        try await Task.sleep(for: .milliseconds(50))
        
        XCTAssertEqual(statusCallbacks.count, 1, "Should not receive callback after checker is deallocated")
    }

    func testPublisherCleanup() {
        weak var checkerRef: SubscriptionOnWakeEntitlementChecker?
        
        autoreleasepool {
            let checker = SubscriptionOnWakeEntitlementChecker(
                subscriptionManager: subscriptionManager,
                feature: .networkProtection,
                onEntitlementStatus: { feature, hasEntitlement in
                    self.statusCallbacks.append((feature, hasEntitlement))
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