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
    var allTabsModel: TabsModelReading { get }
    var currentBrowsingMode: BrowsingMode { get }
    func tabsModel(for mode: BrowsingMode) -> TabsModelManaging
    @MainActor func prepareAllTabsExceptCurrentForDataClearing(browsingMode: BrowsingMode?)
    @MainActor func prepareCurrentTabForDataClearing(browsingMode: BrowsingMode?)
    @MainActor func removeAll(browsingMode: BrowsingMode?) -> Result<Void, Error>
    @MainActor func viewModelForCurrentTab() -> TabViewModel?
    @MainActor func prepareTab(_ tab: Tab)
    @MainActor func isCurrentTab(_ tab: Tab) -> Bool
    @MainActor func closeTab(_ tab: Tab,
                             shouldCreateEmptyTabAtSamePosition: Bool,
                             clearTabHistory: Bool)
    func controller(for tab: Tab) -> TabViewController?
    /// Closes the tab and navigates to homepage reusing an existing homepage or creating a new one
    @MainActor func closeTabAndNavigateToHomepage(_ tab: Tab, clearTabHistory: Bool)
    @MainActor func closeTabAndOpenNewChat(_ tab: Tab, clearTabHistory: Bool)
    @MainActor func setBrowsingMode(_ mode: BrowsingMode, source: FireModeSwitchSource)
}

enum FireModeSwitchSource: String {
    case tabSelection = "tab_selection"
    case longPressTabsIcon = "long_press_tabs_icon"
    case menuPromotion = "menu_promotion"
    case ntpPromotion = "ntp_promotion"
    case longPressLink = "long_press_link"
    case tabSwitcherLongPress = "tab_switcher_long_press"
    case keyCommand = "key_command"
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

@MainActor
protocol TabManagerFireModeDelegate: AnyObject {
    func tabManagerDidCloseLastFireTab()
    func tabManagerDidChangeBrowsingMode(_ mode: BrowsingMode)
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
        FireModeCapability.create()
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
    
    var normalTabsModel: TabsModelManaging {
        tabsModelProvider.normalTabsModel
    }

    var fireModeTabsModel: TabsModelManaging {
        tabsModelProvider.fireModeTabsModel
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
    private let favicons: FaviconManaging
    private let websiteDataManager: WebsiteDataManaging
    private let appSettings: AppSettings
    private let autoplaySettings: AutoplaySettings
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
    private let toggleModeStorage: ToggleModeStoring
    private let fireModePromotionEligibility: FireModePromotionCoordinating?
    private let duckAiNativeStorageHandler: DuckAiNativeStorageHandling?
    private let duckAiFireModeStorageHandler: DuckAiNativeStorageHandling?

    // Save debouncing. Fires after `saveDebounceInterval` of quiet, or `saveMaxWait` since
    // the first call in the burst (whichever comes first) so sustained activity cannot push
    // the save out indefinitely.
    private static let saveDebounceInterval: DispatchTimeInterval = .milliseconds(300)
    private static let saveMaxWait: DispatchTimeInterval = .seconds(1)
    private var pendingSaveWorkItem: DispatchWorkItem?
    private var pendingSaveBurstDeadline: DispatchTime?

    /// Single app-lifetime instance shared across all tabs, MainViewController, and SettingsViewModel.
    let adBlockingAvailability: AdBlockingAvailabilityProviding

    weak var delegate: TabDelegate?
    weak var aiChatContentDelegate: AIChatContentHandlingDelegate?
    weak var fireModeDelegate: TabManagerFireModeDelegate?

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
         autoplaySettings: AutoplaySettings = DefaultAutoplaySettings(),
         textZoomCoordinatorProvider: TextZoomCoordinatorProviding,
         autoconsentManagementProvider: AutoconsentManagementProviding,
         websiteDataManager: WebsiteDataManaging,
         fireproofing: Fireproofing,
         favicons: FaviconManaging,
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
         darkReaderFeatureSettings: DarkReaderFeatureSettings,
         duckAiNativeStorageHandler: DuckAiNativeStorageHandling? = nil,
         duckAiFireModeStorageHandler: DuckAiNativeStorageHandling? = nil,
         toggleModeStorage: ToggleModeStoring = ToggleModeStorage(),
         fireModePromotionEligibility: FireModePromotionCoordinating? = nil,
         adBlockingAvailability: AdBlockingAvailabilityProviding
    ) {
        self.duckAiNativeStorageHandler = duckAiNativeStorageHandler
        self.duckAiFireModeStorageHandler = duckAiFireModeStorageHandler
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
        self.autoplaySettings = autoplaySettings
        self.textZoomCoordinatorProvider = textZoomCoordinatorProvider
        self.autoconsentManagementProvider = autoconsentManagementProvider
        self.websiteDataManager = websiteDataManager
        self.fireproofing = fireproofing
        self.favicons = favicons
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
        self.toggleModeStorage = toggleModeStorage
        self.darkReaderFeatureSettings = darkReaderFeatureSettings
        self.fireModePromotionEligibility = fireModePromotionEligibility
        self.adBlockingAvailability = adBlockingAvailability
        registerForNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }


