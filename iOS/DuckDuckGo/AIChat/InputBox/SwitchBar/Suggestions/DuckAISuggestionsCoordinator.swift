//
//  DuckAISuggestionsCoordinator.swift
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
import Core
import DDGSync
import Suggestions
import UIKit
import PrivacyConfig

protocol DuckAISuggestionsCoordinatorDelegate: AnyObject {
    func duckAISuggestionsDidSelectChat(_ chat: AIChatSuggestion)
    func duckAISuggestionsDidSelectURL(_ suggestion: Suggestion)
    func duckAISuggestionsDidDeleteURL(_ suggestion: Suggestion)
    func duckAISuggestionsDidSelectSearchDuckDuckGo(query: String)
    func duckAISuggestionsDidRequestSyncSetup()
}

/// Owns the chat fetcher, URL fetcher, and multi-section VC for Duck.ai mode; container talks to this instead of the fetchers directly.
@MainActor
final class DuckAISuggestionsCoordinator {

    weak var delegate: DuckAISuggestionsCoordinatorDelegate?

    var onContentChanged: (() -> Void)?

    private let chatManager: AIChatHistoryManager
    private let urlLoader: DuckAIURLSuggestionsLoader
    private let chatViewModel: AIChatSuggestionsViewModel
    private let historyManager: HistoryManaging
    private let queryProvider: () -> String
    private let layoutConfiguration: DuckAISuggestionsViewController.LayoutConfiguration
    private let syncPromoManager: SyncPromoManaging?
    private let syncService: DDGSyncing?

    private var viewController: DuckAISuggestionsViewController?
    private var cancellables = Set<AnyCancellable>()

    /// True when both fetchers have settled for `query`. Container gates Dax visibility on this to avoid mid-keystroke flashes.
    func hasSettled(forQuery query: String) -> Bool {
        Self.hasSettled(forQuery: query,
                        chatLastQuery: chatManager.lastCompletedFetchQuery,
                        urlLastQuery: urlLoader.lastCompletedFetchQuery)
    }

    static func hasSettled(forQuery query: String, chatLastQuery: String?, urlLastQuery: String?) -> Bool {
        chatLastQuery == query && urlLastQuery == query
    }

    var hasContent: Bool {
        !chatViewModel.filteredSuggestions.isEmpty
            || !urlLoader.topURLs.isEmpty
            || !queryProvider().isEmpty
    }

    init(chatManager: AIChatHistoryManager,
         urlLoader: DuckAIURLSuggestionsLoader,
         chatViewModel: AIChatSuggestionsViewModel,
         historyManager: HistoryManaging,
         queryProvider: @escaping () -> String,
         layoutConfiguration: DuckAISuggestionsViewController.LayoutConfiguration = .standard,
         syncPromoManager: SyncPromoManaging? = nil,
         syncService: DDGSyncing? = nil) {
        self.chatManager = chatManager
        self.urlLoader = urlLoader
        self.chatViewModel = chatViewModel
        self.historyManager = historyManager
        self.queryProvider = queryProvider
        self.layoutConfiguration = layoutConfiguration
        self.syncPromoManager = syncPromoManager
        self.syncService = syncService
    }

