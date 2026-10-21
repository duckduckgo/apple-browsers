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
    case askAIChat(value: String)

    public var url: URL? {
        switch self {
        case .website(url: let url),
             .historyEntry(title: _, url: let url, _),
             .bookmark(title: _, url: let url, isFavorite: _, _),
             .internalPage(title: _, url: let url, _),
             .openTab(title: _, url: let url, _, _):
            return url
        case .phrase, .unknown, .askAIChat:
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
        case .phrase, .website, .unknown, .askAIChat:
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
