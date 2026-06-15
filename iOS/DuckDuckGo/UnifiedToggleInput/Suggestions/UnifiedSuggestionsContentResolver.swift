//
//  UnifiedSuggestionsContentResolver.swift
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

/// Which list data source is active for a `.list` presentation.
enum SuggestionsListSourceKind: Hashable {
    case search
    case duckAI
    case recents
}

/// The presentation the unified suggestions view should render. Pure value — no view models.
enum UnifiedSuggestionsContentKind: Hashable {
    case list(SuggestionsListSourceKind)
    case favorites
    case logo
}

/// The complete set of facts that decide the presentation. No UIKit, no managers.
struct UnifiedSuggestionsInputs: Equatable {
    let mode: TextEntryMode
    let isTyping: Bool
    let hasFavorites: Bool
    let hasMessages: Bool
    let hasRecents: Bool
    let resultsPending: Bool
}

/// Pure decision table. `previous` lets us hold the prior presentation while
/// duck.ai fetchers are still settling, so the logo never flashes mid-query.
enum UnifiedSuggestionsContentResolver {

    static func resolve(_ inputs: UnifiedSuggestionsInputs,
                        previous: UnifiedSuggestionsContentKind?) -> UnifiedSuggestionsContentKind {
        switch inputs.mode {
        case .search:
            guard inputs.isTyping else {
                return (inputs.hasFavorites || inputs.hasMessages) ? .favorites : .logo
            }
            return .list(.search)

        case .aiChat:
            guard inputs.isTyping else {
                return inputs.hasRecents ? .list(.recents) : .logo
            }
            if inputs.resultsPending {
                if let previous, case .list = previous { return previous }
                return .list(.duckAI)
            }
            return .list(.duckAI)
        }
    }
}