    func setWebExtensionManager(_ manager: WebExtensionManaging?) {
        self.webExtensionManager = manager
    }
    
    @MainActor
    func setBrowsingMode(_ mode: BrowsingMode, source: FireModeSwitchSource) {
        guard mode != currentBrowsingMode else {
            return
        }
        _currentBrowsingMode = mode
        fireModeDelegate?.tabManagerDidChangeBrowsingMode(mode)
        if mode == .fire {
            fireModePromotionEligibility?.markFireModeVisited()
        }
        Pixel.fire(pixel: .browsingModeSwitched, withAdditionalParameters: [
            PixelParameters.browsingMode: mode.pixelParamValue,
            PixelParameters.source: source.rawValue
        ])
    }

    func tabsModel(for mode: BrowsingMode) -> TabsModelManaging {
        switch mode {
        case .fire: return tabsModelProvider.fireModeTabsModel
        case .normal: return tabsModelProvider.normalTabsModel
        }
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
        configuration.mediaTypesRequiringUserActionForPlayback = autoplaySettings.currentAutoplayBlockingMode.mediaTypesRequiringUserAction

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
                                                              favicons: favicons,
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
                                                              darkReaderFeatureSettings: darkReaderFeatureSettings,
                                                              autoplaySettings: autoplaySettings,
                                                              duckAiNativeStorageHandler: duckAiNativeStorageHandler,
                                                              duckAiFireModeStorageHandler: duckAiFireModeStorageHandler,
                                                              adBlockingAvailability: adBlockingAvailability)
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

    func controller(forWebView webView: WKWebView) -> TabViewController? {
        return tabControllerCache.first { $0.webView === webView }
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
                                                              favicons: favicons,
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
                                                              darkReaderFeatureSettings: darkReaderFeatureSettings,
                                                              autoplaySettings: autoplaySettings,
                                                              duckAiNativeStorageHandler: duckAiNativeStorageHandler,
                                                              duckAiFireModeStorageHandler: duckAiFireModeStorageHandler,
                                                              adBlockingAvailability: adBlockingAvailability)
        controller.attachWebView(configuration: configCopy,
                                 andLoadRequest: request,
                                 consumeCookies: !currentTabsModel.hasActiveTabs,
                                 loadingInitiatedByParentTab: true)
        controller.delegate = delegate
        controller.loadViewIfNeeded()
        controller.applyInheritedAttribution(inheritedAttribution)
        tabControllerCache.append(controller)
        cacheDelegate?.tabManager(self, didCreateController: controller)

        _ = save()
        return controller
    }

