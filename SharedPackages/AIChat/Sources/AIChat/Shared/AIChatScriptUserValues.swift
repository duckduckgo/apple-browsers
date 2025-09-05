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
    public let platform: String
    public let tool: Tool?

    public enum Tool: Equatable {
        case query(Query)
        case summary(TextSummary)
        case translation(Translation)

    }

    public struct Query: Codable, Equatable {
        public static let tool = "query"

        public let prompt: String
        public let autoSubmit: Bool
    }

    public struct TextSummary: Codable, Equatable {
        public static let tool = "summary"

        public let text: String
        public let sourceURL: String?
        public let sourceTitle: String?
    }

    public struct Translation: Codable, Equatable {
        public static let tool = "translation"

        public let text: String
        public let sourceURL: String?
        public let sourceTitle: String?
        public let sourceTLD: String?
        public let sourceLanguage: String?
        public let targetLanguage: String

        private enum CodingKeys: String, CodingKey {
            case text, sourceURL, sourceTitle, sourceTLD, sourceLanguage, targetLanguage
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
            try container.encodeIfPresent(sourceTitle, forKey: .sourceTitle)
            if let sourceTLD {
                try container.encodeIfPresent(sourceTLD, forKey: .sourceTLD)
            } else {
                // sourceTLD requires to be passed explicitly as nil if lacks value
                try container.encodeNil(forKey: .sourceTLD)
            }
            if let sourceLanguage {
                try container.encodeIfPresent(sourceLanguage, forKey: .sourceLanguage)
            } else {
                // sourceLanguage requires to be passed explicitly as nil if lacks value
                try container.encodeNil(forKey: .sourceLanguage)
            }
            try container.encode(targetLanguage, forKey: .targetLanguage)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case platform
        case tool
        case query
        case summary
        case translation
    }

    public init(platform: String, tool: Tool?) {
        self.platform = platform
        self.tool = tool
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        platform = try container.decode(String.self, forKey: .platform)

        let toolString = try container.decodeIfPresent(String.self, forKey: .tool)

        switch toolString {
        case Query.tool:
            let query = try container.decode(Query.self, forKey: .query)
            tool = .query(query)
        case TextSummary.tool:
            let summary = try container.decode(TextSummary.self, forKey: .summary)
            tool = .summary(summary)
        case Translation.tool:
            let translation = try container.decode(Translation.self, forKey: .translation)
            tool = .translation(translation)
        default:
            tool = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(platform, forKey: .platform)

        switch tool {
        case .query(let query):
            try container.encode(Query.tool, forKey: .tool)
            try container.encode(query, forKey: .query)
        case .summary(let summary):
            try container.encode(TextSummary.tool, forKey: .tool)
            try container.encode(summary, forKey: .summary)
        case .translation(let translation):
            try container.encode(Translation.tool, forKey: .tool)
            try container.encode(translation, forKey: .translation)
        case .none:
            try container.encodeNil(forKey: .tool)
        }
    }

    public static func queryPrompt(_ prompt: String, autoSubmit: Bool) -> AIChatNativePrompt {
        AIChatNativePrompt(platform: Platform.name, tool: .query(.init(prompt: prompt, autoSubmit: autoSubmit)))
    }

    public static func summaryPrompt(_ text: String, url: URL?, title: String?) -> AIChatNativePrompt {
        AIChatNativePrompt(platform: Platform.name, tool: .summary(.init(text: text, sourceURL: url?.absoluteString, sourceTitle: title)))
    }

    public static func translationPrompt(_ text: String, url: URL?, title: String?, sourceTLD: String?, sourceLanguage: String?, targetLanguage: String) -> AIChatNativePrompt {

        let translation = AIChatNativePrompt.Tool.translation(.init(text: text,
                                                                    sourceURL: url?.absoluteString,
                                                                    sourceTitle: title,
                                                                    sourceTLD: sourceTLD,
                                                                    sourceLanguage: sourceLanguage,
                                                                    targetLanguage: targetLanguage))

        return AIChatNativePrompt(platform: Platform.name, tool: translation)
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
