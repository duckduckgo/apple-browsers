//
//  ChatContext.swift
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

/// What the app hands the package for one chat. Validated once here; everything downstream trusts it.
public struct ChatContext: Equatable, Sendable {
    public let page: PageContext?
    public let selections: [Selection]
    public let opening: Opening?

    public init(page: PageContext?, selections: [Selection], opening: Opening?) throws(ChatContextError) {
        if case .request = opening, page == nil, selections.isEmpty {
            throw .requestWithoutSource
        }
        self.page = page
        self.selections = selections
        self.opening = opening
    }

    /// The parts the first user message carries, in frontend order.
    public var contextParts: [ContextPart] {
        var parts: [ContextPart] = []
        if case .request(let request) = opening {
            parts.append(.request(request))
        }
        if let page {
            parts.append(.page(page))
        }
        parts += selections.map(ContextPart.selection)
        return parts
    }
}

public enum ChatContextError: Error, Equatable {
    case requestWithoutSource
}

/// The first user turn, sent on open. A request and a typed prompt are exclusive, as in the frontend.
public enum Opening: Equatable, Sendable {
    case prompt(String)
    case request(ChatRequest)
}

public enum ChatRequest: Equatable, Sendable {
    case summarize
    case translate(into: TargetLanguage)
}

public struct TargetLanguage: Hashable, Sendable {
    /// BCP 47, for example "de".
    public let code: String
    /// What the model is told, for example "German".
    public let name: String

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

public struct PageContext: Equatable, Sendable {
    public let title: String
    public let url: URL?
    /// Already capped by the app.
    public let content: String

    public init(title: String, url: URL?, content: String) {
        self.title = title
        self.url = url
        self.content = content
    }
}

public struct Selection: Equatable, Sendable {
    public let title: String
    public let url: URL?
    public let content: String

    public init(title: String, url: URL?, content: String) {
        self.title = title
        self.url = url
        self.content = content
    }
}
