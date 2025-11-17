//
//  Fire.swift
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
import DDGSync
import FeatureFlags
import Foundation
import History
import os.log
import PrivacyDashboard
import PrivacyStats
import AutoconsentStats
import SecureStorage
import WebKit

protocol FireProtocol: AnyObject {
    var burningData: Fire.BurningData? { get }
    var fireproofDomains: FireproofDomains { get }
    var visualizeFireAnimationDecider: VisualizeFireSettingsDecider { get }
    var burningDataPublisher: AnyPublisher<Fire.BurningData?, Never> { get }

    func fireAnimationDidStart()
    func fireAnimationDidFinish()

    @MainActor func burnAll(isBurnOnExit: Bool,
                            opening url: URL,
                            includeCookiesAndSiteData: Bool,
                            includeChatHistory: Bool,
                            completion: (@MainActor () -> Void)?)
    @MainActor func burnEntity(_ entity: Fire.BurningEntity,
                               includingHistory: Bool,
                               includeCookiesAndSiteData: Bool,
                               includeChatHistory: Bool,
                               completion: (@MainActor () -> Void)?)
    @MainActor func burnVisits(_ visits: [Visit],
                               except fireproofDomains: DomainFireproofStatusProviding,
                               isToday: Bool,
                               closeWindows: Bool,
                               clearSiteData: Bool,
                               clearChatHistory: Bool,
                               urlToOpenIfWindowsAreClosed url: URL?,
                               completion: (@MainActor () -> Void)?)
    @MainActor func burnChatHistory() async
}

extension FireProtocol {

    @MainActor
    func burnAll(isBurnOnExit: Bool = false,
                 opening url: URL = .newtab,
                 includeChatHistory: Bool = true,
                 completion: (@MainActor () -> Void)? = nil) {
        burnAll(isBurnOnExit: isBurnOnExit,
                opening: url,
                includeCookiesAndSiteData: true,
                includeChatHistory: includeChatHistory,
                completion: completion)
    }

    @MainActor
    func burnAll(isBurnOnExit: Bool = false,
                 opening url: URL = .newtab,
                 includeCookiesAndSiteData: Bool = true,
                 includeChatHistory: Bool) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.burnAll(isBurnOnExit: isBurnOnExit,
                         opening: url,
                         includeCookiesAndSiteData: includeCookiesAndSiteData,
                         includeChatHistory: includeChatHistory) {
                continuation.resume()
            }
        }
    }

    @MainActor
    func burnEntity(_ entity: Fire.BurningEntity, completion: (() -> Void)? = nil) {
        burnEntity(entity,
                   includingHistory: true,
                   includeCookiesAndSiteData: true,
                   includeChatHistory: false,
                   completion: completion)
    }

    @MainActor
    func burnEntity(_ entity: Fire.BurningEntity,
                    includingHistory: Bool,
                    includeCookiesAndSiteData: Bool = true,
                    includeChatHistory: Bool) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.burnEntity(entity,
                            includingHistory: includingHistory,
                            includeCookiesAndSiteData: includeCookiesAndSiteData,
                            includeChatHistory: includeChatHistory) {
                continuation.resume()
            }
        }
    }

    @MainActor
    func burnVisits(_ visits: [Visit],
                    except fireproofDomains: DomainFireproofStatusProviding,
                    isToday: Bool,
                    closeWindows: Bool,
                    clearSiteData: Bool,
                    clearChatHistory: Bool,
                    urlToOpenIfWindowsAreClosed url: URL? = .newtab) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.burnVisits(visits,
                            except: fireproofDomains,
                            isToday: isToday,
                            closeWindows: closeWindows,
                            clearSiteData: clearSiteData,
                            clearChatHistory: clearChatHistory,
                            urlToOpenIfWindowsAreClosed: url) {
                continuation.resume()
            }
        }
    }

    @MainActor
    func burnVisits(_ visits: [Visit],
                    except fireproofDomains: DomainFireproofStatusProviding,
                    isToday: Bool,
                    closeWindows: Bool,
                    clearSiteData: Bool,
                    clearChatHistory: Bool,
                    completion: (@MainActor () -> Void)?) {
        burnVisits(visits, except: fireproofDomains, isToday: isToday, closeWindows: closeWindows, clearSiteData: clearSiteData, clearChatHistory: clearChatHistory, urlToOpenIfWindowsAreClosed: .newtab, completion: completion)
    }

}

