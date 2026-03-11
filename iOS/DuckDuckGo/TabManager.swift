//
//  TabManager.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

import Common
import Core
import DDGSync
import WebKit
import BrowserServicesKit
import Persistence
import History
import Subscription
import os.log
import AIChat
import Combine
import PrivacyConfig
import WebExtensions

protocol TabManaging {
    var currentTabsModel: TabsModelManaging { get }
    @MainActor func prepareAllTabsExceptCurrentForDataClearing()
    @MainActor func prepareCurrentTabForDataClearing()
    func removeAll()
    @MainActor func viewModelForCurrentTab() -> TabViewModel?
    @MainActor func prepareTab(_ tab: Tab)
    @MainActor func isCurrentTab(_ tab: Tab) -> Bool
    @MainActor func closeTab(_ tab: Tab,
                             shouldCreateEmptyTabAtSamePosition: Bool,
                             clearTabHistory: Bool)
    func controller(for tab: Tab) -> TabViewController?
    /// Closes the tab and navigates to homepage reusing an existing homepage or creating a new one
    @MainActor func closeTabAndNavigateToHomepage(_ tab: Tab, clearTabHistory: Bool)
    @MainActor func setBrowsingMode(_ mode: BrowsingMode)
}

/// Receives lifecycle events for TabViewController instances managed by TabManager.
@MainActor
protocol TabControllerCacheDelegate: AnyObject {
    /// Called when a new TabViewController has been created and added to the cache for the first time.
    func tabManager(_ tabManager: TabManager, didCreateController controller: TabViewController)
    /// Called when a background tab's WebKit process terminated and its controller was evicted
    /// from the cache. The tab still exists in the model; a replacement will be created on next activation.
    func tabManager(_ tabManager: TabManager, didInvalidateController controller: TabViewController)
}

protocol TrackerAnimationSuppressing {
    @MainActor func markTabAsExternalLaunch(_ tab: Tab)
    @MainActor func clearExternalLaunchFlags()
    @MainActor func setSuppressTrackerAnimationOnFirstLoad(for tab: Tab, shouldSuppress: Bool)
    @MainActor func applyTrackerAnimationSuppressionBasedOnLaunchSource()
}

class TabManager: TabManaging, TrackerAnimationSuppressing {

    private let tabsModelProvider: TabsModelProviding
    private var fireModeCapability: FireModeCapable {
        FireModeCapability.create(using: featureFlagger)
    }
    private var _currentBrowsingMode: BrowsingMode = .normal
    var currentBrowsingMode: BrowsingMode {
        guard fireModeCapability.isFireModeEnabled else {
            return .normal
        }
        return _currentBrowsingMode
    }
    
    var currentTabsModel: TabsModelManaging {
        switch currentBrowsingMode {
        case .fire:
            return tabsModelProvider.fireModeTabsModel
        case .normal:
            return tabsModelProvider.normalTabsModel
        }
    }
    
    var allTabsModel: TabsModelReading {
        tabsModelProvider.aggregateTabsModel
    }
    
    private var tabControllerCache = [TabViewController]()

    weak var cacheDelegate: (any TabControllerCacheDelegate)?

    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let bookmarksDatabase: CoreDataDatabase
    private let historyManager: HistoryManaging
    private let syncService: DDGSyncing
    private let userScriptsDependencies: DefaultScriptSourceProvider.Dependencies
    private let contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>
    private var previewsSource: TabPreviewsSource
    private let interactionStateSource: TabInteractionStateSource?
    private var subscriptionDataReporter: SubscriptionDataReporting
    private let contextualOnboardingPresenter: ContextualOnboardingPresenting
    private let contextualOnboardingLogic: ContextualOnboardingLogic
    private let onboardingPixelReporter: OnboardingPixelReporting
    private let featureFlagger: FeatureFlagger
    private let contentScopeExperimentManager: ContentScopeExperimentsManaging
    private let textZoomCoordinatorProvider: TextZoomCoordinatorProviding
    private let autoconsentManagementProvider: AutoconsentManagementProviding
    private let fireproofing: Fireproofing
    private let websiteDataManager: WebsiteDataManaging
    private let appSettings: AppSettings
    private let maliciousSiteProtectionManager: MaliciousSiteProtectionManaging
    private let maliciousSiteProtectionPreferencesManager: MaliciousSiteProtectionPreferencesManaging
    private let featureDiscovery: FeatureDiscovery
    private let keyValueStore: ThrowingKeyValueStoring
    private let daxDialogsManager: DaxDialogsManaging
    private let aiChatSettings: AIChatSettingsProvider
    private let productSurfaceTelemetry: ProductSurfaceTelemetry
    private let sharedSecureVault: (any AutofillSecureVault)?
    private let privacyStats: PrivacyStatsProviding
    private let voiceSearchHelper: VoiceSearchHelperProtocol
    private var webExtensionManager: WebExtensionManaging?
    private let launchSourceManager: LaunchSourceManaging
    private let darkReaderFeatureSettings: DarkReaderFeatureSettings

