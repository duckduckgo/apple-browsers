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
                            isAutoClear: Bool,
                            dataClearingWideEventService: DataClearingWideEventService?,
                            completion: (@MainActor () -> Void)?)
    @MainActor func burnEntity(_ entity: Fire.BurningEntity,
                               includingHistory: Bool,
                               includeCookiesAndSiteData: Bool,
                               includeChatHistory: Bool,
                               dataClearingWideEventService: DataClearingWideEventService?,
                               completion: (@MainActor () -> Void)?)
    @MainActor func burnVisits(_ visits: [Visit],
                               except fireproofDomains: DomainFireproofStatusProviding,
                               isToday: Bool,
                               closeWindows: Bool,
                               clearSiteData: Bool,
                               clearChatHistory: Bool,
                               urlToOpenIfWindowsAreClosed url: URL?,
                               dataClearingWideEventService: DataClearingWideEventService?,
                               completion: (@MainActor () -> Void)?)
    @MainActor func burnChatHistory() async -> Result<Void, Error>
}

extension FireProtocol {

    @MainActor
    func burnAll(isBurnOnExit: Bool = false,
                 opening url: URL = .newtab,
                 includeChatHistory: Bool = true,
                 isAutoClear: Bool = false,
                 dataClearingWideEventService: DataClearingWideEventService? = nil,
                 completion: (@MainActor () -> Void)? = nil) {
        burnAll(isBurnOnExit: isBurnOnExit,
                opening: url,
                includeCookiesAndSiteData: true,
                includeChatHistory: includeChatHistory,
                isAutoClear: isAutoClear,
                dataClearingWideEventService: dataClearingWideEventService,
                completion: completion)
    }

