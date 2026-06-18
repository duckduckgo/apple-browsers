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
import FoundationExtensions

/// Indicates whether the Duck.ai conversion pixel is being fired by a new or returning install.
///
/// `unknown` is reported on platforms/build channels that cannot determine this — e.g. macOS
/// App Store builds, which have no reliable reinstall signal — so it isn't conflated with `new`.
public enum AIChatInstallType: String, Codable {
    case new
    case returning
    case unknown
}

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
    public let supportsPageContext: Bool
    public let supportsStandaloneMigration: Bool
    public let supportsAIChatFullMode: Bool
    public let supportsAIChatContextualMode: Bool
    public let appVersion: String
    public let supportsHomePageEntryPoint: Bool
    public let supportsOpenAIChatLink: Bool
    public let supportsAIChatSync: Bool
    public let supportsMultipleContexts: Bool
    public let supportsTabPicker: Bool
    public let supportsNativeStorage: Bool
    /// `true` when the native side supplies page-type signals so the duck.ai web app can render
    /// page-tailored suggested prompts ("suggestions").
    public let supportsSuggestions: Bool
    /// `true` when the native app handles the "voice chat start failed" remediation UI
    /// (e.g. surfaces the OS microphone-disabled prompt). When this is `true` the FE
    /// must suppress its own in-page tooltip and post `voiceChatStartFailed` to native
    /// after `getUserMedia` rejects.
    public let supportsNativeVoicePermissionHandler: Bool
    /// Whether this is a new or returning (reinstall) install — `unknown` when the platform
    /// can't tell. Surfaced on the `web.conversion.duckai.prompt` pixel.
    public let installType: AIChatInstallType
    /// Bucketed age of the install (days since the ATB install date):
    /// 0 = same day, 1 = 1–7, 2 = 8–14, 3 = 15–21, 4 = 22–28, 5 = after day 28.
    public let installAge: Int

    public static var defaultValues: AIChatNativeConfigValues {
#if os(iOS)
        return AIChatNativeConfigValues(isAIChatHandoffEnabled: true,
                                        supportsClosingAIChat: true,
                                        supportsOpeningSettings: true,
                                        supportsNativePrompt: false,
                                        supportsStandaloneMigration: false,
                                        supportsNativeChatInput: false,
                                        supportsURLChatIDRestoration: true,
                                        supportsFullChatRestoration: true,
                                        supportsPageContext: false,
                                        supportsAIChatFullMode: false,
                                        supportsAIChatContextualMode: false,
                                        appVersion: "",
                                        supportsHomePageEntryPoint: true,
                                        supportsOpenAIChatLink: true,
                                        supportsAIChatSync: false,
                                        supportsMultipleContexts: false,
                                        supportsNativeStorage: false,
                                        supportsNativeVoicePermissionHandler: false)
#endif

#if os(macOS)
        return AIChatNativeConfigValues(isAIChatHandoffEnabled: false,
                                        supportsClosingAIChat: true,
                                        supportsOpeningSettings: true,
                                        supportsNativePrompt: true,
                                        supportsStandaloneMigration: false,
                                        supportsNativeChatInput: false,
                                        supportsURLChatIDRestoration: false,
                                        supportsFullChatRestoration: false,
                                        supportsPageContext: false,
                                        supportsAIChatFullMode: false,
                                        supportsAIChatContextualMode: false,
                                        appVersion: "",
                                        supportsHomePageEntryPoint: true,
                                        supportsOpenAIChatLink: true,
                                        supportsAIChatSync: false,
                                        supportsMultipleContexts: false,
                                        supportsNativeStorage: false,
                                        supportsNativeVoicePermissionHandler: true)
#endif
    }

    public init(isAIChatHandoffEnabled: Bool,
                supportsClosingAIChat: Bool,
                supportsOpeningSettings: Bool,
                supportsNativePrompt: Bool,
                supportsStandaloneMigration: Bool,
                supportsNativeChatInput: Bool,
                supportsURLChatIDRestoration: Bool,
                supportsFullChatRestoration: Bool,
                supportsPageContext: Bool,
                supportsAIChatFullMode: Bool,
                supportsAIChatContextualMode: Bool,
                appVersion: String,
                supportsHomePageEntryPoint: Bool = true,
                supportsOpenAIChatLink: Bool = true,
                supportsAIChatSync: Bool,
                supportsMultipleContexts: Bool = false,
                supportsTabPicker: Bool = false,
                supportsNativeStorage: Bool = false,
                supportsSuggestions: Bool = false,
                supportsNativeVoicePermissionHandler: Bool = false,
                installType: AIChatInstallType = .new,
                installAge: Int = 0) {
        self.isAIChatHandoffEnabled = isAIChatHandoffEnabled
        self.platform = Platform.name
        self.supportsClosingAIChat = supportsClosingAIChat
        self.supportsOpeningSettings = supportsOpeningSettings
        self.supportsNativePrompt = supportsNativePrompt
        self.supportsNativeChatInput = supportsNativeChatInput
        self.supportsURLChatIDRestoration = supportsURLChatIDRestoration
        self.supportsFullChatRestoration = supportsFullChatRestoration
        self.supportsPageContext = supportsPageContext
        self.supportsStandaloneMigration = supportsStandaloneMigration
        self.supportsAIChatFullMode = supportsAIChatFullMode
        self.supportsAIChatContextualMode = supportsAIChatContextualMode
        self.appVersion = appVersion
        self.supportsHomePageEntryPoint = supportsHomePageEntryPoint
        self.supportsOpenAIChatLink = supportsOpenAIChatLink
        self.supportsAIChatSync = supportsAIChatSync
        self.supportsMultipleContexts = supportsMultipleContexts
        self.supportsTabPicker = supportsTabPicker
        self.supportsNativeStorage = supportsNativeStorage
        self.supportsSuggestions = supportsSuggestions
        self.supportsNativeVoicePermissionHandler = supportsNativeVoicePermissionHandler
        self.installType = installType
        self.installAge = installAge
    }

    /// Buckets the days between the install date and `now` into the values expected by the
    /// `web.conversion.duckai.prompt` pixel. A `nil` install date (ATB round-trip not yet
    /// completed on a fresh install) maps to `0` (same day), as do future/negative dates.
    public static func installAgeBucket(installDate: Date?, now: Date = Date()) -> Int {
        guard let installDate else { return 0 }
        let days = Calendar.current.numberOfDaysBetween(
            Calendar.current.startOfDay(for: installDate),
            and: Calendar.current.startOfDay(for: now)) ?? 0
        switch days {
        case ..<1: return 0
        case 1...7: return 1
        case 8...14: return 2
        case 15...21: return 3
        case 22...28: return 4
        default: return 5
        }
    }
}