    weak var delegate: TabDelegate?
    weak var aiChatContentDelegate: AIChatContentHandlingDelegate?

    @UserDefaultsWrapper(key: .faviconTabsCacheNeedsCleanup, defaultValue: true)
    var tabsCacheNeedsCleanup: Bool

    @MainActor
    init(tabsModelProvider: TabsModelProviding,
         previewsSource: TabPreviewsSource,
         interactionStateSource: TabInteractionStateSource?,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         bookmarksDatabase: CoreDataDatabase,
         historyManager: HistoryManaging,
         syncService: DDGSyncing,
         userScriptsDependencies: DefaultScriptSourceProvider.Dependencies,
         contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>,
         subscriptionDataReporter: SubscriptionDataReporting,
         contextualOnboardingPresenter: ContextualOnboardingPresenting,
         contextualOnboardingLogic: ContextualOnboardingLogic,
         onboardingPixelReporter: OnboardingPixelReporting,
         featureFlagger: FeatureFlagger,
         contentScopeExperimentManager: ContentScopeExperimentsManaging,
         appSettings: AppSettings,
         textZoomCoordinatorProvider: TextZoomCoordinatorProviding,
         autoconsentManagementProvider: AutoconsentManagementProviding,
         websiteDataManager: WebsiteDataManaging,
         fireproofing: Fireproofing,
         maliciousSiteProtectionManager: MaliciousSiteProtectionManaging,
         maliciousSiteProtectionPreferencesManager: MaliciousSiteProtectionPreferencesManaging,
         featureDiscovery: FeatureDiscovery,
         keyValueStore: ThrowingKeyValueStoring,
         daxDialogsManager: DaxDialogsManaging,
         aiChatSettings: AIChatSettingsProvider,
         productSurfaceTelemetry: ProductSurfaceTelemetry,
         sharedSecureVault: (any AutofillSecureVault)? = nil,
         privacyStats: PrivacyStatsProviding,
         voiceSearchHelper: VoiceSearchHelperProtocol,
         launchSourceManager: LaunchSourceManaging,
         darkReaderFeatureSettings: DarkReaderFeatureSettings
    ) {
        self.tabsModelProvider = tabsModelProvider
        self.previewsSource = previewsSource
        self.interactionStateSource = interactionStateSource
        self.privacyConfigurationManager = privacyConfigurationManager
        self.bookmarksDatabase = bookmarksDatabase
        self.historyManager = historyManager
        self.syncService = syncService
        self.userScriptsDependencies = userScriptsDependencies
        self.contentBlockingAssetsPublisher = contentBlockingAssetsPublisher
        self.subscriptionDataReporter = subscriptionDataReporter
        self.contextualOnboardingPresenter = contextualOnboardingPresenter
        self.contextualOnboardingLogic = contextualOnboardingLogic
        self.onboardingPixelReporter = onboardingPixelReporter
        self.featureFlagger = featureFlagger
        self.contentScopeExperimentManager = contentScopeExperimentManager
        self.appSettings = appSettings
        self.textZoomCoordinatorProvider = textZoomCoordinatorProvider
        self.autoconsentManagementProvider = autoconsentManagementProvider
        self.websiteDataManager = websiteDataManager
        self.fireproofing = fireproofing
        self.maliciousSiteProtectionManager = maliciousSiteProtectionManager
        self.maliciousSiteProtectionPreferencesManager = maliciousSiteProtectionPreferencesManager
        self.featureDiscovery = featureDiscovery
        self.keyValueStore = keyValueStore
        self.daxDialogsManager = daxDialogsManager
        self.aiChatSettings = aiChatSettings
        self.productSurfaceTelemetry = productSurfaceTelemetry
        self.sharedSecureVault = sharedSecureVault
        self.privacyStats = privacyStats
        self.voiceSearchHelper = voiceSearchHelper
        self.launchSourceManager = launchSourceManager
        self.darkReaderFeatureSettings = darkReaderFeatureSettings
        registerForNotifications()
    }

