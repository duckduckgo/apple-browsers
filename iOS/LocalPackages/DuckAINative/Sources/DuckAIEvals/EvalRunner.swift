//
//  EvalRunner.swift
//  DuckDuckGo
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

import DuckAIChatCore
import Foundation

public enum EvalOutcome: String, Codable, Sendable {
    case completed
    case refused
    case failed
    case timedOut
}

/// One run of one case on one provider. Times are seconds.
public struct EvalRecord: Codable, Equatable, Sendable {
    public let caseID: String
    public let task: EvalTask
    public let providerID: String
    public let modelName: String
    public let runIndex: Int
    public let outcome: EvalOutcome
    public let error: String?
    public let output: String
    public let estimatedInputTokens: Int
    public let timeToFirstToken: Double?
    public let totalTime: Double
    public let generatedTokens: Int?
    public let tokensPerSecond: Double?
    public let peakMemoryBytes: Int64?
    public let thermalState: String?

    public init(caseID: String,
                task: EvalTask,
                providerID: String,
                modelName: String,
                runIndex: Int,
                outcome: EvalOutcome,
                error: String?,
                output: String,
                estimatedInputTokens: Int,
                timeToFirstToken: Double?,
                totalTime: Double,
                generatedTokens: Int?,
                tokensPerSecond: Double?,
                peakMemoryBytes: Int64?,
                thermalState: String?) {
        self.caseID = caseID
        self.task = task
        self.providerID = providerID
        self.modelName = modelName
        self.runIndex = runIndex
        self.outcome = outcome
        self.error = error
        self.output = output
        self.estimatedInputTokens = estimatedInputTokens
        self.timeToFirstToken = timeToFirstToken
        self.totalTime = totalTime
        self.generatedTokens = generatedTokens
        self.tokensPerSecond = tokensPerSecond
        self.peakMemoryBytes = peakMemoryBytes
        self.thermalState = thermalState
    }
}

public struct EvalReport: Codable, Equatable, Sendable {
    public let device: String
    public let osVersion: String
    public let startedAt: Date
    public let records: [EvalRecord]

    public init(device: String,
                osVersion: String,
                startedAt: Date,
                records: [EvalRecord]) {
        self.device = device
        self.osVersion = osVersion
        self.startedAt = startedAt
        self.records = records
    }
}

/// What the runner samples around each run. The app supplies a real one (phys_footprint, thermal state).
public protocol DeviceMetricsSampling: Sendable {
    func beginRun()
    /// Peak memory since `beginRun()`, and the thermal state now.
    func endRun() -> (peakMemoryBytes: Int64?, thermalState: String?)
}

public struct NoDeviceMetrics: DeviceMetricsSampling {
    public init() {}
    public func beginRun() {}
    public func endRun() -> (peakMemoryBytes: Int64?, thermalState: String?) { (nil, nil) }
}

/// Runs cases through one provider, one at a time, `runs` times each, and never throws: a failing case is a record.
public struct EvalRunner: Sendable {
    public static let defaultTimeout: Duration = .seconds(120)

    private let provider: any ChatProvider
    private let metrics: any DeviceMetricsSampling
    private let timeout: Duration

    public init(provider: any ChatProvider, metrics: any DeviceMetricsSampling = NoDeviceMetrics(),
                timeout: Duration = EvalRunner.defaultTimeout) {
        self.provider = provider
        self.metrics = metrics
        self.timeout = timeout
    }

    /// - Builds each case's turn with `EvalCase.turn`; a case that throws becomes a `.failed` record with zero times.
    /// - `timeToFirstToken` is from sending to the first `.textDelta`; `totalTime` to the end of the stream.
    /// - `generatedTokens` and `tokensPerSecond` come from `.finished` stats when present
    ///   (`tokensPerSecond` = generatedTokens / generateTime).
    /// - `.refusal` gives `.refused`; a thrown error gives `.failed` with its description; passing `timeout` raises the
    ///   reply's StopSignal and gives `.timedOut` with the text so far.
    /// - `progress` is called after every record with (done, total).
    public func run(_ cases: [EvalCase], runs: Int = 1, device: String, osVersion: String, now: Date = Date(),
                    progress: @Sendable (Int, Int) -> Void = { _, _ in }) async -> EvalReport {
        var records: [EvalRecord] = []
        let runCount = max(0, runs)
        for evalCase in cases {
            for runIndex in 0..<runCount {
                let record = await run(evalCase, runIndex: runIndex)
                records.append(record)
                progress(records.count, cases.count * runCount)
            }
        }
        return EvalReport(device: device, osVersion: osVersion, startedAt: now, records: records)
    }
}

