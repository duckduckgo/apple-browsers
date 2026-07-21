//
//  ServeCommand.swift
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

import AppKit
import ArgumentParser
import DataBrokerProtectionCore
import DebugServer
import Foundation
import PIRDebugKit

/// Long-running mode. One shared `PIRDebugSession` behind a localhost HTTP server. `POST /scan` and
/// `POST /optout` start work in a background task and return `202 {jobId}` immediately (the
/// server's route handlers are synchronous and share one serial queue, so they must not block).
struct ServeCommand: CLIRunnable {

    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Run a localhost HTTP server sharing one PIRDebugSession (POST /scan, POST /optout, GET /jobs/<id>, GET /brokers, GET /events?since=<cursor>).")

    @OptionGroup var rules: RulesSourceOptions
    @OptionGroup var script: ScriptSourceOptions
    @OptionGroup var auth: AuthOptions
    @OptionGroup var runtime: RuntimeOptions

    @Option(name: .long, help: "TCP port to listen on (localhost).")
    var port: UInt16 = 8475

    var activationPolicy: NSApplication.ActivationPolicy { runtime.showWebview ? .accessory : .prohibited }
    // Long-running: no watchdog.
    var watchdogTimeout: TimeInterval? { nil }

    func validateOptions() throws {
        try runtime.checkBounds(checkTimeout: false)
    }

    // MARK: - Request bodies

    private struct ScanRequest: Decodable {
        let profile: DebugProfile
        let broker: String?
        let all: Bool?
    }

    private struct OptOutRequest: Decodable {
        let profile: DebugProfile
        let broker: String
        let extracted: OptOutSupport.ExtractedRecords
        let index: Int?
        let allMatches: Bool?
        let waitForEmail: Bool?
        let pollInterval: Double?
    }

    // MARK: - Run

