//
//  NewTabPageDataModel+Omnibar.swift
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

public extension NewTabPageDataModel {

    // https://duckduckgo.github.io/content-scope-scripts/documents/New_Tab_Page.Omnibar_Widget.html

    // MARK: - omnibar_getConfig

    enum OmnibarMode: String, Codable {
        case search, ai
    }

    struct AIModelItem: Codable, Equatable {
        public let id: String
        public let name: String
        public let shortName: String
        public let isEnabled: Bool
        public let supportsImageUpload: Bool
        public let supportedTools: [String]
        /// Reasoning effort levels the model supports (e.g. `["none", "low", "medium", "high"]`).
        /// Empty when the model does not support reasoning, or when the reasoning-effort
        /// feature is disabled natively — in which case the picker is hidden web-side.
        public let supportedReasoningEffort: [String]
        /// MIME types the model accepts as file attachments (e.g. `["application/pdf"]`). Empty
        /// when the model accepts no files; the web uses this to drive the file picker's `accept`
        /// and to clear attached files whose MIME isn't supported when the user switches models.
        public let supportedFileTypes: [String]

        public init(id: String, name: String, shortName: String, isEnabled: Bool, supportsImageUpload: Bool, supportedTools: [String] = [], supportedReasoningEffort: [String] = [], supportedFileTypes: [String] = []) {
            self.id = id
            self.name = name
            self.shortName = shortName
            self.isEnabled = isEnabled
            self.supportsImageUpload = supportsImageUpload
            self.supportedTools = supportedTools
            self.supportedReasoningEffort = supportedReasoningEffort
            self.supportedFileTypes = supportedFileTypes
        }
    }

    struct AIModelSection: Codable, Equatable {
        public let header: String?
        public let items: [AIModelItem]

        public init(header: String?, items: [AIModelItem]) {
            self.header = header
            self.items = items
        }
    }

    /// Attachment limits sourced from the Duck.ai backend (`/duckchat/v1/models`, field
    /// `attachmentLimits`), already resolved for the user's tier. Forwarded to the web so the NTP
    /// omnibar can enforce them instead of hardcoding defaults. Mirrors the resolved shape of
    /// `AIChat.AIChatAttachmentTierLimits`.
    struct AttachmentLimits: Codable, Equatable {
        public struct FileLimits: Codable, Equatable {
            let maxPerConversation: Int
            let maxFileSizeMB: Int
            let maxTotalFileSizeBytes: Int
            let maxPagesPerFile: Int

            public init(maxPerConversation: Int, maxFileSizeMB: Int, maxTotalFileSizeBytes: Int, maxPagesPerFile: Int) {
                self.maxPerConversation = maxPerConversation
                self.maxFileSizeMB = maxFileSizeMB
                self.maxTotalFileSizeBytes = maxTotalFileSizeBytes
                self.maxPagesPerFile = maxPagesPerFile
            }
        }

        public struct ImageLimits: Codable, Equatable {
            let maxPerTurn: Int
            let maxPerConversation: Int
            let maxInputCharsWithAttachments: Int

            public init(maxPerTurn: Int, maxPerConversation: Int, maxInputCharsWithAttachments: Int) {
                self.maxPerTurn = maxPerTurn
                self.maxPerConversation = maxPerConversation
                self.maxInputCharsWithAttachments = maxInputCharsWithAttachments
            }
        }

        let files: FileLimits
        let images: ImageLimits

        public init(files: FileLimits, images: ImageLimits) {
            self.files = files
            self.images = images
        }
    }

