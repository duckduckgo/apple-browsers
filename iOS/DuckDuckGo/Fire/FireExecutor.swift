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
import BrowserServicesKit
import PrivacyConfig
import UserScript
import WKAbstractions

struct FireRequest {
    
    let options: Options
    let trigger: Trigger
    let scope: Scope
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
    }
    
    enum Scope {
        case tab(viewModel: TabViewModel)
        case all
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
    
    // MARK: - Variables
    
    private let tabManager: TabManaging
    private let downloadManager: DownloadManaging
    private let websiteDataManager: WebsiteDataManaging
    private let daxDialogsManager: DaxDialogsManaging
    private let syncService: DDGSyncing
    private weak var bookmarksDatabaseCleaner: BookmarkDatabaseCleaning?
    private let fireproofing: Fireproofing
    private let textZoomCoordinator: TextZoomCoordinating
    private let historyManager: HistoryManaging
    private let featureFlagger: FeatureFlagger
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let dataStore: (any DDGWebsiteDataStore)?
    private let appSettings: AppSettings
    private let privacyStats: PrivacyStatsProviding?

    weak var delegate: FireExecutorDelegate?
    private var burnInProgress = false
    private var dataStoreWarmup: DataStoreWarmup? = DataStoreWarmup()
    private let aiChatHistoryCleaner: HistoryCleaning
    private var preparedOptions: FireRequest.Options = []
    
    // MARK: - Init
    
    init(tabManager: TabManaging,
         downloadManager: DownloadManaging = AppDependencyProvider.shared.downloadManager,
         websiteDataManager: WebsiteDataManaging,
         daxDialogsManager: DaxDialogsManaging,
         syncService: DDGSyncing,
         bookmarksDatabaseCleaner: BookmarkDatabaseCleaning,
         fireproofing: Fireproofing,
         textZoomCoordinator: TextZoomCoordinating,
         historyManager: HistoryManaging,
         featureFlagger: FeatureFlagger,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         dataStore: (any DDGWebsiteDataStore)? = nil,
         aiChatHistoryCleaner: HistoryCleaning? = nil,
         appSettings: AppSettings,
         privacyStats: PrivacyStatsProviding? = nil) {
        self.tabManager = tabManager
        self.downloadManager = downloadManager
        self.websiteDataManager = websiteDataManager
        self.daxDialogsManager = daxDialogsManager
        self.syncService = syncService
        self.bookmarksDatabaseCleaner = bookmarksDatabaseCleaner
        self.fireproofing = fireproofing
        self.textZoomCoordinator = textZoomCoordinator
        self.historyManager = historyManager
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.dataStore = dataStore
        self.aiChatHistoryCleaner = aiChatHistoryCleaner ?? HistoryCleaner(featureFlagger: featureFlagger,
                                                                          privacyConfig: privacyConfigurationManager)
        self.appSettings = appSettings
        self.privacyStats = privacyStats
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
        
        // Ensure all requested options are prepared
        let unpreparedOptions = request.options.subtracting(preparedOptions)
        if !unpreparedOptions.isEmpty {
            let newRequest = FireRequest(options: unpreparedOptions, trigger: request.trigger, scope: request.scope)
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
        downloadManager.cancelAllDownloads()
    }

    @MainActor
    private func didFinishBurning(fireRequest: FireRequest) async {
        if case .tab(let viewModel) = fireRequest.scope,
           fireRequest.options.contains(.tabs) {
            await historyManager.removeTabHistory(for: [viewModel.tab.uid])
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
        await burnAIHistory(scope: request.scope)
        delegate?.didFinishBurningAIHistory(fireRequest: request)
    }
    
    // MARK: Burn Tabs Helpers

    @MainActor
    private func prepareForBurningTabs(scope: FireRequest.Scope) {
        switch scope {
        case .all:
            tabManager.prepareAllTabsExceptCurrentForDataClearing()
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
            tabManager.prepareCurrentTabForDataClearing()
            tabManager.removeAll()
            Favicons.shared.clearCache(.tabs)
        case .tab(let viewModel):
            guard let domains else {
                Logger.general.error("Expected domains to be present when burning a single tab")
                return
            }
            // Prepare the tab if it's the current tab (non-current tabs were prepared earlier)
            if tabManager.isCurrentTab(viewModel.tab) {
                tabManager.prepareTab(viewModel.tab)
            }
            let isLastOpenTab = tabManager.count == 1

            // Pass false to clearTabHistory to preserve tab history while burning
            // As tab history is needed by other processes running in parallel
            // didFinishBurning(fireRequest:) manually clears data after burn is complete
            tabManager.closeTab(viewModel.tab,
                                shouldCreateEmptyTabAtSamePosition: isLastOpenTab,
                                clearTabHistory: false)
            
            Favicons.shared.removeTabFavicons(forDomains: domains)
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

        // This needs to happen only once per app launch
        if let dataStoreWarmup {
            await dataStoreWarmup.ensureReady(applicationState: applicationState)
            self.dataStoreWarmup = nil
        }

        switch scope {
        case .tab(let viewModel):
            await burnTabData(tab: viewModel, domains: domains)
        case .all:
            await burnAllData()
        }

        self.burnInProgress = false
    }
    
    @MainActor
    private func burnAllData() async {
        URLSession.shared.configuration.urlCache?.removeAllCachedResponses()

        let pixel = TimedPixel(.forgetAllDataCleared)
        
        // If the user is on a version that uses containers, then we'll clear the current container, then migrate it. Otherwise
        //  this is the same as `WKWebsiteDataStore.default()`
        let storeToUse = dataStore ?? DDGWebsiteDataStoreProvider.current()
        await websiteDataManager.clear(dataStore: storeToUse)
        pixel.fire(withAdditionalParameters: [PixelParameters.tabCount: "\(self.tabManager.count)"])

        AutoconsentManagement.shared.clearCache()
        daxDialogsManager.clearHeldURLData()

        if self.syncService.authState == .inactive {
            self.bookmarksDatabaseCleaner?.cleanUpDatabaseNow()
        }

        self.forgetTextZoom()
        await historyManager.removeAllHistory()
        await privacyStats?.clearPrivacyStats()
    }
    
    @MainActor
    private func burnTabData(tab: TabViewModel, domains: [String]?) async {
        guard let domains else {
            Logger.general.error("Expected domains to be present when burning tab scoped data")
            return
        }
        // If the user is on a version that uses containers, then we'll clear the current container, then migrate it. Otherwise
        //  this is the same as `WKWebsiteDataStore.default()`
        let storeToUse = dataStore ?? DDGWebsiteDataStoreProvider.current()
        await websiteDataManager.clear(dataStore: storeToUse, forDomains: domains)
        
        AutoconsentManagement.shared.clearCache(forDomains: domains)
        
        forgetTextZoom(forDomains: domains)
        await historyManager.removeBrowsingHistory(tabID: tab.tab.uid)
    }
    
    private func forgetTextZoom() {
        let allowedDomains = fireproofing.allowedDomains
        textZoomCoordinator.resetTextZoomLevels(excludingDomains: allowedDomains)
    }
    
    private func forgetTextZoom(forDomains domains: [String]) {
        let allowedDomains = fireproofing.allowedDomains
        textZoomCoordinator.resetTextZoomLevels(forVisitedDomains: domains, excludingDomains: allowedDomains)
    }
    
    // MARK: - Clear AI History
    
    /// For auto-clear with enhancedDataClearingSettings FF ON:
    /// - User configures what to clear via the enhanced settings UI
    /// For manual fire OR auto-clear with FF OFF (legacy):
    /// - AI chats clear only if autoClearAIChatHistory setting is enabled
    /// - Returns: A boolean indicating if we should run the ai chats burn flow
    private func shouldBurnAIHistory(_ request: FireRequest) -> Bool {
        let chosenThroughNewAutoClearUI = featureFlagger.isFeatureOn(.enhancedDataClearingSettings) && request.trigger != .manualFire
        let shouldAllowAIChatsBurn = chosenThroughNewAutoClearUI || appSettings.autoClearAIChatHistory
        return request.options.contains(.aiChats) && shouldAllowAIChatsBurn
    }
    
    private func burnAIHistory(scope: FireRequest.Scope) async {
        switch scope {
        case .tab(let viewModel):
            await burnTabAIHistory(tab: viewModel)
        case .all:
            await burnAllAIHistory()
        }
    }
    
    private func burnAllAIHistory() async {
        // Skip clearing AI chats if on old UI and clearing ai chats is disabled by the user.
        let result = await aiChatHistoryCleaner.cleanAIChatHistory()
        switch result {
        case .success:
            DailyPixel.fireDailyAndCount(pixel: .aiChatHistoryDeleteSuccessful)
        case .failure(let error):
            Logger.aiChat.debug("Failed to clear Duck.ai chat history: \(error.localizedDescription)")
            DailyPixel.fireDailyAndCount(pixel: .aiChatHistoryDeleteFailed)

            if let userScriptError = error as? UserScriptError {
                userScriptError.fireLoadJSFailedPixelIfNeeded()
            }
        }
    }
    
    private func burnTabAIHistory(tab: TabViewModel) async {
        // TODO: - Implement tab specific AI chats burning
    }
}
