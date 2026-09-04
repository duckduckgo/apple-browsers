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

/// Finds which of a server's advertised WireGuard ports are reachable from this network.
protocol EndpointPortProbing {

    /// Sends the probe to every port in parallel and returns the ports that answered within the timeout.
    func respondingPorts(host: NWEndpoint.Host, ports: [UInt16]) async -> Set<UInt16>

}

/// Sends `DDGPROBE` over UDP and treats a `DDG` reply as proof the port is reachable.
final class EndpointPortProber: EndpointPortProbing {

    static let request = Data("DDGPROBE".utf8)
    static let expectedResponse = Data("DDG".utf8)

    private let timeout: TimeInterval
    private let retransmitInterval: TimeInterval

    init(timeout: TimeInterval = 1.5, retransmitInterval: TimeInterval = 0.5) {
        self.timeout = timeout
        self.retransmitInterval = retransmitInterval
    }

    func respondingPorts(host: NWEndpoint.Host, ports: [UInt16]) async -> Set<UInt16> {
        await withTaskGroup(of: (UInt16, Bool).self) { group in
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
    }

    private func probe(host: NWEndpoint.Host, port: UInt16) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }

        let parameters = NWParameters.udp
        // The probe must reach the physical network, not loop back through a tunnel that's already up.
        parameters.prohibitedInterfaceTypes = [.other]

        let connection = NWConnection(host: host, port: nwPort, using: parameters)
        let queue = DispatchQueue(label: "com.duckduckgo.EndpointPortProber.\(port)")

        return await withCheckedContinuation { continuation in
            var didResume = false

            func resume(_ result: Bool) {
                dispatchPrecondition(condition: .onQueue(queue))
                guard !didResume else { return }
                didResume = true
                connection.cancel()
                continuation.resume(returning: result)
            }

            func send() {
                dispatchPrecondition(condition: .onQueue(queue))
                guard !didResume else { return }
                connection.send(content: Self.request, completion: .contentProcessed { _ in })
            }

            // Arms a single-shot receive; a reply that isn't the expected one (garbled, stray, or from
            // an unrelated retransmit) just re-arms rather than failing the probe.
            func armReceive() {
                connection.receiveMessage { content, _, _, _ in
                    queue.async {
                        guard !didResume else { return }
                        if content == Self.expectedResponse {
                            resume(true)
                        } else {
                            armReceive()
                        }
                    }
                }
            }

            // A lost datagram shouldn't be read as a dead port: keep resending until `resume` runs.
            func scheduleRetransmit() {
                queue.asyncAfter(deadline: .now() + self.retransmitInterval) {
                    guard !didResume else { return }
                    send()
                    scheduleRetransmit()
                }
            }

            connection.stateUpdateHandler = { state in
                queue.async {
                    switch state {
                    case .ready:
                        armReceive()
                        send()
                        scheduleRetransmit()
                    case .failed, .cancelled:
                        resume(false)
                    default:
                        break
                    }
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                resume(false)
            }
        }
    }

}