    struct OmnibarConfig: Codable, Equatable {
        let mode: OmnibarMode
        let enableAi: Bool
        let showAiSetting: Bool?
        let showCustomizePopover: Bool?
        let enableRecentAiChats: Bool?
        let showViewAllAiChats: Bool?
        let enableAiChatTools: Bool?
        let enableImageGeneration: Bool?
        let enableWebSearch: Bool?
        /// When true, the omnibar shows a 1-click voice-chat button. Driven by the native
        /// `aiChatOmnibarVoiceChatAccess` feature flag and reactive over `omnibar_onConfigUpdate`
        /// so the affordance appears/disappears without a page reload when the flag flips.
        let enableVoiceChatAccess: Bool?
        /// When false, the omnibar must not render the inline "Ask Duck.ai: <query>" entry in
        /// the suggestions dropdown. Native sets this to the value of the user's "Autocomplete
        /// suggestions" preference so the dropdown matches the address bar (which hides the
        /// equivalent `.askAIChat` entry when the preference is off). Reactive over
        /// `omnibar_onConfigUpdate`. `nil` means "treat as true" for back-compat with web
        /// clients that don't know about this field yet.
        let enableAskAiSuggestion: Bool?
        let selectedModelId: String?
        let aiModelSections: [AIModelSection]?
        /// The user's persisted reasoning effort (e.g. `"none"`, `"low"`, `"medium"`). `nil` when
        /// nothing is selected or when the reasoning-effort feature is disabled natively.
        let selectedReasoningEffort: String?
        /// When true, the omnibar shows the paperclip entry point and accepts `@` mentions for
        /// attaching open tabs (and files) as context to a Duck.ai submission. Driven by the
        /// `aiChatNtpAttachMoreTabs` feature flag and reactive over `omnibar_onConfigUpdate`.
        /// `nil`/false means the affordances stay hidden and existing flows are unchanged.
        let enableAttachTabs: Bool?
        /// Backend-provided attachment limits, already tier-resolved. `nil` on older native builds
        /// or when the backend omits them, in which case the web falls back to its built-in defaults.
        /// The `= nil` default makes this a trailing optional parameter of the synthesized memberwise
        /// initializer, so the existing `OmnibarConfig(...)` call sites (and tests) compile unchanged.
        var attachmentLimits: AttachmentLimits? = nil
    }

    // MARK: - omnibar_getSuggestions

    struct OmnibarGetSuggestionsRequest: Codable, Equatable {
        let term: String
    }

    struct SuggestionsData: Codable, Equatable {
        let suggestions: Suggestions
    }

    struct Suggestions: Codable, Equatable {
        let topHits: [Suggestion]
        let duckduckgoSuggestions: [Suggestion]
        let localSuggestions: [Suggestion]

        public init(topHits: [Suggestion], duckduckgoSuggestions: [Suggestion], localSuggestions: [Suggestion]) {
            self.topHits = topHits
            self.duckduckgoSuggestions = duckduckgoSuggestions
            self.localSuggestions = localSuggestions
        }

        public static let empty = Self(topHits: [], duckduckgoSuggestions: [], localSuggestions: [])
    }

    enum Suggestion: Codable, Equatable {
        case phrase(phrase: String)
        case website(url: String)
        case bookmark(title: String, url: String, isFavorite: Bool, score: Int)
        case historyEntry(title: String?, url: String, score: Int)
        case internalPage(title: String, url: String, score: Int)
        case openTab(title: String, tabId: String?, score: Int)

        private enum CodingKeys: String, CodingKey {
            case kind
            case phrase
            case url
            case title
            case isFavorite
            case score
            case tabId
        }

        private enum Kind: String, Codable {
            case phrase
            case website
            case bookmark
            case historyEntry
            case internalPage
            case openTab
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(Kind.self, forKey: .kind)

