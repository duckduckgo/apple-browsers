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

/// Owns the chat fetcher, URL fetcher, and multi-section VC for Duck.ai mode; container talks to this instead of the fetchers directly.
@MainActor
final class DuckAISuggestionsCoordinator {

    weak var delegate: DuckAISuggestionsCoordinatorDelegate?

    /// Fires when either fetcher's results change. Subscribed via the coordinator's own cancellables so lifetime tracks `tearDown`.
    var onContentChanged: (() -> Void)?

    private let chatManager: AIChatHistoryManager
    private let urlLoader: DuckAIURLSuggestionsLoader
    private let chatViewModel: AIChatSuggestionsViewModel
    private let queryProvider: () -> String

    private var viewController: DuckAISuggestionsViewController?
    private var cancellables = Set<AnyCancellable>()

    var hasCompletedInitialChatFetch: Bool { chatManager.hasCompletedInitialFetch }

    /// True when both fetchers have settled for `query`. Container gates Dax visibility on this to avoid mid-keystroke flashes.
    func hasSettled(forQuery query: String) -> Bool {
        chatManager.lastCompletedFetchQuery == query
            && urlLoader.lastCompletedFetchQuery == query
    }

    /// True when the surface has anything to render. Any non-empty query renders at least the "Search DuckDuckGo" row.
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

    func setEscapeHatch(_ model: EscapeHatchModel?, onTapped: (() -> Void)?) {
        viewController?.setEscapeHatch(model, onTapped: onTapped)
    }

    func setAdditionalTopInset(_ inset: CGFloat) {
        viewController?.setAdditionalTopInset(inset)
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
