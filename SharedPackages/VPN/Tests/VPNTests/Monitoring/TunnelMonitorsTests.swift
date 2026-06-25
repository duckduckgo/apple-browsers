//
//  TunnelMonitorsTests.swift
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
import Network
import XCTest
@testable import VPN

@MainActor
final class TunnelMonitorsTests: XCTestCase {

    private var tunnelFailureMonitor: MockTunnelFailureMonitor!
    private var latencyMonitor: MockLatencyMonitor!
    private var entitlementMonitor: MockEntitlementMonitor!
    private var serverStatusMonitor: MockServerStatusMonitor!
    private var keyExpirationTester: MockKeyExpirationTester!
    private var connectionTester: MockConnectionTester!
    private var failureRecoveryHandler: MockFailureRecoveryHandler!
    private var tunnelState: MockTunnelStateProvider!
    private var settings: VPNSettings!
    private var firedEvents: FiredEventsBox!
    private var events: EventMapping<PacketTunnelProvider.Event>!
    private var tunables: TunablesBox!
    private var hooks: HooksBox!
    private var monitors: TunnelMonitors!

    override func setUp() {
        super.setUp()

        tunnelFailureMonitor = MockTunnelFailureMonitor()
        latencyMonitor = MockLatencyMonitor()
        entitlementMonitor = MockEntitlementMonitor()
        serverStatusMonitor = MockServerStatusMonitor()
        keyExpirationTester = MockKeyExpirationTester()
        connectionTester = MockConnectionTester()
        failureRecoveryHandler = MockFailureRecoveryHandler()

        tunnelState = MockTunnelStateProvider()
        tunnelState.lastSelectedServer = .mockBaseServer
        tunnelState.lastSelectedServerInfo = .mock
        tunnelState.tunnelInterfaceName = "utun42"
        tunnelState.excludeLocalNetworks = false

        settings = VPNSettings(defaults: .standard)

        let eventsBox = FiredEventsBox()
        firedEvents = eventsBox
        events = EventMapping<PacketTunnelProvider.Event> { event, _, _, _ in
            eventsBox.events.append(event)
        }

        let tunablesBox = TunablesBox()
        tunables = tunablesBox

        let hooksBox = HooksBox()
        hooks = hooksBox

        monitors = TunnelMonitors(
            tunnelFailureMonitor: tunnelFailureMonitor,
            latencyMonitor: latencyMonitor,
            entitlementMonitor: entitlementMonitor,
            serverStatusMonitor: serverStatusMonitor,
            keyExpirationTester: keyExpirationTester,
            connectionTester: connectionTester,
            failureRecoveryHandler: failureRecoveryHandler,
            tunnelState: tunnelState,
            settings: settings,
            events: events,
            entitlementCheck: { tunablesBox.entitlementResult },
            isConnectionTesterEnabled: { tunablesBox.connectionTesterEnabled },
            onReconfigureForMigration: {
                hooksBox.reconfigureForMigrationCount += 1
                if let error = hooksBox.reconfigureForMigrationError {
                    throw error
                }
            },
            onConnectionTestResult: { result in
                hooksBox.lastConnectionTestResult = result
            },
            onFailureRecoveryConfigUpdate: { result in
                hooksBox.lastFailureRecoveryConfigUpdate = result
                if let error = hooksBox.failureRecoveryConfigUpdateError {
                    throw error
                }
            },
            onAccessRevoked: {
                hooksBox.accessRevokedCount += 1
            }
        )
    }

    override func tearDown() {
        monitors = nil
        hooks = nil
        tunables = nil
        events = nil
        firedEvents = nil
        settings = nil
        tunnelState = nil
        failureRecoveryHandler = nil
        connectionTester = nil
        keyExpirationTester = nil
        serverStatusMonitor = nil
        entitlementMonitor = nil
        latencyMonitor = nil
        tunnelFailureMonitor = nil
        super.tearDown()
    }

