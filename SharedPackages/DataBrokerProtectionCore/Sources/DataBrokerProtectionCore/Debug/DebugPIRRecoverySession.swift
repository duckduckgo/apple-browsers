//
//  DebugPIRRecoverySession.swift
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

#if DEBUG
import Foundation
import WebKit
import os.log

/// App-owned generation is injected only into manually launched debug jobs. Core has no model dependency.
@MainActor
public final class DebugPIRRecoverySession {
    public struct Request: Sendable {
        public let stepJSON: String
        public let completedActionCount: Int
        public let failedActionID: String
        public let availableData: [String]
    }

    /// Returns a normal PIR action. The existing runner owns all execution and subsequent steps.
    public typealias Generator = @MainActor (Request, WKWebView, @escaping () -> Bool, @escaping (String) -> Void) async throws -> Action?
    let generate: Generator
    var attempted = false
    var isGenerating = false
    var isInvalidated = false
    var originalActionID: String?
    var replacementActionID: String?
    var completedReplacementID: String?

    public init(generate: @escaping Generator) {
        self.generate = generate
    }
}

public extension SubJobWebRunning {
    @MainActor var debugRecovery: DebugPIRRecoverySession? { nil }

    @MainActor
    func acceptDebugRecoveryCallback(actionID: String) -> Bool {
        guard let recovery = debugRecovery else { return true }
        // A late callback from the timed-out original action must not advance or fail its replacement.
        return !recovery.isGenerating && !recovery.isInvalidated
            && actionID != recovery.originalActionID && actionID != recovery.completedReplacementID
    }

    @MainActor
    func recordDebugRecoveryExecution(actionID: String) {
        guard let recovery = debugRecovery, recovery.replacementActionID == actionID else { return }
        recovery.completedReplacementID = actionID
        recovery.replacementActionID = nil
        logDebugRecovery("Replacement executed. Resuming the authored sequence; subsequent PIR steps determine progress and job completion.", phase: "replacement-executed")
    }

    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    func attemptDebugRecovery(after error: Error) async -> Bool {
        guard let recovery = debugRecovery else { return false }
        if recovery.isGenerating {
            // Non-action failures (navigation/process errors) still terminate the job while inference is pending.
            recovery.isInvalidated = true
            return false
        }
        guard !recovery.attempted else {
            logDebugRecovery("Recovery unavailable: the one-attempt budget for this job has been used. Returning to normal failure handling.", phase: "budget-exhausted")
            return false
        }
        guard case DataBrokerProtectionError.actionFailed(let actionID, _) = error,
              let handler = actionsHandler, let action = handler.currentAction(), action.id == actionID,
              action.actionType == .click || action.actionType == .fillForm,
              let webView = webViewHandler?.webViewForInspection else {
            logDebugRecovery("Failure is outside supported click/fillForm recovery. Returning to normal failure handling.")
            return false
        }
        recovery.attempted = true
        recovery.isGenerating = true
        defer { recovery.isGenerating = false }
        logDebugRecovery("Started after normal retries were exhausted. Failed action: \(actionID) (\(action.actionType.rawValue)). Capturing the live PIR page.", phase: "started")
        do {
            guard let step = try handler.debugRecoveryStep() else { return false }
            var availableData: [String] = []
            if !context.profileQuery.firstName.isEmpty { availableData.append("userProfile.firstName") }
            if !context.profileQuery.lastName.isEmpty { availableData.append("userProfile.lastName") }
            if let fetchedEmail, !fetchedEmail.isEmpty { availableData.append("fetchedEmail.email") }
            if let url = extractedProfile?.profileUrl, !url.isEmpty { availableData.append("extractedProfile.profileUrl") }
            let request = DebugPIRRecoverySession.Request(stepJSON: step.json, completedActionCount: step.index,
                                                         failedActionID: actionID, availableData: availableData)
            let replacement = try await recovery.generate(request, webView, { [weak self, weak recovery] in
                self?.shouldRunNextStep() == true && recovery?.isInvalidated == false
            }, { [weak self] message in
                self?.logDebugRecovery(message)
            })
            guard !recovery.isInvalidated else { return true }
            guard shouldRunNextStep(), !Task.isCancelled else {
                logDebugRecovery("Canceled or timed out during generation. No replacement executed.", phase: "canceled")
                await failAsCancelledAndTearDown()
                return true
            }
            guard let replacement else {
                logDebugRecovery("No eligible replacement. Returning to normal failure handling.", phase: "no-replacement")
                return false
            }
            guard replacement.actionType == action.actionType, replacement.id != actionID,
                  handler.replaceCurrentActionForDebugRecovery(replacement, expectedID: actionID) else {
                logDebugRecovery("Replacement rejected: action type or runner position changed.")
                return false
            }
            recovery.originalActionID = actionID
            recovery.replacementActionID = replacement.id
            recovery.isGenerating = false
            logDebugRecovery("Executing generated action \(replacement.id) through the PIR runner.", phase: "executing-replacement")
            await runNextAction(replacement)
            return true
        } catch {
            guard !recovery.isInvalidated else { return true }
            if !shouldRunNextStep() || Task.isCancelled {
                logDebugRecovery("Canceled or timed out. No replacement executed.", phase: "canceled")
                await failAsCancelledAndTearDown()
                return true
            }
            logDebugRecovery("Generation or validation failed: \(error.localizedDescription). Returning to normal failure handling.", phase: "generation-failed")
            return false
        }
    }

    @MainActor
    private func logDebugRecovery(_ message: String, phase: String = "progress") {
        // Full details remain in the existing in-memory debug event UI; system logs redact page-derived text.
        Logger.dataBrokerProtection.notice("[PIR Recovery] phase=\(phase, privacy: .public) details=\(message, privacy: .private)")
        recordDebugEvent(kind: .actionRetry, actionType: actionsHandler?.currentAction()?.actionType,
                         details: "[PIR Recovery] " + message)
    }
}
#endif
