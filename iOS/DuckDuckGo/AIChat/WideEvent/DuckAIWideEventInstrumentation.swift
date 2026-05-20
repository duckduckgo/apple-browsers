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

protocol DuckAIWideEventInstrumentation: AnyObject {

    /// User submitted a Duck.ai prompt. Starts a new wide-event flow.
    func submissionStarted(modelId: String?,
                           userTier: AIChatUserTier,
                           reasoningEffort: AIChatReasoningEffort?,
                           entryPoint: DuckAIPromptSubmissionWideEventData.EntryPoint,
                           inputMode: DuckAIPromptSubmissionWideEventData.InputMode,
                           fireMode: Bool,
                           isFirstPrompt: Bool,
                           frontendDeliveryPath: DuckAIPromptSubmissionWideEventData.FrontendDeliveryPath,
                           hasPageContext: Bool,
                           toolsSelected: Bool,
                           attachmentsSelected: Bool)

    /// Native attempted to hand the prompt to the frontend. Records whether
    /// contextual delivery was queued and whether a user-script bridge message was sent.
    func promptDeliveryUpdated(wasQueued: Bool?, didSendBridgeMessage: Bool?)

    /// The Duck.ai frontend reported its prompt-submitted metric for the active flow.
    func frontendSubmissionAcknowledged()

    /// The Duck.ai chat status published a new value. The instrumentation
    /// completes the active flow as SUCCESS the first time `.ready` is observed
    /// after at least one non-`.ready` value during the flow's lifetime. A page-
    /// reported `.error` or `.blocked` status completes the flow as FAILURE.
    func chatStatusChanged(_ status: AIChatStatusValue)

    /// User tapped the stop-generating button. Completes the active flow as
    /// CANCELLED with `cancellation_reason = stop_button`. After this, any
    /// subsequent `.ready` status is ignored.
    func stopGeneratingTapped()

    /// User closed a Duck.ai tab while a response was still in flight.
    /// Completes the active flow as CANCELLED with
    /// `cancellation_reason = tab_closed`. No-op if no flow is active.
    func tabClosedDuringGeneration()

    /// The contextual chat sheet was explicitly dismissed (user tapped
    /// delete-chat, or the fire-button workflow cleared it) while a response
    /// was still in flight. Completes the active flow as CANCELLED with
    /// `cancellation_reason = sheet_dismissed`. No-op if no flow is active.
    func sheetDismissedDuringGeneration()

    /// The Duck.ai webview's navigation failed (e.g. network error, DNS
    /// failure). If a submission is in flight, completes the active flow as
    /// FAILURE with `failing_step = navigation_failed` and attaches the
    /// `NSError` domain/code to the event's error data. No-op if no flow is in
    /// flight.
    func pageLoadFailed(error: Error)
}

final class DefaultDuckAIWideEventInstrumentation: DuckAIWideEventInstrumentation {

    private let wideEvent: WideEventManaging
    private let dateProvider: () -> Date
    private var activeFlow: DuckAIPromptSubmissionWideEventData?
    private var hasObservedNonReady = false

    init(wideEvent: WideEventManaging,
         completeOrphanedFlowsOnInit: Bool = false,
         dateProvider: @escaping () -> Date = { Date() }) {
        self.wideEvent = wideEvent
        self.dateProvider = dateProvider

        if completeOrphanedFlowsOnInit {
            completeOrphanedFlowsFromPreviousAppSession()
        }
    }

