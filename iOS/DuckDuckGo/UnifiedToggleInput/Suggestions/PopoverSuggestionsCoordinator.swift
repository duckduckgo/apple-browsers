//
//  PopoverSuggestionsCoordinator.swift
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
import BrowserServicesKit
import Combine
import Core
import History
import Persistence
import PrivacyConfig

/// The view operations the coordinator drives to present its decision. Implemented by the owner
/// (`MainViewController`), which reveals/hides the popover container and shows the favorites grid.
@MainActor
protocol PopoverSuggestionsHosting: AnyObject {
    /// Reveal the search autocomplete list for `query` (anchored under the collapsed bar).
    func showPopoverSearchList(query: String)
    /// Reveal the Duck.ai list for `query` (anchored under the expanded input box).
    func showPopoverDuckAIList(query: String)
    /// Show the favorites (NTP) grid; returns false when there are none to show.
    @discardableResult func showPopoverFavorites() -> Bool
    /// Hide the popover container, keeping the list surfaces alive.
    func hidePopover()
}

/// Owns the iPad popover's suggestion *decision* and its Duck.ai surface lifecycle: from the current
/// mode + query it tells the host what to present, and builds/feeds the Duck.ai source. The tray hosts
/// the list views; the host reveals the container. Centralising the decision here keeps the surfaces
/// from racing each other across toggles, edits, and tab switches.
@MainActor
final class PopoverSuggestionsCoordinator {

    struct Dependencies {
        let historyManager: HistoryManaging
        let bookmarksDatabase: CoreDataDatabase
        let featureFlagger: FeatureFlagger
        let aiChatSettings: AIChatSettingsProvider
        let privacyConfigurationManager: PrivacyConfigurationManaging
        let aiChatSyncCleaner: AIChatSyncCleaning?
        let duckAiNativeStorageHandler: DuckAiNativeStorageHandling?
        let tabsModelProvider: () -> TabsModelManaging?
        let isFireTab: () -> Bool
    }

    private let dependencies: Dependencies
    private weak var tray: SuggestionTrayViewController?
    private weak var host: PopoverSuggestionsHosting?
    /// Routes Duck.ai row taps to navigation (the tray resolves the row id, the delegate navigates).
    private weak var navigationDelegate: SuggestionTrayDuckAINavigationDelegate?

    private var duckAIQuerySubject: CurrentValueSubject<String, Never>?
    /// Cached so the async Duck.ai content callback can re-apply the same surface once recents/URLs land.
    private var lastSurface: IPadOmnibarFocusModel.Surface = .none
    /// Guards against re-entrancy: building the Duck.ai surface can emit sections synchronously, which
    /// re-fires the content callback into `present` mid-setup. The re-entrant call is a no-op.
    private var isPresenting = false

    init(dependencies: Dependencies,
         tray: SuggestionTrayViewController,
         host: PopoverSuggestionsHosting,
         navigationDelegate: SuggestionTrayDuckAINavigationDelegate) {
        self.dependencies = dependencies
        self.tray = tray
        self.host = host
        self.navigationDelegate = navigationDelegate
    }

    /// Applies a surface decided by `IPadOmnibarFocusModel`. The only runtime concern left here is the
    /// async Duck.ai content gate: the query is always fed (so recents/URLs fetch), and the list is shown
    /// only once it has rows — the content callback re-applies this surface when they arrive.
    func present(_ surface: IPadOmnibarFocusModel.Surface) {
        let isUnchanged = surface == lastSurface
        lastSurface = surface
        guard !isPresenting else { return }
        // Re-applying an identical surface only matters for Duck.ai, whose recents/URLs arrive async and
        // re-trigger this to re-check for rows. For favorites/search it's a no-op that visibly re-shows
        // (flashes) the popover, so skip it.
        if isUnchanged {
            guard case .duckAISuggestions = surface else { return }
        }
        isPresenting = true
        defer { isPresenting = false }

        ensureSurfaces()
        guard let tray, let host else { return }

        switch surface {
        case .none:
            host.hidePopover()
        case .favorites:
            tray.setPopoverMode(.search)
            if !host.showPopoverFavorites() { host.hidePopover() }
        case .searchSuggestions(let query):
            tray.setPopoverMode(.search)
            host.showPopoverSearchList(query: query)
        case .duckAISuggestions(let query):
            tray.setPopoverMode(.duckAI)
            tray.updatePopoverDuckAIQuery(query)
            if tray.popoverDuckAIHasContent {
                host.showPopoverDuckAIList(query: query)
            } else {
                host.hidePopover()
            }
        }
    }

    /// Tears down both surfaces (on dismiss or tab switch) so the next session rebuilds fresh.
    func teardown() {
        tray?.teardownPopoverSuggestions()
        duckAIQuerySubject = nil
        lastSurface = .none
    }

    /// Builds the search + Duck.ai surfaces once per focus session (idempotent). Search is built by the
    /// tray; the Duck.ai surface (recents + URL hits + Search row, like iPhone) is built here.
    private func ensureSurfaces() {
        guard let tray, let tabsModel = dependencies.tabsModelProvider() else { return }
        tray.preparePopoverSearchController()
        guard !tray.hasPopoverDuckAISource else { return }

        let (chatManager, chatViewModel) = AIChatHistoryManager.makeHistoryManager(
            isFireTab: dependencies.isFireTab(),
            isIPadExperience: true,
            featureFlagger: dependencies.featureFlagger,
            privacyConfigurationManager: dependencies.privacyConfigurationManager,
            chatSyncCleaner: dependencies.aiChatSyncCleaner,
            chatSettings: dependencies.aiChatSettings,
            nativeStorageHandler: dependencies.duckAiNativeStorageHandler)

        let requestRunner = AutocompleteRequestRunner()
        let dataSource = AutocompleteSuggestionsDataSource(
            historyManager: dependencies.historyManager,
            bookmarksDatabase: dependencies.bookmarksDatabase,
            featureFlagger: dependencies.featureFlagger,
            tabsModel: tabsModel
        ) { request, completion in
            requestRunner.run(request, completion: completion)
        }
        let urlLoader = DuckAIURLSuggestionsLoader(dataSource: dataSource)
        let querySubject = CurrentValueSubject<String, Never>("")
        duckAIQuerySubject = querySubject
        let source = DuckAISuggestionsSource(
            chatViewModel: chatViewModel,
            urlLoader: urlLoader,
            chatManager: chatManager,
            query: { querySubject.value },
            deleteEnabled: { [featureFlagger = dependencies.featureFlagger] in featureFlagger.isFeatureOn(.removeChatHistory) })

        tray.duckAINavigationDelegate = navigationDelegate
        // Duck.ai content arrives asynchronously; re-apply only while a Duck.ai surface is current. In
        // search mode the source is alive but irrelevant — a late fetch must not clobber the decision.
        tray.onPopoverDuckAIContentChanged = { [weak self] _ in
            guard let self, case .duckAISuggestions = self.lastSurface else { return }
            self.present(self.lastSurface)
        }
        tray.setPopoverDuckAISource(source, querySubject: querySubject)
    }
}
