//
//  VPNConnectionStatusMonitorTests.swift
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
import NetworkExtension
@testable import VPN

@MainActor
final class VPNConnectionStatusMonitorTests: XCTestCase {
    private let notificationCenter = NotificationCenter()
    private let manager = NETunnelProviderManager()
    private var status: NEVPNStatus = .disconnected
    private var monitor: VPNConnectionStatusMonitor!

    override func tearDown() async throws {
        await MainActor.run {
            monitor?.stopObserving()
            monitor = nil
        }
        try await super.tearDown()
    }

    func testLaunchCheckRecognizesBothStartupErrorsOnADisconnectedConnection() async {
        let errors: [PacketTunnelProvider.TunnelError] = [
            .startingTunnelWithoutAuthToken(internalError: URLError(.userAuthenticationRequired)),
            .reconnectBlocked
        ]
        for error in errors {
            monitor = makeMonitor { _ in throw error }
            let shouldNotify = await monitor.hasStartupFailureAtLaunch(on: manager.connection)
            XCTAssertTrue(shouldNotify)
        }
    }

    func testLaunchCheckIgnoresUnrelatedAndMissingErrors() async {
        monitor = makeMonitor { _ in throw URLError(.timedOut) }
        let unrelated = await monitor.hasStartupFailureAtLaunch(on: manager.connection)
        XCTAssertFalse(unrelated)
        monitor = makeMonitor { _ in }
        let missing = await monitor.hasStartupFailureAtLaunch(on: manager.connection)
        XCTAssertFalse(missing)
    }

    func testLaunchCheckSkipsActiveConnectionsAndDiscardsSupersededLookups() async {
        status = .connecting
        monitor = makeMonitor { _ in XCTFail("A retry in progress belongs to the live monitor") }
        let retry = await monitor.hasStartupFailureAtLaunch(on: manager.connection)
        XCTAssertFalse(retry)

        status = .disconnected
        monitor = makeMonitor { _ in
            await MainActor.run { self.status = .connected }
            throw PacketTunnelProvider.TunnelError.reconnectBlocked
        }
        let recovered = await monitor.hasStartupFailureAtLaunch(on: manager.connection)
        XCTAssertFalse(recovered)

        status = .disconnected
        monitor = makeMonitor { _ in
            await MainActor.run { self.monitor.resetPendingFailures() }
            throw PacketTunnelProvider.TunnelError.reconnectBlocked
        }
        let superseded = await monitor.hasStartupFailureAtLaunch(on: manager.connection)
        XCTAssertFalse(superseded)
    }

    func testStatusOnlyObservationDoesNotFetchErrorsOrReplayStatus() async {
        let statusReceived = expectation(description: "Connected status received once")
        monitor = makeMonitor { _ in XCTFail("Status-only observation must not fetch errors") }
        monitor.observe(onStatus: { connection, status in
            XCTAssertTrue(connection === self.manager.connection)
            XCTAssertEqual(status, .connected)
            statusReceived.fulfill()
        })
        post(.connected)
        await fulfillment(of: [statusReceived], timeout: 1)
    }

    func testStatusObservationIgnoresNonTunnelConnections() async {
        let statusReceived = expectation(description: "Only tunnel status received")
        monitor = makeMonitor { _ in XCTFail("Status-only observation must not fetch errors") }
        monitor.observe(onStatus: { connection, _ in
            XCTAssertTrue(connection === self.manager.connection)
            statusReceived.fulfill()
        })
        notificationCenter.post(name: .NEVPNStatusDidChange, object: NEVPNManager.shared().connection)
        post(.connected)
        await fulfillment(of: [statusReceived], timeout: 1)
    }

    func testFailureObservationDoesNotInspectInitialErrorOrUnrelatedProfiles() async {
        let lookup = expectation(description: "Only current profile inspected")
        monitor = makeMonitor { connection in
            XCTAssertTrue(connection === self.manager.connection)
            lookup.fulfill()
        }
        monitor.observe(onStatus: { _, _ in }, currentConnection: { self.manager.connection }, onFailure: { _, _ in
            XCTFail("No typed failure")
        })
        notificationCenter.post(name: .NEVPNStatusDidChange, object: NETunnelProviderManager().connection)
        post(.disconnected)
        await fulfillment(of: [lookup], timeout: 1)
    }