    func setWebExtensionManager(_ manager: WebExtensionManaging?) {
        self.webExtensionManager = manager
    }

    func tabsModel(for mode: BrowsingMode) -> TabsModelManaging {
        switch mode {
        case .fire: return tabsModelProvider.fireModeTabsModel
        case .normal: return tabsModelProvider.normalTabsModel
        }
    }

    @MainActor
    func setBrowsingMode(_ mode: BrowsingMode) {
        guard mode != currentBrowsingMode else {
            return
        }
        _currentBrowsingMode = mode
        // TODO: - Fire pixel
    }

    @MainActor
    private func buildController(forTab tab: Tab, inheritedAttribution: AdClickAttributionLogic.State?, interactionState: Data?) -> TabViewController {
        let url = tab.link?.url
        return buildController(forTab: tab, url: url, inheritedAttribution: inheritedAttribution, interactionState: interactionState)
    }

    @MainActor
    private func buildController(forTab tab: Tab,
                                 url: URL?,
                                 inheritedAttribution: AdClickAttributionLogic.State?,
                                 interactionState: Data?) -> TabViewController {
        let configuration = WKWebViewConfiguration.persistent(fireMode: tab.fireTab)

        if #available(iOS 18.4, *), let webExtensionManager = webExtensionManager {
            configuration.webExtensionController = webExtensionManager.controller
        }

        let specialErrorPageNavigationHandler = SpecialErrorPageNavigationHandler(
            maliciousSiteProtectionNavigationHandler: MaliciousSiteProtectionNavigationHandler(
                maliciousSiteProtectionManager: maliciousSiteProtectionManager
            )
        )

