//
//  DuckAIPromptFlowStart.swift
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

import AIChat
import Foundation

/// Submit-time values for an `ios-duckai-prompt` flow started outside Unified Input, captured before the
/// receiving tab is known.
struct DuckAIPromptFlowStart {
    var modelId: String?
    var reasoningEffort: AIChatReasoningEffort?
    var userTier: AIChatUserTier
    var toolsSelected = false
    var attachmentsSelected = false
}

extension DuckAIPromptFlowStart {

    init(controlValues: IPadDuckAIControlValues, tools: [AIChatRAGTool]?) {
        let selectedTools = tools ?? controlValues.selectedTools
        self.init(modelId: controlValues.selectedModelId,
                  reasoningEffort: controlValues.selectedReasoningEffort,
                  userTier: controlValues.userTier,
                  toolsSelected: selectedTools?.isEmpty == false,
                  attachmentsSelected: controlValues.selectedImages?.isEmpty == false || controlValues.selectedFiles?.isEmpty == false)
    }
}