    func testDisconnectingWithoutErrorDoesNotSuppressDisconnectedFailure() async {
        let firstLookup = expectation(description: "Disconnecting inspected")
        let failureReceived = expectation(description: "Disconnected failure received")
        var lookupCount = 0
        monitor = makeMonitor { _ in
            lookupCount += 1
            if lookupCount == 1 {
                firstLookup.fulfill()
                return
            }
            throw PacketTunnelProvider.TunnelError.startingTunnelWithoutAuthToken(internalError: URLError(.userAuthenticationRequired))
        }
        monitor.observe(onStatus: { _, _ in }, currentConnection: { self.manager.connection }, onFailure: { _, code in
            XCTAssertEqual(code, .startingTunnelWithoutAuthToken)
            failureReceived.fulfill()
        })
        post(.disconnecting)
        await fulfillment(of: [firstLookup], timeout: 1)
        post(.disconnected)
        await fulfillment(of: [failureReceived], timeout: 1)
        XCTAssertEqual(lookupCount, 2)
    }

    func testPendingFailureSurvivesAutomaticRetryAndUnrelatedSuccess() async {
        let lookup = expectation(description: "Error lookup started")
        let failureReceived = expectation(description: "Retry failure received")
        var finishLookup: CheckedContinuation<Void, Never>?
        monitor = makeMonitor { _ in
            await withCheckedContinuation { finishLookup = $0; lookup.fulfill() }
            throw PacketTunnelProvider.TunnelError.reconnectBlocked
        }
        monitor.observe(onStatus: { _, _ in }, currentConnection: { self.manager.connection }, onFailure: { connection, code in
            XCTAssertTrue(connection === self.manager.connection)
            XCTAssertEqual(code, .reconnectBlocked)
            failureReceived.fulfill()
        })
        post(.disconnected)
        await fulfillment(of: [lookup], timeout: 1)
        status = .connected
        notificationCenter.post(name: .NEVPNStatusDidChange, object: NETunnelProviderManager().connection)
        post(.connecting)
        finishLookup?.resume()
        await fulfillment(of: [failureReceived], timeout: 1)
    }

    func testSuccessAndInvalidationDiscardPendingFailures() async {
        for terminalStatus in [NEVPNStatus.connected, .reasserting, .invalid] {
            let lookup = expectation(description: "Error lookup started")
            let terminalReceived = expectation(description: "Terminal status received")
            let failureReceived = expectation(description: "Stale failure suppressed")
            failureReceived.isInverted = true
            var finishLookup: CheckedContinuation<Void, Never>?
            monitor = makeMonitor { _ in
                await withCheckedContinuation { finishLookup = $0; lookup.fulfill() }
                throw PacketTunnelProvider.TunnelError.reconnectBlocked
            }
            monitor.observe(onStatus: { _, status in
                if status == terminalStatus { terminalReceived.fulfill() }
            }, currentConnection: { self.manager.connection }, onFailure: { _, _ in failureReceived.fulfill() })
            post(.disconnected)
            await fulfillment(of: [lookup], timeout: 1)
            post(terminalStatus)
            await fulfillment(of: [terminalReceived], timeout: 1)
            // A following retry must not make an old lookup relevant again.
            post(.connecting)
            finishLookup?.resume()
            await fulfillment(of: [failureReceived], timeout: 0.05)
            monitor.stopObserving()
        }
    }

    func testDeliberateRestartDiscardsPendingFailureButAllowsLaterFailure() async {
        let lookup = expectation(description: "Error lookup started")
        let oldFailure = expectation(description: "Old failure suppressed")
        oldFailure.isInverted = true
        let newFailure = expectation(description: "New failure received")
        var finishLookup: CheckedContinuation<Void, Never>?
        var lookupCount = 0
        var expectingNewFailure = false
        monitor = makeMonitor { _ in
            lookupCount += 1
            if lookupCount == 1 {
                await withCheckedContinuation { finishLookup = $0; lookup.fulfill() }
            }
            throw PacketTunnelProvider.TunnelError.reconnectBlocked
        }
        monitor.observe(onStatus: { _, _ in }, currentConnection: { self.manager.connection }, onFailure: { _, _ in
            (expectingNewFailure ? newFailure : oldFailure).fulfill()
        })
        post(.disconnected)
        await fulfillment(of: [lookup], timeout: 1)
        monitor.resetPendingFailures()
        post(.connecting)
        finishLookup?.resume()
        await fulfillment(of: [oldFailure], timeout: 0.05)

        expectingNewFailure = true
        post(.disconnected)
        await fulfillment(of: [newFailure], timeout: 1)
    }

    func testDeliberateStartDiscardsFailureQueuedBeforeItsTaskRuns() async {
        let statusReceived = expectation(description: "Queued status delivered")
        monitor = makeMonitor { _ in XCTFail("A deliberate start superseded this queued failure") }
        monitor.observe(onStatus: { _, _ in statusReceived.fulfill() },
                        currentConnection: { self.manager.connection },
                        onFailure: { _, _ in XCTFail("Queued failure was superseded") })
        post(.disconnected)
        monitor.resetPendingFailures()
        await fulfillment(of: [statusReceived], timeout: 1)
    }