            switch kind {
            case .phrase:
                let phrase = try container.decode(String.self, forKey: .phrase)
                self = .phrase(phrase: phrase)

            case .website:
                let url = try container.decode(String.self, forKey: .url)
                self = .website(url: url)

            case .bookmark:
                let title = try container.decode(String.self, forKey: .title)
                let url = try container.decode(String.self, forKey: .url)
                let isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
                let score = try container.decode(Int.self, forKey: .score)
                self = .bookmark(title: title, url: url, isFavorite: isFavorite, score: score)

            case .historyEntry:
                let title = try container.decodeIfPresent(String.self, forKey: .title)
                let url = try container.decode(String.self, forKey: .url)
                let score = try container.decode(Int.self, forKey: .score)
                self = .historyEntry(title: title, url: url, score: score)

            case .internalPage:
                let title = try container.decode(String.self, forKey: .title)
                let url = try container.decode(String.self, forKey: .url)
                let score = try container.decode(Int.self, forKey: .score)
                self = .internalPage(title: title, url: url, score: score)

            case .openTab:
                let title = try container.decode(String.self, forKey: .title)
                let tabId = try container.decodeIfPresent(String.self, forKey: .tabId)
                let score = try container.decode(Int.self, forKey: .score)
                self = .openTab(title: title, tabId: tabId, score: score)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case .phrase(let phrase):
                try container.encode(Kind.phrase, forKey: .kind)
                try container.encode(phrase, forKey: .phrase)

            case .website(let url):
                try container.encode(Kind.website, forKey: .kind)
                try container.encode(url, forKey: .url)

            case .bookmark(let title, let url, let isFavorite, let score):
                try container.encode(Kind.bookmark, forKey: .kind)
                try container.encode(title, forKey: .title)
                try container.encode(url, forKey: .url)
                try container.encode(isFavorite, forKey: .isFavorite)
                try container.encode(score, forKey: .score)

            case .historyEntry(let title, let url, let score):
                try container.encode(Kind.historyEntry, forKey: .kind)
                try container.encodeIfPresent(title, forKey: .title)
                try container.encode(url, forKey: .url)
                try container.encode(score, forKey: .score)

            case .internalPage(let title, let url, let score):
                try container.encode(Kind.internalPage, forKey: .kind)
                try container.encode(title, forKey: .title)
                try container.encode(url, forKey: .url)
                try container.encode(score, forKey: .score)

            case .openTab(let title, let tabId, let score):
                try container.encode(Kind.openTab, forKey: .kind)
                try container.encode(title, forKey: .title)
                try container.encodeIfPresent(tabId, forKey: .tabId)
                try container.encode(score, forKey: .score)
            }
        }
    }

    // MARK: - omnibar_submitSearch

    struct SubmitSearchAction: Codable, Equatable {
        let target: OpenTarget
        let term: String
    }

    // MARK: - omnibar_openSuggestion

    struct OpenSuggestionAction: Codable, Equatable {
        let suggestion: Suggestion
        let target: OpenTarget
    }

    struct OmnibarOpenSuggestionNotification: Codable, Equatable {
        let method: String // should always be "omnibar_openSuggestion"
        let params: OpenSuggestionAction
    }

    // MARK: - omnibar_submitChat

    struct SubmitChatImage: Codable, Equatable {
        public let data: String
        public let format: String
    }

    struct SubmitChatAction: Codable, Equatable {
        let chat: String
        let target: OpenTarget
        let modelId: String?
        let images: [SubmitChatImage]?
        let mode: String?
        let toolChoice: [String]?
        /// Reasoning effort to attach to this submission. Ignored natively when the reasoning-effort
        /// feature is disabled or when the value isn't supported by the submission's model.
        let reasoningEffort: String?
        /// Page contexts attached from open tabs via the attach-tabs picker. Each entry is the
        /// same shape returned by `omnibar_getTabContent` and carries a `tabId`. Omitted when no
        /// tabs are attached so existing handlers continue to work unchanged.
        let pageContext: [OmnibarPageContext]?
        /// Files (PDFs in v1) attached via the paperclip menu. Omitted when none are attached.
        let files: [OmnibarPromptFile]?
    }

    // MARK: - omnibar_getOpenTabs / omnibar_getTabContent (attach tabs)

