//
//  DebugHTTPServer.swift
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
import os

/// A local HTTP server built on `NWListener` for debug tooling.
///
/// Register routes with `addRoute(_:method:handler:)` before calling `start()`.
///
/// ```swift
/// let server = DebugHTTPServer(port: 8473)
/// server.addRoute("/api/data", method: .GET) { request in
///     .json(someData)
/// }
/// try server.start()
/// ```
/// All mutable state is confined to queue, including public accessors and route registration.
/// Async handlers transfer only Sendable request/response values; completion returns to queue.
public final class DebugHTTPServer: HTTPServerProtocol, @unchecked Sendable {

    // MARK: - Properties

    private var storedState: ServerState = .stopped
    private var storedStateDidChange: (@Sendable (ServerState) -> Void)?
    private let queueKey = DispatchSpecificKey<UInt8>()

    public private(set) var state: ServerState {
        get { withQueue { storedState } }
        set {
            withQueue {
                storedState = newValue
                storedStateDidChange?(newValue)
            }
        }
    }

    public var stateDidChange: (@Sendable (ServerState) -> Void)? {
        get { withQueue { storedStateDidChange } }
        set { withQueue { storedStateDidChange = newValue } }
    }

    private let port: UInt16
    private let loopbackOnly: Bool
    private let maximumRequestBytes = 1_048_576
    private var asyncRoutes: [RouteKey: AsyncRouteHandler] = [:]
    private var requestTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private let queue: DispatchQueue
    private var listener: NWListener?
    private var activeConnections: [NWConnection] = []
    private var routes: [RouteKey: RouteHandler] = [:]
    private var prefixRoutes: [RouteKey: RouteHandler] = [:]
    private var isStopping = false
    private let parser = RequestParser()
    private let serializer = ResponseSerializer()
    private let logger = Logger(subsystem: "com.debugserver", category: "HTTPServer")

    // MARK: - Init

    /// Creates a new debug server.
    ///
    /// - Parameters:
    ///   - port: The TCP port to listen on. Defaults to `8473`.
    ///   - loopbackOnly: Restrict the listener to IPv4 loopback for local tooling.
    public init(port: UInt16 = 8473, loopbackOnly: Bool = false) {
        self.port = port
        self.loopbackOnly = loopbackOnly
        self.queue = DispatchQueue(label: "com.debugserver.listener", qos: .userInitiated)
        self.queue.setSpecific(key: queueKey, value: 1)
    }

    private func withQueue<Value>(_ operation: () throws -> Value) rethrows -> Value {
        if DispatchQueue.getSpecific(key: queueKey) != nil { return try operation() }
        return try queue.sync(execute: operation)
    }

    // MARK: - HTTPServerProtocol

