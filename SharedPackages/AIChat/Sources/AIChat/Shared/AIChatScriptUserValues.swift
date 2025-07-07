//
//  AIChatScriptUserValues.swift
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

import Foundation

public struct AIChatNativeHandoffData: Codable {
    public let isAIChatHandoffEnabled: Bool
    public let platform: String
    public let aiChatPayload: AIChatPayload?

    enum CodingKeys: String, CodingKey {
        case isAIChatHandoffEnabled
        case platform
        case aiChatPayload
    }

    init(isAIChatHandoffEnabled: Bool, platform: String, aiChatPayload: [String: Any]?) {
        self.isAIChatHandoffEnabled = isAIChatHandoffEnabled
        self.platform = platform
        self.aiChatPayload = aiChatPayload
    }

    public static func defaultValuesWithPayload(_ payload: AIChatPayload?) -> AIChatNativeHandoffData {
        AIChatNativeHandoffData(isAIChatHandoffEnabled: true,
                                platform: Platform.name,
                                aiChatPayload: payload)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isAIChatHandoffEnabled = try container.decode(Bool.self, forKey: .isAIChatHandoffEnabled)
        platform = try container.decode(String.self, forKey: .platform)

        if let aiChatPayloadData = try? container.decodeIfPresent(Data.self, forKey: .aiChatPayload) {
            aiChatPayload = try JSONSerialization.jsonObject(with: aiChatPayloadData, options: []) as? AIChatPayload
        } else {
            aiChatPayload = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isAIChatHandoffEnabled, forKey: .isAIChatHandoffEnabled)
        try container.encode(platform, forKey: .platform)

        if let aiChatPayload = aiChatPayload,
           let data = try? JSONSerialization.data(withJSONObject: aiChatPayload, options: []),
           let jsonString = String(data: data, encoding: .utf8) {
            try container.encode(jsonString, forKey: .aiChatPayload)
        } else {
            try container.encodeNil(forKey: .aiChatPayload)
        }
    }
}

public struct AIChatNativeConfigValues: Codable {
    public let isAIChatHandoffEnabled: Bool
    public let platform: String
    public let supportsClosingAIChat: Bool
    public let supportsOpeningSettings: Bool
    public let supportsNativePrompt: Bool
    public let supportsNativeChatInput: Bool
    public let supportsURLChatIDRestoration: Bool
    public let supportsFullChatRestoration: Bool

    public static var defaultValues: AIChatNativeConfigValues {
#if os(iOS)
        return AIChatNativeConfigValues(isAIChatHandoffEnabled: true,
                                        supportsClosingAIChat: true,
                                        supportsOpeningSettings: true,
                                        supportsNativePrompt: false,
                                        supportsNativeChatInput: false,
                                        supportsURLChatIDRestoration: false,
                                        supportsFullChatRestoration: false)
#endif

#if os(macOS)
        return AIChatNativeConfigValues(isAIChatHandoffEnabled: false,
                                        supportsClosingAIChat: true,
                                        supportsOpeningSettings: true,
                                        supportsNativePrompt: true,
                                        supportsNativeChatInput: false,
                                        supportsURLChatIDRestoration: false,
                                        supportsFullChatRestoration: false)
#endif
    }

    public init(isAIChatHandoffEnabled: Bool,
                supportsClosingAIChat: Bool,
                supportsOpeningSettings: Bool,
                supportsNativePrompt: Bool,
                supportsNativeChatInput: Bool,
                supportsURLChatIDRestoration: Bool,
                supportsFullChatRestoration: Bool) {
        self.isAIChatHandoffEnabled = isAIChatHandoffEnabled
        self.platform = Platform.name
        self.supportsClosingAIChat = supportsClosingAIChat
        self.supportsOpeningSettings = supportsOpeningSettings
        self.supportsNativePrompt = supportsNativePrompt
        self.supportsNativeChatInput = supportsNativeChatInput
        self.supportsURLChatIDRestoration = supportsURLChatIDRestoration
        self.supportsFullChatRestoration = supportsFullChatRestoration
    }
}

public struct AIChatNativePrompt: Codable, Equatable {
    public struct Query: Codable, Equatable {
        public let prompt: String
        public let autoSubmit: Bool
    }

    public let platform: String
    public let query: Query?

    public static func queryPrompt(_ prompt: String, autoSubmit: Bool) -> AIChatNativePrompt {
        AIChatNativePrompt(platform: Platform.name, query: .init(prompt: prompt,
                                                                 autoSubmit: autoSubmit))
    }
}

enum Platform {
#if os(iOS)
    static let name: String = "ios"
#endif

#if os(macOS)
    static let name: String = "macOS"
#endif
}
