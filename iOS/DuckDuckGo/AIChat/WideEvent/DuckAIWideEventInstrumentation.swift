//
//  DuckAIWideEventInstrumentation.swift
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
import AIChat
import PixelKit

enum DuckAIWideEventFlowScope: Hashable {
    case tab(TabUID)
    case contextual(UUID)
}

@MainActor
protocol DuckAIWideEventInstrumentation: AnyObject {

    /// User submitted a Duck.ai prompt. Starts a new wide-event flow.
    func submissionStarted(scope: DuckAIWideEventFlowScope,
                           modelId: String?,
                           userTier: AIChatUserTier,
                           reasoningEffort: AIChatReasoningEffort?,
                           entryPoint: DuckAIPromptWideEventData.EntryPoint,
                           inputMode: DuckAIPromptWideEventData.InputMode,
                           fireMode: Bool,
                           isFirstPrompt: Bool,
                           frontendDeliveryPath: DuckAIPromptWideEventData.FrontendDeliveryPath,
                           hasPageContext: Bool,
                           toolsSelected: Bool,
                           attachmentsSelected: Bool)

    /// Native attempted to hand the prompt to the frontend. Records whether
    /// contextual delivery was queued and whether a user-script bridge message was sent.
    func promptDeliveryUpdated(scope: DuckAIWideEventFlowScope, wasQueued: Bool?, didSendBridgeMessage: Bool?)

    /// The Duck.ai frontend reported its prompt-submitted metric for the active flow.
    func frontendSubmissionAcknowledged(scope: DuckAIWideEventFlowScope)

    /// The Duck.ai chat status published a new value. The instrumentation
    /// completes the active flow as SUCCESS the first time `.ready` is observed
    /// after at least one non-`.ready` value during the flow's lifetime. A page-
    /// reported `.error` or `.blocked` status completes the flow as FAILURE.
    func chatStatusChanged(_ status: AIChatStatusValue, scope: DuckAIWideEventFlowScope)

    /// User tapped the stop-generating button. Completes the active flow as
    /// CANCELLED with `cancellation_reason = stop_button`. After this, any
    /// subsequent `.ready` status is ignored.
    func stopGeneratingTapped(scope: DuckAIWideEventFlowScope)

    /// User closed a Duck.ai tab while a response was still in flight.
    /// Completes the active flow as CANCELLED with
    /// `cancellation_reason = tab_closed`. No-op if no flow is active.
    func tabClosedDuringGeneration(tabID: TabUID)

    /// User switched away from a Duck.ai tab while a response was still in
    /// flight. Completes the active flow as CANCELLED with
    /// `cancellation_reason = switched_tabs`. No-op if no flow is active.
    func tabSwitchedAwayDuringGeneration(tabID: TabUID)

    /// User used the Fire button to clear a Duck.ai tab while a response was
    /// still in flight. Completes the active flow as CANCELLED with
    /// `cancellation_reason = fire_button`. No-op if no flow is active.
    func fireButtonClearedTabDuringGeneration(tabID: TabUID)

    /// The contextual chat sheet was explicitly dismissed (user tapped
    /// delete-chat, or the fire-button workflow cleared it) while a response
    /// was still in flight. Completes the active flow as CANCELLED with
    /// `cancellation_reason = sheet_dismissed`. No-op if no flow is active.
    func sheetDismissedDuringGeneration(scope: DuckAIWideEventFlowScope)

    /// The Duck.ai webview's navigation failed (e.g. network error, DNS
    /// failure). If a submission is in flight, completes the active flow as
    /// FAILURE with `failing_step = navigation_failed` and attaches the
    /// `NSError` domain/code to the event's error data. No-op if no flow is in
    /// flight.
    func pageLoadFailed(scope: DuckAIWideEventFlowScope, error: Error)