final class Fire: FireProtocol {

    let webCacheManager: WebCacheManager
    let historyCoordinating: HistoryCoordinating
    let permissionManager: PermissionManagerProtocol
    let savedZoomLevelsCoordinating: SavedZoomLevelsCoordinating
    let downloadListCoordinator: DownloadListCoordinator
    let windowControllersManager: WindowControllersManagerProtocol
    let faviconManagement: FaviconManagement
    let fireproofDomains: FireproofDomains
    let autoconsentManagement: AutoconsentManagement?
    let autoconsentStats: AutoconsentStatsCollecting?
    let stateRestorationManager: AppStateRestorationManager?
    let recentlyClosedCoordinator: RecentlyClosedCoordinating?
    let pinnedTabsManagerProvider: PinnedTabsManagerProviding
    let bookmarkManager: BookmarkManager
    let syncService: DDGSyncing?
    let syncDataProviders: SyncDataProviders?
    let tabCleanupPreparer = TabCleanupPreparer()
    let secureVaultFactory: AutofillVaultFactory
    let tld: TLD
    let getVisitedLinkStore: () -> WKVisitedLinkStoreWrapper?
    let getPrivacyStats: () async -> PrivacyStatsCollecting
    let visualizeFireAnimationDecider: VisualizeFireSettingsDecider
    let isAppActiveProvider: @MainActor () -> Bool
    let aiChatHistoryCleaner: AIChatHistoryCleaning

    private var dispatchGroup: DispatchGroup?

    enum BurningData: Equatable {
        case specificDomains(_ domains: Set<String>, shouldPlayFireAnimation: Bool)
        case all

        func shouldPlayFireAnimation(decider: VisualizeFireSettingsDecider) -> Bool {
            switch self {
            case .all, .specificDomains(_, shouldPlayFireAnimation: true):
                return decider.shouldShowFireAnimation
            // We don't present the fire animation if user burns from the privacy feed
            case .specificDomains(_, shouldPlayFireAnimation: false):
                return false
            }
        }
    }

    /// Represents what should be "burned" (tabs/windows) and for which domains; `close` controls whether UI is closed or only state is cleared.
    enum BurningEntity {
        case none(selectedDomains: Set<String>)
        case tab(tabViewModel: TabViewModel,
                 selectedDomains: Set<String>,
                 parentTabCollectionViewModel: TabCollectionViewModel,
                 close: Bool)
        case window(tabCollectionViewModel: TabCollectionViewModel,
                    selectedDomains: Set<String>,
                    close: Bool)
        case allWindows(mainWindowControllers: [MainWindowController],
                        selectedDomains: Set<String>,
                        customURLToOpen: URL?,
                        close: Bool)

        var shouldClose: Bool {
            switch self {
            case .tab(tabViewModel: _, selectedDomains: _, parentTabCollectionViewModel: _, close: let close),
                    .window(tabCollectionViewModel: _, selectedDomains: _, close: let close),
                    .allWindows(mainWindowControllers: _, selectedDomains: _, customURLToOpen: _, close: let close):
                return close
            case .none:
                return true
            }
        }

        var customURLToOpen: URL? {
            switch self {
            case .allWindows(_, _, customURLToOpen: let url, close: _):
                return url
            case .tab, .window, .none:
                return nil
            }
        }

        func shouldPlayFireAnimation(decider: VisualizeFireSettingsDecider) -> Bool {
            switch self {
            // We don't present the fire animation if user burns from the privacy feed
            case .none:
                return false
            case .tab, .window, .allWindows:
                return decider.shouldShowFireAnimation
            }
        }
    }

    @Published private(set) var burningData: BurningData?

    var burningDataPublisher: AnyPublisher<BurningData?, Never> { $burningData.eraseToAnyPublisher() }

