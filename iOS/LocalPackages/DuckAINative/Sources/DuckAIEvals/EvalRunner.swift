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
}

public struct EvalReport: Codable, Equatable, Sendable {
    public let device: String
    public let osVersion: String
    public let startedAt: Date
    public let records: [EvalRecord]
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
        fatalError("not implemented")
    }
}
