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

    private let prerequisites: DebugPrerequisiteSnapshot
    private let instanceID: String?
    private let server: DebugHTTPServer
    private let readService: DataBrokerProtectionDebugReadService
    private let logReader: DebugLogReading?
    private let runManager: DataBrokerProtectionDebugModeRunning?
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
                runManager: DataBrokerProtectionDebugModeRunning? = nil,
                port: UInt16 = defaultPort,
                instanceID: String? = nil,
                prerequisiteReader: (@MainActor @Sendable () async throws -> DebugPrerequisiteResult)? = nil) {
        self.port = port
        self.instanceID = instanceID
        self.prerequisites = DebugPrerequisiteSnapshot(instanceID: instanceID, debugRunnerReady: runManager != nil, reader: prerequisiteReader)
        self.logReader = logReader
        self.runManager = runManager
        self.server = DebugHTTPServer(port: port, loopbackOnly: true)
        self.readService = DataBrokerProtectionDebugReadService(provider: provider)
    }

    public func start() throws {
        registerRoutes()
        try server.start()
        logger.info("PIR debug server started on 127.0.0.1:\(self.port, privacy: .public)")
    }

    public func stop() {
        prerequisites.stop()
        server.stop()
        logger.info("PIR debug server stopped")
    }

    private func registerRoutes() {
        let service = UncheckedSendable(readService)
        let logReader = logReader.map(UncheckedSendable.init)
        let hasLogReader = logReader != nil
        let hasRunManager = runManager != nil
        let prerequisites = prerequisites
        server.addRoute("/api/debug/prerequisites", method: .GET) { request in
            guard let checkID = request.queryParameters["checkID"], UUID(uuidString: checkID) != nil else {
                return .text("checkID must be a UUID", status: .badRequest)
            }
            return try Self.json(prerequisites.snapshot(checkID: checkID))
        }

        server.addRoute("/api", method: .GET) { _ in
            let service = service.value
            var endpoints = service.defaultEndpoints()
            endpoints.append(.init(path: "/api/debug/prerequisites?checkID={uuid}",
                                   description: "Fresh correlated normal subscription check. Poll the same ID until no longer pending."))
            if hasLogReader {
                endpoints.append(Self.logsEndpointDescription)
            }
            if hasRunManager {
                endpoints.append(contentsOf: Self.debugModeEndpointDescriptions)
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

        if let runManager {
            registerDebugModeRoutes(runManager: UncheckedSendable(runManager))
        }
    }

    private func registerDebugModeRoutes(runManager: UncheckedSendable<DataBrokerProtectionDebugModeRunning>) {
        let instanceID = instanceID
        server.addRoute("/api/debug/scans", method: .POST) { request in
            if !Self.isOwned(request, instanceID: instanceID) {
                return .text("PIR debug instance mismatch", status: .forbidden)
            }
            if Self.isFromWebPage(request) {
                return Self.webPageRejection
            }
            return try Self.debugModeResponse {
                try runManager.value.startScan(try DebugModeScanRequest(body: request.body))
            }
        }

        server.addPrefixRoute("/api/debug/runs/", method: .GET) { request in
            let runId = String(request.path.dropFirst("/api/debug/runs/".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let run = runManager.value.run(id: runId) else {
                return .text("Run not found: \(runId)", status: .notFound)
            }
            return try Self.json(run)
        }

        server.addPrefixRoute("/api/debug/runs/", method: .POST) { request in
            if !Self.isOwned(request, instanceID: instanceID) {
                return .text("PIR debug instance mismatch", status: .forbidden)
            }
            if Self.isFromWebPage(request) {
                return Self.webPageRejection
            }
            guard let action = DebugModeRunAction(path: String(request.path.dropFirst("/api/debug/runs/".count))) else {
                return .text("Unknown run action: \(request.path)", status: .notFound)
            }
            return try Self.debugModeResponse {
                switch action {
                case .optOut(let runId, let resultId):
                    return try runManager.value.startOptOut(runId: runId, resultId: resultId)
                case .continueOptOut(let runId, let resultId):
                    return try runManager.value.continueOptOut(runId: runId, resultId: resultId)
                case .checkForEmailConfirmation(let runId):
                    return try runManager.value.checkForEmailConfirmation(runId: runId)
                }
            }
        }
    }

    static func isOwned(_ request: HTTPRequest, instanceID: String?) -> Bool {
        guard let instanceID else { return true }
        return request.headers.first { $0.key.caseInsensitiveCompare("X-PIR-Debug-Instance") == .orderedSame }?.value == instanceID
    }

    /// Browsers send `Origin` on every POST and pages can't remove it, so this keeps web pages from starting scans or opt-outs.
    private static func isFromWebPage(_ request: HTTPRequest) -> Bool {
        request.headers.keys.contains { $0.caseInsensitiveCompare("Origin") == .orderedSame }
    }

    private static let webPageRejection = HTTPResponse.text("Requests from web pages are not accepted", status: .forbidden)

    private static func debugModeResponse(_ start: () throws -> DebugModeRun) throws -> HTTPResponse {
        do {
            return try json(try start(), status: .accepted)
        } catch let error as DebugModeRunError {
            let status: HTTPStatusCode
            switch error {
            case .invalidRequest:
                status = .badRequest
            case .brokerNotFound, .runNotFound, .resultNotFound:
                status = .notFound
            case .busy, .notAwaitingEmailConfirmation:
                status = .conflict
            }
            return .text(error.localizedDescription, status: status)
        }
    }

    private static let logsEndpointDescription = DebugAPIResponse.Endpoint(
        path: "/api/logs?since={iso8601}&category={category}&limit={n}",
        description: "Unified-log tail for PIR execution detail. 'since' tails new lines; 'category' filters by category; 'limit' defaults to \(DataBrokerProtectionDebugReadService.defaultLimit) and is capped at \(DataBrokerProtectionDebugReadService.maximumLimit).")

    private static let debugModeEndpointDescriptions: [DebugAPIResponse.Endpoint] = [
        .init(path: "POST /api/debug/scans",
              description: "Starts a debug mode scan. Body: {\"broker\": stored broker url or name, or broker JSON, \"profile\": same shape as -pirProfileJSON, \"hidesWebView\": true}. hidesWebView defaults to true and applies to the whole run. The configured job timeouts always apply. Nothing is saved to the PIR database. Returns the run; one activity runs at a time."),
        .init(path: "/api/debug/runs/{runId}",
              description: "A debug run: its activity (omitted when idle), results with their opt-out status, scan errors and the debug mode event log."),
        .init(path: "POST /api/debug/runs/{runId}/optouts/{resultId}",
              description: "Starts the opt-out for a result."),
        .init(path: "POST /api/debug/runs/{runId}/email-confirmation/check",
              description: "Checks the email service for confirmation links of opt-outs awaiting email confirmation."),
        .init(path: "POST /api/debug/runs/{runId}/optouts/{resultId}/continue",
              description: "Finishes an opt-out awaiting email confirmation with its confirmation link.")
    ]

    private static let iso8601 = ISO8601DateFormatter()

    private static func parseDate(_ string: String) -> Date? {
        iso8601.date(from: string)
    }

    private static func resultLimit(from request: HTTPRequest) -> Int {
        DataBrokerProtectionDebugReadService.clampedLimit(request.queryParameters["limit"].flatMap(Int.init))
    }

    private static func json<T: Encodable>(_ value: T, status: HTTPStatusCode = .ok) throws -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return .json(try encoder.encode(value), status: status)
    }
}

private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
