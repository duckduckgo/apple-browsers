//
//  DuckAIPromptSubmissionWideEventData.swift
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

/// Wide-event payload for the Duck.ai prompt submission journey.
final class DuckAIPromptSubmissionWideEventData: WideEventData {

    static let metadata = WideEventMetadata(
        pixelName: "duckai_prompt_submission",
        featureName: "duckai_prompt_submission",
        mobileMetaType: "ios-duckai-prompt-submission",
        // API requires both; only mobileMetaType is read on iOS.
        desktopMetaType: "macos-duckai-prompt-submission",
        version: "1.0.0"
    )

    var globalData: WideEventGlobalData
    var contextData: WideEventContextData
    var appData: WideEventAppData
    var errorData: WideEventErrorData?

    var modelId: String?
    var userTier: String
    /// `AIChatReasoningEffort.rawValue` selected for this submission. Nil when
    /// the selected model does not support a reasoning picker (distinguishes
    /// "no reasoning support" from the `.none` effort value).
    var reasoningEffort: String?
    /// Where the user was when they composed and submitted the prompt.
    var entryPoint: EntryPoint
    /// How the user produced the prompt text. Additional values (suggestion
    /// tap, address-bar shortcut, URL scheme, etc.) will be added as those
    /// entry paths are instrumented.
    var inputMode: InputMode
    /// Whether the submitting tab was in fire mode at submit time.
    var fireMode: Bool
    /// Where in the journey the flow was when it ended. Only surfaced on
    /// FAILURE and UNKNOWN outcomes - cleared by the instrumentation before
    /// SUCCESS / CANCELLED so the field is absent on those payloads.
    var lastStep: LastStep?
    /// Whether an `AIChatUserScript` was bound to the input coordinator at
    /// submit time. Unbound means the prompt was forwarded via the delegate
    /// fallback rather than directly into a live chat session.
    var userScriptBound: Bool
    /// Whether a page-context attachment was present at submit time.
    var hasPageContext: Bool
    /// Identifiers of the tools the user had selected at submit time, in
    /// `AIChatRAGTool.rawValue` form (e.g. `"WebSearch"`, `"GenerateImage"`).
    /// Empty when no tool was selected.
    var selectedTools: [String]
    /// Number of image attachments present at submit time.
    var imageAttachmentCount: Int
    /// Number of valid file attachments present at submit time (excludes ones
    /// rejected by `UTIAttachmentPolicy` validation).
    var fileAttachmentCount: Int
    /// Number of attachments that failed validation and were left in the
    /// composer as error rows. Non-zero suggests UX friction.
    var invalidAttachmentCount: Int

    /// Time to the first non-`.ready` status observed after submission. Marks
    /// when the page transitioned out of idle and began processing the prompt.
    var startThinkingInterval: WideEvent.MeasuredInterval
    /// Time to the first `.streaming` status (TTFT). Nil if the journey never
    /// reached a streaming state (e.g., cancelled or errored before tokens).
    var startGeneratingInterval: WideEvent.MeasuredInterval
    /// Time to the `.ready` status that completed the flow (TTLT). Nil if the
    /// flow was cancelled or orphaned before reaching ready.
    var completeInterval: WideEvent.MeasuredInterval

    init(modelId: String?,
         userTier: String,
         reasoningEffort: String?,
         entryPoint: EntryPoint,
         inputMode: InputMode,
         fireMode: Bool,
         userScriptBound: Bool,
         hasPageContext: Bool,
         selectedTools: [String],
         imageAttachmentCount: Int,
         fileAttachmentCount: Int,
         invalidAttachmentCount: Int,
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
        self.userScriptBound = userScriptBound
        self.hasPageContext = hasPageContext
        self.selectedTools = selectedTools
        self.imageAttachmentCount = imageAttachmentCount
        self.fileAttachmentCount = fileAttachmentCount
        self.invalidAttachmentCount = invalidAttachmentCount
        self.startThinkingInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.startGeneratingInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.completeInterval = WideEvent.MeasuredInterval(start: startedAt)
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

    enum InputMode: String, Codable {
        /// User typed (or pasted) the prompt into the composer.
        case typed
        /// User dictated the prompt via voice search and the transcription
        /// was submitted directly without a typed edit step.
        case voice
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

extension DuckAIPromptSubmissionWideEventData {

    func jsonParameters() -> [String: Encodable] {
        var parameters: [String: Encodable] = Dictionary(compacting: [
            (WideEventParameter.DuckAIPromptSubmissionFeature.modelId, modelId),
            (WideEventParameter.DuckAIPromptSubmissionFeature.userTier, userTier),
            (WideEventParameter.DuckAIPromptSubmissionFeature.reasoningEffort, reasoningEffort),
            (WideEventParameter.DuckAIPromptSubmissionFeature.entryPoint, entryPoint.rawValue),
            (WideEventParameter.DuckAIPromptSubmissionFeature.inputMode, inputMode.rawValue),
            (WideEventParameter.DuckAIPromptSubmissionFeature.lastStep, lastStep?.rawValue),
            (WideEventParameter.DuckAIPromptSubmissionFeature.startThinkingMs, startThinkingInterval.intValue(.noBucketing)),
            (WideEventParameter.DuckAIPromptSubmissionFeature.startGeneratingMs, startGeneratingInterval.intValue(.noBucketing)),
            (WideEventParameter.DuckAIPromptSubmissionFeature.completeMs, completeInterval.intValue(.noBucketing)),
        ])
        parameters[WideEventParameter.DuckAIPromptSubmissionFeature.fireMode] = fireMode
        parameters[WideEventParameter.DuckAIPromptSubmissionFeature.userScriptBound] = userScriptBound
        parameters[WideEventParameter.DuckAIPromptSubmissionFeature.hasPageContext] = hasPageContext
        parameters[WideEventParameter.DuckAIPromptSubmissionFeature.selectedTools] = selectedTools
        parameters[WideEventParameter.DuckAIPromptSubmissionFeature.imageAttachmentCount] = imageAttachmentCount
        parameters[WideEventParameter.DuckAIPromptSubmissionFeature.fileAttachmentCount] = fileAttachmentCount
        parameters[WideEventParameter.DuckAIPromptSubmissionFeature.invalidAttachmentCount] = invalidAttachmentCount
        return parameters
    }
}

extension WideEventParameter {

    enum DuckAIPromptSubmissionFeature {
        static let modelId = "feature.data.ext.model_id"
        static let userTier = "feature.data.ext.user_tier"
        static let reasoningEffort = "feature.data.ext.reasoning_effort"
        static let entryPoint = "feature.data.ext.entry_point"
        static let inputMode = "feature.data.ext.input_mode"
        static let fireMode = "feature.data.ext.fire_mode"
        static let lastStep = "feature.data.ext.last_step"
        static let userScriptBound = "feature.data.ext.user_script_bound"
        static let hasPageContext = "feature.data.ext.has_page_context"
        static let selectedTools = "feature.data.ext.selected_tools"
        static let imageAttachmentCount = "feature.data.ext.attachments.image_count"
        static let fileAttachmentCount = "feature.data.ext.attachments.file_count"
        static let invalidAttachmentCount = "feature.data.ext.attachments.invalid_count"
        static let startThinkingMs = "feature.data.ext.latency.start_thinking_ms"
        static let startGeneratingMs = "feature.data.ext.latency.start_generating_ms"
        static let completeMs = "feature.data.ext.latency.complete_ms"
    }
}
