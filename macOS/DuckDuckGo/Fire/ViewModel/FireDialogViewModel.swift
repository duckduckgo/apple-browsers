//
//  FireDialogViewModel.swift
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

import Cocoa
import Combine
import BrowserServicesKit
import Common
import History
import HistoryView
import PixelKit

@MainActor
final class FireDialogViewModel: ObservableObject {

    enum ClearingOption: Int, CaseIterable {

        case currentTab
        case currentWindow
        case allData

        var string: String {
            switch self {
            case .currentTab: return UserText.currentTab
            case .currentWindow: return UserText.currentWindow
            case .allData: return UserText.allData
            }
        }

        var shouldShowChatHistoryToggle: Bool {
            switch self {
            case .allData: return true
            case .currentTab, .currentWindow: return false
            }
        }

    }

    enum Mode: Equatable {
        case fireButton
        case mainMenuAll
        case historyView(query: DataModel.HistoryQueryKind)

        /// Show Tab/Window/All Data segmented pill control only for fire button/MainMenu entry point
        var shouldShowSegmentedControl: Bool {
            switch self {
            case .fireButton, .mainMenuAll: return true
            case .historyView: return false
            }
        }

        /// Show Close Tabs/Windows toggle?
        var shouldShowCloseTabsToggle: Bool {
            switch self {
            case .fireButton, .mainMenuAll,
                 .historyView(query: .rangeFilter(.today)),
                 .historyView(query: .rangeFilter(.all)),
                 .historyView(query: .rangeFilter(.allSites)):
                return true
            case .historyView:
                return false
            }
        }

        var shouldShowChatHistoryToggle: Bool {
            switch self {
            case .fireButton,
                    .mainMenuAll,
                    .historyView(query: .rangeFilter(.all)):
                return true
            case .historyView:
                return false
            }
        }

        /// Hide fireproof section when dialog is scoped to specific site(s)
        var shouldShowFireproofSection: Bool {
            switch self {
            case .historyView(query: .domainFilter), .historyView(query: .visits):
                return false
            case .fireButton, .mainMenuAll, .historyView:
                return true
            }
        }

        /// Compute custom title for dialog based on mode (when applicable)
        var dialogTitle: String {
            let title = switch self {
            case .fireButton: UserText.fireDialogTitle
            case .mainMenuAll,
                 .historyView(query: .rangeFilter(.all)),
                 .historyView(query: .rangeFilter(.allSites)): HistoryViewDeleteDialogModel.DeleteMode.all.title
            case .historyView(query: .rangeFilter(.today)): HistoryViewDeleteDialogModel.DeleteMode.today.title
            case .historyView(query: .rangeFilter(.yesterday)): HistoryViewDeleteDialogModel.DeleteMode.yesterday.title
            case .historyView(query: .dateFilter(let date)): HistoryViewDeleteDialogModel.DeleteMode.date(date).title
            case .historyView(query: .domainFilter(let domains)): HistoryViewDeleteDialogModel.DeleteMode.sites(domains).title
            case .historyView(query: .rangeFilter(.older)): HistoryViewDeleteDialogModel.DeleteMode.older.title
            case .historyView: UserText.fireDialogTitle
            }
            return title.replacingOccurrences(of: #"\n"#, with: " ")
        }
    }

    struct Item {
        var domain: String
        var favicon: NSImage?
    }

    /// Remember last selected scope
    static var lastSelectedClearingOption: ClearingOption = .currentTab
    static var lastIncludeTabsAndWindowsState: Bool = true
    static var lastIncludeHistoryState: Bool = true
    static var lastIncludeCookiesAndSiteDataState: Bool = true
    static var lastIncludeChatHistoryState: Bool = false

    /// Reset persisted UI defaults - used for tests
    static func resetPersistedDefaults() {
        lastSelectedClearingOption = .currentTab
        lastIncludeTabsAndWindowsState = true
        lastIncludeHistoryState = true
        lastIncludeCookiesAndSiteDataState = true
        lastIncludeChatHistoryState = false
    }

