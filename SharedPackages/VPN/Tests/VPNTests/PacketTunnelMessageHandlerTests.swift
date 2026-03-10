//
//  PacketTunnelMessageHandlerTests.swift
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

import Common
import Foundation
import XCTest
@testable import VPN

// MARK: - Test Notification Center

#if os(macOS)
private final class TestNotificationCenter: NotificationCenter, @unchecked Sendable, NetworkProtectionNotificationPosting {
    func post(_ networkProtectionNotification: NetworkProtectionNotification, object: String?, userInfo: [AnyHashable: Any]?) {}
}
#else
private final class TestNotificationCenter: NotificationCenter, @unchecked Sendable {}
#endif

// MARK: - Test Doubles

@MainActor
private final class MockConnectionTester: ConnectionTesting {
    var resultHandler: (@MainActor (ConnectionTestingResult) -> Void)?
    var failNextTestCalled = false

    func start(tunnelIfName: String, testImmediately: Bool) async throws {}
    func stop() {}
    func failNextTest() { failNextTestCalled = true }
}

private actor MockKeyExpirationTester: KeyExpirationTesting {
    var rekeyIfExpiredCalled = false
    var lastKeyValidity: TimeInterval??

    func start(testImmediately: Bool) async {}
    func stop() {}
    func setKeyValidity(_ validity: TimeInterval?) {
        lastKeyValidity = .some(validity)
    }
    func rekeyIfExpired() async {
        rekeyIfExpiredCalled = true
    }
}

private final class MockAdapter: WireGuardAdapterProtocol {
    var interfaceName: String? = "utun42"

    var runtimeConfigString: String?
    var bytesTransmitted: (UInt64, UInt64)?
    var stopError: WireGuardAdapterError?

    func start(tunnelConfiguration: TunnelConfiguration, completionHandler: @escaping (WireGuardAdapterError?) -> Void) {
        completionHandler(nil)
    }

    func stop(completionHandler: @escaping (WireGuardAdapterError?) -> Void) {
        completionHandler(stopError)
    }

    func update(tunnelConfiguration: TunnelConfiguration, reassert: Bool, completionHandler: @escaping (WireGuardAdapterError?) -> Void) {
        completionHandler(nil)
    }

    func getBytesTransmitted() async throws -> (rx: UInt64, tx: UInt64) {
        guard let bytes = bytesTransmitted else {
            throw NSError(domain: "test", code: 0)
        }
        return (rx: bytes.0, tx: bytes.1)
    }

    func getRuntimeConfiguration(completionHandler: @escaping (String?) -> Void) {
        completionHandler(runtimeConfigString)
    }

    func snooze(completionHandler: @escaping (WireGuardAdapterError?) -> Void) {
        completionHandler(nil)
    }

    func getMostRecentHandshake() async throws -> TimeInterval {
        return 0
    }
}

private final class MockNotificationsPresenter: VPNNotificationsPresenting {
    var showTestNotificationCalled = false

    func showConnectedNotification(serverLocation: String?, snoozeEnded: Bool) {}
    func showReconnectingNotification() {}
    func showConnectionFailureNotification() {}
    func showSnoozingNotification(duration: TimeInterval) {}
    func showSupersededNotification() {}
    func showTestNotification() { showTestNotificationCalled = true }
    func showEntitlementNotification() {}
    func showDebugEventNotification(message: String) {}
}

// MARK: - Tests

@MainActor
final class PacketTunnelMessageHandlerTests: XCTestCase {

    private var keyStore: NetworkProtectionKeyStoreMock!
    private var keyExpirationTester: MockKeyExpirationTester!
    private var controllerErrorStore: NetworkProtectionTunnelErrorStore!
    private var adapter: MockAdapter!
    private var tunnelHealth: NetworkProtectionTunnelHealthStore!
    private var notificationsPresenter: MockNotificationsPresenter!
    private var connectionTester: MockConnectionTester!
    private var settings: VPNSettings!
    private var debugEvents: EventMapping<NetworkProtectionError>!
    private var tunnelState: MockTunnelStateProvider!
    private var tunnelLifecycle: MockTunnelLifecycleManager!
    private var snoozeManager: MockSnoozeManager!
    private var handler: PacketTunnelMessageHandler!

