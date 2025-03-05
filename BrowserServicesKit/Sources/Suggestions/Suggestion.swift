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

    /// The score of this suggestion, if available
    var score: Int {
        switch self {
        case .bookmark(_, _, _, let score),
             .historyEntry(_, _, let score),
             .internalPage(_, _, let score),
             .openTab(_, _, _, let score):
            return score
        case .phrase, .website, .unknown:
            return 0
        }
    }

    /// Returns a new suggestion with the updated score
    func withScore(_ newScore: Int) -> Suggestion {
        switch self {
        case .bookmark(let title, let url, let isFavorite, _):
            return .bookmark(title: title, url: url, isFavorite: isFavorite, score: newScore)
        case .historyEntry(let title, let url, _):
            return .historyEntry(title: title, url: url, score: newScore)
        case .internalPage(let title, let url, _):
            return .internalPage(title: title, url: url, score: newScore)
        case .openTab(title: let title, url: let url, tabId: let tabId, _):
            return .openTab(title: title, url: url, tabId: tabId, score: newScore)
        case .phrase, .website, .unknown:
            return self // No score field to update
        }
    }

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

    public var isOpenTab: Bool {
        if case .openTab = self {
            return true
        }
        return false
    }

    public var isBookmark: Bool {
        if case .bookmark = self {
            return true
        }
        return false
    }

    public var isHistoryEntry: Bool {
        if case .historyEntry = self {
            return true
        }
        return false
    }
}

extension Suggestion {

    public init?(bookmark: Bookmark, score: Int) {
        guard let urlObject = URL(string: bookmark.url) else { return nil }
        self = .bookmark(title: bookmark.title, url: urlObject, isFavorite: bookmark.isFavorite, score: score)
    }

    public init(historyEntry: HistorySuggestion, score: Int) {
        self = .historyEntry(title: historyEntry.title, url: historyEntry.url, score: score)
    }

    public init(internalPage: InternalPage, score: Int) {
        self = .internalPage(title: internalPage.title, url: internalPage.url, score: score)
    }

    public init(tab: BrowserTab, score: Int) {
        self = .openTab(title: tab.title, url: tab.url, tabId: tab.tabId, score: score)
    }

    public init(url: URL) {
        self = .website(url: url)
    }

}
