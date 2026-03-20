//
//  FireExecutor.swift
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

import Core
import Common
import DDGSync
import Bookmarks
import AIChat
import PixelKit
import PrivacyConfig
import UserScript
import WebKit
import WKAbstractions

struct FireRequest {
    
    let options: Options
    let trigger: Trigger
    let scope: Scope
    let source: Source
    
    struct Options: OptionSet {
        
        let rawValue: Int
        
        static let tabs = Options(rawValue: 1 << 0)
        static let data = Options(rawValue: 1 << 1)
        static let aiChats = Options(rawValue: 1 << 2)
        static let all: Options = [.tabs, .data, .aiChats]
    }
    
    enum Trigger {
        case manualFire              // User pressed Fire Button
        case autoClearOnLaunch       // Auto-clear during app launch
        case autoClearOnForeground   // Auto-clear after period of inactivity when returning to foreground
        case fireModeAutoClear       // Auto-clear fire mode data when all fire tabs are closed
    }
    
    enum Scope {
        case tab(viewModel: TabViewModel)
        case fireMode
        case normalMode
        case all
    }
    
    enum Source: String {
        case browsing
        case tabSwitcher
        case settings
        case quickFire
        case deeplink
        case autoClear
    }
}

protocol FireExecutorDelegate: AnyObject {
    func willStartBurning(fireRequest: FireRequest)
    func willStartBurningTabs(fireRequest: FireRequest)
    func didFinishBurningTabs(fireRequest: FireRequest)
    func willStartBurningData(fireRequest: FireRequest)
    func didFinishBurningData(fireRequest: FireRequest)
    func willStartBurningAIHistory(fireRequest: FireRequest)
    func didFinishBurningAIHistory(fireRequest: FireRequest)
    func didFinishBurning(fireRequest: FireRequest)
}

protocol FireExecuting {
    @MainActor func prepare(for request: FireRequest)
    @MainActor func burn(request: FireRequest,
                         applicationState: DataStoreWarmup.ApplicationState) async
    var delegate: FireExecutorDelegate? { get set }
}

class FireExecutor: FireExecuting {
    
    typealias HistoryCleanerProvider = (WKWebsiteDataStore?) -> HistoryCleaning
    
    // MARK: - Variables
    private let fireWorkers: [FireExecutorWorker]
    private let tabManager: TabManaging
    private let downloadManager: DownloadManaging
    private let historyManager: HistoryManaging
    private let featureFlagger: FeatureFlagger
    private let dataClearingCapability: DataClearingCapable
    private let fireModeCapability: FireModeCapable
    private let appSettings: AppSettings
    private let aiChatSyncCleaner: AIChatSyncCleaning
    let pixelsReporter: DataClearingPixelsReporter
    private let dataClearingWideEventService: DataClearingWideEventService?
    private let aiChatDeleter: AIChatDeleting
    private let idManager: DataStoreIDManaging

    weak var delegate: FireExecutorDelegate?
    private var burnInProgress = false
    private var dataStoreWarmupWorker: DataStoreWarmupWorker = .init()
    private let historyCleanerProvider: HistoryCleanerProvider
    private var preparedOptions: FireRequest.Options = []
    
    // MARK: - Init
    
