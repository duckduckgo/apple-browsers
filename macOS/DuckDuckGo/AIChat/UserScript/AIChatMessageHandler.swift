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

enum AIChatMessageType {
    case nativeConfigValues
    case nativeHandoffData
    case nativePrompt
}

protocol AIChatMessageHandling {
    func getDataForMessageType(_ type: AIChatMessageType) -> Encodable?
}

struct AIChatMessageHandler: AIChatMessageHandling {
    private let promptHandler: any AIChatConsumableDataHandling

    init(promptHandler: any AIChatConsumableDataHandling = AIChatPromptHandler.shared) {
        self.promptHandler = promptHandler
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
        AIChatNativeConfigValues.defaultValues
    }

    private func getNativeHandoffData() -> Encodable? {
        return nil
    }

    private func getAIChatNativePrompt() -> Encodable? {
        guard let prompt = promptHandler.consumeData() as? String else {
            return nil
        }

        return AIChatNativePrompt.defaultValuesWithPrompt(prompt)
    }
}
