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
import AppKit
import WebKit

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
    private(set) var preservesAutomation = false
    var action: Action?
    var resume: (() async -> Void)?
    var cancel: (() async -> Void)?
    let budget = PIRManualControlContext.budget

    var canTakeControl: Bool { !isPaused && action != nil }

    var instruction: String {
        isManagedChallenge ? "Complete Cloudflare's security check on this page."
            : "Automation is paused. Use this page, then choose Resume automatically."
    }

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
        isPaused = false
        budget?.isPaused = false
    }

    /// Patch only the pinned POC engine, rather than alter a shared package checkout.
    /// Fail closed if a package update changes these execution points.
    static func guardedScript(_ script: WKUserScript) throws -> WKUserScript {
        let hooks = [
            ("async processActionAndNotify(action, data2) {", "async processActionAndNotify(action, data2) { const pirEpoch = globalThis.__pirControl.epoch;"),
            ("const { results, exceptions } = await this.exec(action, data2);", "const { results, exceptions } = await this.exec(action, data2); if (!await globalThis.__pirControl.wait(pirEpoch)) return;"),
            ("this.log.error(\"unhandled exception: \"", "if (!await globalThis.__pirControl.wait(pirEpoch)) return; this.log.error(\"unhandled exception: \""),
            ("async exec(action, data2) {", "async exec(action, data2) { const pirEpoch = globalThis.__pirControl.epoch; if (!await globalThis.__pirControl.wait(pirEpoch)) throw new Error('Manual control');"),
            ("retry(() => execute(action, data2, document), retryConfig);", "retry(async () => { if (!await globalThis.__pirControl.wait(pirEpoch)) return new SuccessResponse({ actionID: action.id, actionType: action.actionType, response: null }); return execute(action, data2, document); }, retryConfig); if (!await globalThis.__pirControl.wait(pirEpoch)) throw new Error('Manual control');"),
            ("var BrokerProtection = class extends ActionExecutorBase {", "globalThis.__pirControl = { paused: false, epoch: 0, wait: async (epoch) => { while (globalThis.__pirControl.paused && epoch === globalThis.__pirControl.epoch) await new Promise(resolve => setTimeout(resolve, 50)); return epoch === globalThis.__pirControl.epoch; } }; var BrokerProtection = class extends ActionExecutorBase {")
        ]
        var source = script.source
        for (original, replacement) in hooks {
            guard source.components(separatedBy: original).count == 2 else {
                throw DataBrokerProtectionError.unknown("PIR manual control script hook is unavailable")
            }
            source = source.replacingOccurrences(of: original, with: replacement)
        }
        return WKUserScript(source: source, injectionTime: script.injectionTime,
                            forMainFrameOnly: script.isForMainFrameOnly, in: .defaultClient)
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
