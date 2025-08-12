//
//  SuggestionTrayManager.swift
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

import Foundation
import UIKit
import Combine
import BrowserServicesKit
import Bookmarks
import Persistence
import History
import Suggestions
import Core
import AIChat

/// Dependencies required for the suggestion tray
struct SuggestionTrayDependencies {
    let favoritesViewModel: FavoritesListInteracting
    let bookmarksDatabase: CoreDataDatabase
    let historyManager: HistoryManaging
    let tabsModel: TabsModel
    let featureFlagger: FeatureFlagger
    let appSettings: AppSettings
    let aiChatSettings: AIChatSettingsProvider
    let newTabPageDependencies: SuggestionTrayViewController.NewTabPageDependencies
}

/// Protocol for handling suggestion tray events
protocol SuggestionTrayManagerDelegate: AnyObject {
    func suggestionTrayManager(_ manager: SuggestionTrayManager, didSelectSuggestion suggestion: Suggestion)
    func suggestionTrayManager(_ manager: SuggestionTrayManager, didSelectFavorite favorite: BookmarkEntity)
    func suggestionTrayManager(_ manager: SuggestionTrayManager, shouldUpdateTextTo text: String)
}

/// Manages the suggestion tray functionality including favorites and autocomplete
final class SuggestionTrayManager: NSObject {
    
    // MARK: - Properties
    
    weak var delegate: SuggestionTrayManagerDelegate?
    
    private let switchBarHandler: SwitchBarHandling
    private let dependencies: SuggestionTrayDependencies
    private var cancellables = Set<AnyCancellable>()
    
    private(set) var suggestionTrayViewController: SuggestionTrayViewController?

    var isShowingSuggestionTray: Bool {
        suggestionTrayViewController?.view.isHidden == false
    }

    var shouldDisplayFavoritesOverlay: Bool {
        let canDisplayFavorites = suggestionTrayViewController?.canShow(for: .favorites) ?? false
        let hasRemoteMessages = suggestionTrayViewController?.hasRemoteMessages ?? false

        return !shouldDisplaySuggestionTray && (canDisplayFavorites || hasRemoteMessages)
    }

    var shouldDisplaySuggestionTray: Bool {
        let query = switchBarHandler.currentText
        // No text so don't show suggestins
        guard !query.isBlank else { return false }

        // For URLs, only show suggestions if the user has interacted with the text
        if switchBarHandler.isCurrentTextValidURL {
            return switchBarHandler.hasUserInteractedWithText
        }

        // For all other cases just show suggestions
        return true
    }

    // MARK: - Initialization
    
    init(switchBarHandler: SwitchBarHandling, dependencies: SuggestionTrayDependencies) {
        self.switchBarHandler = switchBarHandler
        self.dependencies = dependencies
        super.init()
        setupBindings()
    }
    
    // MARK: - Public Methods
    
