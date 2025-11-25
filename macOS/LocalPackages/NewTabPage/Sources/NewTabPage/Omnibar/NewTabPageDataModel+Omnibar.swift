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

    struct OmnibarConfig: Codable, Equatable {
        let mode: OmnibarMode
        let enableAi: Bool
        let showAiSetting: Bool?
        let showCustomizePopover: Bool?
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

    struct SubmitChatAction: Codable, Equatable {
        let chat: String
        let target: OpenTarget
    }

}
