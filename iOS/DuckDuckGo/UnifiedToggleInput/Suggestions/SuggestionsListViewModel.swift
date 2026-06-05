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

    // MARK: - Keyboard navigation

    func moveSelectionDown() { moveSelection(by: +1) }
    func moveSelectionUp() { moveSelection(by: -1) }

    func commitSelection() {
        if let id = selectedRowID { onSelect?(id) }
    }

    private func moveSelection(by delta: Int) {
        let ids = sections.flatMap { $0.rows.map(\.id) }
        guard !ids.isEmpty else { selectedRowID = nil; return }
        guard let current = selectedRowID, let idx = ids.firstIndex(of: current) else {
            selectedRowID = delta > 0 ? ids.first : ids.last
            return
        }
        let next = idx + delta
        if ids.indices.contains(next) { selectedRowID = ids[next] }
    }
}
