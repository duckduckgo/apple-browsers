//
//  FireDialogViewModel.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

    /// Reset persisted UI defaults - used for tests
    static func resetPersistedDefaults() {
        lastSelectedClearingOption = .currentTab
        lastIncludeTabsAndWindowsState = true
        lastIncludeHistoryState = true
        lastIncludeCookiesAndSiteDataState = true
    }

    init(fireViewModel: FireViewModel,
         tabCollectionViewModel: TabCollectionViewModel,
         historyCoordinating: HistoryCoordinating,
         fireproofDomains: FireproofDomains,
         faviconManagement: FaviconManagement,
         clearingOption: ClearingOption? = nil,
         includeTabsAndWindows: Bool? = nil,
         includeHistory: Bool? = nil,
         includeCookiesAndSiteData: Bool? = nil,
         tld: TLD,
         onboardingContextualDialogsManager: ContextualOnboardingStateUpdater) {

        self.fireViewModel = fireViewModel
        self.tabCollectionViewModel = tabCollectionViewModel
        self.historyCoordinating = historyCoordinating
        self.fireproofDomains = fireproofDomains
        self.faviconManagement = faviconManagement
        self.clearingOption = clearingOption ?? Self.lastSelectedClearingOption
        self.includeTabsAndWindows = includeTabsAndWindows ?? Self.lastIncludeTabsAndWindowsState
        self.includeHistory = includeHistory ?? Self.lastIncludeHistoryState
        self.includeCookiesAndSiteData = includeCookiesAndSiteData ?? Self.lastIncludeCookiesAndSiteDataState

        self.tld = tld
        self.onboardingContextualDialogsManager = onboardingContextualDialogsManager

        // Initialize selectable/fireproofed lists so counts (e.g., cookiesSitesCountForCurrentScope) are available immediately
        updateItems(for: self.clearingOption)
    }

    private(set) var shouldShowPinnedTabsInfo: Bool = false

    private let fireViewModel: FireViewModel
    private(set) weak var tabCollectionViewModel: TabCollectionViewModel?
    private let historyCoordinating: HistoryCoordinating
    private let fireproofDomains: FireproofDomains
    private let faviconManagement: FaviconManagement
    private let tld: TLD
    private let onboardingContextualDialogsManager: ContextualOnboardingStateUpdater

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

    @Published private(set) var selectable: [Item] = []
    @Published private(set) var fireproofed: [Item] = []
    @Published private(set) var selected: Set<Int> = Set()
    @Published private(set) var historyVisits: [Visit] = []

    var isPinnedTabSelected: Bool {
        tabCollectionViewModel?.selectedTabViewModel?.tab.isPinned ?? false
    }

    let selectableSectionIndex = 0
    let fireproofedSectionIndex = 1

    // MARK: - Options

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
                return (historyCoordinating.history?.visitedDomains(tld: tld) ?? Set<String>())
                    .union(tabCollectionViewModel?.localHistoryDomains ?? Set<String>())
            }
        }

        let visitedDomains = visitedDomains(basedOn: clearingOption)
        let visitedETLDPlus1Domains = Set(visitedDomains.compactMap { tld.eTLDplus1($0) })

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

        // Update history visits for current scope to mirror burn behavior exactly
        switch clearingOption {
        case .allData:
            self.historyVisits = historyCoordinating.allHistoryVisits ?? []
        case .currentTab:
            if let tab = tabCollectionViewModel?.selectedTabViewModel?.tab {
                self.historyVisits = tab.localHistory
            } else {
                self.historyVisits = []
            }
        case .currentWindow:
            if let vm = tabCollectionViewModel {
                self.historyVisits = vm.localHistory
            } else {
                self.historyVisits = []
            }
        }
    }

    // MARK: - Counts for subtitles

    var historyItemsCountForCurrentScope: Int { historyVisits.count }

    /// Cookies/sites are deleted for non-fireproofed visited eTLD+1 domains
    var cookiesSitesCountForCurrentScope: Int { selectable.count }

    // MARK: - Selection

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

    // MARK: - Burning

    /// Triggers data clearing for the selected scope using the three toggles.
    /// - Parameters:
    ///   - includeHistory: when true, history is cleared for the selected scope.
    ///   - includeTabsAndWindows: when true, selected tabs/windows are closed; when false, tabs remain open, but their history/session state is cleared if includeHistory is true.
    ///   - includeCookiesAndSiteData: when true, cookies/site data are cleared for the selected (non-fireproof) domains in scope.
    func burn() {
        onboardingContextualDialogsManager.fireButtonUsed()
        PixelKit.fire(GeneralPixel.fireButtonFirstBurn, frequency: .legacyDailyNoSuffix)

        // Domains to clear cookies/site-data for
        let cookieDomains: Set<String> = includeCookiesAndSiteData ? selectedDomains : []

        switch (clearingOption, areAllSelected && includeCookiesAndSiteData) {
        case (.currentTab, _):
            guard let tabCollectionViewModel = tabCollectionViewModel,
                  let tabViewModel = tabCollectionViewModel.selectedTabViewModel else {
                assertionFailure("No tab selected")
                return
            }
            PixelKit.fire(GeneralPixel.fireButton(option: .tab))
            let burningEntity = Fire.BurningEntity.tab(tabViewModel: tabViewModel,
                                                       selectedDomains: cookieDomains,
                                                       parentTabCollectionViewModel: tabCollectionViewModel,
                                                       close: includeTabsAndWindows)
            fireViewModel.fire.burnEntity(entity: burningEntity, includingHistory: includeHistory)

        case (.currentWindow, _):
            guard let tabCollectionViewModel = tabCollectionViewModel else {
                assertionFailure("FireDialogViewModel: TabCollectionViewModel is not present")
                return
            }
            PixelKit.fire(GeneralPixel.fireButton(option: .window))
            let burningEntity = Fire.BurningEntity.window(tabCollectionViewModel: tabCollectionViewModel,
                                                          selectedDomains: cookieDomains,
                                                          close: includeTabsAndWindows)
            fireViewModel.fire.burnEntity(entity: burningEntity, includingHistory: includeHistory)

        case (.allData, /* allSelected: */ true):
            PixelKit.fire(GeneralPixel.fireButton(option: .allSites))
            // "All" implies history too; respect includeHistory by routing via burnAll or burnEntity
            if includeTabsAndWindows && includeHistory {
                fireViewModel.fire.burnAll()
            } else {
                let entity = Fire.BurningEntity.allWindows(mainWindowControllers: Application.appDelegate.windowControllersManager.mainWindowControllers,
                                                           selectedDomains: cookieDomains,
                                                           customURLToOpen: nil,
                                                           close: includeTabsAndWindows)
                fireViewModel.fire.burnEntity(entity: entity, includingHistory: includeHistory)
            }

        case (.allData, /* allSelected: */ false):
            PixelKit.fire(GeneralPixel.fireButton(option: .allSites))
            let entity = Fire.BurningEntity.allWindows(mainWindowControllers: Application.appDelegate.windowControllersManager.mainWindowControllers,
                                                       selectedDomains: cookieDomains,
                                                       customURLToOpen: nil,
                                                       close: includeTabsAndWindows)
            fireViewModel.fire.burnEntity(entity: entity, includingHistory: includeHistory)
        }
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
