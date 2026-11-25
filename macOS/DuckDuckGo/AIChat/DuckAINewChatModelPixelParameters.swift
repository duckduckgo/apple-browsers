//
//  DuckAINewChatModelPixelParameters.swift
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

/// The model parameters on a new chat's first-prompt pixel. `nil` when no model is sent.
struct DuckAINewChatModelPixelParameters: Equatable {
    let source: DuckAINewChatModelSource?
    let modelId: String
    let reasoningEffort: String?

    init?(sentModelId: String?,
          sentReasoningEffort: String?,
          isModelPicked: Bool,
          pickedReasoningEffort: String?,
          newChatDefault: AIChatNewChatSelection?,
          isImageGeneration: Bool = false) {
        guard let sentModelId else { return nil }
        let sendsDefaultEffort = pickedReasoningEffort == nil || pickedReasoningEffort == newChatDefault?.reasoningEffort?.rawValue
        // Image generation picks its own model, so it reports no source.
        source = isImageGeneration ? nil : DuckAINewChatModelSource.resolve(sentModelId: sentModelId,
                                                                            sendsDefaultEffort: sendsDefaultEffort,
                                                                            isPicked: isModelPicked || pickedReasoningEffort != nil,
                                                                            newChatDefault: newChatDefault)
        modelId = sentModelId
        reasoningEffort = sentReasoningEffort
    }

    var parameters: [String: String] {
        var parameters = ["model_id": modelId]
        parameters[DuckAINewChatModelSource.pixelParameterKey] = source?.rawValue
        parameters["reasoning_effort"] = reasoningEffort
        return parameters
    }
}
