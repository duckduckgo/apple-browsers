//
//  SuggestionContainer.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Combine
import Common
import Foundation
import History
import os.log
import PixelKit
import Suggestions

final class SuggestionContainer {

    static let maximumNumberOfSuggestions = 9

    @PublishedAfter var result: SuggestionResult?

    typealias OpenTabsProvider = @MainActor () -> [any Suggestions.BrowserTab]
    private let openTabsProvider: OpenTabsProvider

    protocol HistoryProvider {
        func history(for suggestionLoading: SuggestionLoading) -> [HistorySuggestion]
    }
    private let historyProvider: HistoryProvider

    protocol BookmarkProvider {
        func bookmarks(for suggestionLoading: SuggestionLoading) -> [Suggestions.Bookmark]
    }
    private let bookmarkProvider: BookmarkProvider

    private let startupPreferences: StartupPreferences
    private let featureFlagger: FeatureFlagger
    private let loading: SuggestionLoading
    private let burnerMode: BurnerMode
    private let windowControllersManager: WindowControllersManagerProtocol

    // Used for presenting the same suggestions after the removal of the local suggestion
    private(set) var suggestionDataCache: Data?

    private var latestQuery: String?

    private let urlSession: URLSession

    init(
        openTabsProvider: OpenTabsProvider? = nil,
        suggestionLoading: SuggestionLoading? = nil,
        urlSession: URLSession? = nil,
        historyProvider: HistoryProvider,
        bookmarkProvider: BookmarkProvider,
        startupPreferences: StartupPreferences = NSApp.delegateTyped.startupPreferences,
        featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
        burnerMode: BurnerMode,
        isUrlIgnored: @escaping (URL) -> Bool,
        windowControllersManager: WindowControllersManagerProtocol? = nil
    ) {
        let windowControllersManager = windowControllersManager ?? WindowControllersManager.shared
        self.openTabsProvider = openTabsProvider ?? Self.defaultOpenTabsProvider(burnerMode: burnerMode, windowControllersManager: windowControllersManager)
        self.bookmarkProvider = bookmarkProvider
        self.historyProvider = historyProvider
        self.startupPreferences = startupPreferences
        self.featureFlagger = featureFlagger
        self.loading = suggestionLoading ?? SuggestionLoader(urlFactory: URL.makeURL(fromSuggestionPhrase:), isUrlIgnored: isUrlIgnored)
        self.urlSession = urlSession ?? URLSession(configuration: .ephemeral)
        self.burnerMode = burnerMode
        self.windowControllersManager = windowControllersManager
    }

    @MainActor
    convenience init(burnerMode: BurnerMode, isUrlIgnored: @escaping (URL) -> Bool, windowControllersManager: WindowControllersManagerProtocol? = nil) {
        self.init(historyProvider: HistoryCoordinator.shared,
                  bookmarkProvider: LocalBookmarkManager.shared,
                  burnerMode: burnerMode,
                  isUrlIgnored: isUrlIgnored,
                  windowControllersManager: windowControllersManager)
    }

    func getSuggestions(for query: String, useCachedData: Bool = false) {
        latestQuery = query

        // Don't use cache by default
        if !useCachedData {
            suggestionDataCache = nil
        }

        loading.getSuggestions(query: query, usingDataSource: self) { [weak self] result, error in
            dispatchPrecondition(condition: .onQueue(.main))

            guard let self, self.latestQuery == query else { return }
            guard let result else {
                self.result = nil
                Logger.general.error("Suggestions: Failed to get suggestions - \(String(describing: error))")
                PixelKit.fire(DebugEvent(GeneralPixel.suggestionsFetchFailed, error: error))
                return
            }

            if let error = error {
                // Fetching remote suggestions failed but local can be presented
                Logger.general.error("Suggestions: Error when getting suggestions - \(error.localizedDescription)")
            }

            self.result = result
        }
    }

    func stopGettingSuggestions() {
        latestQuery = nil
    }

