//
//  UnifiedDuckAISuggestionsHost.swift
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

import AIChat
import Combine
import DDGSync
import Suggestions
import SwiftUI
import UIKit

/// Hosts the SwiftUI `UnifiedSuggestionsView` for the Duck.ai surface. Exposes the same
/// container-facing surface as `DuckAISuggestionsCoordinator`, so it is a drop-in replacement
/// for the UTI-flag-ON Duck.ai path. The Dax logo stays driven by `DaxLogoManager`.
@MainActor
final class UnifiedDuckAISuggestionsHost {

    weak var delegate: DuckAISuggestionsCoordinatorDelegate?
    var onContentChanged: (() -> Void)?

    private let chatManager: AIChatHistoryManager
    private let urlLoader: DuckAIURLSuggestionsLoader
    private let chatViewModel: AIChatSuggestionsViewModel
    private let queryProvider: () -> String
    private let isAddressBarAtBottom: Bool
    private let deleteHistory: (URL) async -> Void

    private let source: DuckAISuggestionsSource
    private let listViewModel: SuggestionsListViewModel
    private var hostingController: UIHostingController<UnifiedSuggestionsView>?
    private var escapeHatchModel: EscapeHatchModel?
    private var cancellables = Set<AnyCancellable>()

    init(chatManager: AIChatHistoryManager,
         urlLoader: DuckAIURLSuggestionsLoader,
         chatViewModel: AIChatSuggestionsViewModel,
         queryProvider: @escaping () -> String,
         isAddressBarAtBottom: Bool,
         deleteHistory: @escaping (URL) async -> Void) {
        self.chatManager = chatManager
        self.urlLoader = urlLoader
        self.chatViewModel = chatViewModel
        self.queryProvider = queryProvider
        self.isAddressBarAtBottom = isAddressBarAtBottom
        self.deleteHistory = deleteHistory

        let pipeline = DuckAISuggestionsPipeline(
            chatsPublisher: chatViewModel.$filteredSuggestions.eraseToAnyPublisher(),
            urlsPublisher: urlLoader.$topURLs.eraseToAnyPublisher(),
            latestDispatchedQuery: queryProvider,
            lastCompletedURLQuery: { [weak urlLoader] in urlLoader?.lastCompletedFetchQuery ?? "" })
        self.source = DuckAISuggestionsSource(snapshotPublisher: pipeline.snapshotPublisher,
                                              query: queryProvider)
        self.listViewModel = SuggestionsListViewModel(source: source)
    }

    // MARK: - Container-facing surface (mirrors DuckAISuggestionsCoordinator)

    var hasContent: Bool {
        !chatViewModel.filteredSuggestions.isEmpty || !urlLoader.topURLs.isEmpty || !queryProvider().isEmpty
    }

    /// True when both fetchers have settled for `query`. Container gates Dax visibility on this
    /// to avoid mid-keystroke flashes. Ports the coordinator's logic verbatim.
    func hasSettled(forQuery query: String) -> Bool {
        chatManager.lastCompletedFetchQuery == query && urlLoader.lastCompletedFetchQuery == query
    }

    func start<P: Publisher>(in containerView: UIView,
                             parentViewController: UIViewController,
                             textPublisher: P) where P.Output == String, P.Failure == Never {
        guard hostingController == nil else { return }

        chatManager.subscribeToTextChanges(textPublisher)
        urlLoader.subscribeToTextChanges(textPublisher)

        listViewModel.onSelect = { [weak self] id in self?.handleSelect(id) }
        listViewModel.onTapAhead = { [weak self] id in self?.handleTapAhead(id) }
        listViewModel.onDelete = { [weak self] id in self?.handleDelete(id) }

        chatViewModel.$filteredSuggestions
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.onContentChanged?() }
            .store(in: &cancellables)
        urlLoader.$topURLs
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.onContentChanged?() }
            .store(in: &cancellables)

        let view = UnifiedSuggestionsView(
            viewModel: listViewModel,
            isAddressBarAtBottom: isAddressBarAtBottom,
            header: makeHeader())
        let hosting = UIHostingController(rootView: view)
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        parentViewController.addChild(hosting)
        containerView.addSubview(hosting.view)
        // The SwiftUI List needs a definite height or it collapses; pin the bottom to the
        // keyboard guide (mirrors the legacy DuckAISuggestionsViewController table pinning).
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: containerView.keyboardLayoutGuide.topAnchor)
        ])
        hosting.didMove(toParent: parentViewController)
        hostingController = hosting

        chatManager.refreshSuggestions(query: queryProvider())
    }

    func setEscapeHatch(_ model: EscapeHatchModel?) {
        escapeHatchModel = model
        rebuildRootView()
    }

    func setAdditionalTopInset(_ inset: CGFloat) {
        hostingController?.additionalSafeAreaInsets.top = inset
    }

    /// No-op: visibility gating is handled by `DaxLogoManager` + `hasContent`/`hasSettled`; the host
    /// renders into the container's always-present chatPageContainer.
    func setIsVisibleContent(_ visible: Bool) {}

    func tearDown() {
        cancellables.removeAll()
        onContentChanged = nil
        chatManager.tearDown()
        urlLoader.tearDown()
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        hostingController = nil
    }

    // MARK: - Private

    private func makeHeader() -> AnyView? {
        guard let escapeHatchModel else { return nil }
        return AnyView(EscapeHatchView(model: escapeHatchModel))
    }

    private func rebuildRootView() {
        guard let hosting = hostingController else { return }
        hosting.rootView = UnifiedSuggestionsView(
            viewModel: listViewModel,
            isAddressBarAtBottom: isAddressBarAtBottom,
            header: makeHeader())
    }

    private func handleSelect(_ id: String) {
        switch source.selection(forRowID: id) {
        case .chat(let chat): delegate?.duckAISuggestionsDidSelectChat(chat)
        case .url(let suggestion): delegate?.duckAISuggestionsDidSelectURL(suggestion)
        case .searchDuckDuckGo(let query): delegate?.duckAISuggestionsDidSelectSearchDuckDuckGo(query: query)
        case .none: break
        }
    }

    private func handleTapAhead(_ id: String) {
        // Tap-ahead fills the query field; route same as select for phrase rows.
        handleSelect(id)
    }

    private func handleDelete(_ id: String) {
        guard case .url(let suggestion) = source.selection(forRowID: id),
              case .historyEntry(_, let url, _) = suggestion else { return }
        Task { [weak self] in
            await self?.deleteHistory(url)
            guard let self else { return }
            self.urlLoader.fetch(query: self.queryProvider())
        }
    }
}
