//
//  MainViewController+Segues.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import UIKit
import Common
import FoundationExtensions
import Core
import Bookmarks
import BrowserServicesKit
import SwiftUI
import PrivacyDashboard
import Subscription
import DDGSync
import os.log
import DataBrokerProtection_iOS

extension MainViewController {

    func segueToAppearanceSettings() {
        launchSettings(completion: {
            $0.triggerDeepLinkNavigation(to: .appearance)
        }, deepLinkTarget: .appearance)
    }

    func segueToGeneralSettings() {
        launchSettings(completion: {
            $0.triggerDeepLinkNavigation(to: .general)
        }, deepLinkTarget: .general)
    }

    func segueToCustomizeAddressBarSettings() {
        launchSettings(completion: {
            $0.triggerDeepLinkNavigation(to: .customizeAddressBarButton)
        }, deepLinkTarget: .customizeAddressBarButton)
    }

    func segueToCustomizeToolbarSettings() {
        launchSettings(completion: {
            $0.triggerDeepLinkNavigation(to: .customizeToolbarButton)
        }, deepLinkTarget: .customizeToolbarButton)
    }

    func segueToDaxOnboarding(completion: (() -> Void)? = nil) {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()

        let viewModel = OnboardingIntroFactory.makeViewModel(
            pixelReporter: contextualOnboardingPixelReporter,
            systemSettingsPiPTutorialManager: systemSettingsPiPTutorialManager,
            daxDialogsManager: daxDialogsManager,
            syncAutoRestoreHandler: syncAutoRestoreHandler,
            onboardingManager: onboardingManager
        )
        let controller = OnboardingIntroFactory.makeController(
            viewModel: viewModel,
            isRebranded: featureFlagger.isFeatureOn(.onboardingRebranding),
            delegate: self
        )
        controller.modalPresentationStyle = .overFullScreen
        linearOnboardingContext = OnboardingIntroContext(
            onboardingViewController: controller,
            onboardingViewModel: viewModel
        )
        present(controller, animated: false, completion: completion)
    }

    func segueToHomeRow() {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()
        let storyboard = UIStoryboard(name: "HomeRow", bundle: nil)
        guard let controller = storyboard.instantiateInitialViewController() else {
            assertionFailure()
            return
        }
        controller.modalPresentationStyle = .overCurrentContext
        present(controller, animated: true)
    }

    func segueToBookmarks() {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()
        launchBookmarksViewController()
    }

    func segueToEditCurrentBookmark() {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()
        guard let link = currentTab?.link,
              let bookmark = menuBookmarksViewModel.favorite(for: link.url) ??
                menuBookmarksViewModel.bookmark(for: link.url) else {
            assertionFailure()
            return
        }
        segueToEditBookmark(bookmark)
    }

    func segueToEditBookmark(_ bookmark: BookmarkEntity) {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()
        launchBookmarksViewController {
            $0.openEditFormForBookmark(bookmark)
        }
    }

