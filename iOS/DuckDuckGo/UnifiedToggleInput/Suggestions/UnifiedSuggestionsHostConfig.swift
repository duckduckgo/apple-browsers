//
//  UnifiedSuggestionsHostConfig.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.

import Combine
import UIKit

/// Per-surface configuration for `UnifiedSuggestionsHost`.
@MainActor
struct UnifiedSuggestionsHostConfig {
    let source: SuggestionsSource
    let inputsPublisher: AnyPublisher<UnifiedSuggestionsInputs, Never>
    let isAddressBarAtBottom: Bool
    /// Builds the favorites controller on demand; nil for surfaces without a favorites state (Duck.ai).
    let favoritesProvider: () -> NewTabPageViewController?
    let onSelectRow: (String) -> Void
    let onDeleteRow: (String) -> Void
    let onTapAheadRow: (String) -> Void
    /// Imperative facts the container reads for Dax visibility.
    let hasContent: () -> Bool
    let hasSettled: (String) -> Bool
}

/// The lazily-attached duck.ai surface for the single-host path. Carries its own source +
/// row handlers; the host builds a dedicated list VM for it so `.list(.duckAI|.recents)` rows
/// resolve to duck.ai data while `.list(.search)` keeps resolving to the search VM.
@MainActor
struct UnifiedSuggestionsDuckAISurface {
    let source: SuggestionsSource
    let onSelectRow: (String) -> Void
    let onDeleteRow: (String) -> Void
    let onTapAheadRow: (String) -> Void
}