    /// The submitted text was interpreted as a URL and navigated to instead of
    /// being sent to Duck.ai. Completes the active flow as CANCELLED with
    /// `cancellation_reason = interpreted_as_url`. No-op if no flow is active.
    func promptInterpretedAsURL(scope: DuckAIWideEventFlowScope)
}

@MainActor
final class DefaultDuckAIWideEventInstrumentation: DuckAIWideEventInstrumentation {

    private struct ActiveFlow {
        var data: DuckAIPromptWideEventData
        var hasObservedNonReady = false
    }

    private let wideEvent: WideEventManaging
    private let dateProvider: () -> Date
    private var activeFlows: [DuckAIWideEventFlowScope: ActiveFlow] = [:]

    init(wideEvent: WideEventManaging,
         completeOrphanedFlowsOnInit: Bool = false,
         dateProvider: @escaping () -> Date = { Date() }) {
        self.wideEvent = wideEvent
        self.dateProvider = dateProvider

        if completeOrphanedFlowsOnInit {
            completeOrphanedFlowsFromPreviousAppSession()
        }
    }

    func submissionStarted(scope: DuckAIWideEventFlowScope,
                           modelId: String?,
                           userTier: AIChatUserTier,
                           reasoningEffort: AIChatReasoningEffort?,
                           entryPoint: DuckAIPromptWideEventData.EntryPoint,
                           inputMode: DuckAIPromptWideEventData.InputMode,
                           fireMode: Bool,
                           isFirstPrompt: Bool,
                           frontendDeliveryPath: DuckAIPromptWideEventData.FrontendDeliveryPath,
                           hasPageContext: Bool,
                           toolsSelected: Bool,
                           attachmentsSelected: Bool) {
        completeSupersededFlowIfNeeded(scope: scope)

        let data = DuckAIPromptWideEventData(
            modelId: modelId,
            userTier: userTier.rawValue,
            reasoningEffort: reasoningEffort?.rawValue,
            entryPoint: entryPoint,
            inputMode: inputMode,
            fireMode: fireMode,
            isFirstPrompt: isFirstPrompt,
            frontendDeliveryPath: frontendDeliveryPath,
            hasPageContext: hasPageContext,
            toolsSelected: toolsSelected,
            attachmentsSelected: attachmentsSelected,
            startedAt: dateProvider()
        )
        activeFlows[scope] = ActiveFlow(data: data)
        data.lastStep = .submitted
        wideEvent.startFlow(data)
    }

    func promptDeliveryUpdated(scope: DuckAIWideEventFlowScope, wasQueued: Bool?, didSendBridgeMessage: Bool?) {
        guard let activeFlow = activeFlows[scope] else { return }
        let data = activeFlow.data

        if let wasQueued {
            data.frontendDeliveryQueued = wasQueued
        }

        if let didSendBridgeMessage {
            data.didSendBridgeMessage = didSendBridgeMessage
        }

        if wasQueued != true {
            data.didAttemptDelivery = true
        }

        wideEvent.updateFlow(data)
    }

    func frontendSubmissionAcknowledged(scope: DuckAIWideEventFlowScope) {
        guard let activeFlow = activeFlows[scope],
              activeFlow.data.frontendSubmissionAckInterval.end == nil else { return }

        activeFlow.data.frontendSubmissionAckInterval.end = dateProvider()
        wideEvent.updateFlow(activeFlow.data)
    }