    /// Installs the suggestion tray in the provided container view
    func installInContainerView(_ containerView: UIView, parentViewController: UIViewController) {
        guard suggestionTrayViewController == nil else { return }
        
        let storyboard = UIStoryboard(name: "SuggestionTray", bundle: nil)
        
        guard let controller = storyboard.instantiateInitialViewController(creator: { coder in
            SuggestionTrayViewController(
                coder: coder,
                favoritesViewModel: self.dependencies.favoritesViewModel,
                bookmarksDatabase: self.dependencies.bookmarksDatabase,
                historyManager: self.dependencies.historyManager,
                tabsModel: self.dependencies.tabsModel,
                featureFlagger: self.dependencies.featureFlagger,
                appSettings: self.dependencies.appSettings,
                aiChatSettings: self.dependencies.aiChatSettings,
                newTabPageDependencies: self.dependencies.newTabPageDependencies
            )
        }) else {
            assertionFailure("Failed to instantiate SuggestionTrayViewController")
            return
        }

        controller.coversFullScreen = true
        controller.isUsingSearchInputCustomStyling = true

        parentViewController.addChild(controller)
        containerView.addSubview(controller.view)
        suggestionTrayViewController = controller

        controller.view.translatesAutoresizingMaskIntoConstraints = false

        // Prevent flash during initial load
        controller.view.isHidden = true

        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.bottomAnchor)
        ])

        controller.autocompleteDelegate = self
        controller.favoritesOverlayDelegate = self
        controller.newTabPageControllerDelegate = self
        controller.didMove(toParent: parentViewController)

        showInitialSuggestions()
        containerView.layoutIfNeeded()
    }
    
    /// Handles query updates and shows appropriate suggestions
    func handleQueryUpdate(_ query: String) {
        guard switchBarHandler.currentToggleState == .search else { return }

        updateSuggestionTrayForCurrentState()
    }
    
    /// Shows the suggestion tray for the initial selected state
    func showInitialSuggestions() {
        updateSuggestionTrayForCurrentState()
    }
    
    // MARK: - Private Methods

    private func setupBindings() {
        switchBarHandler.toggleStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self = self else { return }
                
                switch newState {
                case .search:
                    self.updateSuggestionTrayForCurrentState()
                case .aiChat:
                    break
                }
            }
            .store(in: &cancellables)
        
        switchBarHandler.hasUserInteractedWithTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.switchBarHandler.currentToggleState == .search {
                    self.updateSuggestionTrayForCurrentState()
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateSuggestionTrayForCurrentState() {
        if shouldDisplaySuggestionTray {
            let query = switchBarHandler.currentText
            showSuggestionTray(.autocomplete(query: query))
        } else {
            showSuggestionTray(.favorites)
        }
    }
    
    private func showSuggestionTray(_ type: SuggestionTrayViewController.SuggestionType) {
        guard let suggestionTray = suggestionTrayViewController else { return }
        
        let canShowSuggestion =
            suggestionTray.canShow(for: type) ||
            (type == .favorites && suggestionTray.hasRemoteMessages)

        if canShowSuggestion {
            suggestionTray.fill()
            suggestionTray.show(for: type, animated: false)
            suggestionTray.view.isHidden = false
        } else {
            suggestionTray.view.isHidden = true
        }
    }
    
    private func extractText(from suggestion: Suggestion) -> String? {
        switch suggestion {
        case .phrase(let phrase):
            return phrase
        case .website(let url):
            return extractTextFromURL(url)
        case .bookmark(let title, _, _, _):
            return title
        case .historyEntry(let title, _, _):
            return title
        case .openTab:
            return nil
        case .unknown(let value),
                .internalPage(let value, _, _):
            assertionFailure("Unexpected suggestion type: \(value)")
            return nil
        }
    }
    
    private func extractTextFromURL(_ url: URL) -> String? {
        if url.isDuckDuckGoSearch, let query = url.searchQuery {
            return query
        }
        
        if url.isBookmarklet() {
            return nil
        }
        return url.absoluteString
    }
}

// MARK: - AutocompleteViewControllerDelegate

extension SuggestionTrayManager: AutocompleteViewControllerDelegate {
    
    func autocompleteDidEndWithUserQuery() {
    }
    
    func autocomplete(selectedSuggestion suggestion: Suggestion) {
        delegate?.suggestionTrayManager(self, didSelectSuggestion: suggestion)
    }
    
    func autocomplete(highlighted suggestion: Suggestion, for query: String) {
    }
    
    func autocomplete(pressedPlusButtonForSuggestion suggestion: Suggestion) {
        guard let textToUpdate = extractText(from: suggestion) else { return }
        delegate?.suggestionTrayManager(self, shouldUpdateTextTo: textToUpdate)
    }
    
    func autocompleteWasDismissed() {
    }
}

// MARK: - FavoritesOverlayDelegate

extension SuggestionTrayManager: FavoritesOverlayDelegate {
    
    func favoritesOverlay(_ overlay: FavoritesOverlay, didSelect favorite: BookmarkEntity) {
        delegate?.suggestionTrayManager(self, didSelectFavorite: favorite)
    }
}

// MARK: - NewTabPageControllerDelegate

extension SuggestionTrayManager: NewTabPageControllerDelegate {

    func newTabPageDidSelectFavorite(_ controller: NewTabPageViewController, favorite: BookmarkEntity) {
        delegate?.suggestionTrayManager(self, didSelectFavorite: favorite)
    }
    
    func newTabPageDidDeleteFavorite(_ controller: NewTabPageViewController, favorite: Bookmarks.BookmarkEntity) {
        assertionFailure("Unexpected")
    }
    
    func newTabPageDidEditFavorite(_ controller: NewTabPageViewController, favorite: Bookmarks.BookmarkEntity) {
        assertionFailure("Unexpected")
    }
    
    func newTabPageDidRequestFaviconsFetcherOnboarding(_ controller: NewTabPageViewController) {
        // no-op this is handled by the main view controller on a real new tab page
    }

}