    init(tabManager: TabManaging,
         downloadManager: DownloadManaging = AppDependencyProvider.shared.downloadManager,
         websiteDataManager: WebsiteDataManaging,
         daxDialogsManager: DaxDialogsManaging,
         syncService: DDGSyncing,
         bookmarksDatabaseCleaner: BookmarkDatabaseCleaning,
         fireproofing: Fireproofing,
         textZoomCoordinatorProvider: TextZoomCoordinatorProviding,
         autoconsentManagementProvider: AutoconsentManagementProviding,
         historyManager: HistoryManaging,
         featureFlagger: FeatureFlagger,
         dataClearingCapability: DataClearingCapable? = nil,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         dataStore: (any DDGWebsiteDataStore)? = nil,
         historyCleanerProvider: HistoryCleanerProvider? = nil,
         appSettings: AppSettings,
         privacyStats: PrivacyStatsProviding? = nil,
         aiChatSyncCleaner: AIChatSyncCleaning,
         pixelsReporter: DataClearingPixelsReporter = DataClearingPixelsReporter(),
         wideEvent: WideEventManaging? = nil,
         idManager: DataStoreIDManaging = DataStoreIDManager.shared) {
        self.tabManager = tabManager
        self.downloadManager = downloadManager
        self.historyManager = historyManager
        self.featureFlagger = featureFlagger
        self.idManager = idManager
        self.dataClearingCapability = dataClearingCapability ?? DataClearingCapability.create(using: featureFlagger)
        self.fireModeCapability = FireModeCapability.create(using: featureFlagger)
        self.historyCleanerProvider = historyCleanerProvider ??
        { dataStore in return HistoryCleaner(featureFlagger: featureFlagger,
                                             privacyConfig: privacyConfigurationManager,
                                             websiteDataStore: dataStore)}
        self.appSettings = appSettings
        self.aiChatSyncCleaner = aiChatSyncCleaner
        self.pixelsReporter = pixelsReporter
        self.dataClearingWideEventService = wideEvent.map { DataClearingWideEventService(wideEvent: $0) }
        let aiChatDeleter = AIChatDeleter(historyCleanerProvider: self.historyCleanerProvider,
                                          aiChatSyncCleaner: aiChatSyncCleaner,
                                          idManager: idManager)
        self.aiChatDeleter = aiChatDeleter
        self.fireWorkers = [
            URLCacheFireWorker(dataClearingWideEventService: dataClearingWideEventService),
            WebsiteDataFireWorker(websiteDataManager: websiteDataManager,
                                  dataStore: dataStore,
                                  dataClearingWideEventService: dataClearingWideEventService),
            AutoConsentFireWorker(autoconsentManagementProvider: autoconsentManagementProvider,
                                  dataClearingWideEventService: dataClearingWideEventService),
            DaxDialogsFireWorker(daxDialogsManager: daxDialogsManager,
                                 dataClearingWideEventService: dataClearingWideEventService),
            BookmarksFireWorker(syncService: syncService,
                                bookmarksDatabaseCleaner: bookmarksDatabaseCleaner,
                                dataClearingWideEventService: dataClearingWideEventService),
            TextZoomFireWorker(fireproofing: fireproofing,
                               textZoomCoordinatorProvider: textZoomCoordinatorProvider,
                               dataClearingWideEventService: dataClearingWideEventService),
            HistoryFireWorker(historyManager: historyManager,
                              dataClearingWideEventService: dataClearingWideEventService),
            PrivacyStatsFireWorker(privacyStats: privacyStats,
                                   dataClearingWideEventService: dataClearingWideEventService),
            ContextualChatFireWorker(appSettings: appSettings,
                                     tabManager: tabManager,
                                     aiChatDeleter: aiChatDeleter,
                                     dataClearingWideEventService: dataClearingWideEventService)
        ]
    }

    
    // MARK: - Public Functions
    @MainActor
    func prepare(for request: FireRequest) {
        // Only prepare tabs if requested and not already prepared
        if request.options.contains(.tabs) && !preparedOptions.contains(.tabs) {
            prepareForBurningTabs(scope: request.scope)
        }
        preparedOptions.formUnion(request.options)
    }
    
    @MainActor
    func burn(request: FireRequest,
              applicationState: DataStoreWarmup.ApplicationState) async {
        assert(delegate != nil, "Delegate should not be nil. This leads to unexpected behavior.")

        // Fire retrigger pixel at the start of burn to track rapid manual fire operations
        // Only tracks manual fire triggers (auto-clear is excluded as it follows system timing)
        pixelsReporter.fireRetriggerPixelIfNeeded(request: request)

        dataClearingWideEventService?.start(request: request)

        // Ensure all requested options are prepared
        let unpreparedOptions = request.options.subtracting(preparedOptions)
        if !unpreparedOptions.isEmpty {
            let newRequest = FireRequest(options: unpreparedOptions, trigger: request.trigger, scope: request.scope, source: request.source)
            prepare(for: newRequest)
        }

        // Notify delegate that we're starting
        delegate?.willStartBurning(fireRequest: request)
        
        // Compute flags
        let shouldBurnTabs = request.options.contains(.tabs)
        let shouldBurnData = request.options.contains(.data)
        let shouldBurnAIChats = shouldBurnAIHistory(request)
        
        // Pre-fetch domains once for tab scope when tabs or data burning is needed
        let domains: [String]?
        if case .tab(let viewModel) = request.scope, shouldBurnTabs || shouldBurnData {
            domains = await Array(viewModel.visitedDomains())
        } else {
            domains = nil
        }
        
        // Start async tasks
        async let dataTask: Void = shouldBurnData ? burnDataWithDelegateCallbacks(request: request, applicationState: applicationState, domains: domains) : ()
        
        async let aiTask: Void = shouldBurnAIChats ? burnAIHistoryWithDelegateCallbacks(request: request) : ()

        // Execute sync tasks
        cancelOngoingDownloadsIfNeeded(request)
        if shouldBurnTabs {
            burnTabsWithDelegateCallbacks(request: request, domains: domains)
        }
        
        // Await async tasks
        _ = await (dataTask, aiTask)

        // Notify delegate that we finished
        await didFinishBurning(fireRequest: request)

        dataClearingWideEventService?.complete()

        // Reset prepared state for next burn cycle
        preparedOptions = []
    }
    
