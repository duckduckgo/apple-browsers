//
//  DebugModeRunManager.swift
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
import DataBrokerProtectionDebugServer
import Foundation
import os.log

public final class DebugModeRunManager: DataBrokerProtectionDebugModeRunning, @unchecked Sendable {

    /// Queries that differ only by middle name share a stable ID, so results are told apart by query position.
    private struct RunResult {
        let queryIndex: Int
        let scanResult: DebugScanResult
    }

    private struct OptOut {
        var status: DebugModeRun.OptOutStatus
        var error: String?
    }

    private struct RunState {
        let id: String
        let createdAt = Date()
        let broker: DataBroker
        let queries: [BrokerProfileQueryData]
        let hidesWebView: Bool
        var activity: DebugModeRun.Activity?
        var scanErrors: [String] = []
        var results: [RunResult] = []
        var optOuts: [String: OptOut] = [:]
        var events: [DebugModeRun.Event] = []
    }

    private let runner: DebugModeRunner
    private let lock = NSLock()
    private var runs: [String: RunState] = [:]
    private var activeRunId: String?

    private var scanTimeout: TimeInterval { runner.brokerJobExecutionConfig.scanJobTimeout }
    private var optOutTimeout: TimeInterval { runner.brokerJobExecutionConfig.optOutJobTimeout }

    public init(runner: DebugModeRunner) {
        self.runner = runner
        runner.emailConfirmationEventHandler = { [weak self] message in
            self?.addEventToActiveRun(summary: "Email confirmation", details: message)
        }
    }

    // MARK: - DataBrokerProtectionDebugModeRunning

    public func startScan(_ request: DebugModeScanRequest) throws -> DebugModeRun {
        let broker = try resolveBroker(request.broker)
        let queries = runner.brokerProfileQueryData(for: broker, profile: request.profile)
        let runId = UUID().uuidString.lowercased()
        let state = RunState(id: runId, broker: broker, queries: queries, hidesWebView: request.hidesWebView, activity: .scan)

        let run = try locked {
            try claim(runId)
            runner.debugEmailConfirmationStore.reset()
            runs[runId] = state
            return snapshot(of: state)
        }

        let showWebView = !request.hidesWebView
        launch(runId) {
            await withTaskGroup(of: Void.self) { group in
                for (queryIndex, query) in queries.enumerated() {
                    group.addTask { await self.scan(query, queryIndex: queryIndex, runId: runId, showWebView: showWebView) }
                }
            }
        }
        return run
    }

    public func run(id: String) -> DebugModeRun? {
        locked { runs[id].map(snapshot(of:)) }
    }

    public func startOptOut(runId: String, resultId: String) throws -> DebugModeRun {
        let (run, (scanResult, showWebView)) = try beginActivity(.optOut, runId: runId) { state in
            let result = try Self.result(resultId, in: state)
            state.optOuts[resultId] = OptOut(status: .running)
            return (result, !state.hidesWebView)
        }

        launch(runId) {
            await self.optOut(scanResult, resultId: resultId, showWebView: showWebView, runId: runId)
        }
        return run
    }

    public func checkForEmailConfirmation(runId: String) throws -> DebugModeRun {
        let (run, _) = try beginActivity(.emailConfirmationCheck, runId: runId) { _ in }

        launch(runId) {
            do {
                try await self.runner.checkForEmailConfirmation()
            } catch {
                self.addEvent(runId, kind: .history, profileQuery: "-", summary: "Email confirmation check failed", details: error.localizedDescription)
            }
        }
        return run
    }

    public func continueOptOut(runId: String, resultId: String) throws -> DebugModeRun {
        let (run, (scanResult, confirmationURL, showWebView)) = try beginActivity(.continueOptOut, runId: runId) { state in
            let result = try Self.result(resultId, in: state)
            guard let url = runner.confirmationURL(for: result) else {
                throw DebugModeRunError.notAwaitingEmailConfirmation(resultId: resultId)
            }
            state.optOuts[resultId] = OptOut(status: .running)
            return (result, url, !state.hidesWebView)
        }

        launch(runId) {
            let label = DebugModeRunner.profileQueryText(for: scanResult.profileQuery)
            do {
                try await self.runner.continueOptOut(scanResult,
                                                     confirmationURL: confirmationURL,
                                                     showWebView: showWebView,
                                                     timeout: self.optOutTimeout,
                                                     stageCalculator: self.stageCalculator(runId: runId, stepType: .optOut, broker: scanResult.dataBroker, profileQuery: label))
                self.setOptOutStatus(.confirmed, resultId: resultId, runId: runId)
                self.addHistoryEvent(.optOutConfirmed, runId: runId, profileQuery: label)
            } catch {
                self.recordOptOutFailure(error, resultId: resultId, runId: runId, profileQuery: label)
            }
        }
        return run
    }