    func start<P: Publisher>(in containerView: UIView,
                             parentViewController: UIViewController,
                             textPublisher: P) where P.Output == String, P.Failure == Never {
        guard viewController == nil else { return }

        // Each subscriber gets its own subscription rather than going through `share()` — the upstream is `@Published`-backed
        // (replays on subscribe), and `share()` only delivers the replay to the first subscriber, leaving later ones missing
        // the initial value. With independent subscriptions all fetchers see the current text.
        chatManager.subscribeToTextChanges(textPublisher)
        urlLoader.subscribeToTextChanges(textPublisher)

        // Subscriptions live in coordinator-owned cancellables — container-owned ones leaked one set per install/dismiss cycle.
        chatManager.hasSuggestionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.onContentChanged?() }
            .store(in: &cancellables)
        urlLoader.$topURLs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.onContentChanged?() }
            .store(in: &cancellables)

        let vc = DuckAISuggestionsViewController(
            chatViewModel: chatViewModel,
            urlLoader: urlLoader,
            queryProvider: queryProvider,
            layoutConfiguration: layoutConfiguration,
            syncPromoManager: syncPromoManager,
            syncService: syncService
        )
        vc.delegate = self

        vc.onBecameVisible = { [weak self] in
            guard let self else { return }
            self.chatManager.refreshSuggestions(query: self.queryProvider())
        }

        // Hide the hatch the moment the user starts typing; restore on backspace-to-empty (mirrors Search-side autocomplete covering NTP).
        textPublisher
            .map { !$0.isEmpty }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak vc] active in vc?.setQueryActive(active) }
            .store(in: &cancellables)

        // In-place title refresh on every text change — full `reload()` would land inside the container's per-keystroke
        // spring animator and bounce the table.
        textPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak vc] _ in vc?.updateSearchRowTitle() }
            .store(in: &cancellables)

        parentViewController.addChild(vc)
        containerView.addSubview(vc.view)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            vc.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            vc.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            vc.view.bottomAnchor.constraint(lessThanOrEqualTo: containerView.safeAreaLayoutGuide.bottomAnchor)
        ])
        vc.didMove(toParent: parentViewController)
        viewController = vc
    }

    func setEscapeHatch(_ model: EscapeHatchModel?) {
        viewController?.setEscapeHatch(model)
    }

    func setAdditionalTopInset(_ inset: CGFloat) {
        viewController?.setAdditionalTopInset(inset)
    }

    func setIsVisibleContent(_ visible: Bool) {
        viewController?.setIsVisibleContent(visible)
    }

    func refreshURLSuggestions() {
        urlLoader.refreshSuggestions()
    }

    func tearDown() {
        cancellables.removeAll()
        onContentChanged = nil
        chatManager.tearDown()
        urlLoader.tearDown()
        if let vc = viewController {
            vc.willMove(toParent: nil)
            vc.view.removeFromSuperview()
            vc.removeFromParent()
        }
        viewController = nil
    }
}

extension DuckAISuggestionsCoordinator: DuckAISuggestionsViewControllerDelegate {

    func duckAISuggestionsDidSelectChat(_ chat: AIChatSuggestion) {
        delegate?.duckAISuggestionsDidSelectChat(chat)
    }

    func duckAISuggestionsDidSelectURL(_ suggestion: Suggestion) {
        delegate?.duckAISuggestionsDidSelectURL(suggestion)
    }

    func duckAISuggestionsDidSelectSearchDuckDuckGo(query: String) {
        delegate?.duckAISuggestionsDidSelectSearchDuckDuckGo(query: query)
    }

    func duckAISuggestionsDidRequestChatDeletion(_ chat: AIChatSuggestion, sender: UIViewController) {
        DailyPixel.fireDailyAndCount(pixel: .aiChatRecentChatDeleteButtonTapped)

        RecentChatDeletionAlert.show(for: chat, presenter: sender) {
            DailyPixel.fireDailyAndCount(pixel: .aiChatRecentChatDeleteCancelled)

        } onConfirm: { [weak self] in
            self?.chatManager.deleteChatSuggestion(suggestion: chat)
            DailyPixel.fireDailyAndCount(pixel: .aiChatRecentChatDeleteConfirmed)
        }
    }

    func duckAISuggestionsDidRequestURLDeletion(_ suggestion: Suggestion) {
        guard case .historyEntry(_, let url, _) = suggestion else {
            assertionFailure("Only history suggestions can be deleted")
            return
        }

        Task {
            await historyManager.deleteHistoryForURL(url)
            delegate?.duckAISuggestionsDidDeleteURL(suggestion)
            urlLoader.refreshSuggestions()

            Pixel.fire(pixel: .autocompleteDeleteHistoryEntry)
            DailyPixel.fireDaily(.autocompleteDeleteHistoryEntryDaily)
        }
    }

    func duckAISuggestionsDidRequestSyncSetup() {
        delegate?.duckAISuggestionsDidRequestSyncSetup()
    }
}
