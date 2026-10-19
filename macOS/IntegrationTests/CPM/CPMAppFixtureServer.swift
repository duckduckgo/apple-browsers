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
    private var cacheResponses = 0

    var completedCacheResponses: Int {
        lock.lock()
        defer { lock.unlock() }
        return cacheResponses
    }

    private func recordCacheResponse() {
        lock.lock()
        cacheResponses += 1
        lock.unlock()
    }

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
                let path = string.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                respond(connection, path: path)
            } else if error == nil, !complete, request.count < 65_536 {
                receive(connection, buffered: request)
            } else {
                connection.cancel()
            }
        }
    }

    private func respond(_ connection: NWConnection, path: String) {
        let isImage = path.hasPrefix("/slow.gif")
        let delay: TimeInterval = isImage ? 8 : 0
        let body: Data
        let type: String
        if isImage {
            body = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")!
            type = "image/gif"
        } else if path.hasPrefix("/cache/") {
            body = Data(repeating: 65, count: 2048)
            type = "application/octet-stream"
        } else {
            let image = path.contains("slowPage") ? "<img src='/slow.gif?document=\(UUID().uuidString)'>" : ""
            let cache = path.hasPrefix("/fill")
                ? "<script>let next=0,completed=0;const n=Number(new URL(location).searchParams.get('n'));const ns=new URL(location).searchParams.get('document');Promise.all(Array.from({length:32},async()=>{while(next<n){const i=next++;const r=await fetch('/cache/'+ns+'/'+i);if(!r.ok)throw Error(r.status);await r.arrayBuffer();completed++;}})).then(()=>{document.documentElement.setAttribute('data-cpm-cache-completed',String(completed));document.title='cache filled';}).catch(e=>document.title='cache failed:'+e)</script>"
                : ""
            body = Data("<!doctype html><html><head><title>CPM app integration</title></head><body>CPM fixture\(image)\(cache)</body></html>".utf8)
            type = "text/html"
        }
        let cache = path.hasPrefix("/cache/") ? "Cache-Control: public, max-age=31536000\r\n" : "Cache-Control: no-store\r\n"
        let header = "HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\n\(cache)Connection: close\r\n\r\n"
        let response = Data(header.utf8) + body
        let isCacheResponse = path.hasPrefix("/cache/")
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            connection.send(content: response, completion: .contentProcessed { error in
                if isCacheResponse, error == nil { self?.recordCacheResponse() }
                connection.cancel()
            })
        }
    }
}
