//
//  EndpointPortProberTests.swift
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
import Network
@testable import VPN

final class EndpointPortProberTests: XCTestCase {

    func testRespondingPorts_ReturnsOnlyThePortThatAnswersTheProbe() async throws {
        let responder = try await LoopbackResponder(reply: Data("DDG".utf8))
        defer { responder.stop() }

        // A second, never-probed listener stands in for a genuinely unused port: bind it, read the
        // port it got assigned, then cancel it before probing so it can't collide with anything else
        // in CI.
        let unusedPortHolder = try await LoopbackResponder(reply: Data("DDG".utf8))
        let unusedPort = unusedPortHolder.port
        unusedPortHolder.stop()

        let prober = EndpointPortProber(timeout: 1)

        let responding = try await prober.respondingPorts(host: .ipv4(.loopback), ports: [responder.port, unusedPort])

        XCTAssertEqual(responding, [responder.port])
    }

    func testRespondingPorts_IgnoresAListenerThatRepliesWithAPayloadThatIsOnlyAPrefixMatch() async throws {
        // Starts with "DDG" but isn't equal to it, so this pins the prober to exact-equality
        // matching rather than a prefix check.
        let responder = try await LoopbackResponder(reply: Data("DDGX".utf8))
        defer { responder.stop() }

        let prober = EndpointPortProber(timeout: 1)

        let responding = try await prober.respondingPorts(host: .ipv4(.loopback), ports: [responder.port])

        XCTAssertTrue(responding.isEmpty)
    }

    func testRespondingPorts_EmptyPortListReturnsEmptySetWithoutOpeningAnything() async throws {
        let prober = EndpointPortProber(timeout: 1)

        let responding = try await prober.respondingPorts(host: .ipv4(.loopback), ports: [])

        XCTAssertTrue(responding.isEmpty)
    }

    func testRespondingPorts_CancelledBeforeStartingThrowsCancellation() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await EndpointPortProber().respondingPorts(host: .ipv4(.loopback), ports: [])
        }

        do {
            _ = try await task.value
            XCTFail("Expected cancellation, not an empty probe result")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRespondingPorts_CancellationCompletesAllPendingProbesBeforeTimeout() async throws {
        let received = expectation(description: "Both probes reached their listeners")
        received.expectedFulfillmentCount = 2
        let first = try await LoopbackResponder(reply: nil, onFirstProbe: { received.fulfill() })
        let second = try await LoopbackResponder(reply: nil, onFirstProbe: { received.fulfill() })
        defer {
            first.stop()
            second.stop()
        }
        let completed = expectation(description: "Cancelled probes completed")

        let task = Task {
            defer { completed.fulfill() }
            return try await EndpointPortProber(timeout: 5).respondingPorts(
                host: .ipv4(.loopback), ports: [first.port, second.port])
        }
        await fulfillment(of: [received], timeout: 2)
        task.cancel()
        await fulfillment(of: [completed], timeout: 1)

        do {
            _ = try await task.value
            XCTFail("Cancellation must not be treated as unreachable ports")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRespondingPorts_RetransmitsWhenTheFirstDatagramGetsNoReply() async throws {
        let responder = try await LoopbackResponder(reply: EndpointPortProber.expectedResponse, replyAfterRequests: 2)
        defer { responder.stop() }

        let responding = try await EndpointPortProber(timeout: 2, retransmitInterval: 0.05)
            .respondingPorts(host: .ipv4(.loopback), ports: [responder.port])

        XCTAssertEqual(responding, [responder.port])
    }

}

/// A UDP listener bound to loopback that replies to every `DDGPROBE` datagram it receives with a fixed payload.
private final class LoopbackResponder {

    let port: UInt16
    private let listener: NWListener
    private let queue: DispatchQueue
    private let stopConnections: () -> Void

    init(reply: Data?, replyAfterRequests: Int = 1, onFirstProbe: (() -> Void)? = nil) async throws {
        // All stored properties are assigned from these locals once the await below completes: a class's
        // async init must not leave any property unset across a suspension point.
        let queue = DispatchQueue(label: "LoopbackResponder")
        let parameters = NWParameters.udp
        parameters.requiredInterfaceType = .loopback
        let listener = try NWListener(using: parameters, on: .any)

        var connections: [NWConnection] = []
        listener.newConnectionHandler = { [queue] connection in
            connections.append(connection)
            connection.start(queue: queue)
            var requests = 0
            func receive() {
                connection.receiveMessage { content, _, _, error in
                    guard error == nil, content == EndpointPortProber.request else { return }
                    requests += 1
                    if requests == 1 { onFirstProbe?() }
                    if let reply, requests >= replyAfterRequests {
                        connection.send(content: reply, completion: .contentProcessed { _ in })
                    }
                    receive()
                }
            }
            receive()
        }

        let resolvedPort: UInt16 = try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            listener.stateUpdateHandler = { [queue] state in
                queue.async {
                    guard !didResume else { return }
                    switch state {
                    case .ready:
                        didResume = true
                        continuation.resume(returning: listener.port!.rawValue)
                    case .failed(let error):
                        didResume = true
                        continuation.resume(throwing: error)
                    default:
                        break
                    }
                }
            }
            listener.start(queue: queue)
        }

        self.queue = queue
        self.listener = listener
        self.port = resolvedPort
        self.stopConnections = {
            queue.async {
                connections.forEach { $0.cancel() }
                connections.removeAll()
            }
        }
    }

    func stop() {
        listener.cancel()
        stopConnections()
    }

}
