//
//  MainCoordinator.swift
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

import Foundation
import Core
import Combine
import BrowserServicesKit
import PixelKit
import PrivacyConfig
import Subscription
import Persistence
import DDGSync
import Configuration
import SetDefaultBrowserUI
import SystemSettingsPiPTutorial
import DataBrokerProtection_iOS
import PrivacyStats
import WebExtensions

@MainActor
protocol URLHandling: AnyObject {

    func handleURL(_ url: URL)
    func shouldProcessDeepLink(_ url: URL) -> Bool

}

@MainActor
protocol ShortcutItemHandling {

    func handleShortcutItem(_ item: UIApplicationShortcutItem)

}

@MainActor
protocol UserActivityHandling {

    @discardableResult
    func handleUserActivity(_ userActivity: NSUserActivity) -> Bool

}

@MainActor
final class MainCoordinator {

    let controller: MainViewController

    private(set) var tabManager: TabManager
    private(set) var interactionStateSource: TabInteractionStateSource?

    private let subscriptionManager: any SubscriptionManager
    private let featureFlagger: FeatureFlagger
    private let modalPromptCoordinationService: ModalPromptCoordinationService
    private let launchSourceManager: LaunchSourceManaging
    private let onboardingSearchExperienceSelectionHandler: OnboardingSearchExperienceSelectionHandler
    private let privacyStats: PrivacyStatsProviding
    private let wideEvent: WideEventManaging
    private let voiceSessionStateManager: VoiceSessionStateProviding
    private let voiceShortcutFeature: DuckAIVoiceShortcutFeatureProviding

    private(set) var webExtensionManager: WebExtensionManaging?
    private(set) var webExtensionEventsCoordinator: WebExtensionEventsCoordinator?
    private var webExtensionFeatureFlagHandler: AnyObject?
    private var dataImportUserActivityHandler: DataImportUserActivityHandling?
    private let darkReaderFeatureSettings: DarkReaderFeatureSettings
    private var isSyncingEmbeddedExtensions = false
    private var darkReaderCancellables = Set<AnyCancellable>()
    private var webExtensionLoadTask: Task<Void, Never>?
    private var privacyConfigurationManager: PrivacyConfigurationManaging?

