//
//  NetworkProtectionConnectionTester.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Foundation
import Network
import NetworkExtension
import Common
import os.log

/// This class takes care of testing whether the Network Protection connection is working or not.  Results are handled by
/// an injected object that implements ``NetworkProtectionConnectionTestResultsHandler``.
///
/// In order to test that the connection is working, this class test creating a TCP connection to "www.duckduckgo.com" using
/// the HTTPs port (443) both with and without using the tunnel.  The tunnel connection will be considered to be disconnected
/// whenever the regular connection works fine but the tunnel connection doesn't.
///
@MainActor
final class NetworkProtectionConnectionTester {
    enum Result {
        case connected
        case reconnected(failureCount: Int)
        case disconnected(failureCount: Int)
    }

    enum TesterError: Error {
        case couldNotFindInterface(named: String)
        case connectionTestFailed
    }

    /// Provides a simple mechanism to synchronize an `isRunning` flag for the tester to know if it needs to interrupt its operation.
    /// The reason why this is necessary is that the tester may be stopped while the connection tests are already executing, in a bit
    /// of a race condition which could result in the tester returning results when it's already stopped.
    ///
    private(set) var isRunning = false

    static let connectionTestQueue = DispatchQueue(label: "com.duckduckgo.NetworkProtectionConnectionTester.connectionTestQueue")
    static let monitorQueue = DispatchQueue(label: "com.duckduckgo.NetworkProtectionConnectionTester.monitorQueue")
    static let endpoint = NWEndpoint.hostPort(host: .name("www.duckduckgo.com", nil), port: .https)

    private var task: Task<Never, Error>?

    // MARK: - Dispatch Queue

    private let timerQueue: DispatchQueue

    // MARK: - Tunnel Data

    /// This monitor will be used to retrieve the tunnel's NWInterface
    ///
    private var monitor: NWPathMonitor?

    /// The tunnel's interface we'll use to be able to test a connection going through, and a connection going out of the tunnel.
    ///
    private var tunnelInterface: NWInterface?

    // MARK: - Timing Parameters

    /// The interval of time between the start of each TCP connection test.
    ///
    private let intervalBetweenTests: TimeInterval = .seconds(15)

    /// The time we'll waitfor the TCP connection to fail.  This should always be lower than `intervalBetweenTests`.
    ///
    private static let connectionTimeout: TimeInterval = .seconds(5)

    // MARK: - Test result handling

    private var failureCount = 0
    private let resultHandler: @MainActor (Result) -> Void

    private var simulateFailure = false

    // MARK: - Init & deinit

    init(timerQueue: DispatchQueue, resultHandler: @escaping @MainActor (Result) -> Void) {
        self.timerQueue = timerQueue
        self.resultHandler = resultHandler

        Logger.networkProtectionMemory.debug("[+] \(String(describing: self), privacy: .public)")
    }

    deinit {
        Logger.networkProtectionMemory.debug("[-] \(String(describing: self), privacy: .public)")
        task?.cancel()
    }

    // MARK: - Testing

    func failNextTest() {
        simulateFailure = true
    }

    // MARK: - Starting & Stopping the tester

    func start(tunnelIfName: String, testImmediately: Bool) async throws {
        guard !isRunning else {
            Logger.networkProtectionConnectionTester.log("Will not start the connection tester as it's already running")
            return
        }

        isRunning = true

        Logger.networkProtectionConnectionTester.log("🟢 Starting connection tester (testImmediately: \(String(reflecting: testImmediately), privacy: .public)")
        let tunnelInterface = try await networkInterface(forInterfaceNamed: tunnelIfName)
        self.tunnelInterface = tunnelInterface

        await scheduleTimer(testImmediately: testImmediately)
    }

    func stop() {
        Logger.networkProtectionConnectionTester.log("🔴 Stopping connection tester")
        stopScheduledTimer()
        isRunning = false
    }

    // MARK: - Obtaining the interface