    // MARK: - General Helpers
    
    private func cancelOngoingDownloadsIfNeeded(_ request: FireRequest) {
        guard case .all = request.scope,
              request.options.contains(.tabs),
              request.options.contains(.data) else {
            return
        }
        dataClearingWideEventService?.start(.cancelAllDownloads)
        downloadManager.cancelAllDownloads()
        dataClearingWideEventService?.update(.cancelAllDownloads, result: .success(()))
    }

    @MainActor
    private func didFinishBurning(fireRequest: FireRequest) async {
        if case .tab(let viewModel) = fireRequest.scope,
           fireRequest.options.contains(.tabs) {
            dataClearingWideEventService?.start(.clearTabs)
            let result = await historyManager.removeTabHistory(for: [viewModel.tab.uid])
            dataClearingWideEventService?.update(.clearTabs, result: result)
        }
        delegate?.didFinishBurning(fireRequest: fireRequest)
    }
    
    @MainActor
    private func burnTabsWithDelegateCallbacks(request: FireRequest, domains: [String]?) {
        delegate?.willStartBurningTabs(fireRequest: request)
        burnTabs(scope: request.scope, domains: domains)
        delegate?.didFinishBurningTabs(fireRequest: request)
    }
    
    @MainActor
    private func burnDataWithDelegateCallbacks(request: FireRequest,
                                               applicationState: DataStoreWarmup.ApplicationState,
                                               domains: [String]?) async {
        delegate?.willStartBurningData(fireRequest: request)
        await burnData(scope: request.scope, applicationState: applicationState, domains: domains)
        delegate?.didFinishBurningData(fireRequest: request)
    }
    
    @MainActor
    private func burnAIHistoryWithDelegateCallbacks(request: FireRequest) async {
        delegate?.willStartBurningAIHistory(fireRequest: request)
        await burnAIHistory(request: request)
        delegate?.didFinishBurningAIHistory(fireRequest: request)
    }
    
    // MARK: Burn Tabs Helpers

    @MainActor
    private func prepareForBurningTabs(scope: FireRequest.Scope) {
        switch scope {
        case .all:
            tabManager.prepareAllTabsExceptCurrentForDataClearing(browsingMode: nil)
        case .fireMode:
            tabManager.prepareAllTabsExceptCurrentForDataClearing(browsingMode: .fire)
        case .normalMode:
            tabManager.prepareAllTabsExceptCurrentForDataClearing(browsingMode: .normal)
        case .tab(let viewModel):
            // Only prepare the tab if it's not the current tab
            // Current tabs are prepared during burnTabs
            if !tabManager.isCurrentTab(viewModel.tab) {
                tabManager.prepareTab(viewModel.tab)
            }
        }
    }
    
