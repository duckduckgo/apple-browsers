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

import Common
import ConcurrencyExtensions
import Foundation
import FoundationExtensions
import Network
import NetworkExtension
import os.log

/// This class takes care of testing whether the Network Protection connection is working or not.  Results are handled by
/// an injected object that implements ``NetworkProtectionConnectionTestResultsHandler``.
///
/// In order to test that the connection is working, this class test creating a TCP connection to "www.duckduckgo.com" using
/// the HTTPs port (443) both with and without using the tunnel.  The tunnel connection will be considered to be disconnected
/// whenever the regular connection works fine but the tunnel connection doesn't.
///
@MainActor
final class NetworkProtectionConnectionTester: ConnectionTesting {

    typealias Result = ConnectionTestingResult

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
    private var startupTask: Task<Void, Error>?

    // MARK: - Dispatch Queue

    private let timerQueue: DispatchQueue

    // MARK: - Tunnel Data

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
    var resultHandler: (@MainActor (Result) -> Void)?

    private var simulateFailure = false
    private var testGeneration = UUID()
    private let connectivityResultHandler: ((Bool, Date) -> Void)?
    private let prepareConnectionTest: ((String) async throws -> Void)?
    private let performConnectionTest: (() async throws -> (vpn: Bool, local: Bool))?

    // MARK: - Init & deinit

    init(timerQueue: DispatchQueue,
         connectivityResultHandler: ((Bool, Date) -> Void)? = nil,
         prepareConnectionTest: ((String) async throws -> Void)? = nil,
         performConnectionTest: (() async throws -> (vpn: Bool, local: Bool))? = nil) {
        self.timerQueue = timerQueue
        self.connectivityResultHandler = connectivityResultHandler
        self.prepareConnectionTest = prepareConnectionTest
        self.performConnectionTest = performConnectionTest

        Logger.networkProtectionMemory.debug("[+] \(String(describing: self), privacy: .public)")
    }

    deinit {
        Logger.networkProtectionMemory.debug("[-] \(String(describing: self), privacy: .public)")
        startupTask?.cancel()
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
        let generation = UUID()
        testGeneration = generation

        Logger.networkProtectionConnectionTester.log("🟢 Starting connection tester (testImmediately: \(String(reflecting: testImmediately), privacy: .public)")
        let startupTask = Task { [weak self] in
            guard let self else { return }
            try Task.checkCancellation()
            if let prepareConnectionTest = self.prepareConnectionTest {
                try await prepareConnectionTest(tunnelIfName)
            } else {
                let interface = try await self.networkInterface(forInterfaceNamed: tunnelIfName)
                try Task.checkCancellation()
                self.tunnelInterface = interface
            }
            try Task.checkCancellation()
            guard self.isRunning, generation == self.testGeneration else { throw CancellationError() }
            await self.scheduleTimer(testImmediately: testImmediately)
            try Task.checkCancellation()
        }
        self.startupTask = startupTask

        do {
            try await withTaskCancellationHandler {
                try await startupTask.value
                try Task.checkCancellation()
            } onCancel: {
                startupTask.cancel()
            }
        } catch is CancellationError {
            if generation == testGeneration { stop() }
            // A normal stop (for example, sleep) is not a startup failure for our caller.
            if Task.isCancelled { throw CancellationError() }
        } catch {
            if generation == testGeneration { stop() }
            throw error
        }
    }

    func stop() {
        Logger.networkProtectionConnectionTester.log("🔴 Stopping connection tester")
        startupTask?.cancel()
        startupTask = nil
        stopScheduledTimer()
        tunnelInterface = nil
        isRunning = false
        testGeneration = UUID()
    }

    // MARK: - Obtaining the interface

