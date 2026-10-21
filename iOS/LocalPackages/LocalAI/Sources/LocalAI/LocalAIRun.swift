//
//  LocalAIRun.swift
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

import Foundation
#if os(iOS)
import os
#endif

/// One generation, measured: what the approval write-up needs per request.
public struct LocalAIRunRecord: Codable, Sendable {
    public var caseID: String?
    public var run: Int
    public let engine: LocalAIEngineKind
    public let model: String
    public let task: LocalAITask
    public let target: LocalAITarget
    public let inputCharacters: Int
    public var timeToFirstToken: TimeInterval?
    public var totalTime: TimeInterval
    public var generatedTokens: Int?
    public var promptTokens: Int?
    /// Reading the input (prefill), and waiting for the model to load first, when the engine reports them.
    public var promptTime: TimeInterval?
    public var loadTime: TimeInterval?
    /// Decode rate: generated tokens over the time after the first token.
    public var tokensPerSecond: Double?
    public var peakFootprintBytes: Int64
    public var minimumAvailableMemoryBytes: Int64?
    public let thermalStateAtStart: String
    public var thermalStateAtEnd: String
    public var output: String
    /// `ok`, `cancelled`, or the error.
    public var outcome: String
}

public enum LocalAIDeviceMetrics {

    /// The number iOS compares against the app's memory limit.
    public static func physicalFootprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    /// Headroom before iOS kills the app for memory. `nil` where the API doesn't exist (macOS tests).
    public static func availableMemory() -> Int64? {
        #if os(iOS)
        return Int64(os_proc_available_memory())
        #else
        return nil
        #endif
    }

    public static var thermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}

/// Generations that were running when the app died. A non-zero count after a crash-free session is
/// most likely iOS killing the app for memory.
public enum LocalAIInterruptedRunTracker {

    static let inProgressKey = "localAI.generationInProgress"
    static let interruptedCountKey = "localAI.interruptedGenerations"

    /// Call once at launch.
    public static func recordInterruptedRunIfAny(defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: inProgressKey) else { return }
        defaults.set(defaults.integer(forKey: interruptedCountKey) + 1, forKey: interruptedCountKey)
        defaults.set(false, forKey: inProgressKey)
    }

    public static func interruptedCount(defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: interruptedCountKey)
    }

    public static func reset(defaults: UserDefaults = .standard) {
        defaults.set(0, forKey: interruptedCountKey)
    }

    static func setInProgress(_ inProgress: Bool, defaults: UserDefaults = .standard) {
        defaults.set(inProgress, forKey: inProgressKey)
    }
}

public enum LocalAIRunner {

    /// Streams `request` through `engine`, calling `onText` with each chunk, and measures the run. An
    /// engine error is returned alongside the record, whose `outcome` describes it.
    @MainActor
    public static func run(_ request: LocalAIRequest, engine: LocalAIEngine, caseID: String? = nil, run: Int = 1,
                           onText: (String) -> Void = { _ in }) async -> (record: LocalAIRunRecord, error: Error?) {
        await measure(engine.generate(LocalAIPromptBuilder.prompt(for: request)), request: request, engine: engine,
                      caseID: caseID, run: run, onText: onText)
    }

    /// Like `run`, but a translation goes out in pieces (see `LocalAIPromptBuilder.prompts(for:)`), the way the
    /// chat sends it. The record covers all pieces; its first-token and reading times are the first piece's.
    @MainActor
    public static func runAsShown(_ request: LocalAIRequest, engine: LocalAIEngine, caseID: String? = nil, run: Int = 1,
                                  onStatus: (LocalAIStatus) -> Void = { _ in },
                                  onText: (String) -> Void = { _ in }) async -> (record: LocalAIRunRecord, error: Error?) {
        let start = Date()
        var combined: LocalAIRunRecord?
        var output = ""
        for (index, prompt) in LocalAIPromptBuilder.prompts(for: request).enumerated() {
            if index > 0 {
                output += "\n\n"
                onText("\n\n")
            }
            let (record, error) = await measure(engine.generate(prompt), request: request, engine: engine, caseID: caseID, run: run,
                                                onStatus: index == 0 ? onStatus : { _ in }) { chunk in
                output += chunk
                onText(chunk)
            }
            if var first = combined {
                first.generatedTokens = (first.generatedTokens ?? 0) + (record.generatedTokens ?? 0)
                first.peakFootprintBytes = max(first.peakFootprintBytes, record.peakFootprintBytes)
                first.thermalStateAtEnd = record.thermalStateAtEnd
                combined = first
            } else {
                combined = record
            }
            if error != nil || record.outcome != "ok" {
                combined?.outcome = record.outcome
                return finish(combined!, output: output, start: start, error: error)
            }
        }
        return finish(combined!, output: output, start: start, error: nil)
    }

