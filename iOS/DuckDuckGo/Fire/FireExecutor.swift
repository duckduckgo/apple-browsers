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
    }
    
    enum Scope {
        case tab(viewModel: TabViewModel)
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
    
    typealias HistoryCleanerProvider = () -> HistoryCleaning
    
    // MARK: - Variables
    
    private let tabManager: TabManaging
    private let downloadManager: DownloadManaging
    private let websiteDataManager: WebsiteDataManaging
    private let daxDialogsManager: DaxDialogsManaging
    private let syncService: DDGSyncing
    private weak var bookmarksDatabaseCleaner: BookmarkDatabaseCleaning?
    private let fireproofing: Fireproofing
    private let textZoomCoordinatorProvider: TextZoomCoordinatorProviding
    private let autoconsentManagementProvider: AutoconsentManagementProviding
    private let historyManager: HistoryManaging
    private let featureFlagger: FeatureFlagger
    private let dataClearingCapability: DataClearingCapable
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let dataStore: (any DDGWebsiteDataStore)?
    private let appSettings: AppSettings
    private let privacyStats: PrivacyStatsProviding?
    private let aiChatSyncCleaner: AIChatSyncCleaning
    let pixelsReporter: DataClearingPixelsReporter
    private let dataClearingWideEventService: DataClearingWideEventService?

    weak var delegate: FireExecutorDelegate?
    private var burnInProgress = false
    private var dataStoreWarmup: DataStoreWarmup? = DataStoreWarmup()
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
         wideEvent: WideEventManaging? = nil) {
        self.tabManager = tabManager
        self.downloadManager = downloadManager
        self.websiteDataManager = websiteDataManager
        self.daxDialogsManager = daxDialogsManager
        self.syncService = syncService
        self.bookmarksDatabaseCleaner = bookmarksDatabaseCleaner
        self.fireproofing = fireproofing
        self.textZoomCoordinatorProvider = textZoomCoordinatorProvider
        self.autoconsentManagementProvider = autoconsentManagementProvider
        self.historyManager = historyManager
        self.featureFlagger = featureFlagger
        self.dataClearingCapability = dataClearingCapability ?? DataClearingCapability.create(using: featureFlagger)
        self.privacyConfigurationManager = privacyConfigurationManager
        self.dataStore = dataStore
        self.historyCleanerProvider = historyCleanerProvider ??
        { return HistoryCleaner(featureFlagger: featureFlagger,
                                privacyConfig: privacyConfigurationManager)}
        self.appSettings = appSettings
        self.privacyStats = privacyStats
        self.aiChatSyncCleaner = aiChatSyncCleaner
        self.pixelsReporter = pixelsReporter
        self.dataClearingWideEventService = wideEvent.map { DataClearingWideEventService(wideEvent: $0) }
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
            dataClearingWideEventService?.start(.clearTabs)
            let removeAllResult = tabManager.removeAll()
            dataClearingWideEventService?.update(.clearTabs, result: removeAllResult)
            dataClearingWideEventService?.start(.clearFaviconCache)
            let faviconResult = Favicons.shared.clearCache(.tabs)
            dataClearingWideEventService?.update(.clearFaviconCache, result: faviconResult)
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

        // This needs to happen only once per app launch
        if let dataStoreWarmup {
            await dataStoreWarmup.ensureReady(applicationState: applicationState)
            self.dataStoreWarmup = nil
        }

        switch scope {
        case .tab(let viewModel):
            await burnTabData(tabViewModel: viewModel, domains: domains)
        case .all:
            await burnAllData()
        }

        self.burnInProgress = false
    }
    
    @MainActor
    private func burnAllData() async {
        dataClearingWideEventService?.start(.clearURLCaches)
        URLSession.shared.configuration.urlCache?.removeAllCachedResponses()
        dataClearingWideEventService?.update(.clearURLCaches, result: .success(()))

        let pixel = TimedPixel(.forgetAllDataCleared)

        // If the user is on a version that uses containers, then we'll clear the current container, then migrate it. Otherwise
        //  this is the same as `WKWebsiteDataStore.default()`
        let storeToUse = dataStore ?? DDGWebsiteDataStoreProvider.current()
        let websiteDataResult = await websiteDataManager.clear(dataStore: storeToUse)
        updateWideEventWithWebsiteDataResults(websiteDataResult)

        pixel.fire(withAdditionalParameters: [PixelParameters.tabCount: "\(self.tabManager.currentTabsModel.count)"]) // TODO: - Customize based on browsing mode

        dataClearingWideEventService?.start(.clearAutoconsentManagementCache)
        let autoconsentResult = autoconsentManagementProvider.management(for: .normal).clearCache()
        dataClearingWideEventService?.update(.clearAutoconsentManagementCache, result: autoconsentResult)

        dataClearingWideEventService?.start(.clearDaxDialogsHeldURLData)
        let daxDialogsResult = daxDialogsManager.clearHeldURLData()
        dataClearingWideEventService?.update(.clearDaxDialogsHeldURLData, result: daxDialogsResult)

        if self.syncService.authState == .inactive {
            dataClearingWideEventService?.start(.clearBookmarkDatabase)
            self.bookmarksDatabaseCleaner?.cleanUpDatabaseNow()
            dataClearingWideEventService?.update(.clearBookmarkDatabase, result: .success(()))
        }

        dataClearingWideEventService?.start(.forgetTextZoom)
        let textZoomResult = self.forgetTextZoom()
        dataClearingWideEventService?.update(.forgetTextZoom, result: textZoomResult)

        dataClearingWideEventService?.start(.clearAllHistory)
        let historyResult = await historyManager.removeAllHistory()
        dataClearingWideEventService?.update(.clearAllHistory, result: historyResult)

        dataClearingWideEventService?.start(.clearPrivacyStats)
        let privacyStatsResult = await privacyStats?.clearPrivacyStats() ?? .success(())
        dataClearingWideEventService?.update(.clearPrivacyStats, result: privacyStatsResult)
    }
    
    @MainActor
    private func burnTabData(tabViewModel: TabViewModel, domains: [String]?) async {
        guard let domains else {
            Logger.general.error("Expected domains to be present when burning tab scoped data")
            return
        }

        let timedPixel = TimedPixel(.singleTabDataCleared)

        // If the user is on a version that uses containers, then we'll clear the current container, then migrate it. Otherwise
        //  this is the same as `WKWebsiteDataStore.default()`
        let storeToUse = dataStore ?? DDGWebsiteDataStoreProvider.current()

        // Async tasks
        async let websiteDataTask = websiteDataManager.clear(dataStore: storeToUse, forDomains: domains)
        async let historyTask = historyManager.removeBrowsingHistory(tabID: tabViewModel.tab.uid)
        async let contextualChatTask = deleteContextualChatIfNeeded(tabViewModel: tabViewModel)

        // Sync tasks
        dataClearingWideEventService?.start(.clearAutoconsentManagementCache)
        let autoconsentResult = autoconsentManagementProvider.management(for: tabViewModel.tab.autoconsentContext).clearCache(forDomains: domains)
        dataClearingWideEventService?.update(.clearAutoconsentManagementCache, result: autoconsentResult)

        dataClearingWideEventService?.start(.forgetTextZoom)
        let textZoomResult = forgetTextZoom(forDomains: domains)
        dataClearingWideEventService?.update(.forgetTextZoom, result: textZoomResult)

        // Await async tasks
        let (websiteDataResult, historyResult, contextualChatResult) = await (websiteDataTask, historyTask, contextualChatTask)
        updateWideEventWithWebsiteDataResults(websiteDataResult)
        if let historyResult {
            dataClearingWideEventService?.update(.clearAllHistory, actionResult: historyResult)
        }
        if let contextualChatResult {
            dataClearingWideEventService?.update(.deleteContextualAIChat, actionResult: contextualChatResult)
        }

        // Fire completion pixel with timing
        let tabType = tabViewModel.tab.isAITab ? "ai" : "web"
        timedPixel.fire(withAdditionalParameters: [
            PixelParameters.tabType: tabType,
            PixelParameters.domainsCount: "\(domains.count)"
        ])
    }
    
    private func forgetTextZoom() -> Result<Void, Error> {
        let allowedDomains = fireproofing.allowedDomains
        let coordinator = textZoomCoordinatorProvider.coordinator(for: .normal) // TODO: - Pass fire mode correctly. Also Fire mode ignores fireproofing.
        coordinator.resetTextZoomLevels(excludingDomains: allowedDomains)
        return .success(())
    }

    private func forgetTextZoom(forDomains domains: [String]) -> Result<Void, Error> {
        let allowedDomains = fireproofing.allowedDomains
        let coordinator = textZoomCoordinatorProvider.coordinator(for: .normal) // TODO: - Pass fire mode correctly. Also Fire mode ignores fireproofing.
        coordinator.resetTextZoomLevels(forVisitedDomains: domains, excludingDomains: allowedDomains)
        return .success(())
    }
    
    @MainActor
    private func deleteContextualChatIfNeeded(tabViewModel: TabViewModel) async -> ActionResult? {
        guard appSettings.autoClearAIChatHistory else {
            return nil
        }

        var interval = WideEvent.MeasuredInterval.startingNow()

        guard let contextualChatID = tabViewModel.currentContextualChatId else {
            interval.complete()
            return ActionResult(result: .success(()), measuredInterval: interval)
        }

        let result = await deleteChat(chatID: contextualChatID)
        switch result {
        case .success:
            tabManager.controller(for: tabViewModel.tab)?.aiChatContextualSheetCoordinator.clearActiveChat()
        case .failure:
            Logger.aiChat.debug("Failed to delete contextual ai chat")
        }

        interval.complete()
        return ActionResult(result: result, measuredInterval: interval)
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
        let chosenThroughNewAutoClearUI = dataClearingCapability.isEnhancedDataClearingEnabled && request.trigger != .manualFire

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
        case .all:
            result = await burnAllAIHistory(trigger: request.trigger)
        }
        dataClearingWideEventService?.update(.clearAIChatHistory, result: result)
    }
    
    private func burnAllAIHistory(trigger: FireRequest.Trigger) async -> Result<Void, Error> {
        let cleaner = historyCleanerProvider()
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
    
    private func burnTabAIHistory(tabViewModel: TabViewModel) async -> Result<Void, Error> {
        if let chatID = await tabViewModel.currentAIChatId {
            return await deleteChat(chatID: chatID)
        } else {
            Logger.aiChat.debug("No chatID found for tab, skipping single chat deletion")
            return .success(())
        }
    }

    private func recordAIChatsClearDate(trigger: FireRequest.Trigger) async {
        switch trigger {
        case .manualFire:
            await aiChatSyncCleaner.recordLocalClear(date: Date())
        case .autoClearOnLaunch, .autoClearOnForeground:
            await aiChatSyncCleaner.recordLocalClearFromAutoClearBackgroundTimestampIfPresent()
        }
    }

    @discardableResult
    private func deleteChat(chatID: String) async -> Result<Void, Error> {
        let cleaner = historyCleanerProvider()
        let result = await cleaner.deleteAIChat(chatID: chatID)
        switch result {
        case .success:
            DailyPixel.fireDailyAndCount(pixel: .aiChatSingleDeleteSuccessful)
            await aiChatSyncCleaner.recordChatDeletion(chatID: chatID)
        case .failure(let error):
            DailyPixel.fireDailyAndCount(pixel: .aiChatSingleDeleteFailed)
            Logger.aiChat.debug("Failed to delete AI Chat: \(error.localizedDescription)")
            if let userScriptError = error as? UserScriptError {
                userScriptError.fireLoadJSFailedPixelIfNeeded()
            }
        }
        return result
    }

    private func updateWideEventWithWebsiteDataResults(_ result: WebsiteDataClearingResult) {
        dataClearingWideEventService?.update(.clearSafelyRemovableWebsiteData, actionResult: result.safelyRemovableData)
        dataClearingWideEventService?.update(.clearFireproofableDataForNonFireproofDomains, actionResult: result.fireproofableData)
        dataClearingWideEventService?.update(.clearCookiesForNonFireproofedDomains, actionResult: result.cookies)
        dataClearingWideEventService?.update(.removeObservationsData, actionResult: result.observationsData)
        if let removeContainersResult = result.removeAllContainersAfterDelay {
            dataClearingWideEventService?.update(.removeAllContainersAfterDelay, actionResult: removeContainersResult)
        }
    }
}
