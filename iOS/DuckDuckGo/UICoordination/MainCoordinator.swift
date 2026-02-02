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
import BrowserServicesKit
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

    private(set) var webExtensionManager: WebExtensionManaging?
    private(set) var webExtensionEventsCoordinator: WebExtensionEventsCoordinator?

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
    ) throws {
        self.subscriptionManager = subscriptionManager
        self.featureFlagger = featureFlagger
        self.modalPromptCoordinationService = modalPromptCoordinationService
        let homePageConfiguration = HomePageConfiguration(variantManager: AppDependencyProvider.shared.variantManager,
                                                          remoteMessagingStore: remoteMessagingService.remoteMessagingClient.store,
                                                          subscriptionDataReporter: reportingService.subscriptionDataReporter,
                                                          isStillOnboarding: { daxDialogsManager.isStillOnboarding() })
        let previewsSource = DefaultTabPreviewsSource()
        let tabsPersistence = try TabsModelPersistence()
        let tabsModel = try Self.prepareTabsModel(previewsSource: previewsSource, tabsPersistence: tabsPersistence)
        let historyManager = try Self.makeHistoryManager(tabsModel: tabsModel)
        reportingService.subscriptionDataReporter.injectTabsModel(tabsModel)
        let daxDialogsFactory = ContextualDaxDialogsProvider(featureFlagger: featureFlagger,
                                                         contextualOnboardingLogic: daxDialogs,
                                                         contextualOnboardingPixelReporter: reportingService.onboardingPixelReporter)
        let contextualOnboardingPresenter = ContextualOnboardingPresenter(variantManager: variantManager, daxDialogsFactory: daxDialogsFactory)
        let textZoomCoordinator = Self.makeTextZoomCoordinator()
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
        tabManager = TabManager(model: tabsModel,
                                persistence: tabsPersistence,
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
                                textZoomCoordinator: textZoomCoordinator,
                                websiteDataManager: websiteDataManager,
                                fireproofing: fireproofing,
                                maliciousSiteProtectionManager: maliciousSiteProtectionService.manager,
                                maliciousSiteProtectionPreferencesManager: maliciousSiteProtectionService.preferencesManager,
                                featureDiscovery: DefaultFeatureDiscovery(wasUsedBeforeStorage: UserDefaults.standard),
                                keyValueStore: keyValueStore,
                                daxDialogsManager: daxDialogsManager,
                                aiChatSettings: aiChatSettings,
                                productSurfaceTelemetry: productSurfaceTelemetry,
                                sharedSecureVault: sharedSecureVault,
                                privacyStats: privacyStats,
                                voiceSearchHelper: voiceSearchHelper)
        let fireExecutor = FireExecutor(tabManager: tabManager,
                                        websiteDataManager: websiteDataManager,
                                        daxDialogsManager: daxDialogsManager,
                                        syncService: syncService.sync,
                                        bookmarksDatabaseCleaner: syncService.syncDataProviders.bookmarksAdapter.databaseCleaner,
                                        fireproofing: fireproofing,
                                        textZoomCoordinator: textZoomCoordinator,
                                        historyManager: historyManager,
                                        featureFlagger: featureFlagger,
                                        privacyConfigurationManager: privacyConfigurationManager,
                                        appSettings: AppDependencyProvider.shared.appSettings,
                                        privacyStats: privacyStats)
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
                                        contentScopeExperimentsManager: contentScopeExperimentManager,
                                        fireproofing: fireproofing,
                                        textZoomCoordinator: textZoomCoordinator,
                                        websiteDataManager: websiteDataManager,
                                        appDidFinishLaunchingStartTime: didFinishLaunchingStartTime,
                                        maliciousSiteProtectionPreferencesManager: maliciousSiteProtectionService.preferencesManager,
                                        aiChatSettings: aiChatSettings,
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
                                        productSurfaceTelemetry: productSurfaceTelemetry,
                                        fireExecutor: fireExecutor,
                                        remoteMessagingDebugHandler: remoteMessagingService,
                                        privacyStats: privacyStats,
                                        aiChatSyncCleaner: syncService.aiChatSyncCleaner,
                                        whatsNewRepository: whatsNewRepository)
        setupWebExtensions()
    }

    func start() {
        controller.loadViewIfNeeded()
    }

    private func setupWebExtensions() {
        if #available(iOS 18.4, *), featureFlagger.isFeatureOn(.webExtensions) {
            let webExtensionManager = WebExtensionManagerFactory.makeManager(mainViewController: controller)
            self.webExtensionManager = webExtensionManager

            self.webExtensionEventsCoordinator = WebExtensionEventsCoordinator(webExtensionManager: webExtensionManager,
                                                                               mainViewController: controller)

            tabManager.setWebExtensionManager(webExtensionManager)
            controller.setWebExtensionEventsCoordinator(webExtensionEventsCoordinator)
            controller.setWebExtensionManager(webExtensionManager)
            Task { @MainActor in
                // FIXME: Currently loading installed extensions does not work on iOS due to absolute paths being unstable
                webExtensionManager.uninstallAllExtensions()
//                await webExtensionManager.loadInstalledExtensions()
            }
        } else {
            self.webExtensionManager = nil
            self.webExtensionEventsCoordinator = nil
            tabManager.setWebExtensionManager(nil)
            controller.setWebExtensionEventsCoordinator(nil)
            controller.setWebExtensionManager(nil)
        }
    }

    private static func makeHistoryManager(tabsModel: TabsModel) throws -> HistoryManaging {
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
                                         appSettings: AppSettings = AppDependencyProvider.shared.appSettings) throws -> TabsModel {
        let isPadDevice = UIDevice.current.userInterfaceIdiom == .pad
        let tabsModel: TabsModel
        if AutoClearSettingsModel(settings: appSettings) != nil {
            tabsModel = TabsModel(desktop: isPadDevice)
            tabsPersistence.clear()
            tabsPersistence.save(model: tabsModel)
            previewsSource.removeAllPreviews()
        } else {
            if let storedModel = try tabsPersistence.getTabsModel() {
                tabsModel = storedModel
            } else {
                tabsModel = TabsModel(desktop: isPadDevice)
            }
        }
        return tabsModel
    }

    private static func makeTextZoomCoordinator() -> TextZoomCoordinator {
        TextZoomCoordinator(appSettings: AppDependencyProvider.shared.appSettings,
                            storage: TextZoomStorage()  )
    }

    private static func makeWebsiteDataManager(fireproofing: Fireproofing,
                                               dataStoreIDManager: DataStoreIDManaging = DataStoreIDManager.shared) -> WebsiteDataManaging {
        WebCacheManager(cookieStorage: MigratableCookieStorage(),
                        fireproofing: fireproofing,
                        dataStoreIDManager: dataStoreIDManager)
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

    func onForeground() {
        controller.showBars()
        controller.onForeground()
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
            let request = FireRequest(options: .all, trigger: .manualFire, scope: .all)
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
        controller.loadQueryInNewTab(query)
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
