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
        
        delegate?.willStartBurning(fireRequest: request)
        if request.options.contains(.tabs) {
            delegate?.willStartBurningTabs(fireRequest: request)
            burnTabs(scope: request.scope)
            delegate?.didFinishBurningTabs(fireRequest: request)
        }
        
        cancelOngoingDownloadsIfNeeded(request)

        let shouldBurnData = request.options.contains(.data)
        
        // For auto-clear with enhancedDataClearingSettings FF ON:
        // - User configures what to clear via the enhanced settings UI
        // For manual fire OR auto-clear with FF OFF (legacy):
        // - AI chats clear only if autoClearAIChatHistory setting is enabled
        let chosenThroughNewAutoClearUI = featureFlagger.isFeatureOn(.enhancedDataClearingSettings) && request.trigger != .manualFire
        let shouldAllowAIChatsBurn = chosenThroughNewAutoClearUI || appSettings.autoClearAIChatHistory
        
        let shouldBurnAIChats = request.options.contains(.aiChats) && shouldAllowAIChatsBurn

        if shouldBurnData { delegate?.willStartBurningData(fireRequest: request) }
        if shouldBurnAIChats { delegate?.willStartBurningAIHistory(fireRequest: request) }

        async let dataTask: Void = shouldBurnData ? burnData(applicationState: applicationState) : ()
        async let aiTask: Void = shouldBurnAIChats ? burnAIHistory() : ()
        _ = await (dataTask, aiTask)

        if shouldBurnData { delegate?.didFinishBurningData(fireRequest: request) }
        if shouldBurnAIChats { delegate?.didFinishBurningAIHistory(fireRequest: request) }
        delegate?.didFinishBurning(fireRequest: request)
        
        // Reset prepared state for next burn cycle
        preparedOptions = []
    }
    
    // MARK: - Clearing Downloads
    
    private func cancelOngoingDownloadsIfNeeded(_ request: FireRequest) {
        guard request.options.contains(.tabs), request.options.contains(.data) else {
            return
        }
        downloadManager.cancelAllDownloads()
    }
    
    // MARK: Burn Tabs Helpers
    @MainActor
    private func prepareForBurningTabs(scope: FireRequest.Scope) {
        switch scope {
        case .all:
            tabManager.prepareAllTabsExceptCurrentForDataClearing()
        case .tab:
            return
            // TODO: Prepare the tab if it's not the current tab
        }
    }
    
    @MainActor
    private func burnTabs(scope: FireRequest.Scope) {
        switch scope {
        case .all:
            tabManager.prepareCurrentTabForDataClearing()
            tabManager.removeAll()
            Favicons.shared.clearCache(.tabs)
        case .tab:
            return
            // TODO: Prepare the tab if it's the current tab (non-current tabs were prepared earlier)
            // TODO: Remove just this tab from TabManager
        }
    }
    
    // MARK: - Clear Data Helpers
    
    private func forgetTextZoom() {
        let allowedDomains = fireproofing.allowedDomains
        textZoomCoordinator.resetTextZoomLevels(excludingDomains: allowedDomains)
    }
    
    @MainActor
    private func burnData(applicationState: DataStoreWarmup.ApplicationState) async {
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

        self.burnInProgress = false
    }
    
    // MARK: - Clear AI History
    
    private func burnAIHistory() async {
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
}