    init(privacyConfigurationManager: PrivacyConfigurationManaging,
         syncService: SyncService,
         contentBlockingService: ContentBlockingService,
         bookmarksDatabase: CoreDataDatabase,
         remoteMessagingService: RemoteMessagingService,
         daxDialogs: DaxDialogs,
         reportingService: ReportingService,
         variantManager: DefaultVariantManager,
         subscriptionService: SubscriptionService,
         voiceSearchHelper: VoiceSearchHelper,
         featureFlagger: FeatureFlagger,
         contentScopeExperimentManager: ContentScopeExperimentsManaging,
         aiChatSettings: AIChatSettings,
         fireproofing: Fireproofing,
         favicons: FaviconManaging,
         subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager,
         maliciousSiteProtectionService: MaliciousSiteProtectionService,
         customConfigurationURLProvider: CustomConfigurationURLProviding,
         didFinishLaunchingStartTime: CFAbsoluteTime?,
         keyValueStore: ThrowingKeyValueStoring,
         systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging,
         daxDialogsManager: DaxDialogsManaging,
         dbpIOSPublicInterface: DBPIOSInterface.PublicInterface?,
         launchSourceManager: LaunchSourceManaging,
         winBackOfferService: WinBackOfferService,
         modalPromptCoordinationService: ModalPromptCoordinationService,
         mobileCustomization: MobileCustomization,
         productSurfaceTelemetry: ProductSurfaceTelemetry,
         whatsNewRepository: WhatsNewMessageRepository,
         sharedSecureVault: (any AutofillSecureVault)? = nil,
         syncAutoRestoreDecisionManager: SyncAutoRestoreDecisionManaging = AppDependencyProvider.shared.syncAutoRestoreDecisionManager,
         wideEvent: WideEventManaging
    ) throws {
        self.subscriptionManager = subscriptionManager
        self.featureFlagger = featureFlagger
        self.darkReaderFeatureSettings = AppDarkReaderFeatureSettings(featureFlagger: featureFlagger,
                                                                      privacyConfigurationManager: privacyConfigurationManager)
        self.modalPromptCoordinationService = modalPromptCoordinationService
        self.wideEvent = wideEvent
        self.voiceSessionStateManager = VoiceSessionStateManager()
        self.voiceShortcutFeature = DuckAIVoiceShortcutFeature(featureFlagger: featureFlagger)
        let homePageConfiguration = HomePageConfiguration(variantManager: AppDependencyProvider.shared.variantManager,
                                                          remoteMessagingStore: remoteMessagingService.remoteMessagingClient.store,
                                                          subscriptionDataReporter: reportingService.subscriptionDataReporter,
                                                          isStillOnboarding: { daxDialogsManager.isStillOnboarding() })
        let previewsSource = DefaultTabPreviewsSource()
        let tabsPersistence = try TabsModelPersistence()
        let tabsModelProvider = try Self.prepareTabsModel(previewsSource: previewsSource, tabsPersistence: tabsPersistence, featureFlagger: featureFlagger)
        let historyManager = try Self.makeHistoryManager(tabsModel: tabsModelProvider.aggregateTabsModel)
        reportingService.subscriptionDataReporter.injectTabsModel(tabsModelProvider.aggregateTabsModel)
        let daxDialogsFactory = ContextualDaxDialogsProvider(featureFlagger: featureFlagger,
                                                         contextualOnboardingLogic: daxDialogs,
                                                         contextualOnboardingPixelReporter: reportingService.onboardingPixelReporter)
        let contextualOnboardingPresenter = ContextualOnboardingPresenter(variantManager: variantManager, daxDialogsFactory: daxDialogsFactory)
        let textZoomCoordinatorProvider = Self.makeTextZoomCoordinatorProvider()
        let autoconsentManagementProvider = AutoconsentManagementProvider()
        let websiteDataManager = Self.makeWebsiteDataManager(fireproofing: fireproofing)
        interactionStateSource = TabInteractionStateDiskSource()
        self.launchSourceManager = launchSourceManager
        onboardingSearchExperienceSelectionHandler = OnboardingSearchExperienceSelectionHandler(
            daxDialogs: daxDialogs,
            aiChatSettings: aiChatSettings,
            featureFlagger: featureFlagger,
            onboardingSearchExperienceProvider: OnboardingSearchExperience()
        )
        self.privacyStats = PrivacyStats(databaseProvider: PrivacyStatsDatabase())
        let toggleModeStorage: ToggleModeStoring = ToggleModeStorage()
        tabManager = TabManager(tabsModelProvider: tabsModelProvider,
                                previewsSource: previewsSource,
                                interactionStateSource: interactionStateSource,
                                privacyConfigurationManager: privacyConfigurationManager,
                                bookmarksDatabase: bookmarksDatabase,
                                historyManager: historyManager,
                                syncService: syncService.sync,
                                userScriptsDependencies: contentBlockingService.userScriptsDependencies,
                                contentBlockingAssetsPublisher: contentBlockingService.updating.userContentBlockingAssets,
                                subscriptionDataReporter: reportingService.subscriptionDataReporter,
                                contextualOnboardingPresenter: contextualOnboardingPresenter,
                                contextualOnboardingLogic: daxDialogs,
                                onboardingPixelReporter: reportingService.onboardingPixelReporter,
                                featureFlagger: featureFlagger,
                                contentScopeExperimentManager: contentScopeExperimentManager,
                                appSettings: AppDependencyProvider.shared.appSettings,
                                textZoomCoordinatorProvider: textZoomCoordinatorProvider,
                                autoconsentManagementProvider: autoconsentManagementProvider,
                                websiteDataManager: websiteDataManager,
                                fireproofing: fireproofing,
                                favicons: favicons,
                                maliciousSiteProtectionManager: maliciousSiteProtectionService.manager,
                                maliciousSiteProtectionPreferencesManager: maliciousSiteProtectionService.preferencesManager,
                                featureDiscovery: DefaultFeatureDiscovery(wasUsedBeforeStorage: UserDefaults.standard),
                                keyValueStore: keyValueStore,
                                daxDialogsManager: daxDialogsManager,
                                aiChatSettings: aiChatSettings,
                                productSurfaceTelemetry: productSurfaceTelemetry,
                                sharedSecureVault: sharedSecureVault,
                                privacyStats: privacyStats,
                                voiceSearchHelper: voiceSearchHelper,
                                launchSourceManager: launchSourceManager,
                                darkReaderFeatureSettings: darkReaderFeatureSettings,
                                toggleModeStorage: toggleModeStorage)
        let fireExecutor = FireExecutor(tabManager: tabManager,
                                        websiteDataManager: websiteDataManager,
                                        daxDialogsManager: daxDialogsManager,
                                        syncService: syncService.sync,
                                        bookmarksDatabaseCleaner: syncService.syncDataProviders.bookmarksAdapter.databaseCleaner,
                                        fireproofing: fireproofing,
                                        favicons: favicons,
                                        textZoomCoordinatorProvider: textZoomCoordinatorProvider,
                                        autoconsentManagementProvider: autoconsentManagementProvider,
                                        historyManager: historyManager,
                                        featureFlagger: featureFlagger,
                                        privacyConfigurationManager: privacyConfigurationManager,
                                        appSettings: AppDependencyProvider.shared.appSettings,
                                        privacyStats: privacyStats,
                                        aiChatSyncCleaner: syncService.aiChatSyncCleaner,
                                        wideEvent: wideEvent)
        let syncAutoRestoreHandler = SyncAutoRestoreHandler(
            decisionManager: syncAutoRestoreDecisionManager,
            syncService: syncService.sync
        )
        let aiChatAddressBarExperience = AIChatAddressBarExperience(featureFlagger: featureFlagger, aiChatSettings: aiChatSettings)
        let idleReturnEligibilityManager = IdleReturnEligibilityManager(
            featureFlagger: featureFlagger,
            keyValueStore: keyValueStore,
            privacyConfigurationManager: privacyConfigurationManager,
            isStillOnboarding: { daxDialogsManager.isStillOnboarding() }
        )
        controller = MainViewController(privacyConfigurationManager: privacyConfigurationManager,
                                        bookmarksDatabase: bookmarksDatabase,
                                        historyManager: historyManager,
                                        homePageConfiguration: homePageConfiguration,
                                        syncService: syncService.sync,
                                        syncDataProviders: syncService.syncDataProviders,
                                        userScriptsDependencies: contentBlockingService.userScriptsDependencies,
                                        contentBlockingAssetsPublisher: contentBlockingService.updating.userContentBlockingAssets,
                                        appSettings: AppDependencyProvider.shared.appSettings,
                                        previewsSource: previewsSource,
                                        tabManager: tabManager,
                                        syncPausedStateManager: syncService.syncErrorHandler,
                                        subscriptionDataReporter: reportingService.subscriptionDataReporter,
                                        contextualOnboardingLogic: daxDialogs,
                                        contextualOnboardingPixelReporter: reportingService.onboardingPixelReporter,
                                        subscriptionFeatureAvailability: subscriptionService.subscriptionFeatureAvailability,
                                        voiceSearchHelper: voiceSearchHelper,
                                        featureFlagger: featureFlagger,
                                        idleReturnEligibilityManager: idleReturnEligibilityManager,
                                        syncAutoRestoreHandler: syncAutoRestoreHandler,
                                        contentScopeExperimentsManager: contentScopeExperimentManager,
                                        fireproofing: fireproofing,
                                        favicons: favicons,
                                        textZoomCoordinatorProvider: textZoomCoordinatorProvider,
                                        websiteDataManager: websiteDataManager,
                                        appDidFinishLaunchingStartTime: didFinishLaunchingStartTime,
                                        maliciousSiteProtectionPreferencesManager: maliciousSiteProtectionService.preferencesManager,
                                        aiChatSettings: aiChatSettings,
                                        aiChatAddressBarExperience: aiChatAddressBarExperience,
                                        themeManager: ThemeManager.shared,
                                        keyValueStore: keyValueStore,
                                        customConfigurationURLProvider: customConfigurationURLProvider,
                                        systemSettingsPiPTutorialManager: systemSettingsPiPTutorialManager,
                                        daxDialogsManager: daxDialogsManager,
                                        dbpIOSPublicInterface: dbpIOSPublicInterface,
                                        launchSourceManager: launchSourceManager,
                                        winBackOfferVisibilityManager: winBackOfferService.visibilityManager,
                                        mobileCustomization: mobileCustomization,
                                        remoteMessagingActionHandler: remoteMessagingService.remoteMessagingActionHandler,
                                        remoteMessagingImageLoader: remoteMessagingService.remoteMessagingImageLoader,
                                        remoteMessagingPixelReporter: remoteMessagingService.pixelReporter,
                                        productSurfaceTelemetry: productSurfaceTelemetry,
                                        fireExecutor: fireExecutor,
                                        remoteMessagingDebugHandler: remoteMessagingService,
                                        privacyStats: privacyStats,
                                        whatsNewRepository: whatsNewRepository,
                                        darkReaderFeatureSettings: darkReaderFeatureSettings,
                                        toggleModeStorage: toggleModeStorage)

        setupWebExtensions(privacyConfigurationManager: privacyConfigurationManager)

        // Apply tracker animation suppression early for cold starts
        // This must happen before tabs load their URLs
        if launchSourceManager.source == .standard {
            tabManager.applyTrackerAnimationSuppressionBasedOnLaunchSource()
        }

    }