    public func start() throws {
        try withQueue {
            guard case .stopped = state else { return }

            state = .starting
            isStopping = false

            let parameters = NWParameters.tcp
            let nwPort = NWEndpoint.Port(rawValue: port)!
            let listener: NWListener
            if loopbackOnly {
                parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
                listener = try NWListener(using: parameters)
            } else {
                listener = try NWListener(using: parameters, on: nwPort)
            }

            listener.stateUpdateHandler = { [weak self] listenerState in
                self?.handleListenerStateChange(listenerState)
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            self.listener = listener
            listener.start(queue: queue)
        }
    }

    public func stop() {
        queue.async {
            self.stopOnQueue()
        }
    }

    /// Must be called on `queue`.
    private func stopOnQueue() {
        guard !isStopping else { return }
        isStopping = true

        listener?.cancel()
        listener = nil

        requestTasks.values.forEach { $0.cancel() }
        requestTasks.removeAll()
        for connection in activeConnections {
            connection.cancel()
        }
        activeConnections.removeAll()
        state = .stopped
    }

    // MARK: - RouteRegistrable

    public func addRoute(_ path: String, method: HTTPMethod, handler: @escaping RouteHandler) {
        let key = RouteKey(method: method, path: path)
        withQueue { routes[key] = handler }
    }

    public func addPrefixRoute(_ pathPrefix: String, method: HTTPMethod, handler: @escaping RouteHandler) {
        let key = RouteKey(method: method, path: pathPrefix)
        withQueue { prefixRoutes[key] = handler }
    }

    /// Register before starting the server, as with synchronous routes.
    public func addAsyncRoute(_ path: String, method: HTTPMethod, handler: @escaping AsyncRouteHandler) {
        withQueue { asyncRoutes[RouteKey(method: method, path: path)] = handler }
    }

    public func addStaticRoute(_ path: String, htmlString: String) {
        addRoute(path, method: .GET) { _ in
            .html(htmlString)
        }
    }

    // MARK: - Connection Handling

    private func handleListenerStateChange(_ listenerState: NWListener.State) {
        switch listenerState {
        case .ready:
            state = .running(port: listener?.port?.rawValue ?? port)
            logger.info("DebugServer listening on port \(self.port)")
        case .failed(let error):
            state = .failed(error.localizedDescription)
            logger.error("DebugServer failed: \(error.localizedDescription)")
            stopOnQueue()
        case .cancelled:
            // stopOnQueue() already set .stopped; avoid a duplicate notification.
            if !isStopping {
                state = .stopped
            }
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        guard activeConnections.count < 64 else {
            connection.cancel()
            return
        }
        activeConnections.append(connection)
        queue.asyncAfter(deadline: .now() + 30) { [weak self, weak connection] in
            guard let connection, self?.activeConnections.contains(where: { $0 === connection }) == true else { return }
            self?.removeConnection(connection)
        }

        connection.stateUpdateHandler = { [weak self] connectionState in
            if case .failed = connectionState {
                self?.removeConnection(connection)
            }
        }

        connection.start(queue: queue)
        receiveData(on: connection)
    }

    private static let headerBodySeparator = Data([0x0D, 0x0A, 0x0D, 0x0A])

    private func receiveData(on connection: NWConnection, accumulated: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let error {
                logger.error("Receive error: \(error.localizedDescription)")
                removeConnection(connection)
                return
            }

            guard let chunk = content, !chunk.isEmpty else {
                if isComplete {
                    if !accumulated.isEmpty {
                        respond(to: accumulated, on: connection)
                    } else {
                        removeConnection(connection)
                    }
                }
                return
            }

            var data = accumulated
            data.append(chunk)

            guard data.count <= maximumRequestBytes else {
                sendResponse(.text("Request too large", status: .payloadTooLarge), on: connection)
                return
            }
            let remaining = self.remainingBodyBytes(in: data)
            if remaining == nil || remaining! > 0 {
                receiveData(on: connection, accumulated: data)
                return
            }

            respond(to: data, on: connection)
        }
    }

    private func remainingBodyBytes(in data: Data) -> Int? {
        guard let separatorRange = data.range(of: Self.headerBodySeparator) else {
            return nil
        }

        let headerData = data.subdata(in: 0..<separatorRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return 0
        }

        let lines = headerString.components(separatedBy: "\r\n")
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2,
               parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length",
               let contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                let bodyStart = separatorRange.upperBound
                let currentBodyLength = data.count - bodyStart
                return contentLength - currentBodyLength
            }
        }

        return 0
    }

    private func respond(to data: Data, on connection: NWConnection) {
        guard let request = try? parser.parse(data),
              let handler = asyncRoutes[RouteKey(method: request.method, path: request.path)] else {
            sendResponse(processRequest(data), on: connection)
            return
        }
        let identifier = ObjectIdentifier(connection)
        requestTasks[identifier] = Task { [weak self] in
            let response: HTTPResponse
            do {
                response = try await handler(request)
            } catch {
                response = .text("Internal Server Error", status: .internalServerError)
            }
            guard !Task.isCancelled else { return }
            self?.queue.async { [weak self] in
                guard let self, activeConnections.contains(where: { $0 === connection }) else { return }
                requestTasks[identifier] = nil
                sendResponse(response, on: connection)
            }
        }
    }

    private func processRequest(_ data: Data) -> HTTPResponse {
        do {
            let request = try parser.parse(data)
            let key = RouteKey(method: request.method, path: request.path)

            if let handler = routes[key] {
                return try handler(request)
            }

            if let handler = findPrefixHandler(for: request) {
                return try handler(request)
            }

            return .text("Not Found: \(request.method.rawValue) \(request.path)", status: .notFound)
        } catch let error as RequestParserError {
            return .text("Bad Request: \(error)", status: .badRequest)
        } catch {
            return .text("Internal Server Error: \(error.localizedDescription)", status: .internalServerError)
        }
    }

    private func findPrefixHandler(for request: HTTPRequest) -> RouteHandler? {
        let matchingRoutes = prefixRoutes.filter { key, _ in
            key.method == request.method && request.path.hasPrefix(key.path)
        }

        let bestMatch = matchingRoutes.max { lhs, rhs in
            if lhs.key.path.count == rhs.key.path.count {
                return lhs.key.path > rhs.key.path
            }
            return lhs.key.path.count < rhs.key.path.count
        }

        return bestMatch?.value
    }

    private func sendResponse(_ response: HTTPResponse, on connection: NWConnection) {
        let data = serializer.serialize(response)
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.logger.error("Send error: \(error.localizedDescription)")
            }
            self?.removeConnection(connection)
        })
    }

    private func removeConnection(_ connection: NWConnection) {
        requestTasks.removeValue(forKey: ObjectIdentifier(connection))?.cancel()
        connection.cancel()
        activeConnections.removeAll { $0 === connection }
    }
}

// MARK: - Route Key

private struct RouteKey: Hashable {
    let method: HTTPMethod
    let path: String
}
