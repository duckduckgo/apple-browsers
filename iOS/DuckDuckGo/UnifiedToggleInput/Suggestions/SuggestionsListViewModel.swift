//
//  SuggestionsListViewModel.swift
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
    /// `sourceRect` is the 🔥 button's global frame, used to anchor the iPad delete-confirmation popover.
    var onFireDelete: ((String, CGRect) -> Void)?

    private var cancellable: AnyCancellable?

    init(source: SuggestionsSource) {
        cancellable = source.sectionsPublisher
            .sink { [weak self] sections in
                guard let self else { return }
                self.sections = sections
                self.clearSelectionIfStale()
            }
    }

    func selectRow(id: String) { onSelect?(id) }
    func tapAheadRow(id: String) { onTapAhead?(id) }
    func deleteRow(id: String) { onDelete?(id) }
    func fireDeleteRow(id: String, sourceRect: CGRect) { onFireDelete?(id, sourceRect) }

    // MARK: - Hardware-keyboard selection (iPad popover)

    /// Row ids in display order — the cursor space for arrow-key navigation.
    private var orderedRowIDs: [String] {
        sections.flatMap { $0.rows.map(\.id) }
    }

    /// Down from no selection lands on the first row (mirrors `AutocompleteViewModel.nextSelection`).
    func moveSelectionDown() {
        let ids = orderedRowIDs
        guard !ids.isEmpty else { return }
        guard let current = selectedRowID, let index = ids.firstIndex(of: current) else {
            selectedRowID = ids.first
            return
        }
        let next = index + 1
        if ids.indices.contains(next) { selectedRowID = ids[next] }
    }

    /// Up from no selection is a no-op; up from the first row clears the highlight, returning focus to
    /// the text input (mirrors `AutocompleteViewModel.previousSelection`).
    func moveSelectionUp() {
        let ids = orderedRowIDs
        guard let current = selectedRowID, let index = ids.firstIndex(of: current) else { return }
        let previous = index - 1
        selectedRowID = ids.indices.contains(previous) ? ids[previous] : nil
    }

    private func clearSelectionIfStale() {
        guard let selectedRowID else { return }
        if !orderedRowIDs.contains(selectedRowID) { self.selectedRowID = nil }
    }
}