    override func setUp() {
        super.setUp()

        keyStore = NetworkProtectionKeyStoreMock()
        keyExpirationTester = MockKeyExpirationTester()
        adapter = MockAdapter()
#if os(macOS)
        let notificationCenter = TestNotificationCenter()
        controllerErrorStore = NetworkProtectionTunnelErrorStore(notificationCenter: notificationCenter)
        tunnelHealth = NetworkProtectionTunnelHealthStore(notificationCenter: notificationCenter)
#else
        controllerErrorStore = NetworkProtectionTunnelErrorStore()
        tunnelHealth = NetworkProtectionTunnelHealthStore()
#endif
        notificationsPresenter = MockNotificationsPresenter()
        connectionTester = MockConnectionTester()
        settings = VPNSettings(defaults: .standard)
        debugEvents = EventMapping<NetworkProtectionError> { _, _, _, _ in }
        tunnelState = MockTunnelStateProvider()
        tunnelLifecycle = MockTunnelLifecycleManager()
        snoozeManager = MockSnoozeManager()

        handler = PacketTunnelMessageHandler(
            keyStore: keyStore,
            keyExpirationTester: keyExpirationTester,
            controllerErrorStore: controllerErrorStore,
            adapter: adapter,
            tunnelHealth: tunnelHealth,
            notificationsPresenter: notificationsPresenter,
            connectionTester: connectionTester,
            settings: settings,
            debugEvents: debugEvents,
            tunnelState: tunnelState,
            tunnelLifecycle: tunnelLifecycle,
            snoozeManager: snoozeManager
        )
    }

    override func tearDown() {
        handler = nil
        snoozeManager = nil
        tunnelLifecycle = nil
        tunnelState = nil
        debugEvents = nil
        settings = nil
        connectionTester = nil
        notificationsPresenter = nil
        tunnelHealth = nil
        adapter = nil
        controllerErrorStore = nil
        keyExpirationTester = nil
        keyStore = nil
        super.tearDown()
    }

    // MARK: - Unknown Message

