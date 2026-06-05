//
//  DuckAISuggestionsSelection.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import AIChat
import Suggestions

/// A typed Duck.ai row selection, resolved from a `SuggestionRow.id`.
enum DuckAISuggestionsSelection: Equatable {
    case chat(AIChatSuggestion)
    case url(Suggestion)
    case searchDuckDuckGo(String)
}
