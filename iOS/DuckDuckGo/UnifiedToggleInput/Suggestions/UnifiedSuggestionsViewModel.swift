//
//  UnifiedSuggestionsViewModel.swift
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
import Foundation
import SwiftUI

/// Aggregates input facts, runs `UnifiedSuggestionsContentResolver`, and publishes the
/// presentation `content` for `UnifiedSuggestionsView`. Holds the active list view model.
@MainActor
final class UnifiedSuggestionsViewModel: ObservableObject {

    @Published private(set) var content: UnifiedSuggestionsContentKind = .logo
    /// Reactive sync-promo visibility (driven by the container) so show/hide animates with the
    /// content crossfade instead of snapping via a root-view rebuild.
    @Published var showsSyncPromo = false
    /// The search-surface list VM. On the single-host path the duck.ai surface adds its own
    /// (see `duckAIListViewModel`); the view picks between them by content kind.
    let listViewModel: SuggestionsListViewModel
    /// Present only on the single-host path once the duck.ai surface is attached. `.list(.duckAI)`
    /// and `.list(.recents)` render this; `.list(.search)` renders `listViewModel`.
    private(set) var duckAIListViewModel: SuggestionsListViewModel?
    /// Stable empty list for `.list(.duckAI|.recents)` when no duck.ai surface is attached
    /// (suggestions disabled / pre-attach) — keeps the list mounted without showing Search rows.
    private let emptyListViewModel = SuggestionsListViewModel(source: EmptySuggestionsSource())

    private var cancellable: AnyCancellable?
    private var previousMode: TextEntryMode?

    init(inputsPublisher: AnyPublisher<UnifiedSuggestionsInputs, Never>,
         listViewModel: SuggestionsListViewModel,
         duckAIListViewModel: SuggestionsListViewModel? = nil) {
        self.listViewModel = listViewModel
        self.duckAIListViewModel = duckAIListViewModel
        cancellable = inputsPublisher
            .sink { [weak self] inputs in
                guard let self else { return }
                let resolved = UnifiedSuggestionsContentResolver.resolve(inputs, previous: self.content)
                self.apply(resolved, modeChanged: inputs.mode != self.previousMode)
                self.previousMode = inputs.mode
            }
    }

    /// Crossfades only when a mode switch changes the content *type* (e.g. favorites↔recents,
    /// list↔logo). List↔list keeps the mounted list, and same-mode changes (typing, deletions)
    /// stay snappy. When the sync promo is showing, snap instead — crossfading the recents under the
    /// collapsing promo card makes them flash over its space.
    private func apply(_ newContent: UnifiedSuggestionsContentKind, modeChanged: Bool) {
        guard newContent != content else { return }
        if modeChanged && !Self.sameCategory(content, newContent) && !showsSyncPromo {
            withAnimation(.easeInOut(duration: 0.2)) { content = newContent }
        } else {
            content = newContent
        }
    }

    private static func sameCategory(_ lhs: UnifiedSuggestionsContentKind, _ rhs: UnifiedSuggestionsContentKind) -> Bool {
        switch (lhs, rhs) {
        case (.list, .list), (.favorites, .favorites), (.logo, .logo): return true
        default: return false
        }
    }

    func setDuckAIListViewModel(_ viewModel: SuggestionsListViewModel?) {
        duckAIListViewModel = viewModel
    }

    /// Resolves the list VM for a `.list` content kind. Duck.ai kinds fall back to a stable empty
    /// list (never the Search VM) when no duck.ai surface is attached, so Search rows never render
    /// in Duck.ai mode.
    func listViewModel(for kind: SuggestionsListSourceKind) -> SuggestionsListViewModel {
        switch kind {
        case .search:
            return listViewModel
        case .duckAI, .recents:
            return duckAIListViewModel ?? emptyListViewModel
        }
    }
}