    private func networkInterface(forInterfaceNamed interfaceName: String) async throws -> NWInterface {
        try await withCheckedThrowingContinuation { continuation in
            let monitor = NWPathMonitor()

            monitor.pathUpdateHandler = { path in
                Logger.networkProtectionConnectionTester.log("All interfaces: \(String(describing: path.availableInterfaces), privacy: .public)")

                guard let tunnelInterface = path.availableInterfaces.first(where: { $0.name == interfaceName }) else {
                    Logger.networkProtectionConnectionTester.error("Could not find VPN interface \(interfaceName, privacy: .public)")
                    monitor.cancel()
                    monitor.pathUpdateHandler = nil

                    continuation.resume(throwing: TesterError.couldNotFindInterface(named: interfaceName))
                    return
                }

                monitor.cancel()
                monitor.pathUpdateHandler = nil

                continuation.resume(returning: tunnelInterface)
            }

            monitor.start(queue: Self.monitorQueue)
        }
    }

    // MARK: - Timer scheduling

    private func scheduleTimer(testImmediately: Bool) async {
        stopScheduledTimer()

        if testImmediately {
            await testConnection()
        }

        task = Task.periodic(interval: intervalBetweenTests) { [weak self] in
            // During regular connection tests we don't care about the error thrown
            // by this method, as it'll be handled through the result handler callback.
            // The error we're ignoring here is only used when this class is initialized
            // with an immediate test, to know whether the connection is up while the user
            // still sees "Connecting..."
            await self?.testConnection()
        }
    }

    private func stopScheduledTimer() {
        task?.cancel()
        task = nil
    }

    // MARK: - Testing the connection

    func testConnection() async {
        guard let tunnelInterface = tunnelInterface else {
            Logger.networkProtectionConnectionTester.error("No interface to test!")
            return
        }

        Logger.networkProtectionConnectionTester.debug("Testing connection...")

        let vpnParameters = NWParameters.tcp
        vpnParameters.requiredInterface = tunnelInterface

        let localParameters = NWParameters.tcp
        localParameters.prohibitedInterfaces = [tunnelInterface]

        // This is a bit ugly, but it's a quick way to run the tests in parallel without a task group.
        async let vpnConnected = testConnection(name: "VPN", parameters: vpnParameters)
        async let localConnected = testConnection(name: "Local", parameters: localParameters)
        let vpnIsConnected = await vpnConnected
        let localIsConnected = await localConnected

        let onlyVPNIsDown = simulateFailure || (!vpnIsConnected && localIsConnected)
        simulateFailure = false

        // After completing the connection tests we check if the tester is still supposed to be running
        // to avoid giving results when it should not be running.
        guard isRunning else {
            Logger.networkProtectionConnectionTester.log("Tester skipped returning results as it was stopped while running the tests")
            return
        }

        if onlyVPNIsDown {
            Logger.networkProtectionConnectionTester.log("👎 VPN is DOWN")
            handleDisconnected()
        } else {
            Logger.networkProtectionConnectionTester.log("👍 VPN: \(vpnIsConnected ? "UP" : "DOWN", privacy: .public) local: \(localIsConnected ? "UP" : "DOWN", privacy: .public)")
            handleConnected()
        }
    }

    private func testConnection(name: String, parameters: NWParameters) async -> Bool {
        let connection = NWConnection(to: Self.endpoint, using: parameters)
        let stateUpdateStream = connection.stateUpdateStream

        connection.start(queue: Self.connectionTestQueue)
        defer {
            connection.cancel()
        }

        do {
            // await for .ready connection state and consider working
            return try await withTimeout(Self.connectionTimeout) {
                for await state in stateUpdateStream {
                    if case .ready = state {
                        return true
                    }
                }
                return false
            }
        } catch {
            // timeout
            return false
        }
    }

    // MARK: - Result handling

    @MainActor
    private func handleConnected() {
        if failureCount == 0 {
            resultHandler(.connected)
        } else if failureCount > 0 {
            resultHandler(.reconnected(failureCount: failureCount))
            failureCount = 0
        }
    }

    @MainActor
    private func handleDisconnected() {
        failureCount += 1
        resultHandler(.disconnected(failureCount: failureCount))
    }
}
