//
//  DuckAIPromptWideEventData.swift
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
import Common
import PixelKit

final class DuckAIPromptWideEventData: WideEventData {

    static let metadata = WideEventMetadata(
        pixelName: "duckai_prompt",
        featureName: "duckai-prompt",
        mobileMetaType: "ios-duckai-prompt",
        desktopMetaType: "macos-duckai-prompt",
        version: "1.0.0"
    )

    var globalData: WideEventGlobalData
    var contextData: WideEventContextData
    var appData: WideEventAppData
    var errorData: WideEventErrorData?

    var modelId: String?
    var userTier: String
    var reasoningEffort: String?
    var entryPoint: EntryPoint
    var inputMode: InputMode
    var fireMode: Bool
    var isFirstPrompt: Bool
    var lastStep: LastStep?
    var cancellationReason: CancellationReason?
    var frontendDeliveryPath: FrontendDeliveryPath
    var frontendDeliveryQueued: Bool
    var didSendBridgeMessage: Bool?

    var hasPageContext: Bool
    var toolsSelected: Bool
    var attachmentsSelected: Bool

    /// Time to the first non-`.ready` status observed after submission. Marks
    /// when the page transitioned out of idle and began processing the prompt.
    var startThinkingInterval: WideEvent.MeasuredInterval

    /// Time to the first `.streaming` status (TTFT). Nil if the journey never
    /// reached a streaming state (e.g., cancelled or errored before tokens).
    var startGeneratingInterval: WideEvent.MeasuredInterval

    /// Time to the `.ready` status that completed the flow (TTLT). Nil if the
    /// flow was cancelled or orphaned before reaching ready.
    var generatingCompletedInterval: WideEvent.MeasuredInterval

    /// Time to the outcome, regardless of status. Provides the total observed
    /// duration for failures and cancellations where `.ready` is never reached.
    var endedInterval: WideEvent.MeasuredInterval

    /// Time to the frontend `userDidSubmitPrompt` metric after native submission.
    /// Nil if the frontend never acknowledged the prompt before the flow ended.
    var frontendSubmissionAckInterval: WideEvent.MeasuredInterval

    init(modelId: String?,
         userTier: String,
         reasoningEffort: String?,
         entryPoint: EntryPoint,
         inputMode: InputMode,
         fireMode: Bool,
         isFirstPrompt: Bool,
         frontendDeliveryPath: FrontendDeliveryPath,
         hasPageContext: Bool,
         toolsSelected: Bool,
         attachmentsSelected: Bool,
         startedAt: Date = Date(),
         contextData: WideEventContextData = WideEventContextData(),
         appData: WideEventAppData = WideEventAppData(),
         globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.modelId = modelId
        self.userTier = userTier
        self.reasoningEffort = reasoningEffort
        self.entryPoint = entryPoint
        self.inputMode = inputMode
        self.fireMode = fireMode
        self.isFirstPrompt = isFirstPrompt
        self.frontendDeliveryPath = frontendDeliveryPath
        self.frontendDeliveryQueued = false
        self.hasPageContext = hasPageContext
        self.toolsSelected = toolsSelected
        self.attachmentsSelected = attachmentsSelected
        self.startThinkingInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.startGeneratingInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.generatingCompletedInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.endedInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.frontendSubmissionAckInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }

    enum LastStep: String, Codable {
        /// Flow started; no chat status or page event observed yet.
        case submitted
        /// Page reported `loading` - response is preparing.
        case loading
        /// Page reported `start_stream:new_prompt` - a fresh stream is starting.
        case startStreamNewPrompt = "start_stream_new_prompt"
        /// Page reported `start_stream:restart_stream` - a stream is being restarted.
        case startStreamRestartStream = "start_stream_restart_stream"
        /// Page reported `streaming` - tokens are flowing.
        case streaming
        /// Page reported `unknown` - a non-`ready` status of unknown kind.
        case unknownStatus = "unknown_status"
        /// WKWebView navigation failed before the page could respond. Terminal FAILURE.
        case navigationFailed = "navigation_failed"
        /// Page reported `error` - response state failed. Terminal FAILURE.
        case responseStateError = "response_state_error"
        /// Page reported `blocked` - response was blocked. Terminal FAILURE.
        case responseStateBlocked = "response_state_blocked"
    }

    enum EntryPoint: String, Codable {
        /// User composed the prompt in the browser address bar.
        case omnibar
        /// User composed the prompt on the dedicated Duck.ai tab.
        case aiTab = "ai_tab"
        /// User composed the prompt in the contextual chat sheet that opens
        /// from a regular web tab.
        case contextualChat = "contextual_chat"
    }

    enum CancellationReason: String, Codable {
        /// User tapped the stop-generating button on the composer.
        case stopButton = "stop_button"
        /// User closed the Duck.ai tab while the response was still in flight.
        case tabClosed = "tab_closed"
        /// The contextual chat sheet's session was explicitly ended (user
        /// tapped delete-chat, or the fire-button workflow cleared it) while
        /// the response was still in flight.
        case sheetDismissed = "sheet_dismissed"
        /// User used the Fire button to clear the Duck.ai tab while the
        /// response was still in flight.
        case fireButton = "fire_button"
        /// User switched away from the Duck.ai tab while the response was
        /// still in flight, breaking the current native UI status connection.
        case switchedTabs = "switched_tabs"
        /// Another prompt submission started in the same tab or contextual
        /// sheet before this flow reached a terminal outcome.
        case supersededByNewSubmission = "superseded_by_new_submission"
    }

    enum InputMode: String, Codable {
        /// User typed (or pasted) the prompt into the composer.
        case keyboard
        /// User dictated the prompt via voice search and the transcription
        /// was submitted directly without a typed edit step.
        case voice
    }