private extension EvalRunner {
    func run(_ evalCase: EvalCase, runIndex: Int) async -> EvalRecord {
        let descriptor = provider.descriptor
        let turn: ProviderTurn
        do {
            turn = try evalCase.turn(conversation: ConversationID(), budget: PromptBudget(descriptor))
        } catch {
            return EvalRecord(caseID: evalCase.id, task: evalCase.task, providerID: descriptor.id.rawValue,
                              modelName: descriptor.modelName, runIndex: runIndex, outcome: .failed,
                              error: String(describing: error), output: "", estimatedInputTokens: 0,
                              timeToFirstToken: nil, totalTime: 0, generatedTokens: nil, tokensPerSecond: nil,
                              peakMemoryBytes: nil, thermalState: nil)
        }
        metrics.beginRun()
        let start = ContinuousClock.now
        let stop = StopSignal()
        let result = await withCheckedContinuation { continuation in
            let state = EvalRunState(start: start, continuation: continuation)
            let timer = Task {
                do {
                    try await Task.sleep(for: timeout)
                    await state.timeOut(stop: stop)
                } catch {}
            }
            Task {
                do {
                    for try await event in provider.reply(to: turn, stop: stop) {
                        await state.receive(event)
                    }
                    await state.finish()
                } catch {
                    await state.finish(outcome: .failed, error: String(describing: error))
                }
                timer.cancel()
            }
        }
        let samples = metrics.endRun()
        let tokensPerSecond: Double? = result.stats.flatMap { stats in
            guard let duration = stats.generateTime.map(seconds), duration > 0 else { return nil }
            return Double(stats.generatedTokens) / duration
        }
        return EvalRecord(caseID: evalCase.id, task: evalCase.task, providerID: descriptor.id.rawValue,
                          modelName: descriptor.modelName, runIndex: runIndex, outcome: result.outcome,
                          error: result.error, output: result.output, estimatedInputTokens: turn.estimatedInputTokens,
                          timeToFirstToken: result.timeToFirstToken, totalTime: result.totalTime,
                          generatedTokens: result.stats?.generatedTokens, tokensPerSecond: tokensPerSecond,
                          peakMemoryBytes: samples.peakMemoryBytes, thermalState: samples.thermalState)
    }
}

private struct EvalRunResult: Sendable {
    let outcome: EvalOutcome
    let error: String?
    let output: String
    let timeToFirstToken: Double?
    let totalTime: Double
    let stats: GenerationStats?
}

private actor EvalRunState {
    let start: ContinuousClock.Instant
    let continuation: CheckedContinuation<EvalRunResult, Never>
    var output = ""
    var timeToFirstToken: Double?
    var stats: GenerationStats?
    var finished = false
    var terminalOutcome: EvalOutcome = .completed

    init(start: ContinuousClock.Instant, continuation: CheckedContinuation<EvalRunResult, Never>) {
        self.start = start
        self.continuation = continuation
    }

    func receive(_ event: ProviderEvent) {
        guard !finished else { return }
        switch event {
        case .textDelta(let text):
            if timeToFirstToken == nil { timeToFirstToken = seconds(start.duration(to: .now)) }
            output += text
        case .finished(let stats):
            self.stats = stats
        case .refusal:
            terminalOutcome = .refused
        default:
            break
        }
    }

    func timeOut(stop: StopSignal) {
        guard !finished else { return }
        stop.raise()
        finish(outcome: .timedOut)
    }

    func finish(outcome: EvalOutcome? = nil, error: String? = nil) {
        guard !finished else { return }
        finished = true
        continuation.resume(returning: EvalRunResult(outcome: outcome ?? terminalOutcome, error: error, output: output,
                                                    timeToFirstToken: timeToFirstToken, totalTime: seconds(start.duration(to: .now)), stats: stats))
    }
}

private func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}
