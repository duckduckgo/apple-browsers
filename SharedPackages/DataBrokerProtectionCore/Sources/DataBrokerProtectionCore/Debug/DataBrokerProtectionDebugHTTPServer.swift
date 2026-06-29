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

import DebugServer
import Foundation
import os.log

/// Supplies log lines for the optional `/api/logs` endpoint. Platform-specific: macOS reads the
/// unified log via `OSLogStore`; iOS has no equivalent, so it injects no reader and the endpoint is
/// neither registered nor advertised.
public protocol DebugLogReading {
    func logLines(since: Date?, minLevel: String?, category: String?, limit: Int) throws -> [DebugLogLine]
}

/// A local, read-only HTTP server exposing PIR/DBP state for inspection by curl/scripts and CLI agents.
///
/// Platform-agnostic: macOS hosts it in the background agent, iOS in-app. Debug-only and read-only:
/// no route mutates state. Reachable on the local network; a Mac can reach an on-device iOS server
/// by the device IP, or via USB port-forwarding (`iproxy`).
///
/// Endpoints: `GET /api` (self-describing index), `GET /api/snapshot` (current state),
/// `GET /api/brokers/{broker}` (per-broker drill-in), `GET /api/events?since=` (progress stream),
/// and — when a `DebugLogReading` is injected — `GET /api/logs` (step-level log tail).
public final class DataBrokerProtectionDebugHTTPServer {

    /// Default port. Distinct from `AIChatDebugServer` (8473) to avoid collisions.
    public static let defaultPort: UInt16 = 8474

    public let port: UInt16

    private let server: DebugHTTPServer
    private let readService: DataBrokerProtectionDebugReadService
    private let logReader: DebugLogReading?
    private let logger = Logger(subsystem: "com.duckduckgo.dbp", category: "DebugHTTPServer")

    public var isRunning: Bool {
        if case .running = server.state { return true }
        return false
    }

    public var stateDidChange: (@Sendable (ServerState) -> Void)? {
        get { server.stateDidChange }
        set { server.stateDidChange = newValue }
    }

    /// - Parameters:
    ///   - provider: In-process source of PIR state (the platform's agent/manager).
    ///   - logReader: Platform log source for `/api/logs`. Pass `nil` to omit the endpoint (iOS).
    ///   - port: TCP port to listen on.
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

    // MARK: - Routes

    private func registerRoutes() {
        // `readService` holds a non-Sendable provider; route handlers may run concurrently on the
        // server's handler queue, so access is serialized by the provider's own backing store.
        let service = UncheckedSendable(readService)
        let hasLogReader = logReader != nil

        server.addRoute("/api", method: .GET) { _ in
            var endpoints = service.value.apiIndex().endpoints
            // `/api/logs` is platform-specific (injected log reader), so it's advertised here rather
            // than in the platform-agnostic read service's index.
            if hasLogReader {
                endpoints.append(Self.logsEndpointDescription)
            }
            return try Self.json(DebugAPIIndex(endpoints: endpoints))
        }

        server.addRoute("/api/snapshot", method: .GET) { _ in
            try Self.json(try Self.runBlocking { try await service.value.snapshot() })
        }

        server.addRoute("/api/events", method: .GET) { request in
            let since = request.queryParameters["since"].flatMap(Self.parseDate)
            return try Self.json(service.value.events(since: since))
        }

        if let logReader {
            let reader = UncheckedSendable(logReader)
            server.addRoute("/api/logs", method: .GET) { request in
                let since = request.queryParameters["since"].flatMap(Self.parseDate)
                let minLevel = request.queryParameters["level"]
                let category = request.queryParameters["category"]
                let limit = request.queryParameters["limit"].flatMap(Int.init) ?? Self.defaultLogLimit
                return try Self.json(try reader.value.logLines(since: since,
                                                               minLevel: minLevel,
                                                               category: category,
                                                               limit: limit))
            }
        }

        // /api/brokers/<url-or-name>
        server.addPrefixRoute("/api/brokers/", method: .GET) { request in
            let remainder = String(request.path.dropFirst("/api/brokers/".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !remainder.isEmpty else {
                return .text("Missing broker identifier", status: .badRequest)
            }
            let identifier = remainder.removingPercentEncoding ?? remainder
            guard let detail = try service.value.brokerDetail(brokerIdentifier: identifier) else {
                return .text("Broker not found: \(identifier)", status: .notFound)
            }
            return try Self.json(detail)
        }
    }

    // MARK: - Helpers

    /// Cap on the returned log lines when no explicit `limit` is given.
    private static let defaultLogLimit = 1000

    private static let logsEndpointDescription = DebugAPIIndex.Endpoint(
        path: "/api/logs?since={iso8601}&level={debug|info|notice|error|fault}&category={category}&limit={n}",
        description: "Unified-log tail (subsystem PIR) for step-level execution detail — current action, navigation, captcha/email/polling waits, retries. 'since' tails new lines (oldest-first, mergeable with /api/events); 'level' is minimum severity; 'category' filters (Action, Service, Data Broker Protection, Background Agent, Pixel).")

    private static let iso8601 = ISO8601DateFormatter()

    private static func parseDate(_ string: String) -> Date? {
        iso8601.date(from: string)
    }

    private static func json<T: Encodable>(_ value: T) throws -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return .json(try encoder.encode(value))
    }

    /// Bridges an async call to the synchronous route handler. Safe here: the awaited work runs on
    /// a separate executor (auth manager / DB), not the server's connection queue.
    private static func runBlocking<T>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
        let box = ResultBox<T>()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do { box.result = .success(try await operation()) } catch { box.result = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        return try box.result!.get()
    }
}

// MARK: - Concurrency helpers

private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

private final class ResultBox<Value>: @unchecked Sendable {
    var result: Result<Value, Error>?
}