    @MainActor
    private static func finish(_ record: LocalAIRunRecord, output: String, start: Date, error: Error?) -> (record: LocalAIRunRecord, error: Error?) {
        var record = record
        record.output = output
        record.totalTime = Date().timeIntervalSince(start)
        if let firstToken = record.timeToFirstToken, let tokens = record.generatedTokens, record.totalTime > firstToken, tokens > 1 {
            record.tokensPerSecond = Double(tokens - 1) / (record.totalTime - firstToken)
        }
        return (record, error)
    }

    /// Consumes `events` (one reply, e.g. a turn of a conversation) and measures it like `run`.
    @MainActor
    public static func measure(_ events: AsyncThrowingStream<LocalAIEvent, Error>, request: LocalAIRequest, engine: LocalAIEngine,
                               caseID: String? = nil, run: Int = 1,
                               onStatus: (LocalAIStatus) -> Void = { _ in },
                               onText: (String) -> Void = { _ in }) async -> (record: LocalAIRunRecord, error: Error?) {
        let target: LocalAITarget = if case .page = request.source { .page } else { .selection }
        var record = LocalAIRunRecord(caseID: caseID, run: run, engine: engine.kind, model: engine.modelName,
                                      task: request.task, target: target, inputCharacters: request.source.characterCount,
                                      timeToFirstToken: nil, totalTime: 0, generatedTokens: nil, promptTokens: nil,
                                      promptTime: nil, loadTime: nil,
                                      tokensPerSecond: nil, peakFootprintBytes: LocalAIDeviceMetrics.physicalFootprint(),
                                      minimumAvailableMemoryBytes: LocalAIDeviceMetrics.availableMemory(),
                                      thermalStateAtStart: LocalAIDeviceMetrics.thermalState, thermalStateAtEnd: "",
                                      output: "", outcome: "ok")
        let start = Date()
        var chunks = 0
        var runError: Error?
        LocalAIInterruptedRunTracker.setInProgress(true)
        defer { LocalAIInterruptedRunTracker.setInProgress(false) }

        do {
            for try await event in events {
                switch event {
                case .status(let status):
                    onStatus(status)
                case .text(let text):
                    if record.timeToFirstToken == nil {
                        record.timeToFirstToken = Date().timeIntervalSince(start)
                    }
                    chunks += 1
                    record.output += text
                    onText(text)
                    sampleMemory(into: &record)
                case .finished(let info):
                    record.generatedTokens = info?.generatedTokens
                    record.promptTokens = info?.promptTokens
                    record.promptTime = info?.promptTime
                    record.loadTime = info?.loadTime
                }
            }
            if Task.isCancelled {
                record.outcome = "cancelled"
            }
        } catch is CancellationError {
            record.outcome = "cancelled"
        } catch {
            record.outcome = error.localizedDescription
            runError = error
        }

        record.totalTime = Date().timeIntervalSince(start)
        record.thermalStateAtEnd = LocalAIDeviceMetrics.thermalState
        sampleMemory(into: &record)
        let tokens = record.generatedTokens ?? chunks
        if let firstToken = record.timeToFirstToken, record.totalTime > firstToken, tokens > 1 {
            record.tokensPerSecond = Double(tokens - 1) / (record.totalTime - firstToken)
        }
        return (record, runError)
    }

    private static func sampleMemory(into record: inout LocalAIRunRecord) {
        record.peakFootprintBytes = max(record.peakFootprintBytes, LocalAIDeviceMetrics.physicalFootprint())
        if let available = LocalAIDeviceMetrics.availableMemory() {
            record.minimumAvailableMemoryBytes = min(record.minimumAvailableMemoryBytes ?? available, available)
        }
    }
}
