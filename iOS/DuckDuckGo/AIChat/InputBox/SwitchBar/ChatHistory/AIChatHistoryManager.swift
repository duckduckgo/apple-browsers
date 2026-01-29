//
//  AIChatHistoryManager.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import Combine
import Core
import PrivacyConfig
import UIKit

/// Protocol for handling AI chat history events
protocol AIChatHistoryManagerDelegate: AnyObject {
    func aiChatHistoryManager(_ manager: AIChatHistoryManager, didSelectChatURL url: URL)
}

/// Manages the AI Chat history list installation and interaction
@MainActor
final class AIChatHistoryManager {

    // MARK: - Constants

    private enum Constants {
        static let debounceMilliseconds = 150
    }

    // MARK: - Properties

    weak var delegate: AIChatHistoryManagerDelegate?

    private var historyViewController: AIChatHistoryListViewController?
    private let suggestionsReader: AIChatSuggestionsReading
    private let aiChatSettings: AIChatSettingsProvider
    private let viewModel: AIChatSuggestionsViewModel
    private var cancellables = Set<AnyCancellable>()
    private var currentFetchTask: Task<Void, Never>?

    // MARK: - Initialization

    init(suggestionsReader: AIChatSuggestionsReading,
         aiChatSettings: AIChatSettingsProvider,
         viewModel: AIChatSuggestionsViewModel) {
        self.suggestionsReader = suggestionsReader
        self.aiChatSettings = aiChatSettings
        self.viewModel = viewModel
    }

    // MARK: - Public Methods

    /// Installs the chat history list in the provided container view
    /// - Parameters:
    ///   - containerView: The view to install the chat history list into
    ///   - parentViewController: The parent view controller for the hosting controller
    func installInContainerView(_ containerView: UIView, parentViewController: UIViewController) {
        guard historyViewController == nil else { return }

        let viewController = AIChatHistoryListViewController(
            viewModel: viewModel,
            onChatSelected: { [weak self] chat in
                guard let self else { return }
                let url = self.aiChatSettings.aiChatURL.withChatID(chat.chatId)
                self.delegate?.aiChatHistoryManager(self, didSelectChatURL: url)
            }
        )

        parentViewController.addChild(viewController)
        containerView.addSubview(viewController.view)

        viewController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            viewController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            viewController.view.topAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.topAnchor),
            viewController.view.bottomAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.bottomAnchor)
        ])

        viewController.didMove(toParent: parentViewController)
        self.historyViewController = viewController

        // Initial fetch with empty query (shows recent chats from last week)
        fetchSuggestionsIfNeeded(query: "")
    }

    /// Subscribes to text changes from a publisher with debounce and fetches filtered suggestions
    /// - Parameter textPublisher: A publisher that emits text changes
    func subscribeToTextChanges<P: Publisher>(_ textPublisher: P) where P.Output == String, P.Failure == Never {
        textPublisher
            .debounce(for: .milliseconds(Constants.debounceMilliseconds), scheduler: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self else { return }
                self.fetchSuggestionsIfNeeded(query: text)
            }
            .store(in: &cancellables)
    }

    /// Fetches suggestions from the API with cancellation support
    /// - Parameter query: The search query to filter results
    private func fetchSuggestionsIfNeeded(query: String) {
        currentFetchTask?.cancel()

        let reader = suggestionsReader
        let viewModel = viewModel
        let effectiveQuery = query.isEmpty ? nil : query
        let maxChats = viewModel.maxSuggestions

        currentFetchTask = Task {
            let suggestions = await reader.fetchSuggestions(query: effectiveQuery, maxChats: maxChats)
            guard !Task.isCancelled else { return }
            viewModel.setChats(pinned: suggestions.pinned, recent: suggestions.recent)
        }
    }

    /// Tears down the suggestions reader and releases resources
    func tearDown() {
        currentFetchTask?.cancel()
        currentFetchTask = nil
        cancellables.removeAll()

        if let historyVC = historyViewController {
            historyVC.willMove(toParent: nil)
            historyVC.view.removeFromSuperview()
            historyVC.removeFromParent()
            historyViewController = nil
        }

        suggestionsReader.tearDown()
        viewModel.clearAllChats()
    }
}