    @MainActor
    private func burnTabs(scope: FireRequest.Scope, domains: [String]?) {
        switch scope {
        case .all:
            tabManager.prepareCurrentTabForDataClearing(browsingMode: nil)
            dataClearingWideEventService?.start(.clearTabs)
            let removeAllResult = tabManager.removeAll(browsingMode: nil)
            dataClearingWideEventService?.update(.clearTabs, result: removeAllResult)
            dataClearingWideEventService?.start(.clearFaviconCache)
            let faviconResult = Favicons.shared.clearCache(.tabs)
            dataClearingWideEventService?.update(.clearFaviconCache, result: faviconResult)
        case .fireMode:
            tabManager.prepareCurrentTabForDataClearing(browsingMode: .fire)
            dataClearingWideEventService?.start(.clearTabs)
            let removeAllResult = tabManager.removeAll(browsingMode: .fire)
            dataClearingWideEventService?.update(.clearTabs, result: removeAllResult)
        case .normalMode:
            tabManager.prepareCurrentTabForDataClearing(browsingMode: .normal)
            dataClearingWideEventService?.start(.clearTabs)
            let removeAllResult = tabManager.removeAll(browsingMode: .normal)
            dataClearingWideEventService?.update(.clearTabs, result: removeAllResult)
        case .tab(let viewModel):
            guard let domains else {
                Logger.general.error("Expected domains to be present when burning a single tab")
                return
            }
            // Prepare the tab if it's the current tab (non-current tabs were prepared earlier)
            if tabManager.isCurrentTab(viewModel.tab) {
                tabManager.prepareTab(viewModel.tab)
            }

            // Pass false to clearTabHistory to preserve tab history while burning
            // As tab history is needed by other processes running in parallel
            // didFinishBurning(fireRequest:) manually clears data after burn is complete
            // Close the tab and append a new empty tab, reusing existing one if exists
            tabManager.closeTabAndNavigateToHomepage(viewModel.tab, clearTabHistory: false)

            dataClearingWideEventService?.start(.clearFaviconCache)
            let faviconResult = Favicons.shared.removeTabFavicons(forDomains: domains)
            dataClearingWideEventService?.update(.clearFaviconCache, result: faviconResult)
        }
    }
    
    // MARK: - Clear Data Helpers
    
    @MainActor
    private func burnData(scope: FireRequest.Scope,
                          applicationState: DataStoreWarmup.ApplicationState,
                          domains: [String]?) async {
        guard !burnInProgress else {
            assertionFailure("Shouldn't get called multiple times")
            return
        }
        burnInProgress = true

        await dataStoreWarmupWorker.setApplicationState(applicationState)
        await dataStoreWarmupWorker.execute(scope: scope, domains: domains, fireModeCapability: fireModeCapability)
        
        let pixel = dataClearingTimedPixel(for: scope)
        
        await withTaskGroup(of: Void.self) { group in
            for worker in fireWorkers {
                group.addTask {
                    await worker.execute(scope: scope, domains: domains, fireModeCapability: self.fireModeCapability)
                }
            }
        }
        let params = dataClearingPixelParams(for: scope, domains: domains)
        pixel?.fire(withAdditionalParameters: params)

        self.burnInProgress = false
    }
    
    private func dataClearingTimedPixel(for scope: FireRequest.Scope) -> TimedPixel? {
        switch scope {
        case .tab:
            return TimedPixel(.singleTabDataCleared)
        case .fireMode, .normalMode:
            // TODO: - return new pixel
            return nil
        case .all:
            return TimedPixel(.forgetAllDataCleared)
        }
    }
    
    @MainActor
    private func dataClearingPixelParams(for scope: FireRequest.Scope, domains: [String]?) -> [String: String] {
        let tabsModel: TabsModelReading?
        switch scope {
        case .tab(let viewModel):
            let tabType = viewModel.tab.isAITab ? "ai" : "web"
            return [
                PixelParameters.tabType: tabType,
                PixelParameters.domainsCount: "\(domains?.count ?? 0)"
            ]
        case .fireMode:
            tabsModel = self.tabManager.tabsModel(for: .fire)
        case .normalMode:
            tabsModel = self.tabManager.tabsModel(for: .normal)
        case .all:
            tabsModel = self.tabManager.allTabsModel
        }
        return [PixelParameters.tabCount: "\(tabsModel?.count ?? 0)"]

    }
    
    // MARK: - Clear AI History
    
    /// For auto-clear with enhancedDataClearingSettings FF ON:
    /// - User configures what to clear via the enhanced settings UI
    /// For manual fire OR auto-clear with FF OFF (legacy):
    /// - AI chats clear only if autoClearAIChatHistory setting is enabled
    /// For single chat burning:
    /// - The user setting autoClearAIChatHistory should be ignored
    /// - Returns: A boolean indicating if we should run the ai chats burn flow
    private func shouldBurnAIHistory(_ request: FireRequest) -> Bool {
        let chosenThroughNewAutoClearUI = dataClearingCapability.isEnhancedDataClearingEnabled
            && request.trigger != .manualFire
            && request.trigger != .fireModeAutoClear

        var singleChatBurn: Bool = false
        if case .tab = request.scope { singleChatBurn = true }

        let shouldAllowAIChatsBurn = chosenThroughNewAutoClearUI
        || appSettings.autoClearAIChatHistory
        || singleChatBurn

        return request.options.contains(.aiChats) && shouldAllowAIChatsBurn
    }
    
