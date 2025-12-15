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

    /// Waits for VPN startup to complete successfully or fail
    /// - Parameters:
    ///   - tunnelManager: The tunnel manager to monitor
    ///   - timeout: Maximum time to wait (default 10 seconds)
    @available(macOS 12, *)
    public func waitForStartSuccess(
        _ tunnelManager: NETunnelProviderManager,
        timeout: TimeInterval = 10
    ) async throws {
        try Task.checkCancellation()

        let statusChange = NSNotification.Name.NEVPNStatusDidChange

        try await withThrowingTaskGroup(of: Void.self) { group in
            let targetConnection = tunnelManager.connection

            group.addTask {
                try Task.checkCancellation()

                // Check status after subscribing to catch fast connections
                if self.statusProvider(targetConnection) == .connected {
                    return
                }

                for await notification in self.notificationCenter.notifications(named: statusChange) {
                    try Task.checkCancellation()

                    guard let connection = notification.object as? NEVPNConnection,
                          connection === targetConnection else {
                        continue
                    }

                    switch self.statusProvider(connection) {
                    case .connected:
                        return
                    case .disconnecting, .disconnected:
                        var underlyingError: Error?
                        do {
                            try await self.disconnectErrorProvider(targetConnection)
                        } catch {
                            underlyingError = error
                        }
                        throw StartupError.startTunnelDisconnectedSilently(underlyingError: underlyingError)
                    default:
                        continue
                    }
                }

                try Task.checkCancellation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw StartupError.startTunnelTimedOut
            }

            try await group.next()
            group.cancelAll()
        }
    }
}