        let textZoomCoordinator = textZoomCoordinatorProvider.coordinator(for: tab.textZoomContext)
        let autoconsentManagement = autoconsentManagementProvider.management(for: tab.autoconsentContext)
        let controller = TabViewController.loadFromStoryboard(model: tab,
                                                              privacyConfigurationManager: privacyConfigurationManager,
                                                              bookmarksDatabase: bookmarksDatabase,
                                                              historyManager: historyManager,
                                                              syncService: syncService,
                                                              userScriptsDependencies: userScriptsDependencies,
                                                              contentBlockingAssetsPublisher: contentBlockingAssetsPublisher,
                                                              subscriptionDataReporter: subscriptionDataReporter,
                                                              contextualOnboardingPresenter: contextualOnboardingPresenter,
                                                              contextualOnboardingLogic: contextualOnboardingLogic,
                                                              onboardingPixelReporter: onboardingPixelReporter,
                                                              featureFlagger: featureFlagger,
                                                              contentScopeExperimentManager: contentScopeExperimentManager,
                                                              textZoomCoordinator: textZoomCoordinator,
                                                              autoconsentManagement: autoconsentManagement,
                                                              websiteDataManager: websiteDataManager,
                                                              fireproofing: fireproofing,
                                                              tabInteractionStateSource: interactionStateSource,
                                                              specialErrorPageNavigationHandler: specialErrorPageNavigationHandler,
                                                              featureDiscovery: featureDiscovery,
                                                              keyValueStore: keyValueStore,
                                                              daxDialogsManager: daxDialogsManager,
                                                              aiChatSettings: aiChatSettings,
                                                              productSurfaceTelemetry: productSurfaceTelemetry,
                                                              sharedSecureVault: sharedSecureVault,
                                                              privacyStats: privacyStats,
                                                              voiceSearchHelper: voiceSearchHelper,
                                                              darkReaderFeatureSettings: darkReaderFeatureSettings)
        controller.applyInheritedAttribution(inheritedAttribution)
        controller.attachWebView(configuration: configuration,
                                 interactionStateData: interactionState,
                                 andLoadRequest: url == nil ? nil : URLRequest.userInitiated(url!),
                                 consumeCookies: !currentTabsModel.hasActiveTabs)
        controller.delegate = delegate
        controller.aiChatContentHandlingDelegate = aiChatContentDelegate
        controller.loadViewIfNeeded()
        return controller
    }

    @MainActor
    func current(createIfNeeded: Bool = false) -> TabViewController? {
        guard let tab = currentTabsModel.currentTab else { return nil }

        if let controller = controller(for: tab) {
            return controller
        } else if createIfNeeded {
            Logger.general.debug("Tab not in cache, creating")
            let tabInteractionState = interactionStateSource?.popLastStateForTab(tab)
            let controller = buildController(forTab: tab, inheritedAttribution: nil, interactionState: tabInteractionState)
            tabControllerCache.append(controller)
            cacheDelegate?.tabManager(self, didCreateController: controller)
            return controller
        } else {
            return nil
        }
    }
    
    func controller(for tab: Tab) -> TabViewController? {
        return tabControllerCache.first { $0.tabModel === tab }
    }

    @MainActor
    func viewModel(for tab: Tab) -> TabViewModel {
        if let controller = controller(for: tab) {
            return controller.viewModel
        } else {
            return TabViewModel(tab: tab, historyManager: historyManager)
        }
    }

    @MainActor
    func viewModelForCurrentTab() -> TabViewModel? {
        guard let tab = currentTabsModel.currentTab else { return nil }
        return viewModel(for: tab)
    }

    @MainActor
    func addURLRequest(_ request: URLRequest?,
                       with configuration: WKWebViewConfiguration,
                       inheritedAttribution: AdClickAttributionLogic.State?,
                       in tabsModel: TabsModelManaging? = nil) -> TabViewController {

        let model = tabsModel ?? currentTabsModel
        guard let configCopy = configuration.copy() as? WKWebViewConfiguration else {
            fatalError("Failed to copy configuration")
        }

        let shouldCreateFireTab = model.shouldCreateFireTabs
        if #available(iOS 18.4, *), let webExtensionManager = webExtensionManager {
            configCopy.webExtensionController = webExtensionManager.controller
        }

        let tab: Tab
        if let request {
            tab = Tab(link: request.url == nil ? nil : Link(title: nil, url: request.url!), fireTab: shouldCreateFireTab)
        } else {
            tab = Tab(fireTab: shouldCreateFireTab)
        }
        model.insert(tab: tab, placement: .afterCurrentTab, selectNewTab: true)

        let specialErrorPageNavigationHandler = SpecialErrorPageNavigationHandler(
            maliciousSiteProtectionNavigationHandler: MaliciousSiteProtectionNavigationHandler(
                maliciousSiteProtectionManager: maliciousSiteProtectionManager
            )
        )

        let textZoomCoordinator = textZoomCoordinatorProvider.coordinator(for: tab.textZoomContext)
        let autoconsentManagement = autoconsentManagementProvider.management(for: tab.autoconsentContext)
        let controller = TabViewController.loadFromStoryboard(model: tab,
                                                              privacyConfigurationManager: privacyConfigurationManager,
                                                              bookmarksDatabase: bookmarksDatabase,
                                                              historyManager: historyManager,
                                                              syncService: syncService,
                                                              userScriptsDependencies: userScriptsDependencies,
                                                              contentBlockingAssetsPublisher: contentBlockingAssetsPublisher,
                                                              subscriptionDataReporter: subscriptionDataReporter,
                                                              contextualOnboardingPresenter: contextualOnboardingPresenter,
                                                              contextualOnboardingLogic: contextualOnboardingLogic,
                                                              onboardingPixelReporter: onboardingPixelReporter,
                                                              featureFlagger: featureFlagger,
                                                              contentScopeExperimentManager: contentScopeExperimentManager,
                                                              textZoomCoordinator: textZoomCoordinator,
                                                              autoconsentManagement: autoconsentManagement,
                                                              websiteDataManager: websiteDataManager,
                                                              fireproofing: fireproofing,
                                                              tabInteractionStateSource: interactionStateSource,
                                                              specialErrorPageNavigationHandler: specialErrorPageNavigationHandler,
                                                              featureDiscovery: featureDiscovery,
                                                              keyValueStore: keyValueStore,
                                                              daxDialogsManager: daxDialogsManager,
                                                              aiChatSettings: aiChatSettings,
                                                              productSurfaceTelemetry: productSurfaceTelemetry,
                                                              sharedSecureVault: sharedSecureVault,
                                                              privacyStats: privacyStats,
                                                              voiceSearchHelper: voiceSearchHelper,
                                                              darkReaderFeatureSettings: darkReaderFeatureSettings)
        controller.attachWebView(configuration: configCopy,
                                 andLoadRequest: request,
                                 consumeCookies: !model.hasActiveTabs,
                                 loadingInitiatedByParentTab: true)
        controller.delegate = delegate
        controller.loadViewIfNeeded()
        controller.applyInheritedAttribution(inheritedAttribution)
        tabControllerCache.append(controller)
        cacheDelegate?.tabManager(self, didCreateController: controller)

        save()
        return controller
    }

    func addHomeTab(in tabsModel: TabsModelManaging? = nil) {
        let model = tabsModel ?? currentTabsModel
        let tab = Tab(fireTab: model.shouldCreateFireTabs)
        model.insert(tab: tab, placement: .atEnd, selectNewTab: true)
        save()
    }

    func firstHomeTab(in tabsModel: TabsModelManaging? = nil) -> Tab? {
        let model = tabsModel ?? currentTabsModel
        return model.tabs.first(where: { $0.link == nil })
    }

    func first(withId id: String, in tabsModel: TabsModelManaging? = nil) -> Tab? {
        let model = tabsModel ?? currentTabsModel
        return model.tabs.first { $0.uid == id }
    }

    func first(withUrl url: URL, in tabsModel: TabsModelManaging? = nil) -> Tab? {
        let model = tabsModel ?? currentTabsModel
        return model.tabs.first(where: {
            guard let linkUrl = $0.link?.url else { return false }

            if linkUrl == url {
                return true
            }

            if linkUrl.scheme == "https" && url.scheme == "http" {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                components?.scheme = "https"
                return components?.url == linkUrl
            }

            return false
        })
    }

    @MainActor
    @discardableResult
    func select(_ tab: Tab, forcingMode: Bool = false, dismissCurrent: Bool = true, in tabsModel: TabsModelManaging? = nil) -> TabViewController? {
        if forcingMode {
            setBrowsingMode(tab.mode)
        }
        let model = tabsModel ?? currentTabsModel
        if dismissCurrent {
            current()?.dismiss()
        }
        model.select(tab: tab)
        save()
        return current(createIfNeeded: true)
    }

    @MainActor
    func add(url: URL?,
             inBackground: Bool = false,
             inheritedAttribution: AdClickAttributionLogic.State?,
             in tabsModel: TabsModelManaging? = nil) -> TabViewController {

        let model = tabsModel ?? currentTabsModel
        if !inBackground {
            current()?.dismiss()
        }

        let link = url == nil ? nil : Link(title: nil, url: url!)
        let tab = Tab(link: link, fireTab: model.shouldCreateFireTabs)
        let controller = buildController(forTab: tab, url: url, inheritedAttribution: inheritedAttribution, interactionState: nil)
        tabControllerCache.append(controller)

        model.insert(tab: tab, placement: .afterCurrentTab, selectNewTab: !inBackground)

        cacheDelegate?.tabManager(self, didCreateController: controller)

        save()
        return controller
    }

    /// Warning! This will leave the underlying tabs empty.  This is intentional so that the the
    ///  Tab Switcher's UICollectionView 'delete items' function doesn't complain about mis-matching
    ///   number of items.
    func bulkRemoveTabs(_ tabs: [Tab], in tabsModel: TabsModelManaging? = nil) {
        let model = tabsModel ?? currentTabsModel
        model.removeTabs(tabs)
        clean(tabs: tabs, clearTabHistory: true)
        save()
    }

    func remove(tab: Tab, clearTabHistory: Bool = true, in tabsModel: TabsModelManaging? = nil) {
        let model = tabsModel ?? currentTabsModel
        model.remove(tab: tab)
        clean(tabs: [tab], clearTabHistory: clearTabHistory)
        save()
    }

    func replace(tab: Tab, withNewTab newTab: Tab, clearTabHistory: Bool = true, in tabsModel: TabsModelManaging? = nil) {
        let model = tabsModel ?? currentTabsModel
        if model.tabs.count == 1 { // TODO: - Remove this for fire tabs
            remove(tab: tab, clearTabHistory: clearTabHistory, in: model)
        } else {
            model.insert(tab: newTab, placement: .replacing(tab), selectNewTab: false)
            clean(tabs: [tab], clearTabHistory: clearTabHistory)
        }
        save()
    }

    private func removeFromCache(_ controller: TabViewController) {
        if let index = tabControllerCache.firstIndex(of: controller) {
            tabControllerCache.remove(at: index)
        }
        controller.dismiss()
    }

    func removeAll() {
        // TODO: - Handle fire mode burns
        let tabIDs = currentTabsModel.tabs.map { $0.uid }
        previewsSource.removeAllPreviews()
        currentTabsModel.clearAll()
        for controller in tabControllerCache {
            removeFromCache(controller)
        }
        interactionStateSource?.removeAll(excluding: [])
        removeTabHistory(for: tabIDs)
        save()
    }

    func removeLeftoverInteractionStates() {
        interactionStateSource?.removeAll(excluding: allTabsModel.tabs)
    }

    @MainActor
    func invalidateCache(forController controller: TabViewController) {
        if current() === controller {
            Pixel.fire(pixel: .webKitTerminationDidReloadCurrentTab)
            current()?.reload()
        } else {
            removeFromCache(controller)
            cacheDelegate?.tabManager(self, didInvalidateController: controller)
        }
    }

    func save() {
        tabsModelProvider.save()
    }

    @MainActor
    func prepareAllTabsExceptCurrentForDataClearing() {
        tabControllerCache.filter { $0 !== current() }.forEach { $0.prepareForDataClearing() }
    }
    
    @MainActor
    func prepareCurrentTabForDataClearing() {
        current()?.prepareForDataClearing()
    }
    
    @MainActor
    func prepareTab(_ tab: Tab) {
        controller(for: tab)?.prepareForDataClearing()
    }
    
    @MainActor
    func isCurrentTab(_ tab: Tab) -> Bool {
        currentTabsModel.currentTab === tab
    }
    
    @MainActor
    func closeTab(_ tab: Tab, shouldCreateEmptyTabAtSamePosition: Bool, clearTabHistory: Bool) {
        let behavior: TabClosingBehavior = shouldCreateEmptyTabAtSamePosition ? .createEmptyTabAtSamePosition : .onlyClose
        delegate?.tabDidRequestClose(tab,
                                     behavior: behavior,
                                     clearTabHistory: clearTabHistory)
    }

    @MainActor
    func closeTabAndNavigateToHomepage(_ tab: Tab, clearTabHistory: Bool) {
        // Close the tab and create or reuse an empty tab
        delegate?.tabDidRequestClose(tab,
                                     behavior: .createOrReuseEmptyTab,
                                     clearTabHistory: clearTabHistory)
    }

    func cleanupTabsFaviconCache() {
        guard tabsCacheNeedsCleanup else { return }

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self,
                  let tabsCacheUrl = FaviconsCacheType.tabs.cacheLocation()?.appendingPathComponent(Favicons.Constants.tabsCachePath),
                  let contents = try? FileManager.default.contentsOfDirectory(at: tabsCacheUrl, includingPropertiesForKeys: nil, options: []),
                    !contents.isEmpty else { return }

            let imageDomainURLs = contents.compactMap({ $0.filename })

            // create a Set of all unique hosts in case there are hundreds of tabs with many duplicate hosts
            let tabLink = Set(self.allTabsModel.tabs.compactMap { tab in
                if let host = tab.link?.url.host {
                    return host
                }

                return nil
            })

            // hash the unique tab hosts
            let tabLinksHashed = tabLink.map { FaviconHasher.createHash(ofDomain: $0) }

            // filter images that don't have a corresponding tab
            let toDelete = imageDomainURLs.filter { !tabLinksHashed.contains($0) }
            toDelete.forEach {
                Favicons.shared.removeTabFavicon(forCacheKey: $0)
            }

            self.tabsCacheNeedsCleanup = false
        }
    }

    // MARK: - Tab Cleanup
    
    private func clean(tabs: [Tab], clearTabHistory: Bool) {
        let tabIDs = tabs.map { $0.uid }
        tabs.forEach { tab in
            previewsSource.removePreview(forTab: tab)
            if let controller = controller(for: tab) {
                removeFromCache(controller)
            }
            interactionStateSource?.removeStateForTab(tab)
        }
        if clearTabHistory {
            removeTabHistory(for: tabIDs)
        }
    }

    private func removeTabHistory(for tabIDs: [String]) {
        guard !tabIDs.isEmpty else { return }
        Task {
            await historyManager.removeTabHistory(for: tabIDs)
        }
    }
}