    func execute() async -> Int32 {
        Log.verbose = runtime.verbose
        do {
            let provider = try rules.makeProvider()
            let scriptSource = try await script.resolve()

            Log.info("Fetching brokers…")
            let brokers = try await provider.fetchBrokers()

            let configuration = try PIRDebugSessionConfiguration(
                rulesSource: provider,
                authManager: auth.authenticationManager(),
                scriptSource: scriptSource,
                showWebView: runtime.showWebview,
                operationAwaitTime: runtime.awaitTime,
                servicesEndpoint: rules.resolvedServicesEndpoint,
                userAgentApplicationName: "pir-debug")
            let session = try PIRDebugSession(configuration: configuration)
            let state = ServeState(session: session, brokers: brokers)

            // Buffer events for GET /events.
            let events = session.events
            Task.detached {
                for await event in events {
                    state.appendEvent(event)
                }
            }

            let server = DebugHTTPServer(port: port, requireLoopback: true)
            registerRoutes(on: server, state: state)
            try server.start()
            try await Self.waitUntilListening(server, port: port)
            Log.info("pir-debug serve listening on 127.0.0.1:\(port). Ctrl-C to stop.")

            // Long-running: never return so the delegate does not exit(). The server runs on its own
            // queue; this task just idles until the process is terminated (Ctrl-C).
            while true {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        } catch let error as CLIUsageError {
            Log.error(error.message)
            return CLIExit.usageError
        } catch {
            Log.error(String(describing: error))
            return CLIExit.usageError
        }
    }

    // MARK: - Routes

    private func registerRoutes(on server: DebugHTTPServer, state: ServeState) {
        server.addRoute("/", method: .GET) { _ in
            Self.jsonResponse([
                "endpoints": [
                    "POST /scan {profile, broker?, all?}",
                    "POST /optout {profile, broker, extracted, index?, allMatches?, waitForEmail?, pollInterval?}",
                    "GET /jobs/<id>",
                    "GET /brokers",
                    "GET /events?since=<cursor>"
                ]
            ])
        }

        server.addRoute("/brokers", method: .GET) { _ in
            let summaries = state.brokers.sorted { $0.name < $1.name }.map { broker in
                [
                    "name": broker.name,
                    "url": broker.url,
                    "version": broker.version,
                    "optOutUrl": broker.optOutUrl,
                    "stepTypes": broker.steps.map { $0.type.rawValue }
                ] as [String: Any]
            }
            return Self.jsonResponse(summaries)
        }

        server.addRoute("/events", method: .GET) { request in
            let since = request.queryParameters["since"].flatMap(Int.init) ?? 0
            let (nextCursor, events) = state.eventsSince(since)
            let encoder = CLIJSON.lineEncoder()
            let eventObjects = events.compactMap { event -> Any? in
                guard let data = try? encoder.encode(event) else { return nil }
                return try? JSONSerialization.jsonObject(with: data)
            }
            return Self.jsonResponse(["nextCursor": nextCursor, "events": eventObjects])
        }

        server.addPrefixRoute("/jobs/", method: .GET) { request in
            let id = String(request.path.dropFirst("/jobs/".count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !id.isEmpty, let body = state.jobResponse(id: id) else {
                return .text("Job not found", status: .notFound)
            }
            return .json(body)
        }

        server.addRoute("/scan", method: .POST) { request in
            guard let body = request.body,
                  let req = try? JSONDecoder().decode(ScanRequest.self, from: body) else {
                return .text("Invalid scan request body", status: .badRequest)
            }
            guard let jobId = state.tryCreateJob(kind: .scan) else {
                return Self.jsonResponse(["error": "A job is already running; retry when it completes."], status: .conflict)
            }
            Self.startScan(req: req, jobId: jobId, state: state)
            return Self.jsonResponse(["jobId": jobId], status: .accepted)
        }

        server.addRoute("/optout", method: .POST) { request in
            guard let body = request.body,
                  let req = try? JSONDecoder().decode(OptOutRequest.self, from: body) else {
                return .text("Invalid optout request body", status: .badRequest)
            }
            guard let jobId = state.tryCreateJob(kind: .optout) else {
                return Self.jsonResponse(["error": "A job is already running; retry when it completes."], status: .conflict)
            }
            Self.startOptOut(req: req, jobId: jobId, state: state)
            return Self.jsonResponse(["jobId": jobId], status: .accepted)
        }
    }

    // MARK: - Jobs

    private static func startScan(req: ScanRequest, jobId: String, state: ServeState) {
        Task { @MainActor in
            do {
                let selected = try BrokerSelectionOptions.select(selector: req.broker, all: req.all ?? false, from: state.brokers)
                var results: [PIRScanResult] = []
                for broker in selected {
                    results.append(try await state.session.scan(broker: broker, profile: req.profile.toDataBrokerProtectionProfile()))
                }
                let encoder = CLIJSON.prettyEncoder()
                let data = selected.count == 1 ? try encoder.encode(results[0]) : try encoder.encode(results)
                state.completeJob(id: jobId, resultData: data)
            } catch {
                state.failJob(id: jobId, error: String(describing: error))
            }
        }
    }

    private static func startOptOut(req: OptOutRequest, jobId: String, state: ServeState) {
        Task { @MainActor in
            do {
                let matched = try BrokerSelectionOptions.select(selector: req.broker, all: false, from: state.brokers)
                guard matched.count == 1, let broker = matched.first else {
                    throw CLIUsageError("broker '\(req.broker)' matched \(matched.count) brokers; be more specific.")
                }
                let brokerId = OptOutSupport.stableBrokerId(broker)
                let records = try OptOutSupport.select(records: req.extracted.records,
                                                       brokerId: brokerId,
                                                       index: req.index,
                                                       allMatches: req.allMatches ?? false)
                var results: [PIROptOutResult] = []
                for record in records {
                    let single = try OptOutSupport.reconstructSingleQueryProfile(for: record, from: req.profile)
                    var result = try await state.session.optOut(broker: broker,
                                                                profile: single.toDataBrokerProtectionProfile(),
                                                                extractedProfile: record.extractedProfile)
                    if result.awaitingEmailConfirmation, req.waitForEmail == true {
                        result = try await continueWithEmail(session: state.session,
                                                             pollInterval: req.pollInterval ?? 15,
                                                             fallback: result)
                    }
                    results.append(result)
                }
                let encoder = CLIJSON.prettyEncoder()
                let singleShape = !(req.allMatches ?? false) && results.count == 1
                let data = singleShape ? try encoder.encode(results[0]) : try encoder.encode(results)
                state.completeJob(id: jobId, resultData: data)
            } catch {
                state.failJob(id: jobId, error: String(describing: error))
            }
        }
    }

    /// Polls for the email-confirmation link (bounded so a job cannot hang forever) and continues
    /// the opt-out; returns `fallback` (still awaiting) if the link never arrives.
    private static func continueWithEmail(session: PIRDebugSession,
                                          pollInterval: Double,
                                          fallback: PIROptOutResult) async throws -> PIROptOutResult {
        let maxAttempts = 60
        for _ in 0..<maxAttempts {
            if let url = try await session.checkEmailConfirmation() {
                return try await session.continueOptOut(afterEmailURL: url)
            }
            try await Task.sleep(nanoseconds: UInt64(max(0, pollInterval) * 1_000_000_000))
        }
        return fallback
    }

    /// Polls the listener until it reports `.running`, throwing a usage error (→ exit 2) if the bind
    /// fails (e.g. port already in use, which `NWListener` surfaces asynchronously) rather than
    /// letting the command print "listening" and hang forever.
    private static func waitUntilListening(_ server: DebugHTTPServer, port: UInt16) async throws {
        for _ in 0..<50 {
            switch server.state {
            case .running:
                return
            case .failed(let message):
                throw CLIUsageError("Could not start server on port \(port): \(message)")
            case .stopped:
                // start() sets .starting synchronously; observing .stopped afterwards means the bind
                // failed (e.g. port already in use) and the listener tore itself down.
                throw CLIUsageError("Could not start server on port \(port); is the port already in use?")
            case .starting:
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        throw CLIUsageError("Timed out waiting for the server to start on port \(port).")
    }

    // MARK: - JSON

    private static func jsonResponse(_ object: Any, status: HTTPStatusCode = .ok) -> HTTPResponse {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return .text("Serialization error", status: .internalServerError)
        }
        return .json(data, status: status)
    }
}