    // MARK: - Jobs

    private func scan(_ query: BrokerProfileQueryData, queryIndex: Int, runId: String, showWebView: Bool) async {
        let label = DebugModeRunner.profileQueryText(for: query.profileQuery)
        addHistoryEvent(.scanStarted, runId: runId, profileQuery: label)
        do {
            let profiles = try await runner.scan(query,
                                                 showWebView: showWebView,
                                                 timeout: scanTimeout,
                                                 stageCalculator: stageCalculator(runId: runId, stepType: .scan, broker: query.dataBroker, profileQuery: label))
            let results = profiles.map {
                RunResult(queryIndex: queryIndex,
                          scanResult: DebugScanResult(dataBroker: query.dataBroker, profileQuery: query.profileQuery, extractedProfile: $0))
            }
            update(runId) { $0.results.append(contentsOf: results) }
            addHistoryEvent(profiles.isEmpty ? .noMatchFound : .matchesFound(count: profiles.count), runId: runId, profileQuery: label)
        } catch {
            update(runId) { $0.scanErrors.append("\(label): \(error.localizedDescription)") }
            addHistoryEvent(DebugModeRunner.historyError(error), runId: runId, profileQuery: label)
        }
    }

    private func optOut(_ scanResult: DebugScanResult, resultId: String, showWebView: Bool, runId: String) async {
        let label = DebugModeRunner.profileQueryText(for: scanResult.profileQuery)
        addHistoryEvent(.optOutStarted, runId: runId, profileQuery: label)
        do {
            let requiresEmailConfirmation = try await runner.optOut(scanResult,
                                                                    dataBroker: scanResult.dataBroker,
                                                                    showWebView: showWebView,
                                                                    timeout: optOutTimeout,
                                                                    stageCalculator: stageCalculator(runId: runId, stepType: .optOut, broker: scanResult.dataBroker, profileQuery: label))
            if requiresEmailConfirmation {
                setOptOutStatus(.awaitingEmailConfirmation, resultId: resultId, runId: runId)
                addHistoryEvent(.optOutSubmittedAndAwaitingEmailConfirmation, runId: runId, profileQuery: label)
            } else {
                setOptOutStatus(.confirmed, resultId: resultId, runId: runId)
                addHistoryEvent(.optOutConfirmed, runId: runId, profileQuery: label)
            }
        } catch {
            recordOptOutFailure(error, resultId: resultId, runId: runId, profileQuery: label)
        }
    }

    private func recordOptOutFailure(_ error: Error, resultId: String, runId: String, profileQuery: String) {
        update(runId) { $0.optOuts[resultId] = OptOut(status: .failed, error: error.localizedDescription) }
        addHistoryEvent(DebugModeRunner.historyError(error), runId: runId, profileQuery: profileQuery)
    }

    private func stageCalculator(runId: String, stepType: StepType, broker: DataBroker, profileQuery: String) -> FakeStageDurationCalculator {
        FakeStageDurationCalculator { [weak self] kind, actionType, details in
            let text = DebugModeRunner.runnerEventText(kind: kind, actionType: actionType, stepType: stepType, broker: broker)
            self?.addEvent(runId, kind: kind, profileQuery: profileQuery, summary: text.summary, details: details)
        }
    }

    // MARK: - Brokers

    private func resolveBroker(_ broker: DebugModeScanRequest.Broker) throws -> DataBroker {
        switch broker {
        case .json(let json):
            return try decodeBroker(json)
        case .stored(let identifier):
            let stored = try runner.storedBrokerResources().first {
                $0.broker.url.caseInsensitiveCompare(identifier) == .orderedSame
                    || $0.broker.name.caseInsensitiveCompare(identifier) == .orderedSame
            }
            guard let stored else {
                throw DebugModeRunError.brokerNotFound(identifier)
            }
            return stored.broker
        }
    }