    @MainActor
    func addHomeTab(in tabsModel: TabsModelManaging? = nil) {
        let model = tabsModel ?? currentTabsModel
        let tab = Tab(fireTab: model.shouldCreateFireTabs)
        model.insert(tab: tab, placement: .atEnd, selectNewTab: true)
        _ = save()
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
    func select(_ tab: Tab, dismissCurrent: Bool = true, in tabsModel: TabsModelManaging? = nil) -> TabViewController? {
        setBrowsingMode(tab.mode, source: .tabSelection)
        let model = tabsModel ?? currentTabsModel
        if dismissCurrent {
            current()?.dismiss()
        }
        model.select(tab: tab)
        _ = save()
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
        if !inBackground {
            tab.viewed = true
        }

        cacheDelegate?.tabManager(self, didCreateController: controller)

        _ = save()
        return controller
    }

    /// Warning! This will leave the underlying tabs empty.  This is intentional so that the the
    ///  Tab Switcher's UICollectionView 'delete items' function doesn't complain about mis-matching
    ///   number of items.
    @MainActor
    func bulkRemoveTabs(_ tabs: [Tab], in tabsModel: TabsModelManaging? = nil) {
        let model = tabsModel ?? currentTabsModel
        model.removeTabs(tabs)
        clean(tabs: tabs, clearTabHistory: true)
        _ = save()
        notifyIfLastFireTabClosed(removedTabs: tabs)
    }

    @MainActor
    func remove(tab: Tab, clearTabHistory: Bool = true, in tabsModel: TabsModelManaging? = nil) {
        // Always ensure we're removing the Tab from its owner. This allows us to remove Fire Tabs, while in normal mode
        let model = tabsModel ?? self.tabsModel(for: tab.mode)
        model.remove(tab: tab)
        clean(tabs: [tab], clearTabHistory: clearTabHistory)
        _ = save()
        notifyIfLastFireTabClosed(removedTabs: [tab])
    }

    @MainActor
    func replace(tab: Tab, withNewTab newTab: Tab, clearTabHistory: Bool = true, in tabsModel: TabsModelManaging? = nil) {
        let model = tabsModel ?? currentTabsModel
        // In normal mode, removing the last tab auto-inserts a blank tab, so we skip
        // inserting newTab (the auto-created tab serves the same purpose).
        // In fire mode (allowsEmpty), no auto-insert happens, so we must always insert newTab.
        if model.tabs.count == 1 && !model.allowsEmpty && newTab.link == nil {
            // Since we're not re-inserting we should use the proper removal to ensure
            //  things are cleaned up properly.
            remove(tab: tab, clearTabHistory: clearTabHistory, in: model)
        } else if model.tabs.count == 1 && !model.allowsEmpty {
            // newTab has content (e.g. AI chat URL) so the auto-created blank won't suffice.
            // Use removeTabs (no auto-insert) to avoid ending up with both newTab and an
            // auto-created blank tab.
            model.removeTabs([tab])
            model.insert(tab: newTab, placement: .atEnd, selectNewTab: false)
            clean(tabs: [tab], clearTabHistory: clearTabHistory)
        } else {
            model.insert(tab: newTab, placement: .replacing(tab), selectNewTab: false)
            clean(tabs: [tab], clearTabHistory: clearTabHistory)
        }
        _ = save()
    }

    @MainActor
    private func notifyIfLastFireTabClosed(removedTabs: [Tab]) {
        guard removedTabs.contains(where: { $0.fireTab }),
              tabsModel(for: .fire).tabs.isEmpty else { return }
        fireModeDelegate?.tabManagerDidCloseLastFireTab()
    }

    @MainActor
    private func removeFromCache(_ controller: TabViewController) {
        if let index = tabControllerCache.firstIndex(of: controller) {
            tabControllerCache.remove(at: index)
        }
        controller.dismiss()
    }

    func removeLeftoverInteractionStates() {
        _ = interactionStateSource?.removeAll(excluding: allTabsModel.tabs)
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

    /// Schedules a debounced save. Returns immediately; the write is async. Callers that need
    /// the write on disk before returning, or that need the real write `Result`, must use
    /// `flushPendingSave()` instead. When the `tabsSaveOptimization` feature flag is off, falls
    /// back to a synchronous save (old behavior) but the result is still discarded.
    @MainActor
    func save() {
        guard featureFlagger.isFeatureOn(.tabsSaveOptimization) else {
            _ = tabsModelProvider.flushPendingSave()
            return
        }
        scheduleDebouncedSave()
    }

    /// Cancels any pending debounced save and persists synchronously, blocking until the write
    /// lands on disk. Used at lifecycle boundaries and the data-clearing path. Must run on the
    /// main actor: the inner `persistQueue.sync` would deadlock if invoked from a queue waiting
    /// on main.
    @MainActor
    @discardableResult
    func flushPendingSave() -> Result<Void, Error> {
        cancelPendingSave()
        return tabsModelProvider.flushPendingSave()
    }

    private func scheduleDebouncedSave() {
        // Debouncer state is main-queue only. Callers may invoke `save()` from any thread.
        let perform = { [weak self] in
            guard let self else { return }
            self.pendingSaveWorkItem?.cancel()
            let now = DispatchTime.now()
            let burstDeadline = self.pendingSaveBurstDeadline ?? (now + Self.saveMaxWait)
            self.pendingSaveBurstDeadline = burstDeadline
            let fireAt = min(now + Self.saveDebounceInterval, burstDeadline)
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingSaveWorkItem = nil
                self.pendingSaveBurstDeadline = nil
                _ = self.tabsModelProvider.save()
            }
            self.pendingSaveWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: fireAt, execute: workItem)
        }
        if Thread.isMainThread {
            perform()
        } else {
            DispatchQueue.main.async(execute: perform)
        }
    }

