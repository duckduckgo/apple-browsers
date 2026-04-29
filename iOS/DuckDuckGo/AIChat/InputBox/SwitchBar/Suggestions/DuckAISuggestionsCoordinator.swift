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
import Suggestions
import UIKit

protocol DuckAISuggestionsCoordinatorDelegate: AnyObject {
    func duckAISuggestionsDidSelectChat(_ chat: AIChatSuggestion)
    func duckAISuggestionsDidSelectURL(_ suggestion: Suggestion)
    func duckAISuggestionsDidSelectSearchDuckDuckGo(query: String)
}

/// Single surface that owns the chat-suggestion fetcher, the URL-suggestion fetcher,
/// and the multi-section view controller for Duck.ai mode. Replaces the older
/// `AIChatHistoryManager`-direct usage in container view controllers and keeps the
/// internal composition private.
@MainActor
final class DuckAISuggestionsCoordinator {

    weak var delegate: DuckAISuggestionsCoordinatorDelegate?

    /// Called whenever either fetcher's result set changes. Container view controllers use
    /// this to refresh their derived state (e.g. Dax-empty-state visibility) without
    /// subscribing directly to the fetchers — keeping the lifetime of those subscriptions
    /// tied to the coordinator's `tearDown` rather than the container's `cancellables` set.
    var onContentChanged: (() -> Void)?

    private let chatManager: AIChatHistoryManager
    private let urlLoader: DuckAIURLSuggestionsLoader
    private let chatViewModel: AIChatSuggestionsViewModel
    private let queryProvider: () -> String

    private var viewController: DuckAISuggestionsViewController?
    private var cancellables = Set<AnyCancellable>()

    /// Forwarded for callers that need to know whether the initial chat fetch has settled
    /// (e.g., to suppress the Dax empty state during the brief loading window).
    var hasCompletedInitialChatFetch: Bool { chatManager.hasCompletedInitialFetch }

    /// True when the suggestions surface has anything to render for the current query.
    /// Any non-empty query renders at least the always-visible "Search DuckDuckGo" row.
    var hasContent: Bool {
        !chatViewModel.filteredSuggestions.isEmpty
            || !urlLoader.topURLs.isEmpty
            || !queryProvider().isEmpty
    }

    init(chatManager: AIChatHistoryManager,
         urlLoader: DuckAIURLSuggestionsLoader,
         chatViewModel: AIChatSuggestionsViewModel,
         queryProvider: @escaping () -> String) {
        self.chatManager = chatManager
        self.urlLoader = urlLoader
        self.chatViewModel = chatViewModel
        self.queryProvider = queryProvider
    }

    func start<P: Publisher>(in containerView: UIView,
                             parentViewController: UIViewController,
                             textPublisher: P) where P.Output == String, P.Failure == Never {
        guard viewController == nil else { return }

        let shared = textPublisher.share()
        chatManager.subscribeToTextChanges(shared)
        urlLoader.subscribeToTextChanges(shared)

        // Subscriptions live in the coordinator's own `cancellables` so they're released by
        // `tearDown`. Storing them in the container VC's set leaked one per install/dismiss
        // cycle, with each leaked subscription pinning the prior chat manager + URL loader.
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
            queryProvider: queryProvider
        )
        vc.delegate = self

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
}