    @MainActor
    init(cacheManager: WebCacheManager? = nil,
         historyCoordinating: HistoryCoordinating? = nil,
         permissionManager: PermissionManagerProtocol? = nil,
         savedZoomLevelsCoordinating: SavedZoomLevelsCoordinating = AccessibilityPreferences.shared,
         downloadListCoordinator: DownloadListCoordinator? = nil,
         windowControllersManager: WindowControllersManagerProtocol? = nil,
         faviconManagement: FaviconManagement? = nil,
         fireproofDomains: FireproofDomains? = nil,
         autoconsentManagement: AutoconsentManagement? = nil,
         autoconsentStats: AutoconsentStatsCollecting? = nil,
         stateRestorationManager: AppStateRestorationManager? = nil,
         recentlyClosedCoordinator: RecentlyClosedCoordinating? = nil,
         pinnedTabsManagerProvider: PinnedTabsManagerProviding? = nil,
         tld: TLD,
         bookmarkManager: BookmarkManager? = nil,
         syncService: DDGSyncing? = nil,
         syncDataProviders: SyncDataProviders? = nil,
         secureVaultFactory: AutofillVaultFactory = AutofillSecureVaultFactory,
         getPrivacyStats: (() async -> PrivacyStatsCollecting)? = nil,
         getVisitedLinkStore: (() -> WKVisitedLinkStoreWrapper?)? = nil,
         visualizeFireAnimationDecider: VisualizeFireSettingsDecider? = nil,
         isAppActiveProvider: @escaping @MainActor () -> Bool = { @MainActor in NSApp.isActive },
         aIChatHistoryCleaner: AIChatHistoryCleaning? = nil
    ) {
        self.webCacheManager = cacheManager ?? NSApp.delegateTyped.webCacheManager
        self.historyCoordinating = historyCoordinating ?? NSApp.delegateTyped.historyCoordinator
        self.permissionManager = permissionManager ?? NSApp.delegateTyped.permissionManager
        self.savedZoomLevelsCoordinating = savedZoomLevelsCoordinating
        self.downloadListCoordinator = downloadListCoordinator ?? NSApp.delegateTyped.downloadListCoordinator
        self.windowControllersManager = windowControllersManager ?? Application.appDelegate.windowControllersManager
        self.faviconManagement = faviconManagement ?? NSApp.delegateTyped.faviconManager
        self.fireproofDomains = fireproofDomains ?? NSApp.delegateTyped.fireproofDomains
        self.recentlyClosedCoordinator = recentlyClosedCoordinator ?? NSApp.delegateTyped.recentlyClosedCoordinator
        self.pinnedTabsManagerProvider = pinnedTabsManagerProvider ?? Application.appDelegate.pinnedTabsManagerProvider
        self.bookmarkManager = bookmarkManager ?? NSApp.delegateTyped.bookmarkManager
        self.syncService = syncService ?? NSApp.delegateTyped.syncService
        self.syncDataProviders = syncDataProviders ?? NSApp.delegateTyped.syncDataProviders
        self.secureVaultFactory = secureVaultFactory
        self.tld = tld
        self.getPrivacyStats = getPrivacyStats ?? { NSApp.delegateTyped.privacyStats }
        self.getVisitedLinkStore = getVisitedLinkStore ?? { WKWebViewConfiguration.sharedVisitedLinkStore }
        self.autoconsentManagement = autoconsentManagement ?? NSApp.delegateTyped.autoconsentManagement
        self.autoconsentStats = autoconsentStats ?? NSApp.delegateTyped.autoconsentStats
        self.visualizeFireAnimationDecider = visualizeFireAnimationDecider ?? NSApp.delegateTyped.visualizeFireSettingsDecider
        self.isAppActiveProvider = isAppActiveProvider
        if let stateRestorationManager = stateRestorationManager {
            self.stateRestorationManager = stateRestorationManager
        } else {
            self.stateRestorationManager = NSApp.delegateTyped.stateRestorationManager
        }
        self.aiChatHistoryCleaner = aIChatHistoryCleaner ?? AIChatHistoryCleaner(featureFlagger: NSApp.delegateTyped.featureFlagger,
                                                                                 aiChatMenuConfiguration: NSApp.delegateTyped.aiChatMenuConfiguration,
                                                                                 featureDiscovery: DefaultFeatureDiscovery(),
                                                                                 privacyConfig: NSApp.delegateTyped.privacyFeatures.contentBlocking.privacyConfigurationManager)
    }

