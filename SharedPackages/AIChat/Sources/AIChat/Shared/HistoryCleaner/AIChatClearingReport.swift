//
//  AIChatClearingReport.swift
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

/// What happened during the last JS clear, for telemetry: whether it was retried and where its time went.
public struct AIChatClearingReport {
    public let attempts: Int
    public let firstAttemptError: Error?
    /// Timings of the first attempt, which is the one that failed when a clear was retried.
    public let firstAttemptTimings: AIChatClearingTimings

    public var wasRetried: Bool { attempts > 1 }

    public init(attempts: Int, firstAttemptError: Error?, firstAttemptTimings: AIChatClearingTimings) {
        self.attempts = attempts
        self.firstAttemptError = firstAttemptError
        self.firstAttemptTimings = firstAttemptTimings
    }
}

/// The slowest time of each phase across the origins of one attempt.
public struct AIChatClearingTimings: Equatable {
    public var pageLoadMilliseconds: Int?
    public var scriptReadyMilliseconds: Int?
    public var scriptReplyMilliseconds: Int?

    public init(pageLoadMilliseconds: Int? = nil, scriptReadyMilliseconds: Int? = nil, scriptReplyMilliseconds: Int? = nil) {
        self.pageLoadMilliseconds = pageLoadMilliseconds
        self.scriptReadyMilliseconds = scriptReadyMilliseconds
        self.scriptReplyMilliseconds = scriptReplyMilliseconds
    }
}

@MainActor
final class AIChatClearingTimingsRecorder {

    private(set) var timings = AIChatClearingTimings()

    func measure<T>(_ phase: WritableKeyPath<AIChatClearingTimings, Int?>, _ work: () async -> T) async -> T {
        let start = ProcessInfo.processInfo.systemUptime
        let value = await work()
        let milliseconds = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
        timings[keyPath: phase] = max(timings[keyPath: phase] ?? 0, milliseconds)
        return value
    }
}
