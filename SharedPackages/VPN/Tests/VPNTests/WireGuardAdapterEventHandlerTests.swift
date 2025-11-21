//
//  WireGuardAdapterEventHandlerTests.swift
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
import Common
@testable import VPN

final class WireGuardAdapterEventHandlerTests: XCTestCase {

    // MARK: - Test Infrastructure

    private var providerEvents: MockProviderEvents!
    private var settings: VPNSettings!
    private var notificationsPresenter: MockNotificationsPresenter!
    private var handler: WireGuardAdapterEventHandler!
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        providerEvents = MockProviderEvents()
        suiteName = "test-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        settings = VPNSettings(defaults: userDefaults)
        notificationsPresenter = MockNotificationsPresenter()
        handler = WireGuardAdapterEventHandler(
            providerEvents: providerEvents.eventMapping,
            settings: settings,
            notificationsPresenter: notificationsPresenter
        )
    }

    override func tearDown() {
        handler = nil
        notificationsPresenter = nil
        settings = nil
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
        providerEvents = nil
        super.tearDown()
    }

    // MARK: - Event Handling Tests

    func testHandleEndTemporaryShutdownStateAttemptFailure() {
        // Tests that attempt failure events are properly fired and logged
        let testError = TestError.someError

        handler.handle(.endTemporaryShutdownStateAttemptFailure(testError))

        XCTAssertEqual(providerEvents.firedEvents.count, 1)
        if case .adapterEndTemporaryShutdownStateAttemptFailure(let error) = providerEvents.firedEvents.first {
            XCTAssertEqual((error as? TestError), testError)
        } else {
            XCTFail("Expected adapterEndTemporaryShutdownStateAttemptFailure event")
        }
    }

    func testHandleEndTemporaryShutdownStateRecoveryFailure() {
        // Tests that recovery failure events are properly fired and logged
        let testError = TestError.anotherError

        handler.handle(.endTemporaryShutdownStateRecoveryFailure(testError))

        XCTAssertEqual(providerEvents.firedEvents.count, 1)
        if case .adapterEndTemporaryShutdownStateRecoveryFailure(let error) = providerEvents.firedEvents.first {
            XCTAssertEqual((error as? TestError), testError)
        } else {
            XCTFail("Expected adapterEndTemporaryShutdownStateRecoveryFailure event")
        }
    }

    func testHandleEndTemporaryShutdownStateRecoverySuccess() {
        // Tests that recovery success events are properly fired and logged
        handler.handle(.endTemporaryShutdownStateRecoverySuccess)

        XCTAssertEqual(providerEvents.firedEvents.count, 1)
        if case .adapterEndTemporaryShutdownStateRecoverySuccess = providerEvents.firedEvents.first {
            // Success
        } else {
            XCTFail("Expected adapterEndTemporaryShutdownStateRecoverySuccess event")
        }
    }

    // MARK: - Debug Notification Tests

    func testDebugNotificationsShownWhenEnabled() {
        // Tests that debug notifications are shown when the setting is enabled
        settings.showDebugVPNEventNotifications = true

        handler.handle(.endTemporaryShutdownStateAttemptFailure(TestError.someError))
        XCTAssertEqual(notificationsPresenter.shownMessages.count, 1)
        XCTAssertTrue(notificationsPresenter.shownMessages[0].contains("failed to end temporary shutdown"))

        handler.handle(.endTemporaryShutdownStateRecoveryFailure(TestError.anotherError))
        XCTAssertEqual(notificationsPresenter.shownMessages.count, 2)
        XCTAssertTrue(notificationsPresenter.shownMessages[1].contains("failed to recover from extended temporary shutdown"))

        handler.handle(.endTemporaryShutdownStateRecoverySuccess)
        XCTAssertEqual(notificationsPresenter.shownMessages.count, 3)
        XCTAssertTrue(notificationsPresenter.shownMessages[2].contains("recovered after extended temporary shutdown"))
    }

    func testDebugNotificationsNotShownWhenDisabled() {
        // Tests that debug notifications are not shown when the setting is disabled
        settings.showDebugVPNEventNotifications = false

        handler.handle(.endTemporaryShutdownStateAttemptFailure(TestError.someError))
        handler.handle(.endTemporaryShutdownStateRecoveryFailure(TestError.anotherError))
        handler.handle(.endTemporaryShutdownStateRecoverySuccess)

        XCTAssertEqual(notificationsPresenter.shownMessages.count, 0)
    }

    // MARK: - Mock Types

    private enum TestError: Error, Equatable {
        case someError
        case anotherError
    }

    private class MockProviderEvents {
        var firedEvents: [PacketTunnelProvider.Event] = []

        lazy var eventMapping: EventMapping<PacketTunnelProvider.Event> = {
            EventMapping<PacketTunnelProvider.Event> { [weak self] event, _, _, _ in
                self?.firedEvents.append(event)
            }
        }()
    }

    private class MockNotificationsPresenter: VPNNotificationsPresenting {
        var shownMessages: [String] = []

        func showConnectedNotification(serverLocation: String?, snoozeEnded: Bool) {}
        func showReconnectingNotification() {}
        func showConnectionFailureNotification() {}
        func showSnoozingNotification(duration: TimeInterval) {}
        func showSupersededNotification() {}
        func showTestNotification() {}
        func showEntitlementNotification() {}

        func showDebugEventNotification(message: String) {
            shownMessages.append(message)
        }
    }
}