    @MainActor
    func burnEntity(_ entity: BurningEntity,
                    includingHistory: Bool,
                    includeCookiesAndSiteData: Bool,
                    includeChatHistory: Bool,
                    completion: (@MainActor () -> Void)?) {
        Logger.fire.debug("Fire started")

        let group = DispatchGroup()
        dispatchGroup = group

        let domains = domainsToBurn(from: entity)
        assert(domains.areAllETLDPlus1(tld: tld))

        burningData = .specificDomains(domains, shouldPlayFireAnimation: entity.shouldPlayFireAnimation(decider: visualizeFireAnimationDecider))

        burnLastSessionState()
        burnDeletedBookmarks()

        let tabViewModels = tabViewModels(of: entity)

        Task {
            if entity.shouldClose {
                await tabCleanupPreparer.prepareTabsForCleanup(tabViewModels)
            }

            group.enter()
            self.burnTabs(burningEntity: entity)

            if includeCookiesAndSiteData {
                await self.burnWebCache(baseDomains: domains)
            }

            if includingHistory {
                self.burnHistory(ofEntity: entity) {
                    self.burnFavicons(for: domains) {
                        group.leave()
                    }
                }
            } else {
                group.leave()
            }

            if includeCookiesAndSiteData {
                group.enter()
                self.burnPermissions(of: domains) {
                    self.burnDownloads(of: domains)
                    group.leave()
                }

                self.burnAutoconsentCache()
                await self.burnAutoconsentStats()
                self.burnZoomLevels(of: domains)
            }

            self.burnRecentlyClosed(baseDomains: domains)

            if includeChatHistory {
                group.enter()
                await burnChatHistory()
                group.leave()
            }

            group.notify(queue: .main) {
                self.dispatchGroup = nil
                // windows are closed by MainViewController.closeWindowIfNeeded
                self.reopenWindowIfNeeded(customURL: entity.customURLToOpen)

                self.burningData = nil

                completion?()

                Logger.fire.debug("Fire finished")
            }
        }
    }

    @MainActor
    func burnAll(isBurnOnExit: Bool,
                 opening url: URL,
                 includeCookiesAndSiteData: Bool,
                 includeChatHistory: Bool,
                 completion: (@MainActor () -> Void)?) {
        Logger.fire.debug("Fire started")

        let group = DispatchGroup()
        dispatchGroup = group

        burningData = .all

        let entity = BurningEntity.allWindows(mainWindowControllers: windowControllersManager.mainWindowControllers, selectedDomains: Set(), customURLToOpen: url, close: true)

        // Close windows first if fire animation is disabled
        let shouldCloseWindowsFirst = !visualizeFireAnimationDecider.shouldShowFireAnimation
        if shouldCloseWindowsFirst {
            closeWindows(opening: url)
        }

        burnLastSessionState()
        burnDeletedBookmarks()

        let windowControllers = windowControllersManager.mainWindowControllers

        let tabViewModels = tabViewModels(of: entity)

        Task {
            await tabCleanupPreparer.prepareTabsForCleanup(tabViewModels)

            group.enter()
            self.burnTabs(burningEntity: .allWindows(mainWindowControllers: windowControllers, selectedDomains: Set(), customURLToOpen: url, close: true))

            if includeCookiesAndSiteData {
                await self.burnWebCache()
            }
            await self.burnPrivacyStats()
            if includeChatHistory {
                await burnChatHistory()
            }
            self.burnHistory(ofEntity: .allWindows(mainWindowControllers: windowControllers, selectedDomains: [], customURLToOpen: nil, close: false)) {
                self.burnPermissions {
                    self.burnFavicons {
                        self.burnDownloads()
                        group.leave()
                    }
                }
            }

            self.burnRecentlyClosed()
            self.burnAutoconsentCache()
            await self.burnAutoconsentStats()
            self.burnZoomLevels()

            group.notify(queue: .main) {
                self.dispatchGroup = nil
                // Only close windows at the end if we didn't close them at the beginning
                // windows are closed by MainViewController.closeWindowIfNeeded
                if !isBurnOnExit {
                    self.reopenWindowIfNeeded(customURL: url)
                }

                self.burningData = nil
                completion?()

                Logger.fire.debug("Fire finished")
            }
        }
    }