    private func networkInterface(forInterfaceNamed interfaceName: String) async throws -> NWInterface {
        try Task.checkCancellation()
        let monitor = NWPathMonitor()
        let (paths, continuation) = AsyncStream.makeStream(of: Network.NWPath.self)
        monitor.pathUpdateHandler = { continuation.yield($0) }
        monitor.start(queue: Self.monitorQueue)
        defer {
            monitor.pathUpdateHandler = nil
            monitor.cancel()
            continuation.finish()
        }

        for await path in paths {
            try Task.checkCancellation()
            Logger.networkProtectionConnectionTester.log("All interfaces: \(String(describing: path.availableInterfaces), privacy: .public)")
            guard let interface = path.availableInterfaces.first(where: { $0.name == interfaceName }) else {
                throw TesterError.couldNotFindInterface(named: interfaceName)
            }
            return interface
        }
        throw CancellationError()
    }

    // MARK: - Timer scheduling

    private func scheduleTimer(testImmediately: Bool) async {
        let generation = testGeneration
        stopScheduledTimer()

        if testImmediately {
            await testConnection(expectedGeneration: generation)
        }

        guard !Task.isCancelled, isRunning, generation == testGeneration else { return }
        task = Task.periodic(interval: intervalBetweenTests) { [weak self] in
            await self?.testConnection(expectedGeneration: generation)
        }
    }

    private func stopScheduledTimer() {
        task?.cancel()
        task = nil
    }

    // MARK: - Testing the connection

    func testConnection(expectedGeneration: UUID? = nil) async {
        if let expectedGeneration, expectedGeneration != testGeneration { return }
        guard !Task.isCancelled else { return }
        let startedAt = Date()
        let generation = testGeneration

        do {
            let result: (vpn: Bool, local: Bool)
            if let performConnectionTest {
                result = try await performConnectionTest()
            } else {
                guard let tunnelInterface else { return }
                let vpnParameters = NWParameters.tcp
                vpnParameters.requiredInterface = tunnelInterface
                let localParameters = NWParameters.tcp
                localParameters.prohibitedInterfaces = [tunnelInterface]
                async let vpnConnected = testConnection(parameters: vpnParameters)
                async let localConnected = testConnection(parameters: localParameters)
                result = try await (vpnConnected, localConnected)
            }
            try Task.checkCancellation()
            guard isRunning, generation == testGeneration else { return }

            let onlyVPNIsDown = simulateFailure || (!result.vpn && result.local)
            simulateFailure = false
            connectivityResultHandler?(result.vpn, startedAt)

            if onlyVPNIsDown {
                Logger.networkProtectionConnectionTester.log("👎 VPN is DOWN")
                handleDisconnected()
            } else {
                Logger.networkProtectionConnectionTester.log("👍 VPN: \(result.vpn ? "UP" : "DOWN", privacy: .public) local: \(result.local ? "UP" : "DOWN", privacy: .public)")
                handleConnected()
            }
        } catch is CancellationError {
            // Cancellation is not a connectivity failure and must not reach either callback.
        } catch {
            Logger.networkProtectionConnectionTester.error("Connection check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func testConnection(parameters: NWParameters) async throws -> Bool {
        try Task.checkCancellation()
        let connection = NWConnection(to: Self.endpoint, using: parameters)
        let stateUpdateStream = connection.stateUpdateStream
        connection.start(queue: Self.connectionTestQueue)
        defer {
            connection.stateUpdateHandler = nil
            connection.cancel()
        }

        do {
            let connected = try await withTimeout(Self.connectionTimeout) {
                for await state in stateUpdateStream {
                    try Task.checkCancellation()
                    if case .ready = state { return true }
                }
                try Task.checkCancellation()
                return false
            }
            try Task.checkCancellation()
            return connected
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return false
        }
    }

    // MARK: - Result handling

    @MainActor
    private func handleConnected() {
        if failureCount == 0 {
            resultHandler?(.connected)
        } else if failureCount > 0 {
            resultHandler?(.reconnected(failureCount: failureCount))
            failureCount = 0
        }
    }

    @MainActor
    private func handleDisconnected() {
        failureCount += 1
        resultHandler?(.disconnected(failureCount: failureCount))
    }
}
