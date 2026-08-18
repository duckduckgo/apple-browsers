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
                port: UInt16 = defaultPort) {
        self.port = port
        self.logReader = logReader
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

        server.addRoute("/api", method: .GET) { _ in
            let service = service.value
            var endpoints = service.defaultEndpoints()
            if hasLogReader {
                endpoints.append(Self.logsEndpointDescription)
            }
            return try Self.json(try service.apiResponse(endpoints: endpoints))
        }

        server.addRoute("/api/events", method: .GET) { request in
            let service = service.value
            let since = request.queryParameters["since"].flatMap(Self.parseDate)
            let limit = Self.resultLimit(from: request)
            return try Self.json(service.events(since: since, limit: limit))
        }

        server.addRoute("/api/runtime-status", method: .GET) { _ in
            let service = service.value
            guard let status = service.runtimeStatus() else {
                return .text("Runtime status is only available on iOS", status: .notFound)
            }
            return try Self.json(status)
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
    }

    private static let logsEndpointDescription = DebugAPIResponse.Endpoint(
        path: "/api/logs?since={iso8601}&category={category}&limit={n}",
        description: "Unified-log tail for PIR execution detail. 'since' tails new lines; 'category' filters by category; 'limit' defaults to \(DataBrokerProtectionDebugReadService.defaultLimit) and is capped at \(DataBrokerProtectionDebugReadService.maximumLimit).")

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