    // Burns visit passed to the method but preserves other visits of same domains
    @MainActor
    func burnVisits(_ visits: [Visit],
                    except fireproofDomains: DomainFireproofStatusProviding,
                    isToday: Bool,
                    closeWindows: Bool,
                    clearSiteData: Bool,
                    clearChatHistory: Bool,
                    urlToOpenIfWindowsAreClosed url: URL?,
                    completion: (@MainActor () -> Void)?) {

        // Get domains to burn
        var domains = Set<String>()
        visits.forEach { visit in
            guard let historyEntry = visit.historyEntry else {
                assertionFailure("No history entry")
                return
            }

            if let domain = historyEntry.url.host,
               !fireproofDomains.isFireproof(fireproofDomain: domain) {
                domains.insert(domain)
            }
        }
        // Convert to eTLD+1 domains
        domains = domains.convertedToETLDPlus1(tld: tld)

        burnVisitedLinks(visits)
        historyCoordinating.burnVisits(visits) {
            // If cookie/site data should not be cleared, finish after history burn
            guard clearSiteData else {
                completion?()
                return
            }

            let entity: BurningEntity

            // Burn all windows in case we are burning visits for today (respecting closeWindows flag)
            if isToday {
                entity = .allWindows(mainWindowControllers: self.windowControllersManager.mainWindowControllers, selectedDomains: domains, customURLToOpen: url, close: closeWindows)
            } else {
                entity = .none(selectedDomains: domains)
            }

            self.burnEntity(entity,
                            includingHistory: false,
                            includeCookiesAndSiteData: clearSiteData,
                            includeChatHistory: clearChatHistory,
                            completion: completion)
        }
    }

    // MARK: - Duck.ai Chat History

    @MainActor
    func burnChatHistory() async {
        await aiChatHistoryCleaner.cleanAIChatHistory()
    }

    // MARK: - Fire animation

    func fireAnimationDidStart() {
        assert(dispatchGroup != nil)

        dispatchGroup?.enter()
    }

    func fireAnimationDidFinish() {
        assert(dispatchGroup != nil)

        dispatchGroup?.leave()
    }

    // MARK: - Closing windows

    @MainActor
    private func closeWindows(opening url: URL) {
        for windowController in windowControllersManager.mainWindowControllers {
            guard pinnedTabsManagerProvider.pinnedTabsMode == .shared
                    || windowController.mainViewController.tabCollectionViewModel.pinnedTabsManager?.isEmpty ?? false else { continue }

            let inserted = (insertNewTabIfNeeded(into: windowController, with: url) != nil)
            if !inserted {
                windowController.close()
            }
        }
    }