    func start() {
        controller.loadViewIfNeeded()
    }

    private func subscribeToDarkReaderChanges() {
        darkReaderFeatureSettings.forceDarkModeChangedPublisher
            .sink { [weak self] _ in
                guard #available(iOS 18.4, *) else { return }
                Task { @MainActor in
                    await self?.syncEmbeddedExtensions()
                }
            }
            .store(in: &darkReaderCancellables)
    }

    private func setupWebExtensions(privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.privacyConfigurationManager = privacyConfigurationManager

        guard #available(iOS 18.4, *) else { return }

        let webExtensionsPublisher = featureFlagger.updatesPublisher
            .compactMap { [weak featureFlagger] in
                featureFlagger?.isFeatureOn(.webExtensions)
            }
            .removeDuplicates()
            .eraseToAnyPublisher()

        let embeddedExtensionPublisher = featureFlagger.updatesPublisher
            .compactMap { [weak featureFlagger] in
                featureFlagger?.isFeatureOn(.embeddedExtension)
            }
            .removeDuplicates()
            .eraseToAnyPublisher()

        webExtensionFeatureFlagHandler = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.webExtensionManager },
            featureFlagPublisher: webExtensionsPublisher,
            embeddedExtensionFlagPublisher: embeddedExtensionPublisher,
            onFeatureFlagEnabled: { [weak self] in
                self?.initializeWebExtensions()
            },
            onFeatureFlagDisabled: { [weak self] in
                self?.clearWebExtensionReferences()
            },
            onEmbeddedExtensionFlagEnabled: { [weak self] in
                await self?.syncEmbeddedExtensions()
            }
        )

        if featureFlagger.isFeatureOn(.webExtensions) {
            initializeWebExtensions()
        } else {
            clearWebExtensionReferences()
        }
    }

    @available(iOS 18.4, *)
    private func initializeWebExtensions() {
        guard webExtensionManager == nil else {
            // Already initialized, just reload extensions and re-register tabs
            webExtensionLoadTask?.cancel()
            webExtensionLoadTask = Task { @MainActor [weak self] in
                await self?.webExtensionManager?.loadInstalledExtensions()
                guard !Task.isCancelled else { return }
                await self?.syncEmbeddedExtensions()
                guard !Task.isCancelled else { return }
                self?.webExtensionEventsCoordinator?.registerExistingTabsAndWindow()
            }
            return
        }

        guard let privacyConfigurationManager else { return }

        let webExtensionManager = WebExtensionManagerFactory.makeManager(
            mainViewController: controller,
            privacyConfigurationManager: privacyConfigurationManager,
            autoconsentPreferences: AppUserDefaults(),
            darkReaderExcludedDomainsProvider: darkReaderFeatureSettings
        )
        self.webExtensionManager = webExtensionManager

        self.webExtensionEventsCoordinator = WebExtensionEventsCoordinator(
            webExtensionManager: webExtensionManager,
            mainViewController: controller
        )

        tabManager.setWebExtensionManager(webExtensionManager)
        controller.setWebExtensionEventsCoordinator(webExtensionEventsCoordinator)
        controller.setWebExtensionManager(webExtensionManager)
        subscribeToDarkReaderChanges()

        // Load extensions asynchronously - the controller is already attached to tabs
        webExtensionLoadTask = Task { @MainActor [weak self] in
            await webExtensionManager.loadInstalledExtensions()
            guard !Task.isCancelled else { return }
            await self?.syncEmbeddedExtensions()
            guard !Task.isCancelled else { return }
            self?.webExtensionEventsCoordinator?.registerExistingTabsAndWindow()
        }
    }

    @available(iOS 18.4, *)
    private func syncEmbeddedExtensions() async {
        guard !isSyncingEmbeddedExtensions else { return }
        guard let webExtensionManager = webExtensionManager as? WebExtensionManager else { return }

        isSyncingEmbeddedExtensions = true
        defer { isSyncingEmbeddedExtensions = false }

        var enabledTypes: Set<DuckDuckGoWebExtensionType> = []
        if featureFlagger.isFeatureOn(.embeddedExtension) {
            enabledTypes.insert(.embedded)
        }
        if darkReaderFeatureSettings.isForceDarkModeEnabled == true {
            enabledTypes.insert(.darkReader)
        }
        await webExtensionManager.syncEmbeddedExtensions(enabledTypes: enabledTypes)
    }

    private func clearWebExtensionReferences() {
        webExtensionLoadTask?.cancel()
        webExtensionLoadTask = nil
        webExtensionManager = nil
        webExtensionEventsCoordinator = nil
        darkReaderCancellables.removeAll()
        tabManager.setWebExtensionManager(nil)
        controller.setWebExtensionEventsCoordinator(nil)
        controller.setWebExtensionManager(nil)
    }

    private static func makeHistoryManager(tabsModel: TabsModelReading) throws -> HistoryManaging {
        let provider = AppDependencyProvider.shared
        switch HistoryManager.make(isAutocompleteEnabledByUser: provider.appSettings.autocomplete,
                                   isRecentlyVisitedSitesEnabledByUser: provider.appSettings.recentlyVisitedSites,
                                   openTabIDsProvider: { tabsModel.tabs.map { $0.uid } },
                                   tld: provider.storageCache.tld) {
        case .failure(let error):
            throw TerminationError.historyDatabase(error)
        case .success(let historyManager):
            return historyManager
        }
    }

    private static func prepareTabsModel(previewsSource: TabPreviewsSource = DefaultTabPreviewsSource(),
                                         tabsPersistence: TabsModelPersisting,
                                         featureFlagger: FeatureFlagger,
                                         appSettings: AppSettings = AppDependencyProvider.shared.appSettings) throws -> TabsModelProviding {
        let isPadDevice = UIDevice.current.userInterfaceIdiom == .pad
        let normalModel: TabsModel
        let fireModel: TabsModel

        if AutoClearSettingsModel(settings: appSettings) != nil {
            normalModel = TabsModel(desktop: isPadDevice, mode: .normal)
            fireModel = TabsModel(desktop: isPadDevice, mode: .fire)
            tabsPersistence.clearAll()
            _ = tabsPersistence.save(model: normalModel, for: .normal)
            _ = tabsPersistence.save(model: fireModel, for: .fire)
            _ = previewsSource.removeAllPreviews()
        } else {
            normalModel = try tabsPersistence.getTabsModel(for: .normal)
                ?? TabsModel(desktop: isPadDevice, mode: .normal)
            fireModel = try tabsPersistence.getTabsModel(for: .fire)
                ?? TabsModel(desktop: isPadDevice, mode: .fire)
        }
        return TabsModelProvider(normalTabsModel: normalModel,
                                 fireModeTabsModel: fireModel,
                                 persistence: tabsPersistence,
                                 featureFlagger: featureFlagger)
    }

    private static func makeTextZoomCoordinatorProvider() -> TextZoomCoordinatorProvider {
        TextZoomCoordinatorProvider(appSettings: AppDependencyProvider.shared.appSettings)
    }

    private static func makeWebsiteDataManager(fireproofing: Fireproofing,
                                               dataStoreIDManager: DataStoreIDManaging = DataStoreIDManager.shared) -> WebsiteDataManaging {
        WebCacheManager(cookieStorage: MigratableCookieStorage(),
                        fireproofing: fireproofing,
                        dataStoreIDManager: dataStoreIDManager,
                        isFireproofingETLDPlus1Enabled: { AppDependencyProvider.shared.featureFlagger.isFeatureOn(.fireproofingETLDPlus1) })
    }

    // MARK: - Public API

    func segueToDuckDuckGoSubscription() {
        controller.segueToDuckDuckGoSubscription()
    }

    func presentNetworkProtectionStatusSettingsModal() {
        controller.presentNetworkProtectionStatusSettingsModal()
    }

    func presentDataBrokerProtectionDashboard() {
        controller.presentDataBrokerProtectionDashboard()
    }

    func presentModalPromptIfNeeded() {
        modalPromptCoordinationService.presentModalPromptIfNeeded(from: controller)
    }

    // MARK: App Lifecycle handling

    func onForeground(isFirstForeground: Bool) {
        // Apply tracker animation suppression based on launch source
        // Must be called after launchSourceManager.handleAppAction sets the source
        if isFirstForeground {
            tabManager.applyTrackerAnimationSuppressionBasedOnLaunchSource()
        }

        // Clear external launch flags when app comes to foreground
        // This ensures flags are reset for subsequent in-app navigations
        tabManager.clearExternalLaunchFlags()

        controller.showBars()
        controller.onForeground()

        if #available(iOS 18.4, *) {
            webExtensionEventsCoordinator?.didFocusWindow()
        }
    }

    func onBackground() {
        resetAppStartTime()
        Task {
            await privacyStats.handleAppTermination()
        }
    }

    private func resetAppStartTime() {
        controller.appDidFinishLaunchingStartTime = nil
    }

}

