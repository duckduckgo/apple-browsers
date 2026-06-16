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