    private static func defaultOpenTabsProvider(burnerMode: BurnerMode, windowControllersManager: WindowControllersManagerProtocol) -> OpenTabsProvider {
        { @MainActor in
            let selectedTab = windowControllersManager.selectedTab
            let openTabViewModels = windowControllersManager.allTabViewModels(for: burnerMode, includingPinnedTabs: !burnerMode.isBurner)
            var usedUrls = Set<String>() // deduplicate
            return openTabViewModels.compactMap { model in
                guard model.tab !== selectedTab,
                      model.tab.content.isUrl
                        || model.tab.content.urlForWebView?.isSettingsURL == true
                        || model.tab.content.urlForWebView == .bookmarks,
                      let url = model.tab.content.userEditableUrl,
                      url != selectedTab?.content.userEditableUrl, // doesn‘t match currently selected
                      usedUrls.insert(url.nakedString ?? "").inserted == true /* if did not contain */ else { return nil }

                return OpenTab(tabId: model.tab.id, title: model.title, url: url)
            }
        }
    }

}

struct OpenTab: BrowserTab, Hashable {

    let tabId: String?
    let title: String
    let url: URL

}
extension HistoryCoordinator: SuggestionContainer.HistoryProvider {
    func history(for suggestionLoading: SuggestionLoading) -> [HistorySuggestion] {
        history ?? []
    }
}
extension LocalBookmarkManager: SuggestionContainer.BookmarkProvider {
    func bookmarks(for suggestionLoading: SuggestionLoading) -> [Suggestions.Bookmark] {
        list?.bookmarks() ?? []
    }
}
extension SuggestionContainer: SuggestionLoadingDataSource {

    var platform: Platform {
        return .desktop
    }

    func history(for suggestionLoading: SuggestionLoading) -> [HistorySuggestion] {
        return historyProvider.history(for: suggestionLoading)
    }

    @MainActor func internalPages(for suggestionLoading: Suggestions.SuggestionLoading) -> [Suggestions.InternalPage] {
        var result = [Suggestions.InternalPage]()
        let openTabs = windowControllersManager.allTabViewModels(for: burnerMode, includingPinnedTabs: !burnerMode.isBurner)
        var isSettingsOpened = false
        var isBookmarksOpened = false
        var isHistoryOpened = false
        // suggestions for Bookmarks&Settings if not Switch to Tab suggestions
        for tab in openTabs {
            if tab.tabContent == .bookmarks {
                isBookmarksOpened = true
            } else if case .settings = tab.tabContent {
                isSettingsOpened = true
            } else if case .history = tab.tabContent {
                isHistoryOpened = true
            }
            if isBookmarksOpened && isSettingsOpened && isHistoryOpened { break }
        }
        if !isBookmarksOpened {
            result.append(.init(title: UserText.bookmarks, url: .bookmarks))
        }
        if !isSettingsOpened {
            result.append(.init(title: UserText.settings, url: .settings))
        }
        if !isHistoryOpened {
            result.append(.init(title: UserText.mainMenuHistory, url: .history))
        }
        result += PreferencePaneIdentifier.allCases.map {
            // preference panes URLs
            .init(title: UserText.settings + " → " + $0.displayName, url: .settingsPane($0))
        }
        result += {
            guard startupPreferences.launchToCustomHomePage,
                  let homePage = URL(string: startupPreferences.formattedCustomHomePageURL) else { return [] }
            // home page suggestion
            return [.init(title: UserText.homePage, url: homePage)]
        }()
        return result
    }

    func bookmarks(for suggestionLoading: SuggestionLoading) -> [Suggestions.Bookmark] {
        bookmarkProvider.bookmarks(for: suggestionLoading)
    }

    @MainActor func openTabs(for suggestionLoading: any Suggestions.SuggestionLoading) -> [any Suggestions.BrowserTab] {
        guard featureFlagger.isFeatureOn(.autocompleteTabs) else { return [] }
        return openTabsProvider()
    }

    func suggestionLoading(_ suggestionLoading: SuggestionLoading,
                           suggestionDataFromUrl url: URL,
                           withParameters parameters: [String: String],
                           completion: @escaping (Data?, Error?) -> Void) {
        if let suggestionDataCache = suggestionDataCache {
            completion(suggestionDataCache, nil)
            return
        }

        let url = url.appendingParameters(parameters)
        var request = URLRequest.defaultRequest(with: url)
        request.timeoutInterval = 1

        urlSession.dataTask(with: request) { (data, _, error) in
            self.suggestionDataCache = data
            completion(data, error)
        }.resume()
    }

}

extension HistoryEntry: HistorySuggestion {

    public var numberOfVisits: Int {
        return numberOfTotalVisits
    }

}
