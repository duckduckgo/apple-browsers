//
//  UnifiedSuggestionsViewModel.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import Combine
import Foundation

/// Aggregates input facts, runs `UnifiedSuggestionsContentResolver`, and publishes the
/// presentation `content` for `UnifiedSuggestionsView`. Holds the active list view model.
@MainActor
final class UnifiedSuggestionsViewModel: ObservableObject {

    @Published private(set) var content: UnifiedSuggestionsContentKind = .logo
    /// The search-surface list VM. On the single-host path the duck.ai surface adds its own
    /// (see `duckAIListViewModel`); the view picks between them by content kind.
    let listViewModel: SuggestionsListViewModel
    /// Present only on the single-host path once the duck.ai surface is attached. `.list(.duckAI)`
    /// and `.list(.recents)` render this; `.list(.search)` renders `listViewModel`.
    private(set) var duckAIListViewModel: SuggestionsListViewModel?

    private var cancellable: AnyCancellable?

    init(inputsPublisher: AnyPublisher<UnifiedSuggestionsInputs, Never>,
         listViewModel: SuggestionsListViewModel,
         duckAIListViewModel: SuggestionsListViewModel? = nil) {
        self.listViewModel = listViewModel
        self.duckAIListViewModel = duckAIListViewModel
        cancellable = inputsPublisher
            .sink { [weak self] inputs in
                guard let self else { return }
                self.content = UnifiedSuggestionsContentResolver.resolve(inputs, previous: self.content)
            }
    }

    func setDuckAIListViewModel(_ viewModel: SuggestionsListViewModel?) {
        duckAIListViewModel = viewModel
    }

    /// Resolves the list VM for a `.list` content kind. Falls back to the search VM so the
    /// single-VM (old) path keeps working before any duck.ai surface is attached.
    func listViewModel(for kind: SuggestionsListSourceKind) -> SuggestionsListViewModel {
        switch kind {
        case .search:
            return listViewModel
        case .duckAI, .recents:
            return duckAIListViewModel ?? listViewModel
        }
    }
}
