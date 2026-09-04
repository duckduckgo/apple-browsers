//
//  EndpointPortFallback.swift
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

import ConcurrencyExtensions
import Foundation
import os.log

/// Waits for the first WireGuard handshake after the adapter starts and, when none
/// arrives in time, moves the endpoint through the server's advertised ports.
///
/// WireGuard never signals a failed handshake: a port that the network drops just
/// leaves the most-recent-handshake timestamp unchanged. This controller sends a
/// probe so the adapter has a reason to handshake, then polls that timestamp.
@MainActor
final class EndpointPortFallback {

    enum Outcome: Equatable {
        /// A handshake completed while the endpoint used this port.
        case handshake(port: UInt16)
        /// Every candidate was tried without a handshake.
        case exhausted(triedPorts: [UInt16])
        /// The run was cancelled before it finished.
        case cancelled
        /// The adapter's handshake state could not be read, so no port was changed.
        case handshakeStatusUnavailable
    }

    struct Configuration {
        /// How long to wait for a handshake on each port. wireguard-go sends the
        /// first initiation as soon as there is traffic and retries after 5s, so
        /// 6s gives two attempts per port.
        var handshakeTimeout: TimeInterval = 6
        var pollInterval: TimeInterval = 1
    }

    private let handshakeReporter: HandshakeReporting
    private let probe: @MainActor () async -> Void
    private let applyPort: @MainActor (UInt16) async throws -> Void
    private let sleep: (TimeInterval) async throws -> Void
    private let configuration: Configuration

    /// Number of `pollInterval` waits per port, derived once from the configuration.
    /// A timed-out port performs `pollsPerPort + 1` reads and `pollsPerPort` sleeps.
    private let pollsPerPort: Int

    init(handshakeReporter: HandshakeReporting,
         probe: @escaping @MainActor () async -> Void,
         applyPort: @escaping @MainActor (UInt16) async throws -> Void,
         sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(interval: $0) },
         configuration: Configuration = Configuration()) {
        precondition(configuration.pollInterval > 0)

        self.handshakeReporter = handshakeReporter
        self.probe = probe
        self.applyPort = applyPort
        self.sleep = sleep
        self.configuration = configuration
        self.pollsPerPort = max(1, Int((configuration.handshakeTimeout / configuration.pollInterval).rounded()))
    }

    /// Runs the gate. `currentPort` is the port the adapter is already using.
    /// `candidates` is the ordered list to try; if its first element differs from
    /// `currentPort`, that port is applied before the first wait.
    func run(candidates: [UInt16], currentPort: UInt16) async -> Outcome {
        guard !candidates.isEmpty else {
            return .exhausted(triedPorts: [])
        }

        let baseline: TimeInterval
        switch await readBaseline() {
        case .value(let value):
            baseline = value
        case .unavailable:
            Logger.networkProtection.log("🔵 Port fallback: handshake status unavailable, not changing port")
            return .handshakeStatusUnavailable
        case .cancelled:
            return .cancelled
        }

        var appliedPort = currentPort
        var triedPorts: [UInt16] = []

        for candidate in candidates {
            if Task.isCancelled {
                return .cancelled
            }

            if candidate != appliedPort {
                do {
                    try await applyPort(candidate)
                    appliedPort = candidate
                } catch {
                    Logger.networkProtection.error("🔵 Port fallback: failed to apply port \(candidate, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    triedPorts.append(candidate)
                    continue
                }
            }

            await probe()

            switch await waitForHandshake(baseline: baseline) {
            case .handshake:
                Logger.networkProtection.log("🔵 Port fallback: handshake on port \(candidate, privacy: .public)")
                return .handshake(port: candidate)
            case .cancelled:
                return .cancelled
            case .timedOut:
                triedPorts.append(candidate)
                Logger.networkProtection.log("🔵 Port fallback: no handshake on port \(candidate, privacy: .public) after \(self.configuration.handshakeTimeout, privacy: .public)s")
            }
        }

        return .exhausted(triedPorts: triedPorts)
    }

    private enum BaselineResult {
        case value(TimeInterval)
        case unavailable
        case cancelled
    }

    /// Reads the handshake timestamp to use as the baseline, retrying at the same
    /// cadence as `waitForHandshake` (up to `pollsPerPort + 1` reads) since a thrown
    /// error here must not be silently treated as a baseline of 0 - a stale non-zero
    /// timestamp from a reused peer would then be mistaken for a fresh handshake.
    private func readBaseline() async -> BaselineResult {
        var attempt = 0

        while true {
            if let value = try? await handshakeReporter.getMostRecentHandshake() {
                return .value(value)
            }

            attempt += 1
            if attempt > pollsPerPort {
                return .unavailable
            }

            do {
                try await sleep(configuration.pollInterval)
            } catch {
                return .cancelled
            }
        }
    }

    private enum WaitResult {
        case handshake
        case cancelled
        case timedOut
    }

    /// Polls the handshake timestamp until it moves past `baseline`, or until
    /// `pollsPerPort` sleeps have passed without one.
    private func waitForHandshake(baseline: TimeInterval) async -> WaitResult {
        var attempt = 0

        while true {
            let mostRecentHandshake = (try? await handshakeReporter.getMostRecentHandshake()) ?? 0
            if mostRecentHandshake > baseline {
                return .handshake
            }

            attempt += 1
            if attempt > pollsPerPort {
                return .timedOut
            }

            do {
                try await sleep(configuration.pollInterval)
            } catch {
                return .cancelled
            }
        }
    }
}
