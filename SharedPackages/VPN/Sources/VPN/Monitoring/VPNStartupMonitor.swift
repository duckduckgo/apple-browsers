//
//  VPNStartupMonitor.swift
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

import Foundation
import NetworkExtension

/// Monitors VPN startup to detect successful connection or failure
public final class VPNStartupMonitor {

    public enum StartupError: Error, CustomNSError {
        case startTunnelDisconnectedSilently(underlyingError: Error?)
        case startTunnelTimedOut

        var errorDescription: String? {
            switch self {
            case .startTunnelDisconnectedSilently:
#if DEBUG
                return "[DEBUG] The connection attempt failed silently, please try again"
#else
                return "An unexpected error occurred, please try again"
#endif
            case .startTunnelTimedOut:
#if DEBUG
                return "[DEBUG] The connection attempt timed out, please try again"
#else
                return "An unexpected error occurred, please try again"
#endif
            }
        }

        public var errorCode: Int {
            switch self {
            case .startTunnelDisconnectedSilently: return 1
            case .startTunnelTimedOut: return 2
            }
        }

        public var errorUserInfo: [String: Any] {
            switch self {
            case .startTunnelDisconnectedSilently(let underlyingError):
                if let underlyingError {
                    return [NSUnderlyingErrorKey: underlyingError]
                }
                return [:]
            case .startTunnelTimedOut:
                return [:]
            }
        }
    }

    private let notificationCenter: NotificationCenter
    private let statusProvider: (NEVPNConnection) -> NEVPNStatus
    private let disconnectErrorProvider: (NEVPNConnection) async throws -> Void

    public init(notificationCenter: NotificationCenter = .default,
                statusProvider: @escaping (NEVPNConnection) -> NEVPNStatus = { $0.status },
                disconnectErrorProvider: @escaping (NEVPNConnection) async throws -> Void = { connection in
                    if #available(macOS 13, iOS 16, *) {
                        try await connection.fetchLastDisconnectError()
                    }
                }) {
        self.notificationCenter = notificationCenter
        self.statusProvider = statusProvider
        self.disconnectErrorProvider = disconnectErrorProvider
    }

    /// Classifies an observed VPN status while waiting for a terminal state.
    private enum WaitOutcome {
        case keepWaiting
        case finished
        case failed(Error)
    }

    /// Waits for VPN startup to complete successfully or fail
    /// - Parameters:
    ///   - tunnelManager: The tunnel manager to monitor
    ///   - timeout: Maximum time to wait (default 10 seconds)
    public func waitForStartSuccess(
        _ tunnelManager: NETunnelProviderManager,
        timeout: TimeInterval = 10
    ) async throws {
        try await waitForTerminalStatus(
            tunnelManager,
            timeout: timeout,
            timeoutError: { StartupError.startTunnelTimedOut },
            evaluate: { connection in
                switch self.statusProvider(connection) {
                case .connected:
                    return .finished
                case .disconnecting, .disconnected:
                    var underlyingError: Error?
                    do {
                        try await self.disconnectErrorProvider(connection)
                    } catch {
                        underlyingError = error
                    }
                    return .failed(StartupError.startTunnelDisconnectedSilently(underlyingError: underlyingError))
                default:
                    return .keepWaiting
                }
            }
        )
    }

    /// Waits for the VPN to reach a fully stopped state (`.disconnected`/`.invalid`).
    ///
    /// `stopVPNTunnel()` is fire-and-forget: it returns while the connection is still `.connected`
    /// or `.disconnecting`. A caller that restarts the tunnel must wait for the disconnect to settle
    /// before starting again, otherwise the start races the teardown and the VPN can end up off.
    ///
    /// Best-effort: on timeout it simply returns so the caller can proceed.
    /// - Parameters:
    ///   - tunnelManager: The tunnel manager to monitor
    ///   - timeout: Maximum time to wait (default 10 seconds)
    public func waitForStop(
        _ tunnelManager: NETunnelProviderManager,
        timeout: TimeInterval = 10
    ) async {
        try? await waitForTerminalStatus(
            tunnelManager,
            timeout: timeout,
            timeoutError: { nil },
            evaluate: { connection in
                switch self.statusProvider(connection) {
                case .disconnected, .invalid:
                    return .finished
                default:
                    return .keepWaiting
                }
            }
        )
    }

    /// Races a per-connection `NEVPNStatusDidChange` observer against a timeout, completing when
    /// `evaluate` reports a terminal outcome for the monitored connection.
    ///
    /// On the initial status (before any notification) only `.finished` short-circuits; a `.failed`
    /// outcome is honoured only once observed via a status change.
    /// - Parameters:
    ///   - tunnelManager: The tunnel manager whose connection is monitored.
    ///   - timeout: Maximum time to wait.
    ///   - timeoutError: Error to throw when the timeout elapses, or `nil` to return silently.
    ///   - evaluate: Classifies an observed status as `.keepWaiting`, `.finished`, or `.failed`.
    private func waitForTerminalStatus(
        _ tunnelManager: NETunnelProviderManager,
        timeout: TimeInterval,
        timeoutError: @escaping () -> Error?,
        evaluate: @escaping (NEVPNConnection) async -> WaitOutcome
    ) async throws {
        try Task.checkCancellation()

        let statusChange = NSNotification.Name.NEVPNStatusDidChange

        try await withThrowingTaskGroup(of: Void.self) { group in
            let targetConnection = tunnelManager.connection

            group.addTask {
                try Task.checkCancellation()

                // Evaluate the current status first, in case the connection is already terminal
                // and no further status-change notification is coming.
                if case .finished = await evaluate(targetConnection) {
                    return
                }

                for await notification in self.notificationCenter.notifications(named: statusChange) {
                    try Task.checkCancellation()

                    guard let connection = notification.object as? NEVPNConnection,
                          connection === targetConnection else {
                        continue
                    }

                    switch await evaluate(connection) {
                    case .finished:
                        return
                    case .failed(let error):
                        throw error
                    case .keepWaiting:
                        continue
                    }
                }

                try Task.checkCancellation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let error = timeoutError() {
                    throw error
                }
            }

            try await group.next()
            group.cancelAll()
        }
    }
}
