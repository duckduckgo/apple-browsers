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

struct FireOptions: OptionSet {
    
    let rawValue: Int
    
    static let tabs = FireOptions(rawValue: 1 << 0)
    static let data = FireOptions(rawValue: 1 << 1)
    static let aiChats = FireOptions(rawValue: 1 << 2)
    static let all: FireOptions = [.tabs, .data, .aiChats]
}

enum FireContext {
    case manualFire              // User pressed Fire Button
    case autoClearOnLaunch       // Auto-clear during app launch
    case autoClearOnForeground   // Auto-clear after period of inactivity when returning to foreground
}

protocol FireExecutorDelegate: AnyObject {
    func willStartBurning(fireContext: FireContext)
    func willStartBurningTabs(fireContext: FireContext)
    func didFinishBurningTabs(fireContext: FireContext)
    func willStartBurningData(fireContext: FireContext)
    func didFinishBurningData(fireContext: FireContext)
    func willStartBurningAIHistory(fireContext: FireContext)
    func didFinishBurningAIHistory(fireContext: FireContext)
    func didFinishBurning(fireContext: FireContext)
}

protocol FireExecuting {
    @MainActor func prepare(for options: FireOptions)
    @MainActor func burn(options: FireOptions,
                         applicationState: DataStoreWarmup.ApplicationState,
                         fireContext: FireContext) async
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
    
    weak var delegate: FireExecutorDelegate?
    private var burnInProgress = false
    private var dataStoreWarmup: DataStoreWarmup? = DataStoreWarmup()
    private let aiChatHistoryCleaner: HistoryCleaning
    private var preparedOptions: FireOptions = []
    
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
         appSettings: AppSettings) {
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
    }

    
    // MARK: - Public Functions
    @MainActor
    func prepare(for options: FireOptions) {
        // Only prepare tabs if requested and not already prepared
        if options.contains(.tabs) && !preparedOptions.contains(.tabs) {
            prepareForBurningTabs()
        }
        preparedOptions.formUnion(options)
    }
    
    @MainActor
    func burn(options: FireOptions,
              applicationState: DataStoreWarmup.ApplicationState = .unknown,
              fireContext: FireContext) async {
        assert(delegate != nil, "Delegate should not be nil. This leads to unexpected behavior.")
        
        // Ensure all requested options are prepared
        let unpreparedOptions = options.subtracting(preparedOptions)
        if !unpreparedOptions.isEmpty {
            prepare(for: unpreparedOptions)
        }
        
        delegate?.willStartBurning(fireContext: fireContext)
        if options.contains(.tabs) {
            delegate?.willStartBurningTabs(fireContext: fireContext)
            burnTabs()
            delegate?.didFinishBurningTabs(fireContext: fireContext)
        }
        
        cancelOngoingDownloadsIfNeeded(options)

        let shouldBurnData = options.contains(.data)
        
        // For auto-clear with enhancedDataClearingSettings FF ON:
        // - User configures what to clear via the enhanced settings UI
        // For manual fire OR auto-clear with FF OFF (legacy):
        // - AI chats clear only if autoClearAIChatHistory setting is enabled
        let chosenThroughNewAutoClearUI = featureFlagger.isFeatureOn(.enhancedDataClearingSettings) && fireContext != .manualFire
        let shouldAllowAIChatsBurn = chosenThroughNewAutoClearUI || appSettings.autoClearAIChatHistory
        
        let shouldBurnAIChats = options.contains(.aiChats) && shouldAllowAIChatsBurn

        if shouldBurnData { delegate?.willStartBurningData(fireContext: fireContext) }
        if shouldBurnAIChats { delegate?.willStartBurningAIHistory(fireContext: fireContext) }

        async let dataTask: Void = shouldBurnData ? burnData(applicationState: applicationState) : ()
        async let aiTask: Void = shouldBurnAIChats ? burnAIHistory() : ()
        _ = await (dataTask, aiTask)

        if shouldBurnData { delegate?.didFinishBurningData(fireContext: fireContext) }
        if shouldBurnAIChats { delegate?.didFinishBurningAIHistory(fireContext: fireContext) }
        delegate?.didFinishBurning(fireContext: fireContext)
        
        // Reset prepared state for next burn cycle
        preparedOptions = []
    }
    
    // MARK: - Clearing Downloads
    
    private func cancelOngoingDownloadsIfNeeded(_ options: FireOptions) {
        guard options.contains(.tabs), options.contains(.data) else {
            return
        }
        downloadManager.cancelAllDownloads()
    }
    
    // MARK: Burn Tabs Helpers
    @MainActor
    private func prepareForBurningTabs() {
        tabManager.prepareAllTabsExceptCurrentForDataClearing()
    }
    
    @MainActor
    private func burnTabs() {
        tabManager.prepareCurrentTabForDataClearing()
        tabManager.removeAll()
        Favicons.shared.clearCache(.tabs)
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
