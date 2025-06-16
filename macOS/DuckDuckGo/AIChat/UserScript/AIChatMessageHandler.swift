//
//  AIChatMessageHandler.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import UserScript

enum AIChatMessageType {
    case nativeConfigValues
    case nativeHandoffData
    case nativePrompt
}

protocol AIChatMessageHandling {
    func getDataForMessageType(_ type: AIChatMessageType) -> Encodable?

    var payloadHandler: AIChatPayloadHandler { get }
}

final class AIChatMessageHandler: AIChatMessageHandling {
    private let featureFlagger: FeatureFlagger
    private let promptHandler: any AIChatConsumableDataHandling
    public let payloadHandler: AIChatPayloadHandler

    init(featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger,
         promptHandler: any AIChatConsumableDataHandling = AIChatPromptHandler.shared,
         payloadHandler: AIChatPayloadHandler = AIChatPayloadHandler()) {
        self.featureFlagger = featureFlagger
        self.promptHandler = promptHandler
        self.payloadHandler = payloadHandler
    }

    func getDataForMessageType(_ type: AIChatMessageType) -> Encodable? {
        switch type {
        case .nativeConfigValues:
            return getNativeConfigValues()
        case .nativeHandoffData:
            return getNativeHandoffData()
        case .nativePrompt:
            return getAIChatNativePrompt()
        }
    }
}

// MARK: - Messages
extension AIChatMessageHandler {
    private func getNativeConfigValues() -> Encodable? {
        if featureFlagger.isFeatureOn(.aiChatSidebar) {
            return AIChatNativeConfigValues(isAIChatHandoffEnabled: true,
                                            supportsClosingAIChat: true,
                                            supportsOpeningSettings: true,
                                            supportsNativePrompt: true,
                                            supportsNativeChatInput: false)
        } else {
            return AIChatNativeConfigValues.defaultValues
        }
    }

    private func getNativeHandoffData() -> Encodable? {
        guard let payload = payloadHandler.consumeData() else { return nil }
        return AIChatNativeHandoffData.defaultValuesWithPayload(payload)
    }

    private func getAIChatNativePrompt() -> Encodable? {
        guard let prompt = promptHandler.consumeData() as? AIChatNativePrompt else {
            return nil
        }

        return prompt
    }
}
