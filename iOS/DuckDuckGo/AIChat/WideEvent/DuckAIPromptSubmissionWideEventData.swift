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
    /// Set on FAILURE to identify which phase of the journey broke. Mirrors
    /// the `failing_step` taxonomy in the journey design doc.
    var failingStep: FailingStep?
    /// Whether an `AIChatUserScript` was bound to the input coordinator at
    /// submit time. Unbound means the prompt was forwarded via the delegate
    /// fallback rather than directly into a live chat session.
    var userScriptBound: Bool
    /// Whether a page-context attachment was present at submit time.
    var hasPageContext: Bool

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
         userScriptBound: Bool,
         hasPageContext: Bool,
         startedAt: Date = Date(),
         contextData: WideEventContextData = WideEventContextData(),
         appData: WideEventAppData = WideEventAppData(),
         globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.modelId = modelId
        self.userTier = userTier
        self.userScriptBound = userScriptBound
        self.hasPageContext = hasPageContext
        self.startThinkingInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.startGeneratingInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.completeInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }

    enum FailingStep: String, Codable {
        case responseStateError = "response_state_error"
        case responseStateBlocked = "response_state_blocked"
        case navigationFailed = "navigation_failed"
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
            (WideEventParameter.DuckAIPromptSubmissionFeature.failingStep, failingStep?.rawValue),
            (WideEventParameter.DuckAIPromptSubmissionFeature.startThinkingMs, startThinkingInterval.intValue(.noBucketing)),
            (WideEventParameter.DuckAIPromptSubmissionFeature.startGeneratingMs, startGeneratingInterval.intValue(.noBucketing)),
            (WideEventParameter.DuckAIPromptSubmissionFeature.completeMs, completeInterval.intValue(.noBucketing)),
        ])
        parameters[WideEventParameter.DuckAIPromptSubmissionFeature.userScriptBound] = userScriptBound
        parameters[WideEventParameter.DuckAIPromptSubmissionFeature.hasPageContext] = hasPageContext
        return parameters
    }
}

extension WideEventParameter {

    enum DuckAIPromptSubmissionFeature {
        static let modelId = "feature.data.ext.model_id"
        static let userTier = "feature.data.ext.user_tier"
        static let failingStep = "feature.data.ext.failing_step"
        static let userScriptBound = "feature.data.ext.user_script_bound"
        static let hasPageContext = "feature.data.ext.has_page_context"
        static let startThinkingMs = "feature.data.ext.latency.start_thinking_ms"
        static let startGeneratingMs = "feature.data.ext.latency.start_generating_ms"
        static let completeMs = "feature.data.ext.latency.complete_ms"
    }
}
