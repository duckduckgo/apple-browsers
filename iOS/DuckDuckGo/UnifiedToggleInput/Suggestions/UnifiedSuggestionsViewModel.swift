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
    let listViewModel: SuggestionsListViewModel

    private var cancellable: AnyCancellable?

    init(inputsPublisher: AnyPublisher<UnifiedSuggestionsInputs, Never>,
         listViewModel: SuggestionsListViewModel) {
        self.listViewModel = listViewModel
        cancellable = inputsPublisher
            .sink { [weak self] inputs in
                guard let self else { return }
                self.content = UnifiedSuggestionsContentResolver.resolve(inputs, previous: self.content)
            }
    }
}
