//
//  SuggestionsListViewModel.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import Combine
import Foundation

/// Drives one `.list` presentation: republishes its source's sections and routes
/// row interactions back out by id. Holds no suggestion data of its own.
@MainActor
final class SuggestionsListViewModel: ObservableObject {

    @Published private(set) var sections: [SuggestionSection] = []
    /// Transient keyboard-selection highlight; not part of the row model.
    @Published var selectedRowID: String?

    var onSelect: ((String) -> Void)?
    var onTapAhead: ((String) -> Void)?
    var onDelete: ((String) -> Void)?
    var onFireDelete: ((String) -> Void)?

    private var cancellable: AnyCancellable?

    init(source: SuggestionsSource) {
        cancellable = source.sectionsPublisher
            .sink { [weak self] sections in
                self?.sections = sections
            }
    }

    func selectRow(id: String) { onSelect?(id) }
    func tapAheadRow(id: String) { onTapAhead?(id) }
    func deleteRow(id: String) { onDelete?(id) }
    func fireDeleteRow(id: String) { onFireDelete?(id) }
}