    init(fireViewModel: FireViewModel,
         tabCollectionViewModel: TabCollectionViewModel,
         historyCoordinating: HistoryCoordinating,
         aiChatHistoryCleaner: AIChatHistoryCleaning,
         fireproofDomains: FireproofDomains,
         faviconManagement: FaviconManagement,
         clearingOption: ClearingOption? = nil,
         includeTabsAndWindows: Bool? = nil,
         includeHistory: Bool? = nil,
         includeCookiesAndSiteData: Bool? = nil,
         includeChatHistory: Bool? = nil,
         mode: Mode = .fireButton,
         scopeCookieDomains: Set<String>? = nil,
         scopeVisits: [Visit]? = nil,
         tld: TLD) {

        self.fireViewModel = fireViewModel
        self.tabCollectionViewModel = tabCollectionViewModel
        self.fireproofDomains = fireproofDomains
        self.faviconManagement = faviconManagement
        self.historyCoordinating = historyCoordinating
        self.aiChatHistoryCleaner = aiChatHistoryCleaner
        self.clearingOption = clearingOption ?? Self.lastSelectedClearingOption
        self.includeTabsAndWindows = includeTabsAndWindows ?? Self.lastIncludeTabsAndWindowsState
        self.includeHistory = includeHistory ?? Self.lastIncludeHistoryState
        self.includeCookiesAndSiteData = includeCookiesAndSiteData ?? Self.lastIncludeCookiesAndSiteDataState
        self.includeChatHistorySetting = includeChatHistory ?? Self.lastIncludeChatHistoryState

        self.tld = tld
        self.mode = mode
        self.scopeVisits = scopeVisits

        // Apply provided scope domains BEFORE computing lists to avoid any flash
        self.scopeCookieDomains = scopeCookieDomains

        // Initialize selectable/fireproofed lists so counts are available immediately
        updateItems(for: self.clearingOption)
    }

    private(set) var shouldShowPinnedTabsInfo: Bool = false

    var shouldShowChatHistoryToggle: Bool {
        let isPresentedOnAIChatTab = tabCollectionViewModel?.selectedTab?.url?.isDuckAIURL ?? false
        return aiChatHistoryCleaner.shouldDisplayCleanAIChatHistoryOption
            && mode.shouldShowChatHistoryToggle
            && (clearingOption.shouldShowChatHistoryToggle || isPresentedOnAIChatTab)
    }

    let fireViewModel: FireViewModel
    private(set) weak var tabCollectionViewModel: TabCollectionViewModel?
    private let fireproofDomains: FireproofDomains
    private let faviconManagement: FaviconManagement
    private let historyCoordinating: HistoryCoordinating
    private let aiChatHistoryCleaner: AIChatHistoryCleaning
    let tld: TLD
    let mode: Mode
    private let scopeVisits: [Visit]?

    private(set) var hasOnlySingleFireproofDomain: Bool = false

    var clearingOption: ClearingOption {
        didSet {
            updateItems(for: clearingOption)
            Self.lastSelectedClearingOption = clearingOption
        }
    }

    /// when true, selected tabs/windows are closed; when false, tabs remain open, but their history/session state is cleared if includeHistory is true.
    @Published var includeTabsAndWindows: Bool {
        didSet {
            Self.lastIncludeTabsAndWindowsState = includeTabsAndWindows
        }
    }
    /// when true, history is cleared for the selected scope.
    @Published var includeHistory: Bool {
        didSet {
            Self.lastIncludeHistoryState = includeHistory
        }
    }
    /// when true, cookies/site data are cleared for the selected (non-fireproof) domains in scope.
    @Published var includeCookiesAndSiteData: Bool {
        didSet {
            Self.lastIncludeCookiesAndSiteDataState = includeCookiesAndSiteData
        }
    }
    /// When true, all Duck.ai chat history is cleared.
    /// Use this property (not `includeChatHistorySetting`) to perform the data clearing.
    var includeChatHistory: Bool {
        shouldShowChatHistoryToggle && includeChatHistorySetting
    }
    /// Persisted user setting to clear chat history.
    /// Do not use this property directly to perform the data clearing; use `includeChatHistory` instead.
    @Published var includeChatHistorySetting: Bool {
        didSet {
            Self.lastIncludeChatHistoryState = includeChatHistorySetting
        }
    }

    @Published private(set) var selectable: [Item] = []
    @Published private(set) var fireproofed: [Item] = []
    @Published private(set) var selected: Set<Int> = []
    @Published private(set) var historyVisits: [Visit] = []

    var isPinnedTabSelected: Bool {
        tabCollectionViewModel?.selectedTabViewModel?.tab.isPinned ?? false
    }

    // Determine if pinned tabs are present in the current scope
    var hasPinnedTabsInScope: Bool {
        guard let tabCollectionViewModel else { return false }

        switch clearingOption {
        case .currentTab:
            // For currentTab scope: only if the selected tab itself is pinned
            return isPinnedTabSelected

        case .currentWindow:
            // For currentWindow scope: if current window has pinned tabs
            if let pinnedTabsManager = tabCollectionViewModel.pinnedTabsManager,
               !pinnedTabsManager.isEmpty {
                return true
            }
            return false

        case .allData:
            // For allData scope: if ANY pinned tabs exist globally
            if let provider = tabCollectionViewModel.pinnedTabsManagerProvider {
                return !provider.arePinnedTabsEmpty
            }
            return false
        }
    }