    enum FrontendDeliveryPath: String, Codable {
        /// Native UTI pushed the prompt directly into an already-bound AIChatUserScript.
        case userScript = "user_script"
        /// Native UTI delegated to the host, which opened Duck.ai with URL autosubmit/prompt handoff.
        case urlAutoSubmit = "url_autosubmit"
        /// Contextual sheet native input handed the prompt to the contextual web view.
        case contextualNativeInput = "contextual_native_input"
    }

    /// Orphaned flows are cleaned up by `submissionStarted()` which runs
    /// synchronously before creating a new flow. This avoids a race with
    /// `WideEventService.resume()` where the cleanup task would complete a
    /// freshly created flow as UNKNOWN before any user interaction.
    func completionDecision(for trigger: WideEventCompletionTrigger) async -> WideEventCompletionDecision {
        .keepPending
    }

    static let appTerminatedReason = "app_terminated"
}

extension DuckAIPromptWideEventData {

    /// Shared bucketing for all latency milestones in this event. Each duration
    /// is rounded up to the smallest bucket that contains it. Any duration over
    /// 10s collapses into the 30000 bucket.
    static let latencyBucket: DurationBucket = .bucketed { ms in
        [100, 500, 1_000, 2_000, 3_000, 5_000, 10_000].first(where: { ms <= $0 }) ?? 30_000
    }

    func jsonParameters() -> [String: Encodable] {
        var parameters: [String: Encodable] = Dictionary(compacting: [
            (WideEventParameter.DuckAIPromptFeature.modelId, modelId),
            (WideEventParameter.DuckAIPromptFeature.userTier, userTier),
            (WideEventParameter.DuckAIPromptFeature.reasoningEffort, reasoningEffort),
            (WideEventParameter.DuckAIPromptFeature.entryPoint, entryPoint.rawValue),
            (WideEventParameter.DuckAIPromptFeature.inputMode, inputMode.rawValue),
            (WideEventParameter.DuckAIPromptFeature.lastStep, lastStep?.rawValue),
            (WideEventParameter.DuckAIPromptFeature.cancellationReason, cancellationReason?.rawValue),
            (WideEventParameter.DuckAIPromptFeature.frontendDeliveryPath, frontendDeliveryPath.rawValue),
            (WideEventParameter.DuckAIPromptFeature.didSendBridgeMessage, didSendBridgeMessage),
            (WideEventParameter.DuckAIPromptFeature.startThinkingMs, startThinkingInterval.intValue(Self.latencyBucket)),
            (WideEventParameter.DuckAIPromptFeature.startGeneratingMs, startGeneratingInterval.intValue(Self.latencyBucket)),
            (WideEventParameter.DuckAIPromptFeature.generatingCompletedMs, generatingCompletedInterval.intValue(Self.latencyBucket)),
            (WideEventParameter.DuckAIPromptFeature.endedMs, endedInterval.intValue(Self.latencyBucket)),
            (WideEventParameter.DuckAIPromptFeature.frontendSubmissionAckMs, frontendSubmissionAckInterval.intValue(Self.latencyBucket)),
        ])

        parameters[WideEventParameter.DuckAIPromptFeature.fireMode] = fireMode
        parameters[WideEventParameter.DuckAIPromptFeature.isFirstPrompt] = isFirstPrompt
        parameters[WideEventParameter.DuckAIPromptFeature.frontendDeliveryQueued] = frontendDeliveryQueued
        parameters[WideEventParameter.DuckAIPromptFeature.didReceiveBridgeMessage] = frontendSubmissionAckInterval.end != nil
        parameters[WideEventParameter.DuckAIPromptFeature.hasPageContext] = hasPageContext
        parameters[WideEventParameter.DuckAIPromptFeature.toolsSelected] = toolsSelected
        parameters[WideEventParameter.DuckAIPromptFeature.attachmentsSelected] = attachmentsSelected

        return parameters
    }
}

extension WideEventParameter {

    enum DuckAIPromptFeature {
        static let modelId = "feature.data.ext.prompt.model_id"
        static let userTier = "feature.data.ext.prompt.user_tier"
        static let reasoningEffort = "feature.data.ext.prompt.reasoning_effort"
        static let entryPoint = "feature.data.ext.prompt.entry_point"
        static let inputMode = "feature.data.ext.prompt.input_mode"
        static let fireMode = "feature.data.ext.prompt.fire_mode"
        static let isFirstPrompt = "feature.data.ext.prompt.is_first_prompt"
        static let lastStep = "feature.data.ext.outcome.last_step"
        static let cancellationReason = "feature.data.ext.outcome.cancellation_reason"
        static let frontendDeliveryPath = "feature.data.ext.delivery.path"
        static let frontendDeliveryQueued = "feature.data.ext.delivery.queued"
        static let didSendBridgeMessage = "feature.data.ext.delivery.did_send_bridge_message"
        static let didReceiveBridgeMessage = "feature.data.ext.delivery.did_receive_bridge_message"
        static let hasPageContext = "feature.data.ext.prompt.has_page_context"
        static let toolsSelected = "feature.data.ext.prompt.tools_selected"
        static let attachmentsSelected = "feature.data.ext.prompt.attachments_selected"
        static let startThinkingMs = "feature.data.ext.latency.start_thinking_ms"
        static let startGeneratingMs = "feature.data.ext.latency.start_generating_ms"
        static let generatingCompletedMs = "feature.data.ext.latency.generating_completed_ms"
        static let endedMs = "feature.data.ext.latency.ended_ms"
        static let frontendSubmissionAckMs = "feature.data.ext.latency.frontend_submission_ack_ms"
    }
}
