//
//  DataBrokerProtectionDebugHTTPServer.swift
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

import DataBrokerProtectionCore
import DebugServer
import Foundation
import os.log

public protocol DebugLogReading {
    func logLines(since: Date?, category: String?, limit: Int) throws -> [DebugLogLine]
}

public final class DataBrokerProtectionDebugHTTPServer {

    public static let defaultPort = DataBrokerProtectionDebugServerDefaults.defaultPort

    public let port: UInt16

    private let server: DebugHTTPServer
    private let readService: DataBrokerProtectionDebugReadService
    private let logReader: DebugLogReading?
    private let controller: DataBrokerProtectionDebugControlling?
    private let logger = Logger(subsystem: "com.duckduckgo.dbp", category: "DebugHTTPServer")

    public var isRunning: Bool {
        if case .running = server.state { return true }
        return false
    }

    public var isStartingOrRunning: Bool {
        switch server.state {
        case .starting, .running:
            return true
        case .stopped, .failed:
            return false
        }
    }

    public init(provider: DataBrokerProtectionDebugReadProviding,
                logReader: DebugLogReading? = nil,
                controller: DataBrokerProtectionDebugControlling? = nil,
                port: UInt16 = defaultPort) {
        self.port = port
        self.logReader = logReader
        self.controller = controller
        self.server = DebugHTTPServer(port: port)
        self.readService = DataBrokerProtectionDebugReadService(provider: provider)
    }

    public func start() throws {
        registerRoutes()
        try server.start()
        logger.info("PIR debug server started on 127.0.0.1:\(self.port, privacy: .public)")
    }

    public func stop() {
        server.stop()
        logger.info("PIR debug server stopped")
    }