/// Payload form for the prompt's `pageContext` field. The duck.ai web app accepts either a
/// single `AIChatPageContextData` (the sidebar's current-page case) or an array (the
/// omnibar's multi-tab case) at the same JSON key — this enum encodes/decodes both shapes
/// without a discriminator on the wire.
///
/// Per the discriminator in the tech design: each element's `tabId` discriminates
/// tab-picker contexts (non-nil) from the current sidebar page (nil).
public enum AIChatPageContextPayload: Codable, Equatable {
    case single(AIChatPageContextData)
    case multiple([AIChatPageContextData])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Decode array first — a JSON object would fail array decoding cleanly, and we want
        // to disambiguate without relying on Swift's behavior of partially decoding objects.
        if let array = try? container.decode([AIChatPageContextData].self) {
            self = .multiple(array)
        } else {
            let single = try container.decode(AIChatPageContextData.self)
            self = .single(single)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .single(let value):
            try container.encode(value)
        case .multiple(let values):
            try container.encode(values)
        }
    }
}

public struct AIChatNativePrompt: Codable, Equatable {
    /// Mode value for image generation prompts.
    public static let imageGenerationMode = "image-generation"
    /// Mode value for voice-chat prompts. Duck.ai routes to the voice flow purely from this
    /// mode in the handoff payload — no `?mode=voice` URL parameter is required.
    public static let voiceMode = "voice-mode"