    func submissionStarted(modelId: String?,
                           userTier: AIChatUserTier,
                           reasoningEffort: AIChatReasoningEffort?,
                           entryPoint: DuckAIPromptSubmissionWideEventData.EntryPoint,
                           inputMode: DuckAIPromptSubmissionWideEventData.InputMode,
                           fireMode: Bool,
                           isFirstPrompt: Bool,
                           frontendDeliveryPath: DuckAIPromptSubmissionWideEventData.FrontendDeliveryPath,
                           hasPageContext: Bool,
                           toolsSelected: Bool,
                           attachmentsSelected: Bool) {
        if let activeFlow {
            wideEvent.discardFlow(activeFlow)
            self.activeFlow = nil
        }

        let data = DuckAIPromptSubmissionWideEventData(
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
        activeFlow = data
        hasObservedNonReady = false
        data.lastStep = .submitted
        wideEvent.startFlow(data)
    }

    func promptDeliveryUpdated(wasQueued: Bool?, didSendBridgeMessage: Bool?) {
        guard let activeFlow else { return }

        if let wasQueued {
            activeFlow.frontendDeliveryQueued = wasQueued
        }

        if let didSendBridgeMessage {
            activeFlow.didSendBridgeMessage = didSendBridgeMessage
        }

        wideEvent.updateFlow(activeFlow)
    }

    func frontendSubmissionAcknowledged() {
        guard let activeFlow,
              activeFlow.frontendSubmissionAckInterval.end == nil else { return }

        activeFlow.frontendSubmissionAckInterval.end = dateProvider()
        wideEvent.updateFlow(activeFlow)
    }

    func chatStatusChanged(_ status: AIChatStatusValue) {
        guard let activeFlow else { return }

        if status == .ready {
            guard hasObservedNonReady else { return }
            let now = dateProvider()
            activeFlow.generatingCompletedInterval.end = now
            activeFlow.endedInterval.end = now
            // SUCCESS doesn't carry last_step.
            activeFlow.lastStep = nil
            wideEvent.completeFlow(activeFlow, status: .success(), onComplete: { _, _ in })
            self.activeFlow = nil
            return
        }

        // Map every non-`ready` status to a journey step so UNKNOWN orphans
        // (recovered from storage on next launch) report where the flow was
        // when the app died.
        activeFlow.lastStep = Self.lastStep(for: status)

        let now = dateProvider()
        if activeFlow.startThinkingInterval.end == nil {
            activeFlow.startThinkingInterval.end = now
        }

        if status == .error || status == .blocked {
            activeFlow.endedInterval.end = now
            wideEvent.completeFlow(activeFlow, status: .failure, onComplete: { _, _ in })
            self.activeFlow = nil
            return
        }

        hasObservedNonReady = true
        if status == .streaming, activeFlow.startGeneratingInterval.end == nil {
            activeFlow.startGeneratingInterval.end = now
        }
        // Persist the new step + intervals so orphan recovery sees the
        // latest progression after an app kill.
        wideEvent.updateFlow(activeFlow)
    }

    private static func lastStep(for status: AIChatStatusValue) -> DuckAIPromptSubmissionWideEventData.LastStep {
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

    func stopGeneratingTapped() {
        guard let activeFlow else { return }
        activeFlow.cancellationReason = .stopButton
        activeFlow.endedInterval.end = dateProvider()
        wideEvent.completeFlow(activeFlow, status: .cancelled, onComplete: { _, _ in })
        self.activeFlow = nil
    }

    func tabClosedDuringGeneration() {
        guard let activeFlow else { return }
        activeFlow.cancellationReason = .tabClosed
        activeFlow.endedInterval.end = dateProvider()
        wideEvent.completeFlow(activeFlow, status: .cancelled, onComplete: { _, _ in })
        self.activeFlow = nil
    }

    func sheetDismissedDuringGeneration() {
        guard let activeFlow else { return }
        activeFlow.cancellationReason = .sheetDismissed
        activeFlow.endedInterval.end = dateProvider()
        wideEvent.completeFlow(activeFlow, status: .cancelled, onComplete: { _, _ in })
        self.activeFlow = nil
    }

    func pageLoadFailed(error: Error) {
        guard let activeFlow else { return }
        activeFlow.lastStep = .navigationFailed
        activeFlow.errorData = WideEventErrorData(error: error)
        activeFlow.endedInterval.end = dateProvider()
        wideEvent.completeFlow(activeFlow, status: .failure, onComplete: { _, _ in })
        self.activeFlow = nil
    }

    // MARK: - Helpers

    private func completeOrphanedFlowsFromPreviousAppSession() {
        for orphan in wideEvent.getAllFlowData(DuckAIPromptSubmissionWideEventData.self) {
            wideEvent.completeFlow(
                orphan,
                status: .unknown(reason: DuckAIPromptSubmissionWideEventData.appTerminatedReason),
                onComplete: { _, _ in })
        }
    }
}