    /// Several monitor callbacks spawn detached Tasks. Yield several times so the
    /// scheduler runs them — and any actor-hop continuations — before assertions.
    private func waitForSpawnedTasks() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    private func makeFailureRecoveryConfigResult() -> NetworkProtectionDeviceManagement.GenerateTunnelConfigurationResult {
        (
            tunnelConfiguration: .make(named: "replacement-server"),
            server: .registeredServer(named: "replacement-server")
        )
    }

    // MARK: - start()

    func testStart_callsStartOnAllMonitors_whenPreconditionsMet() async throws {
        try await monitors.start(testImmediately: true)

        let failureStart = await tunnelFailureMonitor.startCount
        let latencyStart = await latencyMonitor.startCount
        let entitlementStart = await entitlementMonitor.startCount
        let serverStatusStart = await serverStatusMonitor.startCount
        let keyExpStart = await keyExpirationTester.startCount
        let connectionStart = connectionTester.startCount

        XCTAssertEqual(failureStart, 1)
        XCTAssertEqual(latencyStart, 1)
        XCTAssertEqual(entitlementStart, 1)
        XCTAssertEqual(serverStatusStart, 1)
        XCTAssertEqual(keyExpStart, 1)
        XCTAssertEqual(connectionStart, 1)
        XCTAssertEqual(connectionTester.lastTunnelIfName, "utun42")
        XCTAssertEqual(connectionTester.lastTestImmediately, true)
    }

    func testStart_passesServerIPToLatencyMonitor() async throws {
        try await monitors.start(testImmediately: false)

        let lastIP = await latencyMonitor.lastServerIP
        XCTAssertEqual(lastIP, IPv4Address("192.168.1.1"))
    }

    func testStart_passesServerNameToServerStatusMonitor() async throws {
        try await monitors.start(testImmediately: false)

        let lastName = await serverStatusMonitor.lastServerName
        XCTAssertEqual(lastName, "Mock Server")
    }

    func testStart_whenMonitorsAlreadyStarted_restartsThem() async throws {
        try await monitors.start(testImmediately: false)
        try await monitors.start(testImmediately: false)

        let failureStart = await tunnelFailureMonitor.startCount
        let failureStop = await tunnelFailureMonitor.stopCount
        let latencyStart = await latencyMonitor.startCount
        let latencyStop = await latencyMonitor.stopCount
        let entitlementStart = await entitlementMonitor.startCount
        let entitlementStop = await entitlementMonitor.stopCount
        let serverStatusStart = await serverStatusMonitor.startCount
        let serverStatusStop = await serverStatusMonitor.stopCount

        XCTAssertEqual(failureStart, 2)
        XCTAssertEqual(failureStop, 1)
        XCTAssertEqual(latencyStart, 2)
        XCTAssertEqual(latencyStop, 1)
        XCTAssertEqual(entitlementStart, 2)
        XCTAssertEqual(entitlementStop, 1)
        XCTAssertEqual(serverStatusStart, 2)
        XCTAssertEqual(serverStatusStop, 1)
    }

