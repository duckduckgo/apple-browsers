//
//  SuggestionResult.swift
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

public struct SuggestionResult: Equatable {

    static var empty: SuggestionResult {
        SuggestionResult(topHits: [], duckduckgoSuggestions: [], localSuggestions: [])
    }

    public let topHits: [Suggestion]
    public let duckduckgoSuggestions: [Suggestion]
    public let localSuggestions: [Suggestion]

    public init(topHits: [Suggestion],
                duckduckgoSuggestions: [Suggestion],
                localSuggestions: [Suggestion]) {
        self.topHits = topHits
        self.duckduckgoSuggestions = duckduckgoSuggestions
        self.localSuggestions = localSuggestions
    }

    public var isEmpty: Bool {
        topHits.isEmpty && duckduckgoSuggestions.isEmpty && localSuggestions.isEmpty
    }

    public var all: [Suggestion] {
        topHits + duckduckgoSuggestions + localSuggestions
    }

    public var count: Int {
        topHits.count + duckduckgoSuggestions.count + localSuggestions.count
    }

    public var canBeAutocompleted: Bool {
        guard let firstTopHit = topHits.first else {
            return false
        }

        // Disable autocompletion for website suggestions
        if case .website = firstTopHit {
            return false
        }

        return true
    }

}
