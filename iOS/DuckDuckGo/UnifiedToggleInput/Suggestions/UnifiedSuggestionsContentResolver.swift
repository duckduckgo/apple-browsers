//
//  UnifiedSuggestionsContentResolver.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import Foundation

/// Which list data source is active for a `.list` presentation.
enum SuggestionsListSourceKind: Equatable {
    case search
    case duckAI
    case recents
}

/// The presentation the unified suggestions view should render. Pure value — no view models.
enum UnifiedSuggestionsContentKind: Equatable {
    case list(SuggestionsListSourceKind)
    case favorites
    case logo
}

/// The complete set of facts that decide the presentation. No UIKit, no managers.
struct UnifiedSuggestionsInputs: Equatable {
    let mode: TextEntryMode
    let isTyping: Bool
    let hasFavoritesOrMessages: Bool
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
                return inputs.hasFavoritesOrMessages ? .favorites : .logo
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
