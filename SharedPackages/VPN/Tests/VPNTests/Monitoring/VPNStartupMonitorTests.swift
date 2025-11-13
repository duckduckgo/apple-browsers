//
//  VPNStartupMonitorTests.swift
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
import NetworkExtension
@testable import VPN

@available(macOS 12, *)
final class VPNStartupMonitorTests: XCTestCase {

    private var notificationCenter: NotificationCenter!
    private var mockStatus: NEVPNStatus!
    private var monitor: VPNStartupMonitor!
    private var tunnelManager: NETunnelProviderManager!

    override func setUp() {
        super.setUp()
        notificationCenter = NotificationCenter()
        mockStatus = .invalid
        monitor = VPNStartupMonitor(
            notificationCenter: notificationCenter,
            statusProvider: { [weak self] _ in self?.mockStatus ?? .invalid }
        )
        tunnelManager = NETunnelProviderManager()
    }

    // MARK: - Success Cases

    func testCompletesWhenConnectionBecomesConnected() async throws {
        let connection = tunnelManager.connection

        Task {
            try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            mockStatus = .connected
            postStatusChange(connection: connection)
        }

        try await monitor.waitForStartSuccess(tunnelManager, timeout: 1)
    }

    func testCompletesImmediatelyWhenAlreadyConnected() async throws {
        mockStatus = .connected

        try await monitor.waitForStartSuccess(tunnelManager, timeout: 1)
    }

    // MARK: - Timeout

    func testThrowsTimeoutErrorWhenNoStatusChangeOccurs() async {
        mockStatus = .connecting

        do {
            try await monitor.waitForStartSuccess(tunnelManager, timeout: 0.1)
            XCTFail("Expected timeout error")
        } catch let error as VPNStartupMonitor.StartupError {
            XCTAssertEqual(error, .startTunnelTimedOut)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Disconnection Failures

    func testThrowsDisconnectedErrorWhenStatusBecomesDisconnected() async {
        let connection = tunnelManager.connection
        mockStatus = .connecting

        Task {
            try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            mockStatus = .disconnected
            postStatusChange(connection: connection)
        }

        do {
            try await monitor.waitForStartSuccess(tunnelManager, timeout: 1)
            XCTFail("Expected disconnected error")
        } catch let error as VPNStartupMonitor.StartupError {
            XCTAssertEqual(error, .startTunnelDisconnectedSilently)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testThrowsDisconnectedErrorWhenStatusBecomesDisconnecting() async {
        let connection = tunnelManager.connection
        mockStatus = .connecting

        Task {
            try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            mockStatus = .disconnecting
            postStatusChange(connection: connection)
        }

        do {
            try await monitor.waitForStartSuccess(tunnelManager, timeout: 1)
            XCTFail("Expected disconnected error")
        } catch let error as VPNStartupMonitor.StartupError {
            XCTAssertEqual(error, .startTunnelDisconnectedSilently)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Connection Identity Filtering

    func testIgnoresNotificationsForDifferentConnections() async throws {
        let connection = tunnelManager.connection
        let otherManager = NETunnelProviderManager()
        let otherConnection = otherManager.connection

        mockStatus = .connecting

        Task {
            try await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)
            // Post for wrong connection - should be ignored
            postStatusChange(connection: otherConnection)

            try await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)
            // Post for correct connection - should complete
            mockStatus = .connected
            postStatusChange(connection: connection)
        }

        try await monitor.waitForStartSuccess(tunnelManager, timeout: 1)
    }

    // MARK: - Status Filtering

    func testIgnoresIrrelevantStatusesUntilConnected() async throws {
        let connection = tunnelManager.connection

        Task {
            try await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)
            mockStatus = .connecting
            postStatusChange(connection: connection)

            try await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)
            mockStatus = .reasserting
            postStatusChange(connection: connection)

            try await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)
            mockStatus = .connected
            postStatusChange(connection: connection)
        }

        try await monitor.waitForStartSuccess(tunnelManager, timeout: 1)
    }

    // MARK: - Cancellation

    func testThrowsCancellationErrorWhenTaskCancelled() async {
        mockStatus = .connecting

        let task = Task {
            try await monitor.waitForStartSuccess(tunnelManager, timeout: 10)
        }

        // Cancel immediately - cooperative cancellation will be checked at the next checkpoint
        task.cancel()

        do {
            try await task.value
            XCTFail("Expected cancellation error")
        } catch is CancellationError {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private func postStatusChange(connection: NEVPNConnection) {
        notificationCenter.post(
            name: .NEVPNStatusDidChange,
            object: connection
        )
    }
}
