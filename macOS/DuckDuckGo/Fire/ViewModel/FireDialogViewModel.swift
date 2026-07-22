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
import FoundationExtensions
import History
import HistoryView
import Persistence
import PixelKit
import PrivacyConfig

struct FireDialogViewSettings: StoringKeys {
    let lastSelectedClearingOption = StorageKey<FireDialogViewModel.ClearingOption>(.fireDialogSelectedClearingOption)
    let lastIncludeTabsAndWindowsState = StorageKey<Bool>(.fireDialogIncludeTabsAndWindows)
    let lastIncludeHistoryState = StorageKey<Bool>(.fireDialogIncludeHistory)
    let lastIncludeCookiesAndSiteDataState = StorageKey<Bool>(.fireDialogIncludeCookiesAndSiteData)
    let lastIncludeChatHistoryState = StorageKey<Bool>(.fireDialogIncludeChatHistory)
}

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

        var description: String {
            switch self {
            case .currentTab: return "current_tab"
            case .currentWindow: return "current_window"
            case .allData: return "all_data"
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
    private var settings: any KeyedStoring<FireDialogViewSettings>

    init(fireViewModel: FireViewModel,
         tabCollectionViewModel: TabCollectionViewModel,
         historyCoordinating: HistoryCoordinating,
         aiChatHistoryCleaner: AIChatHistoryCleaning,
         fireproofDomains: FireproofDomains,
         faviconManagement: FaviconManagement,
         featureFlagger: FeatureFlagger,
         clearingOption: ClearingOption? = nil,
         includeTabsAndWindows: Bool? = nil,
         includeHistory: Bool? = nil,
         includeCookiesAndSiteData: Bool? = nil,
         includeChatHistory: Bool? = nil,
         mode: Mode = .fireButton,
         settings: (any KeyedStoring<FireDialogViewSettings>)? = nil,
         scopeCookieDomains: Set<String>? = nil,
         scopeVisits: [Visit]? = nil,
         tld: TLD,
         windowControllersManager: WindowControllersManagerProtocol,
         dataClearingPreferences: DataClearingPreferences,
         pixelFiring: PixelFiring?) {

        self.fireViewModel = fireViewModel
        self.tabCollectionViewModel = tabCollectionViewModel
        self.fireproofDomains = fireproofDomains
        self.faviconManagement = faviconManagement
        self.featureFlagger = featureFlagger
        self.historyCoordinating = historyCoordinating
        self.aiChatHistoryCleaner = aiChatHistoryCleaner
        self.windowControllersManager = windowControllersManager
        self.dataClearingPreferences = dataClearingPreferences
        self.pixelFiring = pixelFiring

        self.tld = tld
        self.mode = mode
        self.scopeVisits = scopeVisits

        // Apply provided scope domains BEFORE computing lists to avoid any flash
        self.scopeCookieDomains = scopeCookieDomains

        self.settings = if let settings { settings } else { UserDefaults.standard.keyedStoring() }
        self.clearingOption = clearingOption ?? self.settings.lastSelectedClearingOption ?? .currentTab
        self.includeTabsAndWindows = includeTabsAndWindows ?? self.settings.lastIncludeTabsAndWindowsState ?? true
        self.includeHistory = includeHistory ?? self.settings.lastIncludeHistoryState ?? true
        self.includeCookiesAndSiteData = includeCookiesAndSiteData ?? self.settings.lastIncludeCookiesAndSiteDataState ?? true
        self.includeChatHistorySetting = includeChatHistory ?? self.settings.lastIncludeChatHistoryState ?? false

        updateLastSelectedClearingOptionIfNeeded()

        // Initialize selectable/fireproofed lists so counts are available immediately
        updateItems(for: self.clearingOption)
    }

    private func updateLastSelectedClearingOptionIfNeeded() {
        guard featureFlagger.isFeatureOn(.fireDialogSimplified), clearingOption == .currentWindow else {
            return
        }
        self.clearingOption = .allData
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
    private let featureFlagger: FeatureFlagger
    private let historyCoordinating: HistoryCoordinating
    private let aiChatHistoryCleaner: AIChatHistoryCleaning
    private let windowControllersManager: WindowControllersManagerProtocol
    private let dataClearingPreferences: DataClearingPreferences
    let pixelFiring: PixelFiring?
    let tld: TLD
    let mode: Mode
    private let scopeVisits: [Visit]?

    private(set) var hasOnlySingleFireproofDomain: Bool = false

    var clearingOption: ClearingOption {
        didSet {
            updateItems(for: clearingOption)
            settings.lastSelectedClearingOption = clearingOption
            pixelFiring?.fire(FireDialogPixel.fireDialogToggleMode, frequency: .dailyAndCount, doNotEnforcePrefix: true)
        }
    }

    /// when true, selected tabs/windows are closed; when false, tabs remain open, but their history/session state is cleared if includeHistory is true.
    @Published var includeTabsAndWindows: Bool {
        didSet {
            settings.lastIncludeTabsAndWindowsState = includeTabsAndWindows
            pixelFiring?.fire(FireDialogPixel.fireDialogChangeSettings, frequency: .uniqueByName, doNotEnforcePrefix: true)
            pixelFiring?.fire(FireDialogPixel.fireDialogToggleCloseTabs, frequency: .dailyAndCount, doNotEnforcePrefix: true)
        }
    }
    /// when true, history is cleared for the selected scope.
    @Published var includeHistory: Bool {
        didSet {
            settings.lastIncludeHistoryState = includeHistory
            pixelFiring?.fire(FireDialogPixel.fireDialogChangeSettings, frequency: .uniqueByName, doNotEnforcePrefix: true)
            pixelFiring?.fire(FireDialogPixel.fireDialogToggleClearHistory, frequency: .dailyAndCount, doNotEnforcePrefix: true)
        }
    }
    /// when true, cookies/site data are cleared for the selected (non-fireproof) domains in scope.
    @Published var includeCookiesAndSiteData: Bool {
        didSet {
            settings.lastIncludeCookiesAndSiteDataState = includeCookiesAndSiteData
            pixelFiring?.fire(FireDialogPixel.fireDialogChangeSettings, frequency: .uniqueByName, doNotEnforcePrefix: true)
            pixelFiring?.fire(FireDialogPixel.fireDialogToggleClearSiteData, frequency: .dailyAndCount, doNotEnforcePrefix: true)
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
            settings.lastIncludeChatHistoryState = includeChatHistorySetting
            pixelFiring?.fire(FireDialogPixel.fireDialogChangeSettings, frequency: .uniqueByName, doNotEnforcePrefix: true)
            pixelFiring?.fire(FireDialogPixel.fireDialogToggleClearAIChats, frequency: .dailyAndCount, doNotEnforcePrefix: true)
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
                return historyCoordinating.history?.lazy.compactMap(\.url.host).convertedToETLDPlus1(tld: tld) ?? []
            }
        }

        let visitedETLDPlus1Domains = visitedDomains(basedOn: clearingOption).convertedToETLDPlus1(tld: tld)

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

    // MARK: - More Options menu

    /// Opens a new Fire window and dismisses the dialog.
    func openNewFireWindow() {
        dismissDialog()
        windowControllersManager.openNewWindow(burnerMode: BurnerMode(isBurner: true))
    }

    /// Presents the Manage Fireproof Sites dialog stacked above the Fire dialog, then refreshes the scope.
    func showManageFireproofSites() {
        pixelFiring?.fire(FireDialogPixel.fireDialogManageFireproofedSites, frequency: .dailyAndCount, doNotEnforcePrefix: true)
        Task { @MainActor in
            await dataClearingPreferences.presentManageFireproofSitesDialog()
            // Refresh selectable/fireproofed lists in case fireproofing changed.
            updateItems(for: clearingOption)
        }
    }

    /// Dismisses the dialog and opens the per-site history/deletion view.
    func deleteIndividualSites() {
        pixelFiring?.fire(FireDialogPixel.fireDialogDeleteIndividualSitesClicked, frequency: .dailyAndCount, doNotEnforcePrefix: true)
        dismissDialog()
        windowControllersManager.lastKeyMainWindowController?
            .mainViewController
            .browserTabViewController
            .openNewTab(with: .history(pane: .allSites))
    }

    /// Dismisses the dialog and opens Settings → Data Clearing.
    func openDataDeletionSettings() {
        dismissDialog()
        windowControllersManager.showTab(with: .settings(pane: .dataClearing))
    }

    private func dismissDialog() {
        guard let window = windowControllersManager.lastKeyMainWindowController?.window else { return }
        window.endSheet(window.attachedSheet ?? window)
    }

    /// Host of the currently selected tab's user-editable URL, or `nil` when it can't be fireproofed.
    ///
    /// Uses `userEditableUrl` (like the address bar's more-options menu) rather than the resolved
    /// tab URL so Duck Player — and other non-web tabs — are correctly excluded: on a Duck Player
    /// tab `userEditableUrl` is a `duck://player/…` URL, which is not fireproofable.
    private var fireproofableCurrentHost: String? {
        guard let url = tabCollectionViewModel?.selectedTabViewModel?.tab.content.userEditableUrl,
              url.canFireproof, let host = url.host else { return nil }
        return host
    }

    /// Whether the "Fireproof This Site" menu item should be enabled for the current site.
    var canFireproofCurrentSite: Bool {
        fireproofableCurrentHost != nil
    }

    /// Whether the currently selected site is already fireproofed.
    var isCurrentSiteFireproof: Bool {
        guard let host = fireproofableCurrentHost else { return false }
        return fireproofDomains.isFireproof(fireproofDomain: host)
    }

    /// Toggles fireproofing for the currently selected site and refreshes the scope.
    func toggleCurrentSiteFireproofing() {
        guard let host = fireproofableCurrentHost else { return }
        _ = fireproofDomains.toggle(domain: host)
        // Refresh selectable/fireproofed lists and counts to reflect the change
        updateItems(for: clearingOption)
    }

}
