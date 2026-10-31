//
//  DuckWireGuardProbe.swift
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

import DuckWireGuard
import Foundation
import Network

/// Exercises a real peer without requiring a packet-tunnel extension or configuring routes.
@main
struct DuckWireGuardProbe {
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            fail("Usage: duck-wireguard-probe /path/to/config.json")
        }

        do {
            let url = URL(fileURLWithPath: CommandLine.arguments[1])
            let configuration = try JSONDecoder().decode(ProbeConfiguration.self, from: Data(contentsOf: url))
            let probe = try HandshakeProbe(configuration: configuration)
            try probe.run()
            print("Authenticated WireGuard exchange completed.")
        } catch {
            fail("Probe failed: \(error.localizedDescription)")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(EXIT_FAILURE)
    }
}

private struct ProbeConfiguration: Decodable {
    let privateKey: Data
    let peerPublicKey: Data
    let presharedKey: Data?
    let host: String
    let port: UInt16
}

private enum ProbeError: LocalizedError {
    case invalidEndpoint
    case timeout
    case connectionCancelled

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "The peer host must be nonempty and its UDP port must be nonzero."
        case .timeout: return "No authenticated handshake completed within 10 seconds."
        case .connectionCancelled: return "The UDP connection was cancelled."
        }
    }
}

private final class HandshakeProbe {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "DuckWireGuardProbe")
    private let completion = DispatchSemaphore(value: 0)
    private let peer: WireGuardPeer
    // Accessed on `queue`; read by `run` only after the semaphore has signalled.
    private var result: Result<Void, Error>?
    private var retryWork: DispatchWorkItem?
    private var didStart = false

    init(configuration: ProbeConfiguration) throws {
        guard !configuration.host.isEmpty,
              configuration.port != 0,
              let port = NWEndpoint.Port(rawValue: configuration.port) else {
            throw ProbeError.invalidEndpoint
        }
        peer = try WireGuardPeer(
            privateKey: configuration.privateKey,
            peerPublicKey: configuration.peerPublicKey,
            presharedKey: configuration.presharedKey
        )
        connection = NWConnection(host: NWEndpoint.Host(configuration.host), port: port, using: .udp)
    }

    func run() throws {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, self.result == nil else { return }
            switch state {
            case .ready:
                guard !self.didStart else { return }
                self.didStart = true
                self.startHandshake()
                self.receive()
            case .failed(let error):
                self.finish(.failure(error))
            case .cancelled:
                self.finish(.failure(ProbeError.connectionCancelled))
            default:
                break
            }
        }
        connection.start(queue: queue)
        defer { connection.cancel() }
        guard completion.wait(timeout: .now() + 10) == .success else {
            throw ProbeError.timeout
        }
        try result?.get()
    }

    private func startHandshake() {
        guard result == nil else { return }
        do {
            send(try peer.initiateHandshake())
            let retry = DispatchWorkItem { [weak self] in self?.startHandshake() }
            retryWork = retry
            queue.asyncAfter(deadline: .now() + 5 + Double.random(in: 0...0.333), execute: retry)
        } catch {
            finish(.failure(error))
        }
    }

    private func send(_ datagram: Data, completing: Bool = false) {
        connection.send(content: datagram, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error {
                self.finish(.failure(error))
            } else if completing {
                self.finish(.success(()))
            }
        })
    }

    private func receive() {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, self.result == nil else { return }
            if let error {
                self.finish(.failure(error))
                return
            }
            if let data {
                do {
                    let generation = self.peer.handshakeGeneration
                    let received = try self.peer.receive(data)
                    if generation != self.peer.handshakeGeneration, received != .handshakeComplete {
                        self.finish(.success(()))
                        return
                    }
                    switch received {
                    case .handshakeComplete:
                        self.retryWork?.cancel()
                        self.send(try self.peer.keepalive(), completing: true)
                        return
                    case .handshakeResponse(let response):
                        self.send(response, completing: false)
                    case .cookieReceived, .packet, .keepalive:
                        break
                    }
                } catch {
                    self.finish(.failure(error))
                    return
                }
            }
            self.receive()
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard self.result == nil else { return }
        retryWork?.cancel()
        self.result = result
        completion.signal()
    }
}
