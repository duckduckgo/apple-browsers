//
//  PopoverSuggestionsController.swift
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
import DesignResourcesKit
import SwiftUI
import UIKit

/// Hosts the shared SwiftUI `SuggestionsListView` inside the iPad suggestions popover
/// (`SuggestionTrayViewController`), in place of the legacy `AutocompleteViewController`.
/// Surface-agnostic: driven by any `SuggestionsSource` and reports its content height so the
/// popover can size to content (a lazy `List` can't self-report its full height).
@MainActor
final class PopoverSuggestionsController: UIViewController {

    /// Emits the computed content height whenever the rendered sections change.
    var onContentHeightChange: ((CGFloat) -> Void)?

    var onSelectRow: ((String) -> Void)?
    var onTapAheadRow: ((String) -> Void)?
    var onDeleteRow: ((String) -> Void)?
    /// `CGRect` is the 🔥 button's global frame, used to anchor the delete-confirmation popover.
    var onFireDeleteRow: ((String, CGRect) -> Void)?
    /// Fired when the keyboard/pointer selection moves to a row (to preview it in the omnibar text).
    var onHighlightRow: ((String) -> Void)?
    /// Fired when the selection clears (arrow-up past the top, pointer leaves, tap) so the omnibar can
    /// restore the user's typed query instead of leaving the last previewed suggestion in the field.
    var onClearHighlight: (() -> Void)?

    /// The id of the row currently highlighted by arrow-key navigation, for Enter-to-commit.
    var selectedRowID: String? { listViewModel.selectedRowID }

    private let source: SuggestionsSource
    private let listViewModel: SuggestionsListViewModel
    private let isAddressBarAtBottom: Bool
    /// Single source of truth for the typed query: the source's pull-based `query()` reads its
    /// `.value` and the loader subscribes to its publisher, so display and resolution never drift.
    private let querySubject: CurrentValueSubject<String, Never>
    private var hostingController: UIHostingController<SuggestionsListView>?
    private var cancellables = Set<AnyCancellable>()

    init(source: SuggestionsSource,
         isAddressBarAtBottom: Bool,
         querySubject: CurrentValueSubject<String, Never>) {
        self.source = source
        self.isAddressBarAtBottom = isAddressBarAtBottom
        self.listViewModel = SuggestionsListViewModel(source: source)
        self.querySubject = querySubject
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(designSystemColor: .background)

        wireListCallbacks()
        installHostingController()

        source.start(textPublisher: querySubject.removeDuplicates().eraseToAnyPublisher())
        source.sectionsPublisher
            .sink { [weak self] sections in self?.reportHeight(for: sections) }
            .store(in: &cancellables)
        listViewModel.$selectedRowID
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] id in
                if let id { self?.onHighlightRow?(id) } else { self?.onClearHighlight?() }
            }
            .store(in: &cancellables)
    }

    func updateQuery(_ query: String) {
        // Send the query first so a highlight-clear restores the *current* typed text, not the previous
        // query; then clear any keyboard/pointer highlight before new results arrive.
        querySubject.send(query)
        listViewModel.selectedRowID = nil
    }

    func keyboardMoveSelectionDown() { listViewModel.moveSelectionDown() }
    func keyboardMoveSelectionUp() { listViewModel.moveSelectionUp() }
    func clearKeyboardSelection() { listViewModel.selectedRowID = nil }

    /// Cancels the source's loaders/subscriptions; call before removing from the popover.
    func tearDown() {
        source.tearDown()
        cancellables.removeAll()
    }

    private func wireListCallbacks() {
        listViewModel.onSelect = { [weak self] in self?.onSelectRow?($0) }
        listViewModel.onTapAhead = { [weak self] in self?.onTapAheadRow?($0) }
        listViewModel.onDelete = { [weak self] in self?.onDeleteRow?($0) }
        listViewModel.onFireDelete = { [weak self] id, sourceRect in self?.onFireDeleteRow?(id, sourceRect) }
    }

    private func installHostingController() {
        let listView = SuggestionsListView(viewModel: listViewModel, isAddressBarAtBottom: isAddressBarAtBottom)
        let hosting = UIHostingController(rootView: listView)
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hosting)
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)
        hostingController = hosting
    }

    private func reportHeight(for sections: [SuggestionSection]) {
        onContentHeightChange?(SuggestionsListHeightCalculator.height(for: sections, isAddressBarAtBottom: isAddressBarAtBottom))
    }
}
