import Foundation
import Network
import os

/// A local HTTP server built on `NWListener` for debug tooling.
///
/// Register routes with `addRoute(_:method:handler:)` before calling `start()`.
///
/// ```swift
/// let server = DebugHTTPServer(port: 8080)
/// server.addRoute("/api/data", method: .GET) { request in
///     .json(someData)
/// }
/// try server.start()
/// ```
public final class DebugHTTPServer: HTTPServerProtocol {

    // MARK: - Properties

    public private(set) var state: ServerState = .stopped {
        didSet { stateDidChange?(state) }
    }

    public var stateDidChange: (@Sendable (ServerState) -> Void)?

    private let port: UInt16
    private let queue: DispatchQueue
    private var listener: NWListener?
    private var activeConnections: [NWConnection] = []
    private var routes: [RouteKey: RouteHandler] = [:]
    private var prefixRoutes: [RouteKey: RouteHandler] = [:]
    private let parser = RequestParser()
    private let serializer = ResponseSerializer()
    private let logger = Logger(subsystem: "com.debugserver", category: "HTTPServer")

    // MARK: - Init

    /// Creates a new debug server.
    ///
    /// - Parameter port: The TCP port to listen on. Defaults to `8080`.
    public init(port: UInt16 = 8080) {
        self.port = port
        self.queue = DispatchQueue(label: "com.debugserver.listener", qos: .userInitiated)
    }

    // MARK: - HTTPServerProtocol

    public func start() throws {
        guard case .stopped = state else { return }

        state = .starting

        let parameters = NWParameters.tcp
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let listener = try NWListener(using: parameters, on: nwPort)

        listener.stateUpdateHandler = { [weak self] listenerState in
            self?.handleListenerStateChange(listenerState)
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        self.listener = listener
        listener.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil

        for connection in activeConnections {
            connection.cancel()
        }
        activeConnections.removeAll()
        routes.removeAll()
        prefixRoutes.removeAll()
        state = .stopped
    }

    // MARK: - RouteRegistrable

    public func addRoute(_ path: String, method: HTTPMethod, handler: @escaping RouteHandler) {
        let key = RouteKey(method: method, path: path)
        routes[key] = handler
    }

    public func addPrefixRoute(_ pathPrefix: String, method: HTTPMethod, handler: @escaping RouteHandler) {
        let key = RouteKey(method: method, path: pathPrefix)
        prefixRoutes[key] = handler
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
            state = .running(port: port)
            logger.info("DebugServer listening on port \(self.port)")
        case .failed(let error):
            state = .failed(error.localizedDescription)
            logger.error("DebugServer failed: \(error.localizedDescription)")
            listener?.cancel()
            listener = nil
        case .cancelled:
            state = .stopped
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        activeConnections.append(connection)

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
                        let response = processRequest(accumulated)
                        sendResponse(response, on: connection)
                    } else {
                        removeConnection(connection)
                    }
                }
                return
            }

            var data = accumulated
            data.append(chunk)

            if let remaining = self.remainingBodyBytes(in: data) {
                if remaining > 0 {
                    receiveData(on: connection, accumulated: data)
                    return
                }
            }

            let response = processRequest(data)
            sendResponse(response, on: connection)
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
        for (key, handler) in prefixRoutes where key.method == request.method && request.path.hasPrefix(key.path) {
            return handler
        }
        return nil
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
        connection.cancel()
        activeConnections.removeAll { $0 === connection }
    }
}

// MARK: - Route Key

private struct RouteKey: Hashable {
    let method: HTTPMethod
    let path: String
}
