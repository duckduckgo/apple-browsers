//
//  LocalAIRequest.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

public enum LocalAITask: String, Codable, CaseIterable, Sendable {
    case summarize
    case translate
}

public enum LocalAITarget: String, Codable, CaseIterable, Sendable {
    case page
    case selection
}

/// The contextual-sheet suggestions a local model may answer. Any other suggestion id goes to Duck.ai.
public enum LocalAISuggestion: String, CaseIterable, Sendable {
    case summarizePage = "summarize-page"
    case translatePage = "translate-page"
    case summarizeSelection = "summarize-selection"
    case translateSelection = "translate-selection"

    public var task: LocalAITask {
        switch self {
        case .summarizePage, .summarizeSelection: .summarize
        case .translatePage, .translateSelection: .translate
        }
    }

    public var target: LocalAITarget {
        switch self {
        case .summarizePage, .translatePage: .page
        case .summarizeSelection, .translateSelection: .selection
        }
    }
}

public struct LocalAIPage: Equatable, Codable, Sendable {
    public let title: String
    public let url: String
    public let content: String

    public init(title: String, url: String, content: String) {
        self.title = title
        self.url = url
        self.content = content
    }
}

public enum LocalAISource: Equatable, Codable, Sendable {
    case page(LocalAIPage)
    case selection([String])

    public var characterCount: Int {
        switch self {
        case .page(let page): page.content.count
        case .selection(let texts): texts.reduce(0) { $0 + $1.count }
        }
    }
}

public struct LocalAIRequest: Equatable, Codable, Sendable {
    public let task: LocalAITask
    public let source: LocalAISource
    /// English name of the user's language: the translation target, and the language summaries are written in.
    public let language: String

    public init(task: LocalAITask, source: LocalAISource, language: String) {
        self.task = task
        self.source = source
        self.language = language
    }

    /// Builds a request for a suggestion, or `nil` when the suggestion isn't one a local model answers
    /// or its context is missing, in which case the caller sends it to Duck.ai as usual.
    public init?(suggestionID: String, language: String, page: LocalAIPage?, selections: [String]) {
        guard let suggestion = LocalAISuggestion(rawValue: suggestionID) else { return nil }
        let source: LocalAISource
        switch suggestion.target {
        case .page:
            guard let page, !page.content.isEmpty else { return nil }
            source = .page(page)
        case .selection:
            let texts = selections.filter { !$0.isEmpty }
            guard !texts.isEmpty else { return nil }
            source = .selection(texts)
        }
        self.init(task: suggestion.task, source: source, language: language)
    }
}
