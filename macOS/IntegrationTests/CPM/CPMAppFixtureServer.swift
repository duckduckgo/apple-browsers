//
//  CPMAppFixtureServer.swift
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

/// An owned loopback HTTP server: browser requests, resource loading and navigation finish are real.
final class CPMAppFixtureServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.duckduckgo.cpm-app-fixture")
    private var listener: NWListener?
    private let lock = NSLock()
    private var configuredPort: UInt16?
    private var startupError: Error?
    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self else { return }
            lock.lock()
            switch state {
            case .ready: configuredPort = listener?.port?.rawValue
            case .failed(let error): startupError = error
            default: break
            }
            lock.unlock()
        }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .global())
            self?.receive(connection, buffered: Data())
        }
        listener.start(queue: queue)
        for _ in 0..<100 {
            let state = state()
            if let error = state.error { throw error }
            if let port = state.port { return port }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw NSError(domain: "CPMAppFixtureServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Loopback listener did not become ready"])
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func state() -> (port: UInt16?, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        return (configuredPort, startupError)
    }

    private func receive(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] bytes, _, complete, error in
            guard let self else { connection.cancel(); return }
            var request = buffered
            request.append(bytes ?? Data())
            if let string = String(data: request, encoding: .utf8), string.contains("\r\n\r\n") {
                respond(connection)
            } else if error == nil, !complete, request.count < 65_536 {
                receive(connection, buffered: request)
            } else {
                connection.cancel()
            }
        }
    }

    private func respond(_ connection: NWConnection) {
        let body = Data("<!doctype html><html><head><title>CPM app integration</title></head><body>CPM fixture</body></html>".utf8)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}