    private func cancelPendingSave() {
        let perform = { [weak self] in
            guard let self else { return }
            self.pendingSaveWorkItem?.cancel()
            self.pendingSaveWorkItem = nil
            self.pendingSaveBurstDeadline = nil
        }
        if Thread.isMainThread {
            perform()
        } else {
            DispatchQueue.main.sync(execute: perform)
        }
    }

    /// Prepares all tabs for upcoming data clearing, skipping the current tab
    /// - Parameter browsingMode: If provided, only prepares tabs matching the given mode. Otherwise, prepares all tabs.
    @MainActor
    func prepareAllTabsExceptCurrentForDataClearing(browsingMode: BrowsingMode? = nil) {
        tabControllerCache
            .filter { $0 !== current() && (browsingMode == nil || $0.tabModel.mode == browsingMode) }
            .forEach { $0.prepareForDataClearing() }
    }
    
    @MainActor
    func prepareCurrentTabForDataClearing(browsingMode: BrowsingMode? = nil) {
        guard let current = current(),
              browsingMode == nil || current.tabModel.mode == browsingMode else { return }
        current.prepareForDataClearing()
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
    
    @MainActor
    func closeTabAndOpenNewChat(_ tab: Tab, clearTabHistory: Bool) {
        // Close the tab and create or reuse an empty tab
        delegate?.tabDidRequestClose(tab,
                                     behavior: .createNewChat,
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
                self.favicons.removeTabFavicon(forCacheKey: $0)
            }

            self.tabsCacheNeedsCleanup = false
        }
    }

    // MARK: - Tab Cleanup
    
    @MainActor
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

// MARK: - Tabs Removal

extension TabManager {
    
    private struct TabsRemovalData {
        let tabsToDelete: [Tab]
        let tabsToPreserve: [Tab]
        let tabControllersToDelete: [TabViewController]
        let tabIDsToDelete: Set<String>
        let tabIDsToPreserve: Set<String>
        
        init(tabsToDelete: [Tab], tabsToPreserve: [Tab], tabControllersToDelete: [TabViewController]) {
            self.tabsToDelete = tabsToDelete
            self.tabsToPreserve = tabsToPreserve
            self.tabControllersToDelete = tabControllersToDelete
            self.tabIDsToDelete = Set(tabsToDelete.map { $0.uid })
            self.tabIDsToPreserve = Set(tabsToPreserve.map { $0.uid })
        }
    }
    
    @MainActor
    func removeAll(browsingMode: BrowsingMode? = nil) -> Result<Void, Error> {
        let tabsData = tabsRemovalData(browsingMode: browsingMode)

        let previewsResult = previewsSource.removePreviewsWithIdNotIn(tabsData.tabIDsToPreserve)
        tabsModelProvider.clearTabs(for: browsingMode)

        for controller in tabsData.tabControllersToDelete {
            removeFromCache(controller)
        }

        let interactionResult = interactionStateSource?.removeAll(excluding: tabsData.tabsToPreserve)
        removeTabHistory(for: Array(tabsData.tabIDsToDelete))
        // Data-clearing must land on disk before returning; debounced save is not sufficient here.
        let saveResult = flushPendingSave()

        if case .failure(let error) = previewsResult {
            return .failure(error)
        }
        if let interactionResult = interactionResult, case .failure(let error) = interactionResult {
            return .failure(error)
        }
        if case .failure(let error) = saveResult {
            return .failure(error)
        }
        return .success(())
    }
    