    public let platform: String
    public let tool: Tool?
    public let pageContext: AIChatPageContextPayload?

    public enum Tool: Equatable {
        case query(Query)
        case summary(TextSummary)
        case translation(Translation)

    }

    public struct NativePromptImage: Codable, Equatable {
        public let data: String
        public let format: String

        public init(data: String, format: String) {
            self.data = data
            self.format = format
        }
    }

    public struct NativePromptFile: Codable, Equatable {
        public let data: String
        public let fileName: String
        public let mimeType: String

        public init(data: String, fileName: String, mimeType: String) {
            self.data = data
            self.fileName = fileName
            self.mimeType = mimeType
        }
    }

    public struct Query: Codable, Equatable {
        public static let tool = "query"

        public let prompt: String
        public let autoSubmit: Bool
        public let toolChoice: [String]?
        public let images: [NativePromptImage]?
        public let files: [NativePromptFile]?
        public let modelId: String?
        public let mode: String?
        public let reasoningEffort: AIChatReasoningEffort?

        private enum CodingKeys: String, CodingKey {
            case prompt
            case autoSubmit
            case toolChoice
            case images
            case files
            case modelId
            case mode
            case reasoningEffort
        }

        public init(
            prompt: String,
            autoSubmit: Bool,
            toolChoice: [String]?,
            images: [NativePromptImage]?,
            files: [NativePromptFile]?,
            modelId: String?,
            mode: String?,
            reasoningEffort: AIChatReasoningEffort?
        ) {
            self.prompt = prompt
            self.autoSubmit = autoSubmit
            self.toolChoice = toolChoice
            self.images = images
            self.files = files
            self.modelId = modelId
            self.mode = mode
            self.reasoningEffort = reasoningEffort
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            prompt = try container.decode(String.self, forKey: .prompt)
            autoSubmit = try container.decode(Bool.self, forKey: .autoSubmit)
            toolChoice = try container.decodeIfPresent([String].self, forKey: .toolChoice)
            images = try container.decodeIfPresent([NativePromptImage].self, forKey: .images)
            files = try container.decodeIfPresent([NativePromptFile].self, forKey: .files)
            modelId = try container.decodeIfPresent(String.self, forKey: .modelId)
            mode = try container.decodeIfPresent(String.self, forKey: .mode)
            let rawReasoningEffort = try container.decodeIfPresent(String.self, forKey: .reasoningEffort)
            reasoningEffort = rawReasoningEffort.flatMap(AIChatReasoningEffort.init(rawValue:))
        }

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
        case pageContext
    }

    public init(platform: String, tool: Tool?, pageContext: AIChatPageContextPayload? = nil) {
        self.platform = platform
        self.tool = tool
        self.pageContext = pageContext
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

        pageContext = try container.decodeIfPresent(AIChatPageContextPayload.self, forKey: .pageContext)
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

        try container.encodeIfPresent(pageContext, forKey: .pageContext)
    }

    public static func queryPrompt(_ prompt: String, autoSubmit: Bool, toolChoice: [String]? = nil, images: [NativePromptImage]? = nil, files: [NativePromptFile]? = nil, modelId: String? = nil, pageContext: AIChatPageContextPayload? = nil, mode: String? = nil, reasoningEffort: AIChatReasoningEffort? = nil) -> AIChatNativePrompt {
        AIChatNativePrompt(platform: Platform.name, tool: .query(.init(prompt: prompt, autoSubmit: autoSubmit, toolChoice: toolChoice, images: images, files: files, modelId: modelId, mode: mode, reasoningEffort: reasoningEffort)), pageContext: pageContext)
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