    // Get the appropriate pinned tabs message for the current scope
    var pinnedTabsReloadMessage: String? {
        guard hasPinnedTabsInScope, let tabCollectionViewModel else { return nil }

        let count: Int
        switch clearingOption {
        case .currentTab:
            // For currentTab: count is 1 if the selected tab is pinned
            count = isPinnedTabSelected ? 1 : 0
        case .currentWindow:
            // For currentWindow: count pinned tabs in current window
            count = tabCollectionViewModel.pinnedTabsManager?.tabCollection.tabs.count ?? 0
        case .allData:
            // For allData: count all pinned tabs globally
            if let provider = tabCollectionViewModel.pinnedTabsManagerProvider {
                count = provider.currentPinnedTabManagers.reduce(0) { $0 + $1.tabCollection.tabs.count }
            } else {
                count = 0
            }
        }

        guard count > 0 else { return nil }
        return count == 1 ? UserText.fireDialogPinnedTabWillReload : UserText.fireDialogPinnedTabsWillReload
    }

    let selectableSectionIndex = 0
    let fireproofedSectionIndex = 1

    // MARK: - Options

    let scopeCookieDomains: Set<String>?

    private func updateItems(for clearingOption: ClearingOption) {

        func visitedDomains(basedOn clearingOption: ClearingOption) -> Set<String> {
            switch clearingOption {
            case .currentTab:
                guard let tab = tabCollectionViewModel?.selectedTabViewModel?.tab else {
                    assertionFailure("No tab selected")
                    return Set<String>()
                }
                return tab.localHistoryDomains
            case .currentWindow:
                guard let tabCollectionViewModel = tabCollectionViewModel else {
                    return []
                }
                return tabCollectionViewModel.localHistoryDomains
            case .allData:
                if let scopeCookieDomains { return scopeCookieDomains }
                // Fallback: get all domains from history
                return historyCoordinating.history?.visitedDomains(tld: tld) ?? Set<String>()
            }
        }

        let visitedETLDPlus1Domains: Set<String> = {
            let visitedDomains = visitedDomains(basedOn: clearingOption)
            return Set(visitedDomains.compactMap { tld.eTLDplus1($0) })
        }()

        let fireproofed = visitedETLDPlus1Domains
            .filter { domain in
                fireproofDomains.isFireproof(fireproofDomain: domain)
            }
        let selectable = visitedETLDPlus1Domains
            .subtracting(fireproofed)

        self.selectable = selectable
            .map { Item(domain: $0, favicon: faviconManagement.getCachedFavicon(forDomainOrAnySubdomain: $0, sizeCategory: .small)?.image) }
            .sorted { $0.domain < $1.domain }
        self.fireproofed = fireproofed
            .map { Item(domain: $0, favicon: faviconManagement.getCachedFavicon(forDomainOrAnySubdomain: $0, sizeCategory: .small)?.image) }
            .sorted { $0.domain < $1.domain }

        selectAll()

        // Update history visits for current scope
        switch clearingOption {
        case .allData:
            self.historyVisits = scopeVisits ?? historyCoordinating.allHistoryVisits ?? []
        case .currentTab:
            self.historyVisits = tabCollectionViewModel?.selectedTabViewModel?.tab.localHistory ?? []
        case .currentWindow:
            self.historyVisits = tabCollectionViewModel?.localHistory ?? []
        }
    }

    // MARK: - Counts for subtitles

    var historyItemsCountForCurrentScope: Int { historyVisits.count }

    /// Cookies/sites are deleted for non-fireproofed visited eTLD+1 domains
    var cookiesSitesCountForCurrentScope: Int { selectable.count }

    // MARK: - Selection

    /// Public accessor to the currently selected cookie/site-data domains (eTLD+1)
    var selectedCookieDomainsForScope: Set<String> {
        selectedDomains
    }

    var areAllSelected: Bool {
        Set(0..<selectable.count) == selected
    }

    private func selectAll() {
        self.selected = Set(0..<selectable.count)
    }

    func select(index: Int) {
        guard index < selectable.count, index >= 0 else {
            assertionFailure("Index out of range")
            return
        }
        selected.insert(index)
    }

    func deselect(index: Int) {
        guard index < selectable.count, index >= 0 else {
            assertionFailure("Index out of range")
            return
        }
        selected.remove(index)
    }

    private var selectedDomains: Set<String> {
        return Set<String>(selected.compactMap {
            guard let selectedDomain = selectable[safe: $0]?.domain else {
                assertionFailure("Wrong index")
                return nil
            }
            return selectedDomain
        })
    }

}

extension BrowsingHistory {

    func visitedDomains(tld: TLD) -> Set<String> {
        return reduce(Set<String>(), { result, historyEntry in
            if let host = historyEntry.url.host, let eTLDPlus1Domain = tld.eTLDplus1(host) {
                return result.union([eTLDPlus1Domain])
            } else {
                return result
            }
        })
    }

}
