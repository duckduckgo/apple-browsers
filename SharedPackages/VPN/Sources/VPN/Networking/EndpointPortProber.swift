//
//  EndpointPortProber.swift
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

import Foundation
import Network

/// Identifies server ports that answer a reachability probe.
protocol EndpointPortProbing {

    /// Returns the ports that answer concurrent probes before the timeout.
    /// Cancelling the task stops pending probes and throws `CancellationError`.
    func respondingPorts(host: NWEndpoint.Host, ports: [UInt16]) async throws -> Set<UInt16>

}

/// Checks server port reachability with parallel UDP probes.
/// Retries `DDGPROBE` until an exact `DDG` reply arrives, the timeout expires, or the task is cancelled.
final class EndpointPortProber: EndpointPortProbing {

    static let request = Data("DDGPROBE".utf8)
    static let expectedResponse = Data("DDG".utf8)

    private let timeout: TimeInterval
    private let retransmitInterval: TimeInterval

    init(timeout: TimeInterval = 1.5, retransmitInterval: TimeInterval = 0.5) {
        self.timeout = timeout
        self.retransmitInterval = retransmitInterval
    }

    func respondingPorts(host: NWEndpoint.Host, ports: [UInt16]) async throws -> Set<UInt16> {
        try Task.checkCancellation()
        let responding = await withTaskGroup(of: (UInt16, Bool).self) { group in
            for port in ports {
                group.addTask {
                    (port, await self.probe(host: host, port: port))
                }
            }

            var responding = Set<UInt16>()
            for await (port, didRespond) in group where didRespond {
                responding.insert(port)
            }
            return responding
        }
        try Task.checkCancellation()
        return responding
    }

    private func probe(host: NWEndpoint.Host, port: UInt16) async -> Bool {
        guard !Task.isCancelled, let nwPort = NWEndpoint.Port(rawValue: port) else { return false }

        let parameters = NWParameters.udp
        // The probe must reach the physical network, not loop back through a tunnel that's already up.
        parameters.prohibitedInterfaceTypes = [.other]
        let connection = NWConnection(host: host, port: nwPort, using: parameters)
        let probe = Probe(connection: connection, timeout: timeout, retransmitInterval: retransmitInterval)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                probe.start(continuation)
            }
        } onCancel: {
            probe.cancel()
        }
    }

    /// Completes one UDP probe on reply, timeout, or cancellation.
    private final class Probe: @unchecked Sendable {
        private let queue = DispatchQueue(label: "com.duckduckgo.EndpointPortProber")
        private let connection: NWConnection
        private let timeout: TimeInterval
        private let retransmitInterval: TimeInterval
        private var continuation: CheckedContinuation<Bool, Never>?
        private var didFinish = false

        init(connection: NWConnection, timeout: TimeInterval, retransmitInterval: TimeInterval) {
            self.connection = connection
            self.timeout = timeout
            self.retransmitInterval = retransmitInterval
        }

        func start(_ continuation: CheckedContinuation<Bool, Never>) {
            queue.async {
                guard !self.didFinish else {
                    continuation.resume(returning: false)
                    return
                }
                self.continuation = continuation
                self.connection.stateUpdateHandler = { [weak self] state in
                    guard let self, !self.didFinish else { return }
                    switch state {
                    case .ready:
                        self.receive()
                        self.send()
                    case .failed, .cancelled:
                        self.finish(false)
                    default:
                        break
                    }
                }
                self.connection.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + self.timeout) { [weak self] in
                    self?.finish(false)
                }
            }
        }

        func cancel() {
            queue.async {
                self.finish(false)
            }
        }

        private func finish(_ responded: Bool) {
            dispatchPrecondition(condition: .onQueue(queue))
            guard !didFinish else { return }
            didFinish = true
            connection.stateUpdateHandler = nil
            connection.cancel()
            continuation?.resume(returning: responded)
            continuation = nil
        }

        private func receive() {
            connection.receiveMessage { [weak self] content, _, _, _ in
                guard let self, !self.didFinish else { return }
                if content == EndpointPortProber.expectedResponse {
                    self.finish(true)
                } else {
                    self.receive()
                }
            }
        }

        private func send() {
            guard !didFinish else { return }
            connection.send(content: EndpointPortProber.request, completion: .contentProcessed { _ in })
            queue.asyncAfter(deadline: .now() + retransmitInterval) { [weak self] in
                self?.send()
            }
        }
    }
}
