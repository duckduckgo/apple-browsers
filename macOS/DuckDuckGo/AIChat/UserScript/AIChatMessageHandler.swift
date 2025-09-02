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
    case chatRestorationData
    case pageContext
}

protocol AIChatMessageHandling {
    func getDataForMessageType(_ type: AIChatMessageType) -> Encodable?
    func setData(_ data: Any?, forMessageType type: AIChatMessageType)
}

final class AIChatMessageHandler: AIChatMessageHandling {
    private let featureFlagger: FeatureFlagger
    private let promptHandler: any AIChatConsumableDataHandling
    private let payloadHandler: AIChatPayloadHandler
    private let chatRestorationDataHandler: AIChatRestorationDataHandler
    private let pageContextHandler: AIChatPageContextHandler

    init(featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger,
         promptHandler: any AIChatConsumableDataHandling = AIChatPromptHandler.shared,
         payloadHandler: AIChatPayloadHandler = AIChatPayloadHandler(),
         chatRestorationDataHandler: AIChatRestorationDataHandler = AIChatRestorationDataHandler(),
         pageContextHandler: AIChatPageContextHandler = AIChatPageContextHandler()) {
        self.featureFlagger = featureFlagger
        self.promptHandler = promptHandler
        self.payloadHandler = payloadHandler
        self.chatRestorationDataHandler = chatRestorationDataHandler
        self.pageContextHandler = pageContextHandler
    }

    func getDataForMessageType(_ type: AIChatMessageType) -> Encodable? {
        switch type {
        case .nativeConfigValues:
            return getNativeConfigValues()
        case .nativeHandoffData:
            return getNativeHandoffData()
        case .nativePrompt:
            return getAIChatNativePrompt()
        case .chatRestorationData:
            return getAIChatRestorationData()
        case .pageContext:
            return getPageContext()
        }
    }

    func setData(_ data: Any?, forMessageType type: AIChatMessageType) {
        switch type {
        case .nativeHandoffData:
            setNativeHandoffData(data as? AIChatPayload)
        case .chatRestorationData:
            setAIChatRestorationData(data as? AIChatRestorationData)
        case .pageContext:
            setPageContext(data as? AIChatPageContextData)
        default:
            break
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
                                            supportsNativeChatInput: false,
                                            supportsURLChatIDRestoration: true,
                                            supportsFullChatRestoration: true)
        } else {
            return AIChatNativeConfigValues.defaultValues
        }
    }

    private func getNativeHandoffData() -> Encodable? {
        guard let payload = payloadHandler.consumeData() else { return nil }
        return AIChatNativeHandoffData.defaultValuesWithPayload(payload)
    }

    private func setNativeHandoffData(_ payload: AIChatPayload?) {
        guard let payload else {
            payloadHandler.reset()
            return
        }

        payloadHandler.setData(payload)
    }

    private func getAIChatNativePrompt() -> Encodable? {
        guard let prompt = promptHandler.consumeData() as? AIChatNativePrompt else {
            return nil
        }

        return prompt
    }

    private func getAIChatRestorationData() -> Encodable? {
        chatRestorationDataHandler.consumeData()
    }

    private func setAIChatRestorationData(_ data: AIChatRestorationData?) {
        guard let data else {
            chatRestorationDataHandler.reset()
            return
        }

        chatRestorationDataHandler.setData(data)
    }

    private func getPageContext() -> Encodable? {
        guard let data = pageContextHandler.consumeData() else {
            return nil
        }
        return PageContextPayload(serializedPageData: data)
    }

    private func setPageContext(_ data: AIChatPageContextData?) {
        guard let data else {
            pageContextHandler.reset()
            return
        }

        pageContextHandler.setData(data)
    }
}