    /// Favicon for an attached tab. Matches the NewTab `favicon.json` shape. Native populates
    /// `src` with a base64 PNG data URL so the favicon survives the round-trip back on submit
    /// and renders without CSP issues when forwarded to the Duck.ai tab.
    struct OmnibarTabFavicon: Codable, Equatable {
        public let src: String
        public let maxAvailableSize: Int?

        public init(src: String, maxAvailableSize: Int? = nil) {
            self.src = src
            self.maxAvailableSize = maxAvailableSize
        }
    }

    /// Metadata for an open tab, returned by `omnibar_getOpenTabs`.
    struct OmnibarTabMetadata: Codable, Equatable {
        public let tabId: String
        public let title: String
        public let url: String
        public let favicon: OmnibarTabFavicon?

        public init(tabId: String, title: String, url: String, favicon: OmnibarTabFavicon?) {
            self.tabId = tabId
            self.title = title
            self.url = url
            self.favicon = favicon
        }
    }

    /// Extracted page content for a specific tab, returned by `omnibar_getTabContent` and echoed
    /// back on `omnibar_submitChat`.
    struct OmnibarPageContext: Codable, Equatable {
        public let tabId: String?
        public let title: String
        public let url: String
        public let favicon: OmnibarTabFavicon?
        public let content: String?
        public let truncated: Bool?
        public let fullContentLength: Int?

        public init(tabId: String?, title: String, url: String, favicon: OmnibarTabFavicon?, content: String?, truncated: Bool?, fullContentLength: Int?) {
            self.tabId = tabId
            self.title = title
            self.url = url
            self.favicon = favicon
            self.content = content
            self.truncated = truncated
            self.fullContentLength = fullContentLength
        }
    }

    /// A file attached to a Duck.ai prompt (PDFs in v1). Shape mirrors Duck.ai's `NativePromptFile`.
    struct OmnibarPromptFile: Codable, Equatable {
        public let data: String
        public let fileName: String
        public let mimeType: String

        public init(data: String, fileName: String, mimeType: String) {
            self.data = data
            self.fileName = fileName
            self.mimeType = mimeType
        }
    }

    struct OmnibarGetOpenTabsResponse: Codable, Equatable {
        let tabs: [OmnibarTabMetadata]

        public init(tabs: [OmnibarTabMetadata]) {
            self.tabs = tabs
        }
    }

    struct OmnibarGetTabContentRequest: Codable, Equatable {
        let tabId: String
    }

    struct OmnibarGetTabContentResponse: Codable, Equatable {
        let pageContext: OmnibarPageContext?

        public init(pageContext: OmnibarPageContext?) {
            self.pageContext = pageContext
        }
    }

    // MARK: - omnibar_openAiChat

    enum OpenAiChatTrigger: String, Codable {
        case mouse
        case keyboard
    }

    struct OpenAiChatAction: Codable, Equatable {
        let chatId: String
        let target: OpenTarget
        let trigger: OpenAiChatTrigger?
        let isPinned: Bool?
    }

    // MARK: - omnibar_viewAllAIChats

    struct ViewAllAiChatsAction: Codable, Equatable {
        let target: OpenTarget
    }

    // MARK: - omnibar_getAiChats

    struct OmnibarGetAiChatsRequest: Codable, Equatable {
        let query: String?
    }

    struct AiChat: Codable, Equatable {
        let chatId: String
        let title: String
        let pinned: Bool?
        let lastEdit: String?
        let firstUserMessageContent: String?
        let model: String?

        public init(chatId: String, title: String, pinned: Bool? = nil, lastEdit: String? = nil, firstUserMessageContent: String? = nil, model: String? = nil) {
            self.chatId = chatId
            self.title = title
            self.pinned = pinned
            self.lastEdit = lastEdit
            self.firstUserMessageContent = firstUserMessageContent
            self.model = model
        }
    }

    struct AiChatsData: Codable, Equatable {
        let chats: [AiChat]

        public init(chats: [AiChat]) {
            self.chats = chats
        }

        public static let empty = Self(chats: [])
    }

}