    private func launchBookmarksViewController(completion: ((BookmarksViewController) -> Void)? = nil) {
        Logger.lifecycle.debug(#function)

        let storyboard = UIStoryboard(name: "Bookmarks", bundle: nil)
        let bookmarks = storyboard.instantiateViewController(identifier: "BookmarksViewController") { coder in
            BookmarksViewController(coder: coder,
                                    bookmarksDatabase: self.bookmarksDatabase,
                                    bookmarksSearch: self.bookmarksCachingSearch,
                                    favicons: self.favicons,
                                    syncService: self.syncService,
                                    syncDataProviders: self.syncDataProviders,
                                    appSettings: self.appSettings,
                                    keyValueStore: self.keyValueStore,
                                    productSurfaceTelemetry: self.productSurfaceTelemetry)
        }
        bookmarks.delegate = self

        let controller = UINavigationController(rootViewController: bookmarks)
        controller.modalPresentationStyle = .automatic
        present(controller, animated: true) {
            completion?(bookmarks)
        }
    }

    func segueToReportBrokenSite(entryPoint: PrivacyDashboardEntryPoint = .report) {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()

        // Reuse the tab's live PrivacyInfo (with its accumulated tracker/protection state) as the
        // dashboard flow does; only build a fresh one if the tab has none yet.
        guard let currentURL = currentTab?.url,
              let privacyInfo = currentTab?.privacyInfo ?? currentTab?.makePrivacyInfo(url: currentURL) else {
            assertionFailure("Missing fundamental data")
            return
        }

        let controller = PrivacyDashboardViewController(privacyInfo: privacyInfo,
                                                        entryPoint: entryPoint,
                                                        privacyConfigurationManager: self.privacyConfigurationManager,
                                                        contentBlockingManager: ContentBlocking.shared.contentBlockingManager,
                                                        breakageAdditionalInfo: self.currentTab?.makeBreakageAdditionalInfo(webExtensionManager: webExtensionManager))

        currentTab?.privacyDashboard = controller

        controller.popoverPresentationController?.delegate = controller
        controller.view.backgroundColor = UIColor(designSystemColor: .backgroundSheets)

        if UIDevice.current.userInterfaceIdiom == .pad {
            controller.modalPresentationStyle = .formSheet
        } else {
            controller.modalPresentationStyle = .pageSheet
        }
        
        present(controller, animated: true)
    }

    func segueToNegativeFeedbackForm() {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()

        let feedbackPicker = FeedbackPickerViewController.loadFromStoryboard()

        feedbackPicker.popoverPresentationController?.delegate = feedbackPicker
        feedbackPicker.view.backgroundColor = UIColor(designSystemColor: .backgroundSheets)
        feedbackPicker.modalPresentationStyle = isPad ? .formSheet : .pageSheet
        feedbackPicker.loadViewIfNeeded()
        feedbackPicker.configure(with: Feedback.Category.allCases)

        present(UINavigationController(rootViewController: feedbackPicker), animated: true)
    }

    func segueToDownloads() {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()

        present(DownloadsListHostingController(), animated: true)
    }

    func segueToTabSwitcher() async {
        Logger.lifecycle.debug(#function)

        // Guard against concurrent presentations
        guard tabSwitcherController == nil else {
            Logger.lifecycle.debug("Tab switcher presentation already in progress or active")
            return
        }

        hideAllHighlightsIfNeeded()

        // Calculate the initial tracker count state before creating the view controller
        // to ensure correct header sizing during the transition
        let initialTrackerCountState = await TabSwitcherTrackerCountViewModel.calculateInitialState(
            featureFlagger: featureFlagger,
            settings: DefaultTabSwitcherSettings(),
            privacyStats: privacyStats
        )

        // Check again after async work in case another presentation started
        guard tabSwitcherController == nil else {
            Logger.lifecycle.debug("Tab switcher presentation already in progress")
            return
        }

        let duckAIGridContentProvider = DuckAIGridContentResolver(
            featureFlagger: featureFlagger,
            storageHandler: duckAiNativeStorageHandler
        )

        let storyboard = UIStoryboard(name: "TabSwitcher", bundle: nil)
        guard let controller = storyboard.instantiateInitialViewController(creator: { coder in
            TabSwitcherViewController(coder: coder,
                                      bookmarksDatabase: self.bookmarksDatabase,
                                      syncService: self.syncService,
                                      featureFlagger: self.featureFlagger,
                                      favicons: self.favicons,
                                      tabManager: self.tabManager,
                                      aiChatSettings: self.aiChatSettings,
                                      appSettings: self.appSettings,
                                      privacyStats: self.privacyStats,
                                      productSurfaceTelemetry: self.productSurfaceTelemetry,
                                      historyManager: self.historyManager,
                                      fireproofing: self.fireproofing,
                                      keyValueStore: self.keyValueStore,
                                      daxDialogsManager: self.daxDialogsManager,
                                      initialTrackerCountState: initialTrackerCountState,
                                      duckAIGridContentProvider: duckAIGridContentProvider,
                                      duckAIVoiceSessionTracker: self.duckAIVoiceSessionTracker)
        }) else {
            assertionFailure()
            return
        }

        controller.transitioningDelegate = tabSwitcherTransition
        controller.delegate = self
        controller.previewsSource = previewsSource
        controller.modalPresentationStyle = .overCurrentContext

        tabSwitcherController = controller

        present(controller, animated: true)
    }

    func segueToSettings() {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()
        launchSettings()
    }

    func segueToDuckDuckGoSubscription(origin: String?) {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()
        let components: URLComponents? = origin.map {
            var components = URLComponents()
            components.queryItems = [URLQueryItem(name: AttributionParameter.origin, value: $0)]
            return components
        }
        launchSettings(completion: {
            $0.triggerDeepLinkNavigation(to: .subscriptionFlow(redirectURLComponents: components))
        }, deepLinkTarget: .subscriptionFlow(redirectURLComponents: components))
    }

    func segueToSubscriptionRestoreFlow() {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()
        launchSettings(completion: {
            $0.triggerDeepLinkNavigation(to: .restoreFlow)
        }, deepLinkTarget: .restoreFlow)
    }

    func segueToSubscriptionWelcome() {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()
        launchSettings(completion: {
            $0.triggerDeepLinkNavigation(to: .subscriptionWelcome)
        }, deepLinkTarget: .subscriptionWelcome)
    }

    func segueToVPN() {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()
        launchSettings(completion: {
            $0.triggerDeepLinkNavigation(to: .netP)
        }, deepLinkTarget: .netP)
    }

    func segueToDataBrokerProtection() {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()
        launchSettings(completion: {
            $0.triggerDeepLinkNavigation(to: .dbp)
        }, deepLinkTarget: .dbp)
    }

    func segueToPIRWithSubscriptionCheck() {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()

        Task { @MainActor in
            let subscriptionManager = AppDependencyProvider.shared.subscriptionManager
            let hasEntitlement = (try? await subscriptionManager.isFeatureEnabled(.dataBrokerProtection)) ?? false

            if hasEntitlement || freemiumPIREligibilityChecker.canShowEntryPoint() {
                launchSettings(completion: {
                    $0.triggerDeepLinkNavigation(to: .dbp)
                }, deepLinkTarget: .dbp)
            } else {
                launchSettings(completion: {
                    $0.triggerDeepLinkNavigation(to: .subscriptionFlow())
                }, deepLinkTarget: .subscriptionFlow())
            }
        }
    }

    func segueToDebugSettings() {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()
        launchDebugSettings()
    }

    func segueToSettingsCookiePopupManagement() {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()
        launchSettings {
            $0.openCookiePopupManagement()
        }
    }

    func segueToSettingsAutofillWith(account: SecureVaultModels.WebsiteAccount?,
                                     card: SecureVaultModels.CreditCard?,
                                     showCardManagement: Bool = false,
                                     showSettingsScreen: AutofillSettingsDestination? = nil,
                                     source: AutofillSettingsSource?) {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()
        if showCardManagement || showSettingsScreen != nil {
            launchSettings(configure: { viewModel, controller in
                controller.decorateNavigationBar()
                viewModel.shouldPresentAutofillViewWith(accountDetails: nil, card: nil, showCreditCardManagement: showCardManagement, showSettingsScreen: showSettingsScreen, source: source)
            })
        } else {
            launchSettings {
                $0.shouldPresentAutofillViewWith(accountDetails: account, card: card, showCreditCardManagement: showCardManagement, source: source)
            }
        }
    }

    func segueToSettingsAIChat(openedFromSERPSettingsButton: Bool = false, completion: (() -> Void)? = nil) {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()
        launchSettings(completion: { _ in
            completion?()
        }, deepLinkTarget: .aiChat) { viewModel, _ in
            viewModel.openedFromSERPSettingsButton = openedFromSERPSettingsButton
        }
    }

    func segueToSettingsPrivateSearch(completion: (() -> Void)? = nil) {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()
        launchSettings(completion: { _ in
            completion?()
        }, deepLinkTarget: .privateSearch)
    }

    func segueToSettingsSync(with source: String? = nil, pairingInfo: PairingInfo? = nil) {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()

        let launchSync: (SettingsViewModel) -> Void = { settingsViewModel in
            if let source {
                settingsViewModel.shouldPresentSyncViewWithSource(source, animated: false)
            } else {
                settingsViewModel.presentLegacyView(.sync(pairingInfo), animated: false)
            }
        }

        if let navigationController = presentedViewController as? UINavigationController,
           navigationController.viewControllers.first is SettingsHostingController {
            launchSettings(completion: launchSync)
            return
        }

        let presentSyncViaSettings: () -> Void = { [weak self] in
            self?.launchSettings(configure: { settingsViewModel, _ in
                launchSync(settingsViewModel)
            })
        }

        if let presentedViewController {
            presentedViewController.dismiss(animated: false, completion: presentSyncViaSettings)
        } else {
            presentSyncViaSettings()
        }
    }

    func presentDataImportSummary(_ summary: DataImportSummary,
                                  importScreen: DataImportViewModel.ImportScreen = .passwords) {
        let presenter = topMostPresentedViewController(startingFrom: self)

        guard !(presenter is DataImportSummaryViewController) else {
            Logger.autofill.debug("Data import summary already presented")
            return
        }

        let summaryViewController = DataImportSummaryViewController(summary: summary,
                                                                    importScreen: importScreen,
                                                                    syncService: syncService) { [weak self] source in
            guard let self else { return }
            dismissPresentedDataImportSummaryIfNeeded {
                self.segueToSettingsSync(with: source)
            }
        } onCompletion: { }

        presenter.present(summaryViewController, animated: true)
    }

    func segueToFeedback() {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()
        launchSettings {
            $0.presentLegacyView(.feedback)
        }
   }

    func launchSettings(completion: ((SettingsViewModel) -> Void)? = nil,
                        deepLinkTarget: SettingsViewModel.SettingsDeepLinkSection? = nil,
                        configure: ((SettingsViewModel, SettingsHostingController) -> Void)? = nil) {
        let legacyViewProvider = SettingsLegacyViewProvider(syncService: syncService,
                                                            syncDataProviders: syncDataProviders,
                                                            appSettings: appSettings,
                                                            bookmarksDatabase: bookmarksDatabase,
                                                            tabManager: tabManager,
                                                            syncPausedStateManager: syncPausedStateManager,
                                                            fireproofing: fireproofing,
                                                            favicons: favicons,
                                                            websiteDataManager: websiteDataManager,
                                                            customConfigurationURLProvider: customConfigurationURLProvider,
                                                            keyValueStore: keyValueStore,
                                                            systemSettingsPiPTutorialManager: systemSettingsPiPTutorialManager,
                                                            daxDialogsManager: daxDialogsManager,
                                                            dbpIOSPublicInterface: dbpIOSPublicInterface,
                                                            subscriptionDataReporter: subscriptionDataReporter,
                                                            remoteMessagingDebugHandler: remoteMessagingDebugHandler,
                                                            productSurfaceTelemetry: productSurfaceTelemetry,
                                                            webExtensionManager: webExtensionManager,
                                                            syncAutoRestoreHandler: syncAutoRestoreHandler,
                                                            freemiumPIRDebugSettings: freemiumPIRDebugSettings,
                                                            freemiumDBPUserStateManager: freemiumDBPUserStateManager,
                                                            duckAiNativeStorageHandler: duckAiNativeStorageHandler)

        let aiChatSettings = AIChatSettings(privacyConfigurationManager: privacyConfigurationManager)
        let serpSettingsProvider = SERPSettingsProvider(aiChatProvider: aiChatSettings)
        // Share the app key-value store so native AI Features controls read/write the same
        // SERP settings blob the SERP uses.
        serpSettingsProvider.keyValueStore = keyValueStore
        let whatsNewCoordinator = WhatsNewCoordinator(
            displayContext: .onDemand,
            repository: whatsNewRepository,
            remoteMessageActionHandler: remoteMessagingActionHandler,
            isIPad: UIDevice.current.userInterfaceIdiom == .pad,
            pixelReporter: nil,
            userScriptsDependencies: userScriptsDependencies,
            imageLoader: remoteMessagingImageLoader,
            featureFlagger: featureFlagger)

        let settingsViewModel = SettingsViewModel(legacyViewProvider: legacyViewProvider,
                                                  subscriptionManager: AppDependencyProvider.shared.subscriptionManager,
                                                  subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                  voiceSearchHelper: voiceSearchHelper,
                                                  deepLink: deepLinkTarget,
                                                  historyManager: historyManager,
                                                  syncPausedStateManager: syncPausedStateManager,
                                                  subscriptionDataReporter: subscriptionDataReporter,
                                                  aiChatSettings: aiChatSettings,
                                                  serpSettings: serpSettingsProvider,
                                                  maliciousSiteProtectionPreferencesManager: maliciousSiteProtectionPreferencesManager,
                                                  themeManager: themeManager,
                                                  experimentalAIChatManager: ExperimentalAIChatManager(featureFlagger: featureFlagger),
                                                  privacyConfigurationManager: privacyConfigurationManager,
                                                  keyValueStore: keyValueStore,
                                                  contentBlockingAssetsPublisher: contentBlockingAssetsPublisher,
                                                  idleReturnEligibilityManager: idleReturnEligibilityManager,
                                                  afterInactivityOptionAdapter: afterInactivityOptionAdapter,
                                                  lastTabShortcutAdapter: lastTabShortcutAdapter,
                                                  systemSettingsPiPTutorialManager: systemSettingsPiPTutorialManager,
                                                  runPrerequisitesDelegate: dbpIOSPublicInterface,
                                                  dataBrokerProtectionViewControllerProvider: dbpIOSPublicInterface,
                                                  freemiumPIREligibilityChecker: freemiumPIREligibilityChecker,
                                                  winBackOfferVisibilityManager: winBackOfferVisibilityManager,
                                                  mobileCustomization: mobileCustomization,
                                                  userScriptsDependencies: userScriptsDependencies,
                                                  whatsNewCoordinator: whatsNewCoordinator,
                                                  darkReaderFeatureSettings: darkReaderFeatureSettings,
                                                  adBlockingAvailability: adBlockingAvailability)

        settingsViewModel.autoClearActionDelegate = self
        settingsViewModel.onRequestOpenDuckAIChat = { [weak self] in
            self?.dismiss(animated: true) {
                self?.loadUrlInNewTab(.duckAiSettings, inheritedAttribution: nil)
            }
        }
        Pixel.fire(pixel: .settingsPresented)

        func doLaunch() {
            if let navigationController = self.presentedViewController as? UINavigationController,
               let settingsHostingController = navigationController.viewControllers.first as? SettingsHostingController {
                navigationController.popToRootViewController(animated: false)
                completion?(settingsHostingController.viewModel)
            } else {
                assert(self.presentedViewController == nil)

                let settingsController = SettingsHostingController(viewModel: settingsViewModel,
                                                                   viewProvider: legacyViewProvider,
                                                                   productSurfaceTelemetry: self.productSurfaceTelemetry)

                // We are still presenting legacy views, so use a Navcontroller
                let navController = SettingsUINavigationController(rootViewController: settingsController)
                // When Settings is opened purely to host the onboarding subscription purchase, backing out
                // without buying should return home rather than land on Settings (see the override).
                navController.dismissesModalOnSubscriptionBailout = deepLinkTarget?.isOnboardingSubscriptionFlow ?? false
                navController.navigationBar.tintColor = UIColor(designSystemColor: .textPrimary)
                settingsController.modalPresentationStyle = UIModalPresentationStyle.automatic
                // Opaque nav bar and matching view background so sheet top gap (if any) is visually continuous with the bar
                let surfaceColor = UIColor(designSystemColor: .surface)
                navController.view.backgroundColor = surfaceColor
                navController.navigationBar.isTranslucent = false
                navController.navigationBar.barTintColor = surfaceColor
                navController.navigationBar.backgroundColor = surfaceColor

                // Apply custom configuration (e.g. pre-navigate to specific screens before presentation)
                configure?(settingsViewModel, settingsController)

                present(navController, animated: true) {
                    completion?(settingsViewModel)
                }
            }
        }

        if let controller = self.presentedViewController as? OmniBarEditingStateViewController {
            controller.dismissAnimated {
                doLaunch()
            }
        } else {
            doLaunch()
        }
    }

    private func launchDebugSettings(completion: ((DebugScreensViewController) -> Void)? = nil) {
        Logger.lifecycle.debug(#function)

        let debug = DebugScreensViewController(dependencies: .init(
            syncService: self.syncService,
            syncAutoRestoreHandler: self.syncAutoRestoreHandler,
            bookmarksDatabase: self.bookmarksDatabase,
            internalUserDecider: AppDependencyProvider.shared.internalUserDecider,
            tabManager: self.tabManager,
            tipKitUIActionHandler: TipKitDebugOptionsUIActionHandler(),
            fireproofing: self.fireproofing,
            customConfigurationURLProvider: customConfigurationURLProvider,
            keyValueStore: self.keyValueStore,
            systemSettingsPiPTutorialManager: self.systemSettingsPiPTutorialManager,
            daxDialogManager: self.daxDialogsManager,
            databaseDelegate: self.dbpIOSPublicInterface,
            debuggingDelegate: self.dbpIOSPublicInterface,
            runPrequisitesDelegate: self.dbpIOSPublicInterface,
            freemiumPIRDebugSettings: self.freemiumPIRDebugSettings,
            freemiumDBPUserStateManager: self.freemiumDBPUserStateManager,
            subscriptionDataReporter: self.subscriptionDataReporter,
            remoteMessagingDebugHandler: self.remoteMessagingDebugHandler,
            webExtensionManager: self.webExtensionManager,
            duckAiNativeStorageHandler: self.duckAiNativeStorageHandler))

        debug.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: debug, action: #selector(DebugScreensViewController.dismissSelf))

        let controller = UINavigationController(rootViewController: debug)
        controller.modalPresentationStyle = .automatic
        var presenter: UIViewController = self
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(controller, animated: true) {
            completion?(debug)
        }
    }

    private func hideAllHighlightsIfNeeded() {
        Logger.lifecycle.debug(#function)
        if !daxDialogsManager.shouldShowFireButtonPulse {
            ViewHighlighter.hideAll()
        }
    }

    private func dismissPresentedDataImportSummaryIfNeeded(completion: @escaping () -> Void) {
        let topMostViewController = topMostPresentedViewController(startingFrom: self)
        guard topMostViewController is DataImportSummaryViewController else {
            completion()
            return
        }

        topMostViewController.dismiss(animated: true, completion: completion)
    }

    private func topMostPresentedViewController(startingFrom rootViewController: UIViewController) -> UIViewController {
        var currentViewController = rootViewController
        while let presentedViewController = currentViewController.presentedViewController {
            currentViewController = presentedViewController
        }
        return currentViewController
    }

}

// Exists to fire a did disappear notification for settings when the controller did disappear
//  so that we get the event regardless of where in the UI hierarchy it happens.
class SettingsUINavigationController: UINavigationController {

    /// Whether to dismiss the entire Settings modal when the subscription flow was presented,
    /// but a subscription was not purchased
    var dismissesModalOnSubscriptionBailout = false

    /// Whether a subscription was acquired while the subscription flow was presented
    private var didAcquireSubscription = false
    private var subscriptionChangeObserver: Any?

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(rootViewController: SettingsHostingController) {
        super.init(rootViewController: rootViewController)
        subscriptionChangeObserver = NotificationCenter.default.addObserver(forName: .subscriptionDidChange,
                                                                            object: nil,
                                                                            queue: .main) { [weak self] _ in
            self?.didAcquireSubscription = true
        }
    }

    deinit {
        if let subscriptionChangeObserver {
            NotificationCenter.default.removeObserver(subscriptionChangeObserver)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NotificationCenter.default.post(name: .settingsDidDisappear, object: nil)
    }

    override func popViewController(animated: Bool) -> UIViewController? {
        // Bail out to home instead of popping to the Settings root
        // when leaving the onboarding subscription flow without a purchase.
        if dismissesModalOnSubscriptionBailout,
           viewControllers.count == 2,
           !didAcquireSubscription {
            dismiss(animated: true)
            return nil
        }
        return super.popViewController(animated: animated)
    }

    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        // Settings uses NavigationLink for deep linking, but because we don't use it within a NavigationStack, it talks
        // to the hosting navigation controller. It offers no control over navigation animation, so this workaround
        // disables animation any time a view controller is pushed while deep linking is being processed.
        if let settingsHostingController = self.viewControllers.first as? SettingsHostingController, settingsHostingController.isDeepLinking {
            super.pushViewController(viewController, animated: false)
        } else {
            super.pushViewController(viewController, animated: animated)
        }
    }

}

extension NSNotification.Name {
    static let settingsDidDisappear: NSNotification.Name = Notification.Name(rawValue: "com.duckduckgo.settings.didDisappear")
}