    func chatStatusChanged(_ status: AIChatStatusValue, scope: DuckAIWideEventFlowScope) {
        guard var activeFlow = activeFlows[scope] else { return }
        let data = activeFlow.data

        if status == .ready {
            guard activeFlow.hasObservedNonReady else { return }
            let now = dateProvider()
            data.generatingCompletedInterval.end = now
            data.endedInterval.end = now
            // SUCCESS doesn't carry last_step.
            data.lastStep = nil
            wideEvent.completeFlow(data, status: .success(), onComplete: { _, _ in })
            activeFlows[scope] = nil
            return
        }

        // Map every non-`ready` status to a journey step so UNKNOWN orphans
        // (recovered from storage on next launch) report where the flow was
        // when the app died.
        data.lastStep = Self.lastStep(for: status)

        let now = dateProvider()
        if data.startThinkingInterval.end == nil {
            data.startThinkingInterval.end = now
        }

        if status == .error || status == .blocked {
            data.endedInterval.end = now
            wideEvent.completeFlow(data, status: .failure, onComplete: { _, _ in })
            activeFlows[scope] = nil
            return
        }

        activeFlow.hasObservedNonReady = true
        if status == .streaming, data.startGeneratingInterval.end == nil {
            data.startGeneratingInterval.end = now
        }
        // Persist the new step + intervals so orphan recovery sees the
        // latest progression after an app kill.
        activeFlows[scope] = activeFlow
        wideEvent.updateFlow(data)
    }

    private static func lastStep(for status: AIChatStatusValue) -> DuckAIPromptWideEventData.LastStep {
        switch status {
        case .loading: return .loading
        case .streaming: return .streaming
        case .startStreamNewPrompt: return .startStreamNewPrompt
        case .startStreamRestartStream: return .startStreamRestartStream
        case .unknown: return .unknownStatus
        case .error: return .responseStateError
        case .blocked: return .responseStateBlocked
        case .ready: return .submitted // unreachable; .ready is handled above.
        }
    }

    func stopGeneratingTapped(scope: DuckAIWideEventFlowScope) {
        cancelFlow(scope: scope, reason: .stopButton)
    }

    func tabClosedDuringGeneration(tabID: TabUID) {
        cancelFlow(scope: .tab(tabID), reason: .tabClosed)
    }

    func tabSwitchedAwayDuringGeneration(tabID: TabUID) {
        cancelFlow(scope: .tab(tabID), reason: .switchedTabs)
    }

    func fireButtonClearedTabDuringGeneration(tabID: TabUID) {
        cancelFlow(scope: .tab(tabID), reason: .fireButton)
    }

    func sheetDismissedDuringGeneration(scope: DuckAIWideEventFlowScope) {
        cancelFlow(scope: scope, reason: .sheetDismissed)
    }

    func pageLoadFailed(scope: DuckAIWideEventFlowScope, error: Error) {
        guard let activeFlow = activeFlows[scope] else { return }
        activeFlow.data.lastStep = .navigationFailed
        activeFlow.data.errorData = WideEventErrorData(error: error)
        activeFlow.data.endedInterval.end = dateProvider()
        wideEvent.completeFlow(activeFlow.data, status: .failure, onComplete: { _, _ in })
        activeFlows[scope] = nil
    }

    func promptInterpretedAsURL(scope: DuckAIWideEventFlowScope) {
        cancelFlow(scope: scope, reason: .interpretedAsURL)
    }

    // MARK: - Helpers

    private func completeSupersededFlowIfNeeded(scope: DuckAIWideEventFlowScope) {
        cancelFlow(scope: scope, reason: .supersededByNewSubmission)
    }

    private func cancelFlow(scope: DuckAIWideEventFlowScope, reason: DuckAIPromptWideEventData.CancellationReason) {
        guard let activeFlow = activeFlows[scope] else { return }
        activeFlow.data.cancellationReason = reason
        activeFlow.data.endedInterval.end = dateProvider()
        wideEvent.completeFlow(activeFlow.data, status: .cancelled, onComplete: { _, _ in })
        activeFlows[scope] = nil
    }

    private func completeOrphanedFlowsFromPreviousAppSession() {
        for orphan in wideEvent.getAllFlowData(DuckAIPromptWideEventData.self) {
            wideEvent.completeFlow(
                orphan,
                status: .unknown(reason: DuckAIPromptWideEventData.appTerminatedReason),
                onComplete: { _, _ in })
        }
    }
}