extension MainCoordinator: URLHandling {

    func shouldProcessDeepLink(_ url: URL) -> Bool {
        // Ignore deeplinks if onboarding is active
        // as well as handle email sign-up deep link separately
        !controller.needsToShowOnboardingIntro() && !handleEmailSignUpDeepLink(url)
    }

    func handleURL(_ url: URL) {
        guard !handleAppDeepLink(url: url) else { return }
        controller.loadUrlInNewTab(url, reuseExisting: .any, inheritedAttribution: nil, fromExternalLink: true)
    }

    private func handleEmailSignUpDeepLink(_ url: URL) -> Bool {
        guard url.absoluteString.starts(with: URL.emailProtection.absoluteString),
              let navViewController = controller.presentedViewController as? UINavigationController,
              let emailSignUpViewController = navViewController.topViewController as? EmailSignupViewController else {
            return false
        }
        emailSignUpViewController.loadUrl(url)
        return true
    }

    private func handleAppDeepLink(url: URL, application: UIApplication = UIApplication.shared) -> Bool {
        controller.currentTab?.aiChatContextualSheetCoordinator.dismissSheet()

        if url != AppDeepLinkSchemes.openVPN.url && url.scheme != AppDeepLinkSchemes.openAIChat.url.scheme {
            controller.clearNavigationStack()
        }
        switch AppDeepLinkSchemes.fromURL(url) {
        case .newSearch:
            controller.newTab(reuseExisting: true)
            controller.enterSearch()
        case .favorites:
            controller.newTab(reuseExisting: true, allowingKeyboard: false)
        case .quickLink:
            let query = AppDeepLinkSchemes.query(fromQuickLink: url)
            controller.loadQueryInNewTab(query, reuseExisting: .any)
        case .addFavorite:
            controller.startAddFavoriteFlow()
        case .fireButton:
            let request = FireRequest(options: .all, trigger: .manualFire, scope: .all, source: .deeplink)
            controller.forgetAllWithAnimation(request: request)
        case .voiceSearch:
            controller.onVoiceSearchPressed()
        case .newEmail:
            controller.newEmailAddress()
        case .openVPN:
            presentNetworkProtectionStatusSettingsModal()
        case .openPasswords:
            handleOpenPasswords(url: url)
        case .openAIChat:
            AIChatDeepLinkHandler().handleDeepLink(url, on: controller)
        default:
            if featureFlagger.isFeatureOn(.canInterceptSyncSetupUrls), let pairingInfo = PairingInfo(url: url) {
                controller.segueToSettingsSync(with: nil, pairingInfo: pairingInfo)
                return true
            }
            guard application.applicationState == .active, let currentTab = controller.currentTab else {
                return false
            }
            // If app is in active state, treat this navigation as something initiated form the context of the current tab.
            controller.tab(currentTab,
                           didRequestNewTabForUrl: url,
                           openedByPage: true,
                           inheritingAttribution: nil)
        }
        return true
    }

