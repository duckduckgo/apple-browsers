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

    private let chatManager: AIChatHistoryManager
    private let urlLoader: DuckAIURLSuggestionsLoader
    private let chatViewModel: AIChatSuggestionsViewModel
    private let queryProvider: () -> String
    private let isIPadExperience: Bool

    private var viewController: DuckAISuggestionsViewController?
    private var cancellables = Set<AnyCancellable>()

    /// Forwarded for callers that need to know whether the initial chat fetch has settled
    /// (e.g., to suppress the Dax empty state during the brief loading window).
    var hasCompletedInitialChatFetch: Bool { chatManager.hasCompletedInitialFetch }

    /// True when the suggestions surface has anything to render for the current query.
    /// Used by container view controllers to decide whether to show the Duck.ai empty state.
    var hasContent: Bool {
        Self.hasContent(
            chatCount: chatViewModel.filteredSuggestions.count,
            urlCount: urlLoader.topURLs.count,
            queryNonEmpty: !queryProvider().isEmpty
        )
    }

    /// Pure decision so the aggregation rule is unit-testable without spinning up the
    /// fetchers or view model.
    nonisolated static func hasContent(chatCount: Int, urlCount: Int, queryNonEmpty: Bool) -> Bool {
        chatCount > 0 || urlCount > 0 || queryNonEmpty
    }

    init(chatManager: AIChatHistoryManager,
         urlLoader: DuckAIURLSuggestionsLoader,
         chatViewModel: AIChatSuggestionsViewModel,
         isIPadExperience: Bool,
         queryProvider: @escaping () -> String) {
        self.chatManager = chatManager
        self.urlLoader = urlLoader
        self.chatViewModel = chatViewModel
        self.queryProvider = queryProvider
        self.isIPadExperience = isIPadExperience
    }

    func start<P: Publisher>(in containerView: UIView,
                             parentViewController: UIViewController,
                             textPublisher: P) where P.Output == String, P.Failure == Never {
        guard viewController == nil else { return }

        let shared = textPublisher.share()
        chatManager.subscribeToTextChanges(shared)
        urlLoader.subscribeToTextChanges(shared)

        let vc = DuckAISuggestionsViewController(
            chatViewModel: chatViewModel,
            urlLoader: urlLoader,
            isIPadExperience: isIPadExperience,
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
