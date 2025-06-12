//
//  Suggestion.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

public enum Suggestion: Equatable {

    case phrase(phrase: String)
    case website(url: URL)
    case bookmark(title: String, url: URL, isFavorite: Bool, score: Int)
    case historyEntry(title: String?, url: URL, score: Int)
    case internalPage(title: String, url: URL, score: Int)
    case openTab(title: String, url: URL, tabId: String?, score: Int)
    case unknown(value: String)

    public var url: URL? {
        switch self {
        case .website(url: let url),
             .historyEntry(title: _, url: let url, _),
             .bookmark(title: _, url: let url, isFavorite: _, _),
             .internalPage(title: _, url: let url, _),
             .openTab(title: _, url: let url, _, _):
            return url
        case .phrase, .unknown:
            return nil
        }
    }

    var title: String? {
        switch self {
        case .historyEntry(title: let title, url: _, _):
            return title
        case .bookmark(title: let title, url: _, isFavorite: _, _),
             .internalPage(title: let title, url: _, _),
             .openTab(title: let title, url: _, _, _):
            return title
        case .phrase, .website, .unknown:
            return nil
        }
    }

    public var isHistoryEntry: Bool {
        if case .historyEntry = self {
            return true
        }
        return false
    }
}

// MARK: - Codable

extension Suggestion: Codable {

    private enum CodingKeys: String, CodingKey {
        case kind
        case phrase
        case url
        case title
        case isFavorite
        case score
        case tabId
        case value
    }

    private enum Kind: String, Codable {
        case phrase
        case website
        case bookmark
        case historyEntry
        case internalPage
        case openTab
        case unknown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .phrase:
            let phrase = try container.decode(String.self, forKey: .phrase)
            self = .phrase(phrase: phrase)

        case .website:
            let url = try container.decode(URL.self, forKey: .url)
            self = .website(url: url)

        case .bookmark:
            let title = try container.decode(String.self, forKey: .title)
            let url = try container.decode(URL.self, forKey: .url)
            let isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
            let score = try container.decode(Int.self, forKey: .score)
            self = .bookmark(title: title, url: url, isFavorite: isFavorite, score: score)

        case .historyEntry:
            let title = try container.decodeIfPresent(String.self, forKey: .title)
            let url = try container.decode(URL.self, forKey: .url)
            let score = try container.decode(Int.self, forKey: .score)
            self = .historyEntry(title: title, url: url, score: score)

        case .internalPage:
            let title = try container.decode(String.self, forKey: .title)
            let url = try container.decode(URL.self, forKey: .url)
            let score = try container.decode(Int.self, forKey: .score)
            self = .internalPage(title: title, url: url, score: score)

        case .openTab:
            let title = try container.decode(String.self, forKey: .title)
            let url = try container.decode(URL.self, forKey: .url)
            let tabId = try container.decodeIfPresent(String.self, forKey: .tabId)
            let score = try container.decode(Int.self, forKey: .score)
            self = .openTab(title: title, url: url, tabId: tabId, score: score)

        case .unknown:
            let value = try container.decode(String.self, forKey: .value)
            self = .unknown(value: value)
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

        case .openTab(let title, let url, let tabId, let score):
            try container.encode(Kind.openTab, forKey: .kind)
            try container.encode(title, forKey: .title)
            try container.encode(url, forKey: .url)
            try container.encodeIfPresent(tabId, forKey: .tabId)
            try container.encode(score, forKey: .score)

        case .unknown(let value):
            try container.encode(Kind.unknown, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }
}