    private func handleOpenPasswords(url: URL) {
        var source: AutofillSettingsSource = .homeScreenWidget
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           queryItems.contains(where: { $0.name == "ls" }) {
            Pixel.fire(pixel: .autofillLoginsLaunchWidgetLock)
            source = .lockScreenWidget
        } else {
            Pixel.fire(pixel: .autofillLoginsLaunchWidgetHome)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.controller.launchAutofillLogins(openSearch: true, source: source)
        }
    }

    func handleAIChatAppIconShortuct() {
          controller.clearNavigationStack()
          // Give the `clearNavigationStack` call time to complete.
          DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.5) {
              self.controller.openAIChat()
          }
          Pixel.fire(pixel: .openAIChatFromIconShortcut)
      }
}

extension MainCoordinator: ShortcutItemHandling {

    func handleShortcutItem(_ item: UIApplicationShortcutItem) {
        if item.type == ShortcutKey.clipboard, let query = UIPasteboard.general.string {
            handleQuery(query)
        } else if item.type == ShortcutKey.passwords {
            handleSearchPassword()
        } else if item.type == ShortcutKey.openVPNSettings {
            controller.presentNetworkProtectionStatusSettingsModal()
        } else if item.type == ShortcutKey.aiChat {
            handleAIChatAppIconShortuct()
        } else if item.type == ShortcutKey.voiceSearch {
            controller.onVoiceSearchPressed()
        }
    }