    func testFailureObservationAcceptsConfigurationCreatedLater() async {
        let initialStatus = expectation(description: "Initial status received")
        var receivedInitialStatus = false
        let failureReceived = expectation(description: "Newly configured profile failure received")
        var currentConnection: NEVPNConnection?
        monitor = makeMonitor { _ in throw PacketTunnelProvider.TunnelError.reconnectBlocked }
        monitor.observe(onStatus: { _, _ in
            if !receivedInitialStatus {
                receivedInitialStatus = true
                initialStatus.fulfill()
            }
        },
                        currentConnection: { currentConnection },
                        onFailure: { _, code in
            XCTAssertEqual(code, .reconnectBlocked)
            failureReceived.fulfill()
        })
        post(.disconnected)
        await fulfillment(of: [initialStatus], timeout: 1)
        currentConnection = manager.connection
        post(.disconnected)
        await fulfillment(of: [failureReceived], timeout: 1)
    }

    func testProfileReplacementDiscardsPendingFailure() async {
        let lookup = expectation(description: "Error lookup started")
        let failureReceived = expectation(description: "Old profile suppressed")
        failureReceived.isInverted = true
        var currentConnection = manager.connection
        var finishLookup: CheckedContinuation<Void, Never>?
        monitor = makeMonitor { _ in
            await withCheckedContinuation { finishLookup = $0; lookup.fulfill() }
            throw PacketTunnelProvider.TunnelError.reconnectBlocked
        }
        monitor.observe(onStatus: { _, _ in }, currentConnection: { currentConnection }, onFailure: { _, _ in failureReceived.fulfill() })
        post(.disconnected)
        await fulfillment(of: [lookup], timeout: 1)
        currentConnection = NETunnelProviderManager().connection
        finishLookup?.resume()
        await fulfillment(of: [failureReceived], timeout: 0.05)
    }

    func testInvalidStatusDoesNotFetchDisconnectError() async {
        let invalidReceived = expectation(description: "Invalid status received")
        monitor = makeMonitor { _ in XCTFail("Invalid status has no new disconnect reason") }
        monitor.observe(onStatus: { _, status in
            XCTAssertEqual(status, .invalid)
            invalidReceived.fulfill()
        }, currentConnection: { self.manager.connection }, onFailure: { _, _ in XCTFail("Invalid status is not a failure") })
        post(.invalid)
        await fulfillment(of: [invalidReceived], timeout: 1)
    }

    func testUnrelatedErrorIsNotReported() async {
        let lookup = expectation(description: "Error inspected")
        let failureReceived = expectation(description: "Unrelated error suppressed")
        failureReceived.isInverted = true
        monitor = makeMonitor { _ in
            lookup.fulfill()
            throw URLError(.notConnectedToInternet)
        }
        monitor.observe(onStatus: { _, _ in }, currentConnection: { self.manager.connection }, onFailure: { _, _ in failureReceived.fulfill() })
        post(.disconnected)
        await fulfillment(of: [lookup, failureReceived], timeout: 0.05)
    }

    func testStopObservingDiscardsPendingLookupAndFutureEvents() async {
        let lookup = expectation(description: "Error lookup started")
        let failureReceived = expectation(description: "Stopped observation suppressed")
        failureReceived.isInverted = true
        var finishLookup: CheckedContinuation<Void, Never>?
        monitor = makeMonitor { _ in
            await withCheckedContinuation { finishLookup = $0; lookup.fulfill() }
            throw PacketTunnelProvider.TunnelError.reconnectBlocked
        }
        monitor.observe(onStatus: { _, _ in }, currentConnection: { self.manager.connection }, onFailure: { _, _ in failureReceived.fulfill() })
        post(.disconnected)
        await fulfillment(of: [lookup], timeout: 1)
        monitor.stopObserving()
        finishLookup?.resume()
        post(.disconnected)
        await fulfillment(of: [failureReceived], timeout: 0.05)
    }

    private func makeMonitor(errorProvider: @escaping (NEVPNConnection) async throws -> Void) -> VPNConnectionStatusMonitor {
        VPNConnectionStatusMonitor(notificationCenter: notificationCenter,
                                   statusProvider: { [weak self] _ in self?.status ?? .invalid },
                                   disconnectErrorProvider: errorProvider)
    }

    private func post(_ status: NEVPNStatus) {
        self.status = status
        notificationCenter.post(name: .NEVPNStatusDidChange, object: manager.connection)
    }
}
