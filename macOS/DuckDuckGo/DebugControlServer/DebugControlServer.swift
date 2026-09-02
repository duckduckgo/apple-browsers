//
//  DebugControlServer.swift
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

#if DEBUG

import Foundation
import Network
import os.log

extension Logger {
    static var debugControlServer = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DuckDuckGo", category: "Debug Control Server")
}

/// A loopback-only HTTP control surface for driving a local debug build from the command line.
///
/// Compiled out of every non-DEBUG configuration. See `README.md` in this directory for the API.
@MainActor
final class DebugControlServer {

    static let serverVersion = 1
    static let defaultPort: UInt16 = 8788

    private let listener: NWListener
    private let router: DebugControlRouter
    private var parsers: [ObjectIdentifier: DebugControlRequestParser] = [:]

    /// Reads `DDG_CONTROL_PORT`, falling back to `defaultPort`. A value of `0` disables the server.
    static func configuredPort() -> UInt16? {
        guard let raw = ProcessInfo.processInfo.environment["DDG_CONTROL_PORT"] else { return defaultPort }
        guard let port = UInt16(raw), port > 0 else { return nil }
        return port
    }

    init(port: UInt16, router: DebugControlRouter) throws {
        self.router = router

        let parameters = NWParameters.tcp
        // A required local endpoint pins the listener to that address family, so this is 127.0.0.1 only —
        // never reachable from off-machine, and deliberately not ::1.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(integerLiteral: port))
        parameters.allowLocalEndpointReuse = true

        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                guard let self else {
                    connection.cancel()
                    return
                }
                connection.start(queue: .main)
                self.receive(from: connection)
            }
        }
        listener.stateUpdateHandler = { state in
            MainActor.assumeIsolated {
                if case .failed(let error) = state {
                    Logger.debugControlServer.error("Listener failed: \(error.localizedDescription)")
                }
            }
        }
        listener.start(queue: .main)
        Logger.debugControlServer.log("Debug control server listening on 127.0.0.1:\(port)")
    }

    func stop() {
        listener.cancel()
        parsers.removeAll()
    }

    private func receive(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
            // The connection runs on the main queue, so this handler is always delivered on the main thread.
            MainActor.assumeIsolated {
                let key = ObjectIdentifier(connection)

                if let error {
                    Logger.debugControlServer.error("Connection error: \(error.localizedDescription)")
                    self.parsers.removeValue(forKey: key)
                    connection.cancel()
                    return
                }

                if let content, !content.isEmpty {
                    var parser = self.parsers[key] ?? DebugControlRequestParser()
                    let result = parser.append(content)
                    self.parsers[key] = parser

                    switch result {
                    case .incomplete:
                        break
                    case .malformed(let reason):
                        self.parsers.removeValue(forKey: key)
                        self.respond(.failure(reason), on: connection)
                        return
                    case .request(let request):
                        self.parsers.removeValue(forKey: key)
                        Task { @MainActor in
                            let response = await self.router.handle(request)
                            self.respond(response, on: connection)
                        }
                        return
                    }
                }

                if isComplete {
                    self.parsers.removeValue(forKey: key)
                    connection.cancel()
                    return
                }

                if connection.state == .ready {
                    self.receive(from: connection)
                }
            }
        }
    }

    private func respond(_ response: DebugControlResponse, on connection: NWConnection) {
        connection.send(content: response.httpData, completion: .contentProcessed({ error in
            if let error {
                Logger.debugControlServer.error("Failed to send response: \(error.localizedDescription)")
            }
            connection.cancel()
        }))
    }
}

#endif