    @MainActor
    private func reopenWindowIfNeeded(customURL: URL?) {
        // If the app is not active, don't retake focus by opening a new window
        guard isAppActiveProvider(),
              windowControllersManager.mainWindowControllers.isEmpty else { return }

        // Open a new window in case there is none
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // `reopenWindowIfNeeded` should not be called when there were at least one “Regular” window
            // as we should‘ve kept it open by replacing its Tabs with a New Tab.
            // Generally we should get here only when Delete All History is called on a Fire Window,
            // so we should probably respect User‘s choice on whether to open a Fire Window by default.
            let burnerMode = visualizeFireAnimationDecider.isOpenFireWindowByDefaultEnabled ? BurnerMode(isBurner: true) : .regular
            if let customURL {
                let tab = Tab(content: .contentFromURL(customURL, source: .ui), shouldLoadInBackground: true, burnerMode: burnerMode)
                let tabCollection = TabCollection(tabs: [tab], isPopup: false)

                let tabCollectionViewModel = TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManagerProvider: pinnedTabsManagerProvider, burnerMode: burnerMode, windowControllersManager: windowControllersManager)
                windowControllersManager.openNewWindow(with: tabCollectionViewModel, burnerMode: burnerMode, showWindow: true)
            } else {
                windowControllersManager.openNewWindow(burnerMode: burnerMode)
            }
        }
    }

    @MainActor
    func insertNewTabIfNeeded(into windowController: MainWindowController, with customURL: URL? = nil) -> Int? {
        // If closing all Tabs/Windows: Insert a new (Regular) tab to prevent window closing:
        guard !visualizeFireAnimationDecider.isOpenFireWindowByDefaultEnabled,
              !windowController.mainViewController.isBurner,
              windowController.mainViewController.tabCollectionViewModel.pinnedTabs.isEmpty,
              windowControllersManager.lastKeyMainWindowController(where: { !$0.mainViewController.isBurner }) === windowController,
              // don‘t keep an open window for inactive app
              self.isAppActiveProvider() else { return nil }

        let newTabContent: Tab.TabContent = customURL.map { .contentFromURL($0, source: .ui) } ?? .newtab
        let newTab = Tab(content: newTabContent, shouldLoadInBackground: false, burnerMode: .regular)
        let insertionIndex = windowController.mainViewController.tabCollectionViewModel.append(tab: newTab, selected: false, forceChange: true)

        return insertionIndex
    }

    // MARK: - Web cache

    private func burnWebCache() async {
        Logger.fire.debug("WebsiteDataStore began cookie deletion")
        await webCacheManager.clear()
        Logger.fire.debug("WebsiteDataStore completed cookie deletion")
    }

    private func burnWebCache(baseDomains: Set<String>? = nil) async {
        Logger.fire.debug("WebsiteDataStore began cookie deletion")
        await webCacheManager.clear(baseDomains: baseDomains)
        Logger.fire.debug("WebsiteDataStore completed cookie deletion")
    }

    // MARK: - History

    @MainActor
    private func burnHistory(ofEntity entity: BurningEntity, completion: @escaping @MainActor () -> Void) {
        let visits: [Visit]

        switch entity {
        case .none(selectedDomains: let domains):
            burnHistory(of: domains) { urls in
                self.burnVisitedLinks(urls)
                completion()
            }
            return
        case .tab(tabViewModel: let tabViewModel, selectedDomains: _, parentTabCollectionViewModel: _, _):
            visits = tabViewModel.tab.localHistory
            // clear tab navigation history
            tabViewModel.tab.clearNavigationHistory(keepingCurrent: true)

        case .window(tabCollectionViewModel: let tabCollectionViewModel, selectedDomains: _, _):
            visits = tabCollectionViewModel.localHistory
            tabCollectionViewModel.clearLocalHistory(keepingCurrent: true)

        case .allWindows(mainWindowControllers: let mainWindowControllers, selectedDomains: _, customURLToOpen: _, close: _):
            // clear all tabs navigation history
            mainWindowControllers.forEach { wc in
                wc.mainViewController.tabCollectionViewModel.clearLocalHistory(keepingCurrent: true)
            }

            burnAllVisitedLinks()
            burnAllHistory(completion: completion)

            return
        }

        burnVisitedLinks(visits)
        historyCoordinating.burnVisits(visits, completion: completion)
    }

    @MainActor
    private func burnHistory(of baseDomains: Set<String>, completion: @escaping @MainActor (Set<URL>) -> Void) {
        historyCoordinating.burnDomains(baseDomains, tld: tld, completion: completion)
    }

    @MainActor
    private func burnAllHistory(completion: @escaping @MainActor () -> Void) {
        historyCoordinating.burnAll(completion: completion)
    }

    // MARK: - Privacy Stats

    private func burnPrivacyStats() async {
        await getPrivacyStats().clearPrivacyStats()
    }

    // MARK: - Visited links

    @MainActor
    private func burnAllVisitedLinks() {
        getVisitedLinkStore()?.removeAll()
    }

    @MainActor
    private func burnVisitedLinks(_ visits: [Visit]) {
        guard let visitedLinkStore = getVisitedLinkStore() else { return }
        for visit in visits {
            guard let url = visit.historyEntry?.url else { continue }
            visitedLinkStore.removeVisitedLink(with: url)
        }
    }

    @MainActor
    private func burnVisitedLinks(_ urls: Set<URL>) {
        guard let visitedLinkStore = getVisitedLinkStore() else { return }
        for url in urls {
            visitedLinkStore.removeVisitedLink(with: url)
        }
    }

    // MARK: - Zoom levels

     private func burnZoomLevels() {
         savedZoomLevelsCoordinating.burnZoomLevels(except: fireproofDomains)
     }

     private func burnZoomLevels(of baseDomains: Set<String>) {
         savedZoomLevelsCoordinating.burnZoomLevel(of: baseDomains)
     }

    // MARK: - Permissions

    private func burnPermissions(completion: @escaping @MainActor () -> Void) {
        self.permissionManager.burnPermissions(except: fireproofDomains, completion: completion)
    }

    private func burnPermissions(of baseDomains: Set<String>, completion: @MainActor @escaping () -> Void) {
        self.permissionManager.burnPermissions(of: baseDomains, tld: tld, completion: completion)
    }

    // MARK: - Downloads

    @MainActor
    private func burnDownloads() {
        self.downloadListCoordinator.cleanupInactiveDownloads(for: nil)
    }

    @MainActor
    private func burnDownloads(of baseDomains: Set<String>) {
        self.downloadListCoordinator.cleanupInactiveDownloads(for: baseDomains, tld: tld)
    }

    // MARK: - Favicons

    private func autofillDomains() -> Set<String> {
        guard let vault = try? secureVaultFactory.makeVault(reporter: SecureVaultReporter.shared),
              let accounts = try? vault.accounts() else {
            return []
        }
        return Set(accounts.compactMap { $0.domain })
    }

    private func burnFavicons(completion: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            await self.faviconManagement.burn(except: fireproofDomains,
                                              bookmarkManager: bookmarkManager,
                                              savedLogins: autofillDomains())
            completion()
        }
    }

    @MainActor
    private func burnFavicons(for baseDomains: Set<String>, completion: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            await self.faviconManagement.burnDomains(baseDomains,
                                                     exceptBookmarks: bookmarkManager,
                                                     exceptSavedLogins: autofillDomains(),
                                                     exceptExistingHistory: historyCoordinating.history ?? [],
                                                     tld: tld)
            completion()
        }
    }

    // MARK: - Tabs

    @MainActor
    /// Closes tabs/windows when `close` is true; otherwise clears back/forward history and session state when requested.
    private func burnTabs(burningEntity: BurningEntity) {

        func replacementPinnedTab(from pinnedTab: Tab) -> Tab {
            return Tab(content: pinnedTab.content.loadedFromCache(), shouldLoadInBackground: true)
        }

        func selectPinnedTabIfNeeded(in tabCollectionViewModel: TabCollectionViewModel) {
            if !tabCollectionViewModel.pinnedTabs.isEmpty {
                tabCollectionViewModel.select(at: .pinned(0), forceChange: true)
            }
        }

        func burnPinnedTabs(in tabCollectionViewModel: TabCollectionViewModel) {
            guard let pinnedTabsManager = tabCollectionViewModel.pinnedTabsManager else {
                assertionFailure("No pinned tabs manager")
                return
            }

            for (index, pinnedTab) in pinnedTabsManager.tabCollection.tabs.enumerated() {
                let newTab = replacementPinnedTab(from: pinnedTab)
                pinnedTabsManager.tabCollection.replaceTab(at: index, with: newTab)
            }
        }

        // Close tabs or reset history based on entity.close
        switch burningEntity {
        case .none: break
        case .tab(tabViewModel: let tabViewModel,
                  selectedDomains: _,
                  parentTabCollectionViewModel: let tabCollectionViewModel,
                  close: let shouldClose):
            assert(tabViewModel === tabCollectionViewModel.selectedTabViewModel)
            if shouldClose {
                if tabCollectionViewModel.pinnedTabsManager?.isTabPinned(tabViewModel.tab) ?? false {
                    let tab = replacementPinnedTab(from: tabViewModel.tab)
                    if let index = tabCollectionViewModel.selectionIndex {
                        tabCollectionViewModel.replaceTab(at: index, with: tab, forceChange: true)
                    }
                } else {
                    if tabCollectionViewModel.allTabsCount == 1,
                       windowControllersManager.mainWindowControllers.count == 1 {
                        // If closing last Window‘s last Tab: Insert a new tab to prevent key window closing:
                        _=insertNewTabIfNeeded(into: windowControllersManager.mainWindowControllers[0])
                    }
                    tabCollectionViewModel.removeSelected(forceChange: true)
                }
            }

        case .window(tabCollectionViewModel: let tabCollectionViewModel,
                     selectedDomains: _,
                     close: let shouldClose):
            if shouldClose {
                // If closing last Window: Insert a new tab to prevent key window closing:
                var insertedTabIndex: Int?
                if windowControllersManager.mainWindowControllers.count == 1 {
                    insertedTabIndex = insertNewTabIfNeeded(into: windowControllersManager.mainWindowControllers[0])
                }
                tabCollectionViewModel.removeAllTabs(except: insertedTabIndex, forceChange: true)
                burnPinnedTabs(in: tabCollectionViewModel)
                selectPinnedTabIfNeeded(in: tabCollectionViewModel)
            }

        case .allWindows(mainWindowControllers: let mainWindowControllers,
                         selectedDomains: _,
                         customURLToOpen: let customURL,
                         close: let shouldClose):
            guard shouldClose else { break }
            for windowController in mainWindowControllers {
                // If closing all Tabs/Windows: Insert a new tab to prevent key window closing:
                let insertedTabIndex = insertNewTabIfNeeded(into: windowController, with: customURL)
                windowController.mainViewController.tabCollectionViewModel.removeAllTabs(except: insertedTabIndex, forceChange: true)
                burnPinnedTabs(in: windowController.mainViewController.tabCollectionViewModel)
                selectPinnedTabIfNeeded(in: windowController.mainViewController.tabCollectionViewModel)
            }
        }
    }

    private func domainsToBurn(from entity: BurningEntity) -> Set<String> {
        switch entity {
        case .none(let domains):
            return domains
        case .tab(tabViewModel: _, selectedDomains: let domains, parentTabCollectionViewModel: _, _):
            return domains
        case .window(tabCollectionViewModel: _, selectedDomains: let domains, _):
            return domains
        case .allWindows(mainWindowControllers: _, selectedDomains: let domains, customURLToOpen: _, _):
            return domains
        }
    }

    @MainActor
    private func tabViewModels(of entity: BurningEntity) -> [TabViewModel] {
        switch entity {
        case .none:
            return []
        case .tab(tabViewModel: let tabViewModel, selectedDomains: _, parentTabCollectionViewModel: _, _):
            return [tabViewModel]
        case .window(tabCollectionViewModel: let tabCollectionViewModel, selectedDomains: _, _):
            let pinnedTabViewModels = Array(tabCollectionViewModel.pinnedTabsManager?.tabViewModels.values ?? Dictionary().values)
            let tabViewModels = Array(tabCollectionViewModel.tabViewModels.values)
            return pinnedTabViewModels + tabViewModels
        case .allWindows:
            let pinnedTabViewModels = Array(pinnedTabsManagerProvider.currentPinnedTabManagers.flatMap { $0.tabViewModels.values })
            let tabViewModels = windowControllersManager.allTabViewModels
            return pinnedTabViewModels + tabViewModels
        }
    }

    // MARK: - Autoconsent visit cache

    private func burnAutoconsentCache() {
        self.autoconsentManagement?.clearCache()
    }

    private func burnAutoconsentStats() async {
        await self.autoconsentStats?.clearAutoconsentStats()
    }

    // MARK: - Last Session State

    @MainActor
    private func burnLastSessionState() {
        stateRestorationManager?.clearLastSessionState()
    }

    // MARK: - Burn Recently Closed

    @MainActor
    private func burnRecentlyClosed(baseDomains: Set<String>? = nil) {
        recentlyClosedCoordinator?.burnCache(baseDomains: baseDomains, tld: tld)
    }

    // MARK: - Bookmarks cleanup

    private func burnDeletedBookmarks() {
        if syncService?.authState == .inactive {
            syncDataProviders?.bookmarksAdapter.databaseCleaner.cleanUpDatabaseNow()
        }
    }
}

extension TabCollection {

    // Local history of TabCollection instance including history of already closed tabs
    var localHistory: [Visit] {
        tabs.flatMap { $0.localHistory }
    }

    var localHistoryDomains: Set<String> {
        var domains = Set<String>()

        for tab in tabs {
            domains = domains.union(tab.localHistoryDomains)
        }
        return domains
    }

    var localHistoryDomainsOfRemovedTabs: Set<String> {
        var domains = Set<String>()
        for visit in localHistoryOfRemovedTabs {
            if let host = visit.historyEntry?.url.host {
                domains.insert(host)
            }
        }
        return domains
    }

}

extension Set where Element == String {

    func areAllETLDPlus1(tld: TLD) -> Bool {
        for domain in self {
            guard let eTLDPlus1Host = tld.eTLDplus1(domain) else {
                return true // allow `localhost`-s
            }
            if domain != eTLDPlus1Host {
                return false
            }
        }
        return true
    }

}
