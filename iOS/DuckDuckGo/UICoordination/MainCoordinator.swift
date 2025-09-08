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
import Subscription
import Persistence
import DDGSync
import Configuration
import SetDefaultBrowserUI
import SystemSettingsPiPTutorial

@MainActor
protocol URLHandling {

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

    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private let featureFlagger: FeatureFlagger
    private let defaultBrowserPromptPresenter: DefaultBrowserPromptPresenting
    private let launchSourceManager: LaunchSourceManaging

    init(syncService: SyncService,
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
         subscriptionManager: any SubscriptionAuthV1toV2Bridge = AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge,
         maliciousSiteProtectionService: MaliciousSiteProtectionService,
         customConfigurationURLProvider: CustomConfigurationURLProviding,
         didFinishLaunchingStartTime: CFAbsoluteTime?,
         keyValueStore: ThrowingKeyValueStoring,
         defaultBrowserPromptPresenter: DefaultBrowserPromptPresenting,
         systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging,
         daxDialogsManager: DaxDialogsManaging,
         launchSourceManager: LaunchSourceManaging
    ) throws {
        self.subscriptionManager = subscriptionManager
        self.featureFlagger = featureFlagger
        self.defaultBrowserPromptPresenter = defaultBrowserPromptPresenter

        let homePageConfiguration = HomePageConfiguration(variantManager: AppDependencyProvider.shared.variantManager,
                                                          remoteMessagingClient: remoteMessagingService.remoteMessagingClient,
                                                          privacyProDataReporter: reportingService.privacyProDataReporter,
                                                          isStillOnboarding: { daxDialogsManager.isStillOnboarding() })
        let previewsSource = DefaultTabPreviewsSource()
        let historyManager = try Self.makeHistoryManager()
        let tabsPersistence = try TabsModelPersistence()
        let tabsModel = try Self.prepareTabsModel(previewsSource: previewsSource, tabsPersistence: tabsPersistence)
        reportingService.privacyProDataReporter.injectTabsModel(tabsModel)
        let daxDialogsFactory = ExperimentContextualDaxDialogsFactory(contextualOnboardingLogic: daxDialogs,
                                                                      contextualOnboardingPixelReporter: reportingService.onboardingPixelReporter)
        let contextualOnboardingPresenter = ContextualOnboardingPresenter(variantManager: variantManager, daxDialogsFactory: daxDialogsFactory)
        let textZoomCoordinator = Self.makeTextZoomCoordinator()
        let websiteDataManager = Self.makeWebsiteDataManager(fireproofing: fireproofing)
        interactionStateSource = WebViewStateRestorationManager(featureFlagger: featureFlagger).isFeatureEnabled ? TabInteractionStateDiskSource() : nil
        self.launchSourceManager = launchSourceManager

        tabManager = TabManager(model: tabsModel,
                                persistence: tabsPersistence,
                                previewsSource: previewsSource,
                                interactionStateSource: interactionStateSource,
                                bookmarksDatabase: bookmarksDatabase,
                                historyManager: historyManager,
                                syncService: syncService.sync,
                                privacyProDataReporter: reportingService.privacyProDataReporter,
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
                                daxDialogsManager: daxDialogsManager)
        controller = MainViewController(bookmarksDatabase: bookmarksDatabase,
                                        bookmarksDatabaseCleaner: syncService.syncDataProviders.bookmarksAdapter.databaseCleaner,
                                        historyManager: historyManager,
                                        homePageConfiguration: homePageConfiguration,
                                        syncService: syncService.sync,
                                        syncDataProviders: syncService.syncDataProviders,
                                        appSettings: AppDependencyProvider.shared.appSettings,
                                        previewsSource: previewsSource,
                                        tabManager: tabManager,
                                        syncPausedStateManager: syncService.syncErrorHandler,
                                        privacyProDataReporter: reportingService.privacyProDataReporter,
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
                                        launchSourceManager: launchSourceManager,
                                        remoteMessageStore: remoteMessagingService.remoteMessagingClient.store)
    }

    func start() {
        controller.loadViewIfNeeded()
    }

    private static func makeHistoryManager() throws -> HistoryManaging {
        let provider = AppDependencyProvider.shared
        switch HistoryManager.make(isAutocompleteEnabledByUser: provider.appSettings.autocomplete,
                                   isRecentlyVisitedSitesEnabledByUser: provider.appSettings.recentlyVisitedSites,
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
                            storage: TextZoomStorage(),
                            featureFlagger: AppDependencyProvider.shared.featureFlagger)
    }

    private static func makeWebsiteDataManager(fireproofing: Fireproofing,
                                               dataStoreIDManager: DataStoreIDManaging = DataStoreIDManager.shared) -> WebsiteDataManaging {
        WebCacheManager(cookieStorage: MigratableCookieStorage(),
                        fireproofing: fireproofing,
                        dataStoreIDManager: dataStoreIDManager)
    }

    // MARK: - Public API

    func segueToPrivacyPro() {
        controller.segueToPrivacyPro()
    }

    func presentNetworkProtectionStatusSettingsModal() {
        Task {
            if let canShowVPNInUI = try? await subscriptionManager.isFeatureIncludedInSubscription(.networkProtection),
               canShowVPNInUI {
                controller.segueToVPN()
            } else {
                controller.segueToPrivacyPro()
            }
        }
    }

    // MARK: App Lifecycle handling

    func onForeground() {
        controller.showBars()
        controller.onForeground()

        // Present Default Browser Prompt if user is eligible.
        defaultBrowserPromptPresenter.tryPresentDefaultModalPrompt(from: controller)
    }

    func onBackground() {
        resetAppStartTime()
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
            controller.forgetAllWithAnimation()
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
            presentNetworkProtectionStatusSettingsModal()
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