    private func decodeBroker(_ json: Data) throws -> DataBroker {
        do {
            return try JSONDecoder().decode(DataBroker.self, from: json)
        } catch {
            throw DebugModeRunError.invalidRequest("broker JSON doesn't decode: \(error)")
        }
    }

    // MARK: - State

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    /// Call with the lock held.
    private func claim(_ runId: String) throws {
        if let activeRunId {
            throw DebugModeRunError.busy(runId: activeRunId)
        }
        activeRunId = runId
    }

    private func beginActivity<T>(_ activity: DebugModeRun.Activity,
                                  runId: String,
                                  prepare: (inout RunState) throws -> T) throws -> (DebugModeRun, T) {
        try locked {
            guard var state = runs[runId] else {
                throw DebugModeRunError.runNotFound(runId)
            }
            try claim(runId)
            let prepared: T
            do {
                prepared = try prepare(&state)
            } catch {
                activeRunId = nil
                throw error
            }
            state.activity = activity
            runs[runId] = state
            return (snapshot(of: state), prepared)
        }
    }

    private func launch(_ runId: String, _ work: @escaping @Sendable () async -> Void) {
        Task {
            await work()
            self.locked {
                self.runs[runId]?.activity = nil
                self.activeRunId = nil
            }
        }
    }

    private func update(_ runId: String, _ change: (inout RunState) -> Void) {
        locked {
            guard var state = runs[runId] else { return }
            change(&state)
            runs[runId] = state
        }
    }

    private func setOptOutStatus(_ status: DebugModeRun.OptOutStatus, resultId: String, runId: String) {
        update(runId) { $0.optOuts[resultId] = OptOut(status: status) }
    }

    private func addHistoryEvent(_ type: HistoryEvent.EventType, runId: String, profileQuery: String) {
        addEvent(runId, kind: .history, profileQuery: profileQuery, summary: DebugModeRunner.historyEventDescription(type), details: "")
    }

    private func addEvent(_ runId: String, kind: DebugEventKind, profileQuery: String, summary: String, details: String) {
        let event = DebugModeRun.Event(timestamp: Date(), kind: kind.rawValue, profileQuery: profileQuery, summary: summary, details: details)
        update(runId) { $0.events.append(event) }
    }

    private func addEventToActiveRun(summary: String, details: String) {
        guard let runId = locked({ activeRunId }) else { return }
        addEvent(runId, kind: .history, profileQuery: "-", summary: summary, details: details)
    }

    private static func resultId(for result: RunResult) -> String {
        "\(result.queryIndex)-\(result.scanResult.extractedProfile.id ?? 0)"
    }

    private static func result(_ resultId: String, in state: RunState) throws -> DebugScanResult {
        guard let result = state.results.first(where: { Self.resultId(for: $0) == resultId }) else {
            throw DebugModeRunError.resultNotFound(resultId)
        }
        return result.scanResult
    }

    private func snapshot(of state: RunState) -> DebugModeRun {
        DebugModeRun(id: state.id,
                 createdAt: state.createdAt,
                 broker: .init(name: state.broker.name, url: state.broker.url),
                 profileQueries: state.queries.map { DebugModeRunner.profileQueryText(for: $0.profileQuery) },
                 activity: state.activity,
                 scanErrors: state.scanErrors,
                 results: state.results.map { runResult in
                     let id = Self.resultId(for: runResult)
                     let result = runResult.scanResult
                     let profile = result.extractedProfile
                     return DebugModeRun.Result(id: id,
                                            profileQuery: DebugModeRunner.profileQueryText(for: result.profileQuery),
                                            name: profile.name ?? profile.fullName,
                                            age: profile.age,
                                            addresses: profile.addresses?.map(\.fullAddress) ?? [],
                                            profileUrl: profile.profileUrl,
                                            optOutStatus: state.optOuts[id]?.status,
                                            optOutError: state.optOuts[id]?.error,
                                            hasEmailConfirmationLink: runner.confirmationURL(for: result) != nil)
                 },
                 events: state.events)
    }
}