    @MainActor
    func burnAll(isBurnOnExit: Bool = false,
                 opening url: URL = .newtab,
                 includeCookiesAndSiteData: Bool = true,
                 includeChatHistory: Bool,
                 isAutoClear: Bool = false,
                 dataClearingWideEventService: DataClearingWideEventService? = nil) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.burnAll(isBurnOnExit: isBurnOnExit,
                         opening: url,
                         includeCookiesAndSiteData: includeCookiesAndSiteData,
                         includeChatHistory: includeChatHistory,
                         isAutoClear: isAutoClear,
                         dataClearingWideEventService: dataClearingWideEventService) {
                continuation.resume()
            }
        }
    }

    @MainActor
    func burnEntity(_ entity: Fire.BurningEntity,
                    dataClearingWideEventService: DataClearingWideEventService? = nil,
                    completion: (() -> Void)? = nil) {
        burnEntity(entity,
                   includingHistory: true,
                   includeCookiesAndSiteData: true,
                   includeChatHistory: false,
                   dataClearingWideEventService: dataClearingWideEventService,
                   completion: completion)
    }

    @MainActor
    func burnEntity(_ entity: Fire.BurningEntity,
                    includingHistory: Bool,
                    includeCookiesAndSiteData: Bool = true,
                    includeChatHistory: Bool,
                    dataClearingWideEventService: DataClearingWideEventService? = nil) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.burnEntity(entity,
                            includingHistory: includingHistory,
                            includeCookiesAndSiteData: includeCookiesAndSiteData,
                            includeChatHistory: includeChatHistory,
                            dataClearingWideEventService: dataClearingWideEventService) {
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
                    urlToOpenIfWindowsAreClosed url: URL? = .newtab,
                    dataClearingWideEventService: DataClearingWideEventService? = nil) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.burnVisits(visits,
                            except: fireproofDomains,
                            isToday: isToday,
                            closeWindows: closeWindows,
                            clearSiteData: clearSiteData,
                            clearChatHistory: clearChatHistory,
                            urlToOpenIfWindowsAreClosed: url,
                            dataClearingWideEventService: dataClearingWideEventService) {
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
                    dataClearingWideEventService: DataClearingWideEventService? = nil,
                    completion: (@MainActor () -> Void)?) {
        burnVisits(visits, except: fireproofDomains, isToday: isToday, closeWindows: closeWindows, clearSiteData: clearSiteData, clearChatHistory: clearChatHistory, urlToOpenIfWindowsAreClosed: .newtab, dataClearingWideEventService: dataClearingWideEventService, completion: completion)
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
    let syncDataProviders: SyncDataProvidersSource?
    let tabCleanupPreparer: TabCleanupPreparing
    let secureVaultFactory: AutofillVaultFactory
    let tld: TLD
    let getVisitedLinkStore: () -> WKVisitedLinkStoreWrapper?
    let getPrivacyStats: () async -> PrivacyStatsCollecting
    let visualizeFireAnimationDecider: VisualizeFireSettingsDecider
    let isAppActiveProvider: @MainActor () -> Bool
    let aiChatHistoryCleaner: AIChatHistoryCleaning
    let dataClearingPixelsReporter: DataClearingPixelsReporter
    var dataClearingWideEventService: DataClearingWideEventService?

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

        var description: String {
            switch self {
            case .none:
                return "none"
            case .tab:
                return "tab"
            case .window:
                return "window"
            case .allWindows:
                return "all_windows"
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
         savedZoomLevelsCoordinating: SavedZoomLevelsCoordinating? = nil,
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
         syncDataProviders: SyncDataProvidersSource? = nil,
         secureVaultFactory: AutofillVaultFactory = AutofillSecureVaultFactory,
         getPrivacyStats: (() async -> PrivacyStatsCollecting)? = nil,
         getVisitedLinkStore: (() -> WKVisitedLinkStoreWrapper?)? = nil,
         visualizeFireAnimationDecider: VisualizeFireSettingsDecider? = nil,
         isAppActiveProvider: @escaping @MainActor () -> Bool = { @MainActor in NSApp.isActive },
         aIChatHistoryCleaner: AIChatHistoryCleaning? = nil,
         dataClearingPixelsReporter: DataClearingPixelsReporter = .init(),
         dataClearingWideEventService: DataClearingWideEventService? = nil,
         tabCleanupPreparer: TabCleanupPreparing = TabCleanupPreparer()
    ) {
        self.webCacheManager = cacheManager ?? NSApp.delegateTyped.webCacheManager
        self.historyCoordinating = historyCoordinating ?? NSApp.delegateTyped.historyCoordinator
        self.permissionManager = permissionManager ?? NSApp.delegateTyped.permissionManager
        self.savedZoomLevelsCoordinating = savedZoomLevelsCoordinating ?? NSApp.delegateTyped.accessibilityPreferences
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
        self.dataClearingPixelsReporter = dataClearingPixelsReporter
        self.dataClearingWideEventService = dataClearingWideEventService
        self.tabCleanupPreparer = tabCleanupPreparer
    }

    @MainActor
    func burnEntity(_ entity: BurningEntity,
                    includingHistory: Bool,
                    includeCookiesAndSiteData: Bool,
                    includeChatHistory: Bool,
                    dataClearingWideEventService: DataClearingWideEventService?,
                    completion: (@MainActor () -> Void)?) {
        // Prevent re-entry if burn is already in progress
        guard dispatchGroup == nil, burningData == nil else {
            assertionFailure("burnEntity called while burn already in progress")
            completion?()
            return
        }

        // Set the wide event service if provided
        self.dataClearingWideEventService = dataClearingWideEventService

        Logger.fire.debug("Fire started")

        let group = DispatchGroup()
        dispatchGroup = group

        let domains = domainsToBurn(from: entity)
        assert(domains.areAllETLDPlus1(tld: tld))

        burningData = .specificDomains(domains, shouldPlayFireAnimation: entity.shouldPlayFireAnimation(decider: visualizeFireAnimationDecider))

        dataClearingWideEventService?.start(.clearLastSessionState)
        let lastSessionStateResult = burnLastSessionState()
        dataClearingWideEventService?.update(.clearLastSessionState, result: lastSessionStateResult)

        dataClearingWideEventService?.start(.clearBookmarkDatabase)
        let bookmarkDatabaseResult = burnDeletedBookmarks()
        dataClearingWideEventService?.update(.clearBookmarkDatabase, result: bookmarkDatabaseResult)

        let tabViewModels = tabViewModels(of: entity)

        Task {
            if entity.shouldClose {
                await tabCleanupPreparer.prepareTabsForCleanup(tabViewModels)
            }

            group.enter()
            dataClearingWideEventService?.start(.clearTabs)
            let tabsResult = self.burnTabs(burningEntity: entity)
            dataClearingWideEventService?.update(.clearTabs, result: tabsResult)

            if includeCookiesAndSiteData {
                await self.burnWebCache(baseDomains: domains, dataClearingWideEventService: dataClearingWideEventService)
            }

            if includingHistory {
                dataClearingWideEventService?.start(.clearAllHistory)
                self.burnHistory(ofEntity: entity) { result in
                    dataClearingWideEventService?.update(.clearAllHistory, result: result)
                    dataClearingWideEventService?.start(.clearFaviconCache)
                    self.burnFavicons(for: domains) { faviconResult in
                        dataClearingWideEventService?.update(.clearFaviconCache, result: faviconResult)
                        group.leave()
                    }
                }
            } else {
                group.leave()
            }

            if includeCookiesAndSiteData {
                group.enter()
                dataClearingWideEventService?.start(.clearPermissions)
                self.burnPermissions(of: domains) { result in
                    dataClearingWideEventService?.update(.clearPermissions, result: result)
                    dataClearingWideEventService?.start(.cancelAllDownloads)
                    let downloadsResult = self.burnDownloads(of: domains)
                    dataClearingWideEventService?.update(.cancelAllDownloads, result: downloadsResult)
                    group.leave()
                }

                dataClearingWideEventService?.start(.clearAutoconsentManagementCache)
                let autoconsentCacheResult = self.burnAutoconsentCache()
                dataClearingWideEventService?.update(.clearAutoconsentManagementCache, result: autoconsentCacheResult)

                dataClearingWideEventService?.start(.forgetTextZoom)
                let zoomLevelsResult = self.burnZoomLevels(of: domains)
                dataClearingWideEventService?.update(.forgetTextZoom, result: zoomLevelsResult)

                // when removing cookies for the domain we also need to clear cookiePopupBlocked flag
                // this is only necessary when not removing history for the domain - flag is part of HistoryEntry
                if !includingHistory {
                    dataClearingWideEventService?.start(.resetCookiePopupBlockedFlag)
                    let cookiePopupResult = await self.resetCookiePopupBlockedFlag(for: domains)
                    dataClearingWideEventService?.update(.resetCookiePopupBlockedFlag, result: cookiePopupResult)
                }
            }

            dataClearingWideEventService?.start(.clearRecentlyClosed)
            let recentlyClosedResult = self.burnRecentlyClosed(baseDomains: domains)
            dataClearingWideEventService?.update(.clearRecentlyClosed, result: recentlyClosedResult)

            if includeChatHistory {
                group.enter()
                dataClearingWideEventService?.start(.clearAIChatHistory)
                let chatHistoryResult = await burnChatHistory()
                dataClearingWideEventService?.update(.clearAIChatHistory, result: chatHistoryResult)
                group.leave()
            }

            await withCheckedContinuation { continuation in
                group.notify(queue: .main) {
                    continuation.resume()
                }
            }

            await MainActor.run {
                self.dispatchGroup = nil
                // windows are closed by MainViewController.closeWindowIfNeeded
                self.reopenWindowIfNeeded(customURL: entity.customURLToOpen)
                self.burningData = nil
            }

            await self.reloadWebExtensions()

            completion?()
            Logger.fire.debug("Fire finished")
        }
    }

    @MainActor
    func burnAll(isBurnOnExit: Bool,
                 opening url: URL,
                 includeCookiesAndSiteData: Bool,
                 includeChatHistory: Bool,
                 isAutoClear: Bool,
                 dataClearingWideEventService: DataClearingWideEventService?,
                 completion: (@MainActor () -> Void)?) {
        // Prevent re-entry if burn is already in progress
        guard dispatchGroup == nil, burningData == nil else {
            assertionFailure("burnAll called while burn already in progress")
            completion?()
            return
        }

        // Set the wide event service if provided
        self.dataClearingWideEventService = dataClearingWideEventService

        // Start wide event tracking for auto-clear flows
        if isAutoClear {
            let result = makeAutoClearResult(includeCookiesAndSiteData: includeCookiesAndSiteData,
                                              includeChatHistory: includeChatHistory)
            self.dataClearingWideEventService?.start(options: result, path: .burnAll, isAutoClear: true)
        }

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

        dataClearingWideEventService?.start(.clearLastSessionState)
        let lastSessionStateResult = burnLastSessionState()
        dataClearingWideEventService?.update(.clearLastSessionState, result: lastSessionStateResult)

        dataClearingWideEventService?.start(.clearBookmarkDatabase)
        let bookmarkDatabaseResult = burnDeletedBookmarks()
        dataClearingWideEventService?.update(.clearBookmarkDatabase, result: bookmarkDatabaseResult)

        let windowControllers = windowControllersManager.mainWindowControllers

        let tabViewModels = tabViewModels(of: entity)

        Task {
            await tabCleanupPreparer.prepareTabsForCleanup(tabViewModels)

            group.enter()
            dataClearingWideEventService?.start(.clearTabs)
            let tabsResult = self.burnTabs(burningEntity: .allWindows(mainWindowControllers: windowControllers, selectedDomains: Set(), customURLToOpen: url, close: true))
            dataClearingWideEventService?.update(.clearTabs, result: tabsResult)

            if includeCookiesAndSiteData {
                await self.burnWebCache(dataClearingWideEventService: dataClearingWideEventService)
            }

            dataClearingWideEventService?.start(.clearPrivacyStats)
            let privacyStatsResult = await self.burnPrivacyStats()
            dataClearingWideEventService?.update(.clearPrivacyStats, result: privacyStatsResult)

            dataClearingWideEventService?.start(.clearAutoconsentStats)
            let autoconsentStatsResult = await self.burnAutoconsentStats()
            dataClearingWideEventService?.update(.clearAutoconsentStats, result: autoconsentStatsResult)

            if includeChatHistory {
                dataClearingWideEventService?.start(.clearAIChatHistory)
                let chatHistoryResult = await burnChatHistory()
                dataClearingWideEventService?.update(.clearAIChatHistory, result: chatHistoryResult)
            }
            dataClearingWideEventService?.start(.clearAllHistory)
            self.burnHistory(ofEntity: .allWindows(mainWindowControllers: windowControllers, selectedDomains: [], customURLToOpen: nil, close: false)) { historyResult in
                dataClearingWideEventService?.update(.clearAllHistory, result: historyResult)

                dataClearingWideEventService?.start(.clearPermissions)
                self.burnPermissions { result in
                    dataClearingWideEventService?.update(.clearPermissions, result: result)
                    dataClearingWideEventService?.start(.clearFaviconCache)
                    self.burnFavicons { faviconResult in
                        dataClearingWideEventService?.update(.clearFaviconCache, result: faviconResult)
                        dataClearingWideEventService?.start(.cancelAllDownloads)
                        let downloadsResult = self.burnDownloads()
                        dataClearingWideEventService?.update(.cancelAllDownloads, result: downloadsResult)
                        group.leave()
                    }
                }
            }

            dataClearingWideEventService?.start(.clearRecentlyClosed)
            let recentlyClosedResult = self.burnRecentlyClosed()
            dataClearingWideEventService?.update(.clearRecentlyClosed, result: recentlyClosedResult)

            dataClearingWideEventService?.start(.clearAutoconsentManagementCache)
            let autoconsentCacheResult = self.burnAutoconsentCache()
            dataClearingWideEventService?.update(.clearAutoconsentManagementCache, result: autoconsentCacheResult)

            dataClearingWideEventService?.start(.forgetTextZoom)
            let zoomLevelsResult = self.burnZoomLevels()
            dataClearingWideEventService?.update(.forgetTextZoom, result: zoomLevelsResult)

            await withCheckedContinuation { continuation in
                group.notify(queue: .main) {
                    continuation.resume()
                }
            }

            await MainActor.run {
                self.dispatchGroup = nil
                // Only close windows at the end if we didn't close them at the beginning
                // windows are closed by MainViewController.closeWindowIfNeeded
                if !isBurnOnExit {
                    self.reopenWindowIfNeeded(customURL: url)
                }
                self.burningData = nil
            }

            await self.reloadWebExtensions()

            // Complete wide event tracking for auto-clear flows
            if isAutoClear {
                self.dataClearingWideEventService?.complete()
            }

            completion?()
            Logger.fire.debug("Fire finished")
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
                    dataClearingWideEventService: DataClearingWideEventService?,
                    completion: (@MainActor () -> Void)?) {

        // Set the wide event service if provided
        self.dataClearingWideEventService = dataClearingWideEventService

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

        dataClearingWideEventService?.start(.clearVisitedLinks)
        let visitedLinksResult = burnVisitedLinks(visits)
        dataClearingWideEventService?.update(.clearVisitedLinks, result: visitedLinksResult)

        dataClearingWideEventService?.start(.clearVisits)
        historyCoordinating.burnVisits(visits) { result in
            dataClearingWideEventService?.update(.clearVisits, result: result)

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
                            dataClearingWideEventService: dataClearingWideEventService,
                            completion: completion)
        }
    }

    // MARK: - Duck.ai Chat History

    @MainActor
    func burnChatHistory() async -> Result<Void, Error> {
        let result = await aiChatHistoryCleaner.cleanAIChatHistory()
        if syncService?.authState != .inactive {
            syncService?.scheduler.requestSyncImmediately()
        }
        return result
    }

    // MARK: - Fire animation

    func fireAnimationDidStart() {
        assert(dispatchGroup != nil)

        dispatchGroup?.enter()
    }

    func fireAnimationDidFinish() {
        assert(dispatchGroup != nil)

        dispatchGroup?.leave()
        dispatchGroup = nil
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

    private func burnWebCache(dataClearingWideEventService: DataClearingWideEventService?) async {
        await unloadWebExtensions()
        Logger.fire.debug("WebsiteDataStore began cookie deletion")
        await webCacheManager.clear(dataClearingWideEventService: dataClearingWideEventService)
        Logger.fire.debug("WebsiteDataStore completed cookie deletion")
    }

    private func burnWebCache(baseDomains: Set<String>? = nil, dataClearingWideEventService: DataClearingWideEventService?) async {
        await unloadWebExtensions()
        Logger.fire.debug("WebsiteDataStore began cookie deletion")
        await webCacheManager.clear(baseDomains: baseDomains, dataClearingWideEventService: dataClearingWideEventService)
        Logger.fire.debug("WebsiteDataStore completed cookie deletion")
    }

    // MARK: - Web Extensions

    @MainActor
    private func unloadWebExtensions() {
        if #available(macOS 15.4, *), let webExtensionManager = NSApp.delegateTyped.webExtensionManager {
            webExtensionManager.unloadAllExtensions()
        }
    }

    @MainActor
    private func reloadWebExtensions() async {
        if #available(macOS 15.4, *), let webExtensionManager = NSApp.delegateTyped.webExtensionManager {
            await webExtensionManager.loadInstalledExtensions()
        }
    }

    // MARK: - History

    @MainActor
    private func burnHistory(ofEntity entity: BurningEntity, completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        let visits: [Visit]

        switch entity {
        case .none(selectedDomains: let domains):
            burnHistory(of: domains) { result in
                switch result {
                case .success(let urls):
                    self.dataClearingWideEventService?.start(.clearVisitedLinks)
                    let visitedLinksResult = self.burnVisitedLinks(urls)
                    self.dataClearingWideEventService?.update(.clearVisitedLinks, result: visitedLinksResult)
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
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

            dataClearingWideEventService?.start(.clearVisitedLinks)
            let visitedLinksResult = burnAllVisitedLinks()
            dataClearingWideEventService?.update(.clearVisitedLinks, result: visitedLinksResult)

            burnAllHistory(completion: completion)

            return
        }

        dataClearingWideEventService?.start(.clearVisitedLinks)
        let visitedLinksResult = burnVisitedLinks(visits)
        dataClearingWideEventService?.update(.clearVisitedLinks, result: visitedLinksResult)

        dataClearingWideEventService?.start(.clearVisits)
        historyCoordinating.burnVisits(visits) { result in
            self.dataClearingWideEventService?.update(.clearVisits, result: result)
            completion(result)
        }
    }

    @MainActor
    private func burnHistory(of baseDomains: Set<String>, completion: @escaping @MainActor (Result<Set<URL>, Error>) -> Void) {
        historyCoordinating.burnDomains(baseDomains, tld: tld, completion: completion)
    }

    @MainActor
    private func burnAllHistory(completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        historyCoordinating.burnAll(completion: completion)
    }

    // MARK: - Privacy Stats

    private func burnPrivacyStats() async -> Result<Void, Error> {
        return await getPrivacyStats().clearPrivacyStats()
    }

    @MainActor
    private func resetCookiePopupBlockedFlag(for domains: Set<String>) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            historyCoordinating.resetCookiePopupBlocked(for: domains, tld: tld) { result in
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Visited links

    @MainActor
    private func burnAllVisitedLinks() -> Result<Void, Error> {
        guard let visitedLinkStore = getVisitedLinkStore() else {
            return .failure(DataClearingWideEventError(description: "visitedLinkStore not available"))
        }

        visitedLinkStore.removeAll()
        return .success(())
    }

    @MainActor
    private func burnVisitedLinks(_ visits: [Visit]) -> Result<Void, Error> {
        guard let visitedLinkStore = getVisitedLinkStore() else {
            return .failure(DataClearingWideEventError(description: "visitedLinkStore not available"))
        }

        for visit in visits {
            guard let url = visit.historyEntry?.url else { continue }
            visitedLinkStore.removeVisitedLink(with: url)
        }
        return .success(())
    }

    @MainActor
    private func burnVisitedLinks(_ urls: Set<URL>) -> Result<Void, Error> {
        guard let visitedLinkStore = getVisitedLinkStore() else {
            return .failure(DataClearingWideEventError(description: "visitedLinkStore not available"))
        }

        for url in urls {
            visitedLinkStore.removeVisitedLink(with: url)
        }
        return .success(())
    }

    // MARK: - Zoom levels

     private func burnZoomLevels() -> Result<Void, Error> {
         savedZoomLevelsCoordinating.burnZoomLevels(except: fireproofDomains)
         return .success(())
     }

     private func burnZoomLevels(of baseDomains: Set<String>) -> Result<Void, Error> {
         savedZoomLevelsCoordinating.burnZoomLevel(of: baseDomains)
         return .success(())
     }

    // MARK: - Permissions

    private func burnPermissions(completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        self.permissionManager.burnPermissions(except: fireproofDomains, completion: completion)
    }

    private func burnPermissions(of baseDomains: Set<String>, completion: @MainActor @escaping (Result<Void, Error>) -> Void) {
        self.permissionManager.burnPermissions(of: baseDomains, tld: tld, completion: completion)
    }

    // MARK: - Downloads

    @MainActor
    private func burnDownloads() -> Result<Void, Error> {
        return self.downloadListCoordinator.cleanupInactiveDownloads(for: nil)
    }

    @MainActor
    private func burnDownloads(of baseDomains: Set<String>) -> Result<Void, Error> {
        return self.downloadListCoordinator.cleanupInactiveDownloads(for: baseDomains, tld: tld)
    }

    // MARK: - Favicons

    private func autofillDomains() -> Set<String> {
        guard let vault = try? secureVaultFactory.makeVault(reporter: SecureVaultReporter.shared),
              let accounts = try? vault.accounts() else {
            return []
        }
        return Set(accounts.compactMap { $0.domain })
    }

    private func burnFavicons(completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        Task { @MainActor in
            let result = await self.faviconManagement.burn(except: fireproofDomains,
                                                           bookmarkManager: bookmarkManager,
                                                           savedLogins: autofillDomains())
            completion(result)
        }
    }

    @MainActor
    private func burnFavicons(for baseDomains: Set<String>, completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        Task { @MainActor in
            let result = await self.faviconManagement.burnDomains(baseDomains,
                                                                  exceptBookmarks: bookmarkManager,
                                                                  exceptSavedLogins: autofillDomains(),
                                                                  exceptExistingHistory: historyCoordinating.history ?? [],
                                                                  tld: tld)
            completion(result)
        }
    }

    // MARK: - Tabs

    @MainActor
    /// Closes tabs/windows when `close` is true; otherwise clears back/forward history and session state when requested.
    private func burnTabs(burningEntity: BurningEntity) -> Result<Void, Error> {
        var firstError: Error?

        func replacementPinnedTab(from pinnedTab: Tab) -> Tab {
            return Tab(content: pinnedTab.content.loadedFromCache(), shouldLoadInBackground: true)
        }

        func selectPinnedTabIfNeeded(in tabCollectionViewModel: TabCollectionViewModel) {
            if !tabCollectionViewModel.pinnedTabs.isEmpty {
                tabCollectionViewModel.select(at: .pinned(0), forceChange: true)
            }
        }

        func burnPinnedTabs(in tabCollectionViewModel: TabCollectionViewModel) -> Result<Void, Error> {
            guard let pinnedTabsManager = tabCollectionViewModel.pinnedTabsManager else {
                assertionFailure("No pinned tabs manager")
                return .failure(DataClearingWideEventError(description: "No pinned tabs manager"))
            }

            for (index, pinnedTab) in pinnedTabsManager.tabCollection.tabs.enumerated() {
                let newTab = replacementPinnedTab(from: pinnedTab)
                pinnedTabsManager.tabCollection.replaceTab(at: index, with: newTab)
            }
            return .success(())
        }

        func closeFloatingAIChatWindows(for tabIDs: [TabIdentifier]) {
            let uniqueTabIDs = Set(tabIDs)
            guard !uniqueTabIDs.isEmpty else {
                return
            }

            func coordinatorForTabID(_ tabID: TabIdentifier) -> AIChatCoordinating? {
                for windowController in windowControllersManager.mainWindowControllers {
                    let tabCollectionViewModel = windowController.mainViewController.tabCollectionViewModel
                    let hasUnpinnedTab = tabCollectionViewModel.tabCollection.tabs.contains { $0.uuid == tabID }
                    let hasPinnedTab = tabCollectionViewModel.pinnedTabsCollection?.tabs.contains { $0.uuid == tabID } ?? false
                    if hasUnpinnedTab || hasPinnedTab {
                        return windowController.mainViewController.aiChatCoordinator
                    }
                }
                return windowControllersManager.mainWindowControllers.first?.mainViewController.aiChatCoordinator
            }

            uniqueTabIDs.forEach { tabID in
                coordinatorForTabID(tabID)?.closeFloatingWindow(for: tabID)
            }
        }

        func measureError(_ result: Result<Void, Error>) {
            if case .failure(let error) = result {
                firstError = firstError ?? error
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
                closeFloatingAIChatWindows(for: [tabViewModel.tab.uuid])
                if tabCollectionViewModel.pinnedTabsManager?.isTabPinned(tabViewModel.tab) ?? false {
                    let tab = replacementPinnedTab(from: tabViewModel.tab)
                    if let index = tabCollectionViewModel.selectionIndex {
                        let result = tabCollectionViewModel.replaceTab(at: index, with: tab, forceChange: true)
                        measureError(result)
                    }
                } else {
                    if tabCollectionViewModel.allTabsCount == 1,
                       windowControllersManager.mainWindowControllers.count == 1 {
                        // If closing last Window's last Tab: Insert a new tab to prevent key window closing:
                        _=insertNewTabIfNeeded(into: windowControllersManager.mainWindowControllers[0])
                    }
                    let result = tabCollectionViewModel.removeSelected(forceChange: true)
                    measureError(result)
                }
            }

        case .window(tabCollectionViewModel: let tabCollectionViewModel,
                     selectedDomains: _,
                     close: let shouldClose):
            if shouldClose {
                let unpinnedTabIDs = tabCollectionViewModel.tabCollection.tabs.map(\.uuid)
                let pinnedTabIDs = tabCollectionViewModel.pinnedTabsManager?.tabCollection.tabs.map(\.uuid) ?? []
                closeFloatingAIChatWindows(for: unpinnedTabIDs + pinnedTabIDs)
                // If closing last Window: Insert a new tab to prevent key window closing:
                var insertedTabIndex: Int?
                if windowControllersManager.mainWindowControllers.count == 1 {
                    insertedTabIndex = insertNewTabIfNeeded(into: windowControllersManager.mainWindowControllers[0])
                }
                tabCollectionViewModel.removeAllTabs(except: insertedTabIndex, forceChange: true)
                let result = burnPinnedTabs(in: tabCollectionViewModel)
                measureError(result)
                selectPinnedTabIfNeeded(in: tabCollectionViewModel)
            }

        case .allWindows(mainWindowControllers: let mainWindowControllers,
                         selectedDomains: _,
                         customURLToOpen: let customURL,
                         close: let shouldClose):
            guard shouldClose else { break }
            for windowController in mainWindowControllers {
                let tabCollectionViewModel = windowController.mainViewController.tabCollectionViewModel
                let unpinnedTabIDs = tabCollectionViewModel.tabCollection.tabs.map(\.uuid)
                let pinnedTabIDs = tabCollectionViewModel.pinnedTabsManager?.tabCollection.tabs.map(\.uuid) ?? []
                closeFloatingAIChatWindows(for: unpinnedTabIDs + pinnedTabIDs)
                // If closing all Tabs/Windows: Insert a new tab to prevent key window closing:
                let insertedTabIndex = insertNewTabIfNeeded(into: windowController, with: customURL)
                tabCollectionViewModel.removeAllTabs(except: insertedTabIndex, forceChange: true)
                let result = burnPinnedTabs(in: windowController.mainViewController.tabCollectionViewModel)
                measureError(result)
                selectPinnedTabIfNeeded(in: tabCollectionViewModel)
            }
        }

        if let error = firstError {
            return .failure(error)
        }
        return .success(())
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

    private func burnAutoconsentCache() -> Result<Void, Error> {
        self.autoconsentManagement?.clearCache()
        return .success(())
    }

    private func burnAutoconsentStats() async -> Result<Void, Error> {
        guard let autoconsentStats = autoconsentStats else {
            return .failure(DataClearingWideEventError(description: "autoconsentStats is nil"))
        }
        return await autoconsentStats.clearAutoconsentStats()
    }

    // MARK: - Last Session State

    @MainActor
    private func burnLastSessionState() -> Result<Void, Error> {
        guard let stateRestorationManager = stateRestorationManager else {
            return .failure(DataClearingWideEventError(description: "stateRestorationManager is nil"))
        }

        return stateRestorationManager.clearLastSessionState()
    }

    // MARK: - Burn Recently Closed

    @MainActor
    private func burnRecentlyClosed(baseDomains: Set<String>? = nil) -> Result<Void, Error> {
        recentlyClosedCoordinator?.burnCache(baseDomains: baseDomains, tld: tld)
        return .success(())
    }

    // MARK: - Bookmarks cleanup

    private func burnDeletedBookmarks() -> Result<Void, Error> {
        if syncService?.authState == .inactive {
            syncDataProviders?.bookmarksAdapter.databaseCleaner.cleanUpDatabaseNow()
        }
        return .success(())
    }

    // MARK: - Wide Event Helpers

    /// Creates a FireDialogResult representing an auto-clear operation.
    /// Auto-clear always clears all data with all options enabled except chat history (which is configurable).
    private func makeAutoClearResult(includeCookiesAndSiteData: Bool, includeChatHistory: Bool) -> FireDialogResult {
        return FireDialogResult(
            clearingOption: .allData,
            includeHistory: true,
            includeTabsAndWindows: true,
            includeCookiesAndSiteData: includeCookiesAndSiteData,
            includeChatHistory: includeChatHistory,
            selectedCookieDomains: nil,
            selectedVisits: nil,
            isToday: false
        )
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
