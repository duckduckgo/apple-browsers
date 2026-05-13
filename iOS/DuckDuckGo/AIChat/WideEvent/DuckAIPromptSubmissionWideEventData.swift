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

    init(modelId: String?,
         userTier: String,
         contextData: WideEventContextData = WideEventContextData(),
         appData: WideEventAppData = WideEventAppData(),
         globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.modelId = modelId
        self.userTier = userTier
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
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
        Dictionary(compacting: [
            (WideEventParameter.DuckAIPromptSubmissionFeature.modelId, modelId),
            (WideEventParameter.DuckAIPromptSubmissionFeature.userTier, userTier),
        ])
    }
}

extension WideEventParameter {

    enum DuckAIPromptSubmissionFeature {
        static let modelId = "feature.data.ext.model_id"
        static let userTier = "feature.data.ext.user_tier"
    }
}
