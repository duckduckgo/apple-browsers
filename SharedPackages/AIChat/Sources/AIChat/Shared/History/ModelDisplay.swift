//
//  ModelDisplay.swift
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

/// Plain-text model attribution for the chat-history export header.
public struct ModelDisplay: Equatable, Sendable {
    public let fullName: String?
    public let shortName: String
    public let providerPossessive: String?

    public init(fullName: String?, shortName: String, providerPossessive: String?) {
        self.fullName = fullName
        self.shortName = shortName
        self.providerPossessive = providerPossessive
    }
}

public extension AIChatModel.ModelProvider {

    /// Possessive form of the provider name. `nil` for providers without a clean possessive
    /// (OSS / unknown), so the export header falls back to a non-possessive phrasing.
    var possessive: String? {
        switch self {
        case .openAI: return "OpenAI's"
        case .anthropic: return "Anthropic's"
        case .meta: return "Meta's"
        case .mistral: return "Mistral's"
        case .oss, .unknown: return nil
        }
    }
}

public extension AIChatModel {

    func toModelDisplay() -> ModelDisplay {
        ModelDisplay(
            fullName: name,
            shortName: shortName,
            providerPossessive: provider.possessive
        )
    }
}
