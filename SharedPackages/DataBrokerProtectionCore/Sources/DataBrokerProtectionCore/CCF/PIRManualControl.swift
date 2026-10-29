//
//  PIRManualControl.swift
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

#if os(macOS) && DEBUG
import Foundation

/// One operation's manual handoff. Challenge handoffs invalidate older automated work.
@MainActor
final class PIRManualControl {
    var epoch = UUID()
    var isPaused = false
    var isManagedChallenge = false {
        didSet {
            if isManagedChallenge && !oldValue && isPaused {
                invalidateAutomation()
            }
        }
    }
    /// A Turnstile widget inside the broker's own form, which a person has to solve.
    var isEmbeddedChallenge = false
    private(set) var preservesAutomation = false
    var resume: (() async -> Void)?
    var cancel: (() async -> Void)?
    let budget = PIRManualControlContext.budget

    func allows(_ epoch: UUID) -> Bool { !isPaused && !isManagedChallenge && self.epoch == epoch }

    func pause(preservingAutomation: Bool = false) {
        preservesAutomation = preservingAutomation
        if !preservingAutomation { epoch = UUID() }
        isPaused = true
        budget?.isPaused = true
    }

    func invalidateAutomation() {
        preservesAutomation = false
        epoch = UUID()
    }

    func waitForAutomation(_ epoch: UUID) async -> Bool {
        while isPaused && preservesAutomation && !isManagedChallenge && self.epoch == epoch {
            do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return false }
        }
        return !Task.isCancelled && allows(epoch)
    }

    func endPause() {
        isEmbeddedChallenge = false
        isPaused = false
        budget?.isPaused = false
    }
}

@MainActor
final class PIRManualControlBudget {
    var isPaused = false
}

enum PIRManualControlContext {
    @TaskLocal static var budget: PIRManualControlBudget?

    static func withTimeout<T>(_ seconds: TimeInterval, throwing error: Error,
                               operation: @escaping () async throws -> T) async throws -> T {
        let budget = await PIRManualControlBudget()
        return try await $budget.withValue(budget) {
            try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask { try await operation() }
                group.addTask {
                    var automaticTime: TimeInterval = 0
                    var manualTime: TimeInterval = 0
                    var previous = ProcessInfo.processInfo.systemUptime
                    while true {
                        try await Task.sleep(nanoseconds: 250_000_000)
                        let now = ProcessInfo.processInfo.systemUptime
                        let elapsed = now - previous
                        previous = now
                        if await budget.isPaused { manualTime += elapsed } else { automaticTime += elapsed }
                        if automaticTime >= seconds || manualTime >= 600 { throw error }
                    }
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw error }
                return result
            }
        }
    }
}
#endif