    private func tabsRemovalData(browsingMode: BrowsingMode?) -> TabsRemovalData {
        let tabsToDelete: [Tab]
        let tabsToPreserve: [Tab]
        let tabControllersToDelete: [TabViewController]
        switch browsingMode {
        case .fire:
            tabsToDelete = tabsModel(for: .fire).tabs
            tabControllersToDelete = tabControllerCache.filter { $0.tabModel.mode == .fire }
            tabsToPreserve = tabsModel(for: .normal).tabs
        case .normal:
            tabsToDelete = tabsModel(for: .normal).tabs
            tabControllersToDelete = tabControllerCache.filter { $0.tabModel.mode == .normal }
            tabsToPreserve = tabsModel(for: .fire).tabs
        case nil:
            tabsToDelete = allTabsModel.tabs
            tabControllersToDelete = tabControllerCache
            tabsToPreserve = []
        }
        return .init(tabsToDelete: tabsToDelete,
                     tabsToPreserve: tabsToPreserve,
                     tabControllersToDelete: tabControllersToDelete)
    }
}


// MARK: - Debugging Pixels

extension TabManager {

    fileprivate func registerForNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onApplicationBecameActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
        // Force-flush at lifecycle boundaries so a debounced save is not lost on suspend.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onApplicationWillResignActive),
                                               name: UIApplication.willResignActiveNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onApplicationWillTerminate),
                                               name: UIApplication.willTerminateNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onMemoryWarning),
                                               name: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil)
    }

    @MainActor
    @objc
    private func onApplicationBecameActive(_ notification: NSNotification) {
        assertTabPreviewCount()
    }

    @MainActor
    @objc
    private func onApplicationWillResignActive(_ notification: NSNotification) {
        flushPendingSave()
    }

    @MainActor
    @objc
    private func onApplicationWillTerminate(_ notification: NSNotification) {
        flushPendingSave()
    }

    @MainActor
    @objc
    private func onMemoryWarning(_ notification: NSNotification) {
        flushPendingSave()
    }

    private func assertTabPreviewCount() {
        let totalStoredPreviews = previewsSource.totalStoredPreviews()
        let totalTabs = allTabsModel.tabs.count

        if let storedPreviews = totalStoredPreviews, storedPreviews > totalTabs {
            Pixel.fire(pixel: .cachedTabPreviewsExceedsTabCount, withAdditionalParameters: [
                PixelParameters.tabPreviewCountDelta: "\(storedPreviews - totalTabs)"
            ])
            Task(priority: .utility) {
                _ = previewsSource.removePreviewsWithIdNotIn(Set(allTabsModel.tabs.map { $0.uid }))
            }
        }
    }

    // MARK: - External Launch Management

    /// Clears all external launch flags. Should be called on app relaunch
    /// to ensure existing tabs are not treated as external launches.
    @MainActor
    func clearExternalLaunchFlags() {
        Logger.general.debug("Clearing external launch flags for all tabs")
        for tab in allTabsModel.tabs {
            tab.isExternalLaunch = false
        }
    }

    @MainActor
    func markTabAsExternalLaunch(_ tab: Tab) {
        guard !tab.isExternalLaunch else {
            return
        }
        Logger.general.debug("Marking tab \(tab.uid) as external launch")
        tab.isExternalLaunch = true
    }

    @MainActor
    func setSuppressTrackerAnimationOnFirstLoad(for tab: Tab, shouldSuppress: Bool) {
        guard tab.shouldSuppressTrackerAnimationOnFirstLoad != shouldSuppress else {
            return
        }
        Logger.general.debug("Setting suppressTrackerAnimation=\(shouldSuppress) for tab \(tab.uid)")
        tab.shouldSuppressTrackerAnimationOnFirstLoad = shouldSuppress
    }

    @MainActor
    func applyTrackerAnimationSuppressionBasedOnLaunchSource() {
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

// MARK: - AutoplayBlockingMode + WebKit

private extension AutoplayBlockingMode {

    var mediaTypesRequiringUserAction: WKAudiovisualMediaTypes {
        switch self {
        case .allowAll:
            return []
        case .blockAudio:
            return .audio
        case .blockAll:
            return .all
        }
    }
}

extension Tab {
    var mode: BrowsingMode {
        return fireTab ? .fire : .normal
    }
}