    private func registerRoutes() {
        let service = UncheckedSendable(readService)
        let logReader = logReader.map(UncheckedSendable.init)
        let hasLogReader = logReader != nil
        let hasController = controller != nil

        server.addRoute("/api", method: .GET) { _ in
            let service = service.value
            var endpoints = service.defaultEndpoints()
            if hasLogReader {
                endpoints.append(Self.logsEndpointDescription)
            }
            endpoints += Self.webViewEndpointDescriptions
            if hasController {
                endpoints += Self.controlEndpointDescriptions
            }
            return try Self.json(try service.apiResponse(endpoints: endpoints))
        }

        server.addRoute("/api/events", method: .GET) { request in
            let service = service.value
            let since = request.queryParameters["since"].flatMap(Self.parseDate)
            let limit = Self.resultLimit(from: request)
            return try Self.json(service.events(since: since, limit: limit))
        }

        if let logReader {
            server.addRoute("/api/logs", method: .GET) { request in
                let logReader = logReader.value
                let since = request.queryParameters["since"].flatMap(Self.parseDate)
                let category = request.queryParameters["category"]
                let limit = Self.resultLimit(from: request)
                return try Self.json(try logReader.logLines(since: since,
                                                            category: category,
                                                            limit: limit))
            }
        }

        server.addPrefixRoute("/api/brokers/", method: .GET) { request in
            let remainder = String(request.path.dropFirst("/api/brokers/".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !remainder.isEmpty else {
                return .text("Missing broker identifier", status: .badRequest)
            }
            let identifier = remainder.removingPercentEncoding ?? remainder
            let service = service.value
            guard let detail = try service.brokerDetail(brokerIdentifier: identifier) else {
                return .text("Broker not found: \(identifier)", status: .notFound)
            }
            return try Self.json(detail)
        }

        registerWebViewRoutes()
        if let controller {
            registerControlRoutes(controller: UncheckedSendable(controller))
        }
    }

    private func registerWebViewRoutes() {
        server.addRoute("/api/webviews", method: .GET) { _ in
            try Self.json(try DebugWebViewInspector.summaries())
        }

        server.addPrefixRoute("/api/webviews/", method: .GET) { request in
            guard let (id, action) = Self.webViewRoute(request.path) else {
                return .text("Expected /api/webviews/{id}/screenshot or /html", status: .badRequest)
            }
            switch action {
            case "screenshot":
                guard let png = try DebugWebViewInspector.screenshot(id: id) else { return Self.webViewNotFound(id) }
                return HTTPResponse(status: .ok, headers: ["Content-Type": "image/png"], body: png)
            case "html":
                guard let result = try DebugWebViewInspector.evaluate(id: id, body: "return document.documentElement.outerHTML"),
                      case .string(let html) = result.result else { return Self.webViewNotFound(id) }
                return .text(html)
            default:
                return .text("Unknown web view action: \(action)", status: .notFound)
            }
        }

        server.addPrefixRoute("/api/webviews/", method: .POST) { request in
            guard let (id, action) = Self.webViewRoute(request.path) else {
                return .text("Expected /api/webviews/{id}/evaluate or /load", status: .badRequest)
            }
            switch action {
            case "evaluate":
                guard let body = request.body.flatMap({ String(data: $0, encoding: .utf8) }), !body.isEmpty else {
                    return .text("Send the script as the request body", status: .badRequest)
                }
                do {
                    guard let result = try DebugWebViewInspector.evaluate(id: id, body: body) else { return Self.webViewNotFound(id) }
                    return try Self.json(result)
                } catch let error as DebugAwaitError {
                    throw error
                } catch {
                    return .text("Script failed: \(error)", status: .badRequest)
                }
            case "load":
                guard let url = request.queryParameters["url"].flatMap(URL.init(string:)) else {
                    return .text("Missing url query parameter", status: .badRequest)
                }
                return try DebugWebViewInspector.load(id: id, url: url) ? .empty() : Self.webViewNotFound(id)
            default:
                return .text("Unknown web view action: \(action)", status: .notFound)
            }
        }
    }

    private func registerControlRoutes(controller: UncheckedSendable<DataBrokerProtectionDebugControlling>) {
        server.addRoute("/api/brokers", method: .POST) { request in
            guard let body = request.body, !body.isEmpty else {
                return .text("Send the broker JSON as the request body", status: .badRequest)
            }
            return try Self.control { try await controller.value.installBroker(json: body) }
        }

        server.addPrefixRoute("/api/brokers/", method: .POST) { request in
            let remainder = String(request.path.dropFirst("/api/brokers/".count))
            guard remainder.hasSuffix("/scan") else {
                return .text("Expected POST /api/brokers/{broker}/scan", status: .notFound)
            }
            let encoded = String(remainder.dropLast("/scan".count))
            let identifier = encoded.removingPercentEncoding ?? encoded
            return try Self.control { try await controller.value.runScans(brokerIdentifier: identifier) }
        }

        server.addRoute("/api/assisted-optouts", method: .GET) { request in
            let droppingSubmitted = request.queryParameters["dropSubmitted"] == "true"
            return try Self.control { await controller.value.assistedOptOutsForDebugging(droppingSubmitted: droppingSubmitted) }
        }

        server.addPrefixRoute("/api/assisted-optouts/", method: .POST) { request in
            let parts = request.path.dropFirst("/api/assisted-optouts/".count).split(separator: "/").map(String.init)
            guard parts.count == 2 else {
                return .text("Expected POST /api/assisted-optouts/{id}/start or /cancel", status: .badRequest)
            }
            switch parts[1] {
            case "start":
                return try Self.control { try await controller.value.startAssistedOptOutForDebugging(id: parts[0]) }
            case "cancel":
                return try Self.control { try await controller.value.cancelAssistedOptOutForDebugging(id: parts[0]) }
            default:
                return .text("Unknown assisted opt-out action: \(parts[1])", status: .notFound)
            }
        }
    }

    private static let logsEndpointDescription = DebugAPIResponse.Endpoint(
        path: "/api/logs?since={iso8601}&category={category}&limit={n}",
        description: "Unified-log tail for PIR execution detail. 'since' tails new lines; 'category' filters by category; 'limit' defaults to \(DataBrokerProtectionDebugReadService.defaultLimit) and is capped at \(DataBrokerProtectionDebugReadService.maximumLimit).")

    private static let webViewEndpointDescriptions: [DebugAPIResponse.Endpoint] = [
        .init(path: "/api/webviews",
              description: "Live PIR web views (scans, opt-outs, assisted attempts) with their ids, broker and current URL."),
        .init(path: "/api/webviews/{id}/screenshot",
              description: "PNG of the web view's visible area."),
        .init(path: "/api/webviews/{id}/html",
              description: "The page's current outerHTML."),
        .init(path: "POST /api/webviews/{id}/evaluate",
              description: "Runs the request body as an async function in the page and returns {result}. Use `return` for the value."),
        .init(path: "POST /api/webviews/{id}/load?url={url}",
              description: "Loads a URL in the web view.")
    ]

    private static let controlEndpointDescriptions: [DebugAPIResponse.Endpoint] = [
        .init(path: "POST /api/brokers",
              description: "Saves the broker JSON in the request body, replacing the stored broker with the same url whatever its version."),
        .init(path: "POST /api/brokers/{broker}/scan",
              description: "Starts the broker's scan for every profile query in a visible window, outside the regular queue. Follow it with /api/events and /api/webviews."),
        .init(path: "/api/assisted-optouts?dropSubmitted={true}",
              description: "Refreshes and lists the Needs you opt-outs, with the user assistance flag and enabled brokers. dropSubmitted=true clears submitted attempts first, as a dashboard reload does."),
        .init(path: "POST /api/assisted-optouts/{id}/start",
              description: "Starts an assisted opt-out, as Start in the dashboard does. {id} = brokerId-profileQueryId-extractedProfileId."),
        .init(path: "POST /api/assisted-optouts/{id}/cancel",
              description: "Cancels an assisted opt-out, as closing its window does.")
    ]

    private static func webViewRoute(_ path: String) -> (id: Int, action: String)? {
        let parts = path.dropFirst("/api/webviews/".count).split(separator: "/").map(String.init)
        guard parts.count == 2, let id = Int(parts[0]) else { return nil }
        return (id, parts[1])
    }

    private static func webViewNotFound(_ id: Int) -> HTTPResponse {
        .text("No live web view with id \(id). See /api/webviews.", status: .notFound)
    }

    private static func control<T: Encodable>(_ operation: @escaping () async throws -> T) throws -> HTTPResponse {
        do {
            return try json(try awaitMainActor { try await operation() })
        } catch let error as DataBrokerProtectionDebugControlError {
            return .text(error.localizedDescription, status: .badRequest)
        } catch let error as DecodingError {
            return .text("Invalid broker JSON: \(error)", status: .badRequest)
        }
    }

    private static func control(_ operation: @escaping () async throws -> Void) throws -> HTTPResponse {
        do {
            try awaitMainActor { try await operation() }
            return .empty()
        } catch let error as DataBrokerProtectionDebugControlError {
            return .text(error.localizedDescription, status: .badRequest)
        }
    }

    private static let iso8601 = ISO8601DateFormatter()

    private static func parseDate(_ string: String) -> Date? {
        iso8601.date(from: string)
    }

    private static func resultLimit(from request: HTTPRequest) -> Int {
        DataBrokerProtectionDebugReadService.clampedLimit(request.queryParameters["limit"].flatMap(Int.init))
    }

    private static func json<T: Encodable>(_ value: T) throws -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return .json(try encoder.encode(value))
    }
}

private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
