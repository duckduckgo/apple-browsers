//
//  VPNConnectionStatusMonitor.swift
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

import Combine
import Foundation
import NetworkExtension

/// Observes fresh connection events for the lifetime of a VPN controller.
public final class VPNConnectionStatusMonitor {
    private let notificationCenter: NotificationCenter
    private let statusProvider: (NEVPNConnection) -> NEVPNStatus
    private let disconnectErrorProvider: (NEVPNConnection) async throws -> Void
    private let failureLock = NSLock()
    private var pendingFailureRevision = UUID()
    @MainActor private var observation: AnyCancellable?
    @MainActor private var observationRevision = UUID()
    @MainActor private var failureRevisions: [ObjectIdentifier: UUID] = [:]

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

    /// Status events preserve the raw notification semantics. Failure lookup is opt-in and scoped to the current profile.
    /// Installing an observer never reads a potentially stale last-disconnect error.
    @MainActor
    public func observe(
        onStatus: @escaping @MainActor (NEVPNConnection, NEVPNStatus) -> Void,
        currentConnection: (@MainActor () async -> NEVPNConnection?)? = nil,
        onFailure: (@MainActor (NEVPNConnection, PacketTunnelProvider.TunnelError.Code) async -> Void)? = nil
    ) {
        stopObserving()
        let revision = observationRevision
        observation = notificationCenter.publisher(for: .NEVPNStatusDidChange)
            .sink { [weak self] notification in
                guard let self, let connection = notification.object as? NETunnelProviderSession else { return }
                let status = self.statusProvider(connection)
                let pendingRevision = onFailure != nil && currentConnection != nil
                    ? self.failureLock.withLock { self.pendingFailureRevision } : nil
                Task { @MainActor [weak self] in
                    guard let self, self.observationRevision == revision else { return }
                    let identifier = ObjectIdentifier(connection)
                    if status == .connected || status == .reasserting || status == .invalid {
                        self.failureRevisions.removeValue(forKey: identifier)
                    }
                    onStatus(connection, status)
                    guard status == .disconnecting || status == .disconnected,
                          let currentConnection, let onFailure, let pendingRevision,
                          self.failureLock.withLock({ self.pendingFailureRevision == pendingRevision }) else { return }
                    let failureRevision = self.failureRevisions[identifier, default: UUID()]
                    self.failureRevisions[identifier] = failureRevision
                    let isCurrentFailure = {
                        self.observationRevision == revision && self.failureRevisions[identifier] == failureRevision
                            && self.failureLock.withLock { self.pendingFailureRevision == pendingRevision }
                    }
                    guard await currentConnection() === connection else {
                        // The provisional revision also catches success or invalidation while profile resolution awaits.
                        if self.failureRevisions[identifier] == failureRevision {
                            self.failureRevisions.removeValue(forKey: identifier)
                        }
                        return
                    }
                    guard isCurrentFailure() else { return }
                    guard let code = await self.lastStartupFailure(on: connection),
                          await currentConnection() === connection,
                          isCurrentFailure() else { return }
                    // A retry may already be connecting. Only a success, invalidation, or deliberate operation
                    // supersedes an observed failure; automatic retries must still allow recovery.
                    let currentStatus = self.statusProvider(connection)
                    guard currentStatus != .connected, currentStatus != .reasserting, currentStatus != .invalid else { return }
                    await onFailure(connection, code)
                }
            }
    }

    /// The launch check is notification-only. A new or recovered connection supersedes the historical error.
    @MainActor
    public func hasStartupFailureAtLaunch(on connection: NEVPNConnection) async -> Bool {
        guard statusProvider(connection) == .disconnected else { return false }
        let identifier = ObjectIdentifier(connection)
        let revision = failureRevisions[identifier, default: UUID()]
        failureRevisions[identifier] = revision
        guard await lastStartupFailure(on: connection) != nil else { return false }
        return statusProvider(connection) == .disconnected && failureRevisions[identifier] == revision
    }

    @MainActor
    private func lastStartupFailure(on connection: NEVPNConnection) async -> PacketTunnelProvider.TunnelError.Code? {
        do {
            try await disconnectErrorProvider(connection)
            return nil
        } catch {
            let failure = VPNStartupMonitor.StartupError.startTunnelDisconnectedSilently(underlyingError: error)
            guard let reason = failure.disconnectReason,
                  reason.domain == PacketTunnelProvider.TunnelError.errorDomain,
                  let code = PacketTunnelProvider.TunnelError.Code(rawValue: reason.code),
                  code == .startingTunnelWithoutAuthToken || code == .reconnectBlocked else { return nil }
            return code
        }
    }

    /// Discards outstanding error lookups when the controller deliberately starts or stops the VPN.
    @MainActor
    public func resetPendingFailures() {
        failureLock.withLock { pendingFailureRevision = UUID() }
        failureRevisions.removeAll()
    }

    @MainActor
    public func stopObserving() {
        observation = nil
        observationRevision = UUID()
        failureRevisions.removeAll()
    }
}
