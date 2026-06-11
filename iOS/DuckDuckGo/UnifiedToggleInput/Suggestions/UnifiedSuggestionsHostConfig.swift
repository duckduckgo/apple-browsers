//
//  UnifiedSuggestionsHostConfig.swift
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
    let onFireDeleteRow: (String) -> Void
}