    @MainActor
    private func burnAIHistory(request: FireRequest) async {
        dataClearingWideEventService?.start(.clearAIChatHistory)
        let result: Result<Void, Error>
        switch request.scope {
        case .tab(let viewModel):
            result = await burnTabAIHistory(tabViewModel: viewModel)
        case .fireMode:
            if !request.options.contains(.data) { // Invalidating the fire mode datastore makes deleting chats redundant.
                result = await burnFireModeAIHistory()
            } else {
                result = .success(())
            }
        case .normalMode:
            result = await burnNormalModeAIHistory(trigger: request.trigger)
        case .all:
            result = await burnAllAIHistory(trigger: request.trigger, options: request.options)
        }
        dataClearingWideEventService?.update(.clearAIChatHistory, result: result)
    }

    private func burnAllAIHistory(trigger: FireRequest.Trigger, options: FireRequest.Options) async -> Result<Void, Error> {
        async let normalBurnTask = burnNormalModeAIHistory(trigger: trigger)
        let shouldBurnFireModeChats = !options.contains(.data) // Invalidating the fire mode datastore makes deleting chats redundant.
        async let fireBurnTask = shouldBurnFireModeChats ? await burnFireModeAIHistory() : .success(())
        let (normalResult, fireResult) = await (normalBurnTask, fireBurnTask)
        if case .failure = normalResult { return normalResult }
        if case .failure = fireResult { return fireResult }
        return .success(())
    }

    private func burnNormalModeAIHistory(trigger: FireRequest.Trigger) async -> Result<Void, Error> {
        let cleaner = historyCleanerProvider(nil)
        let result = await cleaner.cleanAIChatHistory()
        switch result {
        case .success:
            await recordAIChatsClearDate(trigger: trigger)
            DailyPixel.fireDailyAndCount(pixel: .aiChatHistoryDeleteSuccessful)
        case .failure(let error):
            Logger.aiChat.debug("Failed to clear Duck.ai chat history: \(error.localizedDescription)")
            DailyPixel.fireDailyAndCount(pixel: .aiChatHistoryDeleteFailed)

            if let userScriptError = error as? UserScriptError {
                userScriptError.fireLoadJSFailedPixelIfNeeded()
            }
        }
        return result
    }

    @MainActor
    private func burnFireModeAIHistory() async -> Result<Void, Error> {
        guard fireModeCapability.isFireModeEnabled else {
            return .success(())
        }
        guard #available(iOS 17.0, *) else {
            return .success(())
        }

        let fireDataStore = WKWebsiteDataStore(forIdentifier: idManager.currentFireModeID)
        let cleaner = historyCleanerProvider(fireDataStore)
        let result = await cleaner.cleanAIChatHistory()
        switch result {
        case .success:
            DailyPixel.fireDailyAndCount(pixel: .aiChatHistoryDeleteSuccessful)
        case .failure(let error):
            Logger.aiChat.debug("Failed to clear fire mode Duck.ai chat history: \(error.localizedDescription)")
            DailyPixel.fireDailyAndCount(pixel: .aiChatHistoryDeleteFailed)

            if let userScriptError = error as? UserScriptError {
                userScriptError.fireLoadJSFailedPixelIfNeeded()
            }
        }
        return result
    }

    @MainActor
    private func burnTabAIHistory(tabViewModel: TabViewModel) async -> Result<Void, Error> {
        if let chatID = tabViewModel.currentAIChatId {
            return await aiChatDeleter.deleteChat(chatID: chatID, isFireMode: tabViewModel.tab.fireTab)
        } else {
            Logger.aiChat.debug("No chatID found for tab, skipping single chat deletion")
            return .success(())
        }
    }

    private func recordAIChatsClearDate(trigger: FireRequest.Trigger) async {
        switch trigger {
        case .manualFire, .fireModeAutoClear:
            await aiChatSyncCleaner.recordLocalClear(date: Date())
        case .autoClearOnLaunch, .autoClearOnForeground:
            await aiChatSyncCleaner.recordLocalClearFromAutoClearBackgroundTimestampIfPresent()
        }
    }

}