    func testUnknownMessageReturnsNil() {
        let expectation = expectation(description: "completion called")
        let invalidData = Data([0xFF, 0xFE, 0xFD])

        handler.handleAppMessage(invalidData) { data in
            XCTAssertNil(data)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Simple Handlers

    func testGetLastErrorMessageReturnsStoredError() {
        let errorMessage = "Test error message"
        controllerErrorStore.lastErrorMessage = errorMessage

        let expectation = expectation(description: "completion called")
        let messageData = ExtensionMessage.getLastErrorMessage.rawValue

        handler.handleAppMessage(messageData) { data in
            XCTAssertNotNil(data)
            let response = data.flatMap { ExtensionMessageString(rawValue: $0) }
            XCTAssertEqual(response?.value, errorMessage)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testGetLastErrorMessageReturnsNilWhenNoError() {
        controllerErrorStore.lastErrorMessage = nil

        let expectation = expectation(description: "completion called")
        let messageData = ExtensionMessage.getLastErrorMessage.rawValue

        handler.handleAppMessage(messageData) { data in
            XCTAssertNil(data)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testIsHavingConnectivityIssuesReturnsFalse() {
        tunnelHealth.isHavingConnectivityIssues = false

        let expectation = expectation(description: "completion called")
        let messageData = ExtensionMessage.isHavingConnectivityIssues.rawValue

        handler.handleAppMessage(messageData) { data in
            XCTAssertNotNil(data)
            let response = data.flatMap { ExtensionMessageBool(rawValue: $0) }
            XCTAssertEqual(response?.value, false)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testIsHavingConnectivityIssuesReturnsTrue() {
        tunnelHealth.isHavingConnectivityIssues = true

        let expectation = expectation(description: "completion called")
        let messageData = ExtensionMessage.isHavingConnectivityIssues.rawValue

        handler.handleAppMessage(messageData) { data in
            XCTAssertNotNil(data)
            let response = data.flatMap { ExtensionMessageBool(rawValue: $0) }
            XCTAssertEqual(response?.value, true)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testSendTestNotificationCallsPresenter() {
        let expectation = expectation(description: "completion called")
        let messageData = ExtensionMessage.triggerTestNotification.rawValue

        handler.handleAppMessage(messageData) { data in
            XCTAssertNil(data)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(notificationsPresenter.showTestNotificationCalled)
    }

    func testSimulateConnectionInterruptionCallsFailNextTest() {
        let expectation = expectation(description: "completion called")
        let messageData = ExtensionMessage.simulateConnectionInterruption.rawValue

        handler.handleAppMessage(messageData) { data in
            XCTAssertNil(data)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(connectionTester.failNextTestCalled)
    }

    // MARK: - Deprecated Messages

    func testSetExcludedRoutesReturnsNil() {
        let expectation = expectation(description: "completion called")
        let messageData = ExtensionMessage.setExcludedRoutes([]).rawValue

        handler.handleAppMessage(messageData) { data in
            XCTAssertNil(data)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testSetIncludedRoutesReturnsNil() {
        let expectation = expectation(description: "completion called")
        let messageData = ExtensionMessage.setIncludedRoutes([]).rawValue

        handler.handleAppMessage(messageData) { data in
            XCTAssertNil(data)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Tunnel State Dependent Handlers

    func testGetServerAddressReturnsNilWhenNoServer() {
        tunnelState.lastSelectedServerInfo = nil

        let expectation = expectation(description: "completion called")
        let messageData = ExtensionMessage.getServerAddress.rawValue

        handler.handleAppMessage(messageData) { data in
            XCTAssertNil(data)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testGetServerLocationReturnsNilWhenNoServer() {
        tunnelState.lastSelectedServerInfo = nil

        let expectation = expectation(description: "completion called")
        let messageData = ExtensionMessage.getServerLocation.rawValue

        handler.handleAppMessage(messageData) { data in
            XCTAssertNil(data)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Tunnel Lifecycle Dependent Handlers

    func testResetAllStateCallsResetRegistrationKeyAndCancelTunnel() {
        let expectation = expectation(description: "completion called")
        let messageData = ExtensionMessage.resetAllState.rawValue

        handler.handleAppMessage(messageData) { data in
            XCTAssertNil(data)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(tunnelLifecycle.resetRegistrationKeyCalled)
        XCTAssertTrue(tunnelLifecycle.cancelTunnelCalled)
    }

    func testRestartAdapterCommandCallsRestartAdapter() {
        let expectation = expectation(description: "completion called")
        let request = ExtensionRequest.command(.restartAdapter)
        let messageData = ExtensionMessage.request(request).rawValue

        handler.handleAppMessage(messageData) { data in
            XCTAssertNil(data)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(tunnelLifecycle.restartAdapterCalled)
    }

    // MARK: - Snooze Handlers

    func testStartSnoozeCallsSnoozeManager() {
        let duration: TimeInterval = 300
        let expectation = expectation(description: "completion called")
        let messageData = ExtensionMessage.startSnooze(duration).rawValue

        handler.handleAppMessage(messageData) { data in
            XCTAssertNil(data)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(snoozeManager.startSnoozeCalled)
        XCTAssertEqual(snoozeManager.lastSnoozeDuration, duration)
    }

    func testCancelSnoozeCallsSnoozeManager() {
        let expectation = expectation(description: "completion called")
        let messageData = ExtensionMessage.cancelSnooze.rawValue

        handler.handleAppMessage(messageData) { data in
            XCTAssertNil(data)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(snoozeManager.cancelSnoozeCalled)
    }

    // MARK: - Data Volume

    func testGetDataVolumeReturnsFormattedString() {
        adapter.bytesTransmitted = (1024, 2048)

        let expectation = expectation(description: "completion called")
        let messageData = ExtensionMessage.getDataVolume.rawValue

        handler.handleAppMessage(messageData) { data in
            XCTAssertNotNil(data)
            let response = data.flatMap { ExtensionMessageString(rawValue: $0) }
            XCTAssertEqual(response?.value, "1024,2048")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testGetDataVolumeReturnsNilOnError() {
        adapter.bytesTransmitted = nil

        let expectation = expectation(description: "completion called")
        let messageData = ExtensionMessage.getDataVolume.rawValue

        handler.handleAppMessage(messageData) { data in
            XCTAssertNil(data)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Settings Change

    func testSettingChangeAppRequestAppliesChange() {
        let request = ExtensionRequest.changeTunnelSetting(.setExcludeLocalNetworks(true))
        let messageData = ExtensionMessage.request(request).rawValue

        let expectation = expectation(description: "completion called")

        handler.handleAppMessage(messageData) { data in
            XCTAssertNil(data)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(settings.excludeLocalNetworks)
    }
}