    private func handleQuery(_ query: String) {
        controller.clearNavigationStack()
        controller.loadQueryInNewTab(query, fromExternalLink: true)
    }

    private func handleSearchPassword() {
        controller.clearNavigationStack()
        // Give the `clearNavigationStack` call time to complete.
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.5) {
            self.controller.launchAutofillLogins(openSearch: true, source: .appIconShortcut)
        }
        Pixel.fire(pixel: .autofillLoginsLaunchAppShortcut)
    }

}

extension MainCoordinator: UserActivityHandling {

    @discardableResult
    func handleUserActivity(_ userActivity: NSUserActivity) -> Bool {
        switch userActivity.activityType {
        case DataImportUserActivityHandler.browserKitImportActivityType:
            if dataImportUserActivityHandler == nil {
                dataImportUserActivityHandler = makeDataImportUserActivityHandler()
            }
            return dataImportUserActivityHandler?.handle(userActivity) ?? false
        default:
            Logger.general.debug("Unhandled user activity type: \(userActivity.activityType)")
            return false
        }
    }

    private func makeDataImportUserActivityHandler() -> DataImportUserActivityHandler {
        DataImportUserActivityHandler()
    }

}

// MARK: - IdleReturnLaunchDelegate

extension MainCoordinator: IdleReturnLaunchDelegate {

    func showNewTabPageAfterIdleReturn() {
        if voiceShortcutFeature.isAvailable, voiceSessionStateManager.isVoiceSessionActive {
            return
        }

        controller.prepareForIdleReturnNTP { [weak self] in
            guard let self else { return }
            self.controller.newTab(reuseExisting: true, allowingKeyboard: true, openedAfterIdle: true)
        }
    }

}

// MARK: - SystemSettingsPiPTutorialPresenting

extension MainCoordinator: SystemSettingsPiPTutorialPresenting {

    func attachPlayerView(_ view: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.opacity = 0.001
        controller.view.addSubview(view)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 1),
            view.heightAnchor.constraint(equalToConstant: 1),
            view.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            view.topAnchor.constraint(equalTo: controller.view.topAnchor),
        ])
        controller.view.sendSubviewToBack(view)
    }

    func detachPlayerView(_ view: UIView) {
        view.removeFromSuperview()
    }
}