    func testStart_whenConnectionTesterThrows_wrapsErrorInTesterFailedToStart() async {
        struct StartFailure: Error {}
        connectionTester.startError = StartFailure()

        do {
            try await monitors.start(testImmediately: false)
            XCTFail("Expected ConnectionTesterError.testerFailedToStart")
        } catch PacketTunnelProvider.ConnectionTesterError.testerFailedToStart(let inner) {
            XCTAssertTrue(inner is StartFailure, "wrapped error should be the original")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStart_whenServerInfoMissing_stopsLatencyAndServerStatusMonitors() async throws {
        tunnelState.lastSelectedServerInfo = nil

        try await monitors.start(testImmediately: false)

        let latencyStart = await latencyMonitor.startCount
        let latencyStop = await latencyMonitor.stopCount
        let serverStatusStart = await serverStatusMonitor.startCount
        let serverStatusStop = await serverStatusMonitor.stopCount

        XCTAssertEqual(latencyStart, 0)
        XCTAssertEqual(latencyStop, 1)
        XCTAssertEqual(serverStatusStart, 0)
        XCTAssertEqual(serverStatusStop, 1)
    }

    func testStart_whenEntitlementInvalid_skipsLatencyMonitorStart() async throws {
        tunables.entitlementResult = .success(false)

        try await monitors.start(testImmediately: false)

        let latencyStart = await latencyMonitor.startCount
        XCTAssertEqual(latencyStart, 0)
    }

    func testStart_whenConnectionTesterDisabled_doesNotStartIt() async throws {
        tunables.connectionTesterEnabled = false

        try await monitors.start(testImmediately: false)

        XCTAssertEqual(connectionTester.startCount, 0)
    }

    func testStart_whenInterfaceNameMissing_throwsConnectionTesterError() async {
        tunnelState.tunnelInterfaceName = nil

        do {
            try await monitors.start(testImmediately: false)
            XCTFail("Expected ConnectionTesterError.couldNotRetrieveInterfaceNameFromAdapter")
        } catch PacketTunnelProvider.ConnectionTesterError.couldNotRetrieveInterfaceNameFromAdapter {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - stop()

    func testStop_callsStopOnAllMonitors() async {
        await monitors.stop()

        let failureStop = await tunnelFailureMonitor.stopCount
        let latencyStop = await latencyMonitor.stopCount
        let entitlementStop = await entitlementMonitor.stopCount
        let serverStatusStop = await serverStatusMonitor.stopCount
        let keyExpStop = await keyExpirationTester.stopCount
        let connectionStop = connectionTester.stopCount

        XCTAssertEqual(failureStop, 1)
        XCTAssertEqual(latencyStop, 1)
        XCTAssertEqual(entitlementStop, 1)
        XCTAssertEqual(serverStatusStop, 1)
        XCTAssertEqual(keyExpStop, 1)
        XCTAssertEqual(connectionStop, 1)
    }

    func testStop_stopsFailureRecovery() async {
        await monitors.stop()

        XCTAssertEqual(failureRecoveryHandler.stopCount, 1)
    }

    func testStop_excludingFailureRecovery_stopsOtherMonitorsButLeavesRecoveryRunning() async {
        await monitors.stop(includingFailureRecovery: false)

        let failureStop = await tunnelFailureMonitor.stopCount
        let latencyStop = await latencyMonitor.stopCount
        let entitlementStop = await entitlementMonitor.stopCount
        let serverStatusStop = await serverStatusMonitor.stopCount
        let keyExpStop = await keyExpirationTester.stopCount
        let connectionStop = connectionTester.stopCount

        XCTAssertEqual(failureStop, 1)
        XCTAssertEqual(latencyStop, 1)
        XCTAssertEqual(entitlementStop, 1)
        XCTAssertEqual(serverStatusStop, 1)
        XCTAssertEqual(keyExpStop, 1)
        XCTAssertEqual(connectionStop, 1)

        // A reasserting config update is driven *by* failure recovery, so the
        // reconfiguration stop must leave the in-flight recovery task alone;
        // cancelling it here would truncate the recovery's retry loop.
        XCTAssertEqual(failureRecoveryHandler.stopCount, 0)
    }

    // MARK: - Tunnel-failure callback

    func testTunnelFailureCallback_firesReportTunnelFailureEvent() async throws {
        try await monitors.start(testImmediately: false)
        await tunnelFailureMonitor.fire(.networkPathChanged("eth0"))
        await waitForSpawnedTasks()

        let reported = firedEvents.events.contains { event in
            if case .reportTunnelFailure = event { return true }
            return false
        }
        XCTAssertTrue(reported)
    }

    func testTunnelFailureCallback_failureDetected_invokesFailureRecovery() async throws {
        try await monitors.start(testImmediately: false)
        await tunnelFailureMonitor.fire(.failureDetected)
        await waitForSpawnedTasks()

        XCTAssertEqual(failureRecoveryHandler.attemptCount, 1)
        XCTAssertEqual(failureRecoveryHandler.lastExcludeLocalNetworks, false)
    }

    func testTunnelFailureCallback_failureDetected_appliesRecoveryConfig() async throws {
        let configResult = makeFailureRecoveryConfigResult()
        failureRecoveryHandler.configResultToUpdate = configResult

        try await monitors.start(testImmediately: false)
        await tunnelFailureMonitor.fire(.failureDetected)
        await waitForSpawnedTasks()

        XCTAssertEqual(hooks.lastFailureRecoveryConfigUpdate?.server.serverName, configResult.server.serverName)
    }

    func testTunnelFailureCallback_failureDetected_whenRecoveryAppliesConfig_firesOneUnhealthyCompletedEvent() async throws {
        failureRecoveryHandler.configResultToUpdate = makeFailureRecoveryConfigResult()
        failureRecoveryHandler.afterSuccessfulConfigUpdate = { [weak firedEvents] in
            firedEvents?.events.append(.failureRecoveryAttempt(.completed(.unhealthy)))
        }

        try await monitors.start(testImmediately: false)
        await tunnelFailureMonitor.fire(.failureDetected)
        await waitForSpawnedTasks()

        let unhealthyCompletionCount = firedEvents.events.filter { event in
            if case .failureRecoveryAttempt(.completed(.unhealthy)) = event { return true }
            return false
        }.count
        XCTAssertEqual(unhealthyCompletionCount, 1)
    }

    func testTunnelFailureCallback_failureRecovered_stopsFailureRecovery() async throws {
        try await monitors.start(testImmediately: false)
        await tunnelFailureMonitor.fire(.failureRecovered)
        await waitForSpawnedTasks()

        XCTAssertEqual(failureRecoveryHandler.stopCount, 1)
    }

    func testTunnelFailureCallback_networkPathChanged_doesNotInvokeRecovery() async throws {
        try await monitors.start(testImmediately: false)
        await tunnelFailureMonitor.fire(.networkPathChanged("eth0"))
        await waitForSpawnedTasks()

        XCTAssertEqual(failureRecoveryHandler.attemptCount, 0)
        XCTAssertEqual(failureRecoveryHandler.stopCount, 0)
    }

    // MARK: - Latency callback

    func testLatencyCallback_quality_firesReportLatency() async throws {
        try await monitors.start(testImmediately: false)
        await latencyMonitor.fire(.quality(.unknown))

        let reported = firedEvents.events.contains { event in
            if case .reportLatency(.quality, _) = event { return true }
            return false
        }
        XCTAssertTrue(reported)
    }

    func testLatencyCallback_error_firesReportLatency() async throws {
        try await monitors.start(testImmediately: false)
        await latencyMonitor.fire(.error)

        let reported = firedEvents.events.contains { event in
            if case .reportLatency(.error, _) = event { return true }
            return false
        }
        XCTAssertTrue(reported)
    }

    // MARK: - Entitlement callback

    func testEntitlementCallback_invalidEntitlement_invokesOnAccessRevoked() async throws {
        try await monitors.start(testImmediately: false)
        await entitlementMonitor.fire(.invalidEntitlement)

        XCTAssertEqual(hooks.accessRevokedCount, 1)
    }

    func testEntitlementCallback_validEntitlement_doesNotInvokeOnAccessRevoked() async throws {
        try await monitors.start(testImmediately: false)
        await entitlementMonitor.fire(.validEntitlement)

        XCTAssertEqual(hooks.accessRevokedCount, 0)
    }

    func testEntitlementCallback_error_doesNotInvokeOnAccessRevoked() async throws {
        struct EntitlementError: Error {}

        try await monitors.start(testImmediately: false)
        await entitlementMonitor.fire(.error(EntitlementError()))

        XCTAssertEqual(hooks.accessRevokedCount, 0)
    }

    // MARK: - Server-status callback

    func testServerStatusCallback_shouldMigrate_invokesReconfigure_firesSuccess() async throws {
        try await monitors.start(testImmediately: false)
        await serverStatusMonitor.fire(.serverMigrationRequested)
        await waitForSpawnedTasks()

        XCTAssertEqual(hooks.reconfigureForMigrationCount, 1)
        let kinds = firedEvents.events.compactMap { event -> String? in
            if case .serverMigrationAttempt(.begin) = event { return "begin" }
            if case .serverMigrationAttempt(.success) = event { return "success" }
            if case .serverMigrationAttempt(.failure) = event { return "failure" }
            return nil
        }
        XCTAssertEqual(kinds, ["begin", "success"])
    }

    func testServerStatusCallback_error_doesNotInvokeReconfigure() async throws {
        struct StatusError: Error {}

        try await monitors.start(testImmediately: false)
        await serverStatusMonitor.fire(.error(StatusError()))
        await waitForSpawnedTasks()

        XCTAssertEqual(hooks.reconfigureForMigrationCount, 0)
        let migrationEventFired = firedEvents.events.contains { event in
            if case .serverMigrationAttempt = event { return true }
            return false
        }
        XCTAssertFalse(migrationEventFired)
    }

    func testServerStatusCallback_shouldMigrate_whenReconfigureThrows_firesFailure() async throws {
        struct MigrationError: Error {}
        hooks.reconfigureForMigrationError = MigrationError()

        try await monitors.start(testImmediately: false)
        await serverStatusMonitor.fire(.serverMigrationRequested)
        await waitForSpawnedTasks()

        let kinds = firedEvents.events.compactMap { event -> String? in
            if case .serverMigrationAttempt(.begin) = event { return "begin" }
            if case .serverMigrationAttempt(.success) = event { return "success" }
            if case .serverMigrationAttempt(.failure) = event { return "failure" }
            return nil
        }
        XCTAssertEqual(kinds, ["begin", "failure"])
    }

    // MARK: - Connection-tester result handler

    func testConnectionTester_resultHandlerWiredToHook() async {
        let handler = connectionTester.resultHandler
        XCTAssertNotNil(handler)
        handler?(.connected)

        XCTAssertNotNil(hooks.lastConnectionTestResult)
        if case .connected = hooks.lastConnectionTestResult {
            // expected
        } else {
            XCTFail("expected .connected, got \(String(describing: hooks.lastConnectionTestResult))")
        }
    }
}

// MARK: - Sendable boxes

private final class FiredEventsBox: @unchecked Sendable {
    var events: [PacketTunnelProvider.Event] = []
}

private final class TunablesBox: @unchecked Sendable {
    var entitlementResult: Result<Bool, Error> = .success(true)
    var connectionTesterEnabled: Bool = true
}

private final class HooksBox: @unchecked Sendable {
    var reconfigureForMigrationCount = 0
    var reconfigureForMigrationError: Error?
    var lastConnectionTestResult: ConnectionTestingResult?
    var lastFailureRecoveryConfigUpdate: NetworkProtectionDeviceManagement.GenerateTunnelConfigurationResult?
    var failureRecoveryConfigUpdateError: Error?
    var accessRevokedCount = 0
}

// MARK: - Monitor mocks

private actor MockTunnelFailureMonitor: TunnelFailureMonitoring {
    var isStartedValue = false
    var startCount = 0
    var stopCount = 0
    private var capturedCallback: ((NetworkProtectionTunnelFailureMonitor.Result) -> Void)?

    var isStarted: Bool { isStartedValue }

    func start(callback: @escaping (NetworkProtectionTunnelFailureMonitor.Result) -> Void) {
        startCount += 1
        isStartedValue = true
        capturedCallback = callback
    }

    func stop() {
        stopCount += 1
        isStartedValue = false
    }

    func fire(_ result: NetworkProtectionTunnelFailureMonitor.Result) {
        capturedCallback?(result)
    }
}

private actor MockLatencyMonitor: LatencyMonitoring {
    var isStartedValue = false
    var startCount = 0
    var stopCount = 0
    var lastServerIP: IPv4Address?
    private var capturedCallback: ((NetworkProtectionLatencyMonitor.Result) -> Void)?

    var isStarted: Bool { isStartedValue }

    func start(serverIP: IPv4Address,
               callback: @escaping (NetworkProtectionLatencyMonitor.Result) -> Void) {
        startCount += 1
        lastServerIP = serverIP
        capturedCallback = callback
        isStartedValue = true
    }

    func stop() {
        stopCount += 1
        isStartedValue = false
    }

    func fire(_ result: NetworkProtectionLatencyMonitor.Result) {
        capturedCallback?(result)
    }
}

private actor MockEntitlementMonitor: EntitlementMonitoring {
    var isStartedValue = false
    var startCount = 0
    var stopCount = 0
    private var capturedCallback: ((NetworkProtectionEntitlementMonitor.Result) async -> Void)?

    var isStarted: Bool { isStartedValue }

    func start(entitlementCheck: @escaping () async -> Result<Bool, Error>,
               callback: @escaping (NetworkProtectionEntitlementMonitor.Result) async -> Void) {
        startCount += 1
        isStartedValue = true
        capturedCallback = callback
    }

    func stop() {
        stopCount += 1
        isStartedValue = false
    }

    func fire(_ result: NetworkProtectionEntitlementMonitor.Result) async {
        await capturedCallback?(result)
    }
}

private actor MockServerStatusMonitor: ServerStatusMonitoring {
    var isStartedValue = false
    var startCount = 0
    var stopCount = 0
    var lastServerName: String?
    private var capturedCallback: ((NetworkProtectionServerStatusMonitor.ServerStatusResult) -> Void)?

    var isStarted: Bool { isStartedValue }

    func start(serverName: String,
               callback: @escaping (NetworkProtectionServerStatusMonitor.ServerStatusResult) -> Void) {
        startCount += 1
        lastServerName = serverName
        capturedCallback = callback
        isStartedValue = true
    }

    func stop() {
        stopCount += 1
        isStartedValue = false
    }

    func fire(_ result: NetworkProtectionServerStatusMonitor.ServerStatusResult) {
        capturedCallback?(result)
    }
}

private actor MockKeyExpirationTester: KeyExpirationTesting {
    var startCount = 0
    var stopCount = 0
    var rekeyIfExpiredCount = 0
    var lastKeyValidity: TimeInterval??

    func start(testImmediately: Bool) async {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func setKeyValidity(_ validity: TimeInterval?) {
        lastKeyValidity = .some(validity)
    }

    func rekeyIfExpired() async {
        rekeyIfExpiredCount += 1
    }
}

@MainActor
private final class MockConnectionTester: ConnectionTesting {
    var resultHandler: (@MainActor (ConnectionTestingResult) -> Void)?
    var startCount = 0
    var stopCount = 0
    var lastTunnelIfName: String?
    var lastTestImmediately: Bool?
    var startError: Error?
    var failNextTestCalled = false

    func start(tunnelIfName: String, testImmediately: Bool) async throws {
        startCount += 1
        lastTunnelIfName = tunnelIfName
        lastTestImmediately = testImmediately
        if let startError {
            throw startError
        }
    }

    func stop() {
        stopCount += 1
    }

    func failNextTest() {
        failNextTestCalled = true
    }
}

private final class MockFailureRecoveryHandler: FailureRecoveryHandling, @unchecked Sendable {
    var attemptCount = 0
    var stopCount = 0
    var lastServer: NetworkProtectionServer?
    var lastExcludeLocalNetworks: Bool?
    var lastExcludeCGNAT: Bool?
    var lastDNSSettings: NetworkProtectionDNSSettings?
    var configResultToUpdate: NetworkProtectionDeviceManagement.GenerateTunnelConfigurationResult?
    var afterSuccessfulConfigUpdate: (@MainActor () -> Void)?

    func attemptRecovery(
        to lastConnectedServer: NetworkProtectionServer,
        excludeLocalNetworks: Bool,
        excludeCGNAT: Bool,
        dnsSettings: NetworkProtectionDNSSettings,
        updateConfig: @escaping (NetworkProtectionDeviceManagement.GenerateTunnelConfigurationResult) async throws -> Void
    ) async {
        attemptCount += 1
        lastServer = lastConnectedServer
        lastExcludeLocalNetworks = excludeLocalNetworks
        lastExcludeCGNAT = excludeCGNAT
        lastDNSSettings = dnsSettings

        if let configResultToUpdate {
            do {
                try await updateConfig(configResultToUpdate)
                await afterSuccessfulConfigUpdate?()
            } catch {
                // updateConfig is not expected to throw in these tests.
            }
        }
    }

    func stop() async {
        stopCount += 1
    }
}