// MARK: - Debugging Pixels

extension TabManager {

    fileprivate func registerForNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onApplicationBecameActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
    }

    @objc
    private func onApplicationBecameActive(_ notification: NSNotification) {
        assertTabPreviewCount()
    }

    private func assertTabPreviewCount() {
        let totalStoredPreviews = previewsSource.totalStoredPreviews()
        let totalTabs = allTabsModel.tabs.count

        if let storedPreviews = totalStoredPreviews, storedPreviews > totalTabs {
            Pixel.fire(pixel: .cachedTabPreviewsExceedsTabCount, withAdditionalParameters: [
                PixelParameters.tabPreviewCountDelta: "\(storedPreviews - totalTabs)"
            ])
            Task(priority: .utility) {
                await previewsSource.removePreviewsWithIdNotIn(Set(allTabsModel.tabs.map { $0.uid }))
            }
        }
    }

    // MARK: - External Launch Management

    /// Clears all external launch flags. Should be called on app relaunch
    /// to ensure existing tabs are not treated as external launches.
    @MainActor
    func clearExternalLaunchFlags() {
        guard featureFlagger.isFeatureOn(.suppressTrackerAnimationOnColdStart) else {
            return
        }

        Logger.general.debug("Clearing external launch flags for all tabs")
        for tab in allTabsModel.tabs {
            tab.isExternalLaunch = false
        }
    }

    @MainActor
    func markTabAsExternalLaunch(_ tab: Tab) {
        guard featureFlagger.isFeatureOn(.suppressTrackerAnimationOnColdStart) else {
            return
        }

        guard !tab.isExternalLaunch else {
            return
        }
        Logger.general.debug("Marking tab \(tab.uid) as external launch")
        tab.isExternalLaunch = true
    }

    @MainActor
    func setSuppressTrackerAnimationOnFirstLoad(for tab: Tab, shouldSuppress: Bool) {
        guard featureFlagger.isFeatureOn(.suppressTrackerAnimationOnColdStart) else {
            return
        }

        guard tab.shouldSuppressTrackerAnimationOnFirstLoad != shouldSuppress else {
            return
        }
        Logger.general.debug("Setting suppressTrackerAnimation=\(shouldSuppress) for tab \(tab.uid)")
        tab.shouldSuppressTrackerAnimationOnFirstLoad = shouldSuppress
    }

    /// Applies tracker animation suppression logic to all tabs based on current launch source.
    /// - On cold start with standard launch: suppress tracker animations for all tabs
    /// - On external launch: tracker animation suppression handled per-tab via markTabAsExternalLaunch
    @MainActor
    func applyTrackerAnimationSuppressionBasedOnLaunchSource() {
        guard featureFlagger.isFeatureOn(.suppressTrackerAnimationOnColdStart) else {
            return
        }

        let source = launchSourceManager.source
        Logger.general.debug("Applying tracker animation suppression for launch source: \(source.rawValue)")

        switch source {
        case .standard:
            // On cold start with standard launch, suppress tracker animations for existing tabs with content
            for tab in allTabsModel.tabs {
                // Only suppress for tabs with non-DDG URLs (not NTP, not DDG search)
                guard let url = tab.link?.url, !url.isDuckDuckGoSearch else {
                    continue
                }

                tab.shouldSuppressTrackerAnimationOnFirstLoad = true

                // Also set on TabViewController if it exists
                if let controller = controller(for: tab) {
                    controller.shouldSuppressTrackerAnimationOnFirstLoad = true
                }
            }
        case .URL, .shortcut:
            // For external launches, only the newly created tab (marked via markTabAsExternalLaunch)
            // should have tracker animations, all other tabs must have animations suppressed (which is handled elsewhere)
            break
        }
    }

}

extension Tab {
    var mode: BrowsingMode {
        return fireTab ? .fire : .normal
    }
}
