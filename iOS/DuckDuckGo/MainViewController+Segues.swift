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

    func segueToDaxOnboarding() {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()

        let controller = OnboardingIntroViewController(
            onboardingPixelReporter: contextualOnboardingPixelReporter,
            systemSettingsPiPTutorialManager: systemSettingsPiPTutorialManager,
            daxDialogsManager: daxDialogsManager)
        controller.delegate = self
        controller.modalPresentationStyle = .overFullScreen
        present(controller, animated: false)
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

        guard let currentURL = currentTab?.url,
              let privacyInfo = currentTab?.makePrivacyInfo(url: currentURL) else {
            assertionFailure("Missing fundamental data")
            return
        }

        let storyboard = UIStoryboard(name: "PrivacyDashboard", bundle: nil)
        let controller = storyboard.instantiateInitialViewController { coder in
            PrivacyDashboardViewController(coder: coder,
                                           privacyInfo: privacyInfo,
                                           entryPoint: entryPoint,
                                           privacyConfigurationManager: self.privacyConfigurationManager,
                                           contentBlockingManager: ContentBlocking.shared.contentBlockingManager,
                                           breakageAdditionalInfo: self.currentTab?.makeBreakageAdditionalInfo())
        }
        
        guard let controller = controller else {
            assertionFailure("PrivacyDashboardViewController not initialised")
            return
        }
        
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

        let storyboard = UIStoryboard(name: "Downloads", bundle: nil)
        guard let controller = storyboard.instantiateInitialViewController() else {
            assertionFailure()
            return
        }
        present(controller, animated: true)
    }

    func segueToTabSwitcher() {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()

        let storyboard = UIStoryboard(name: "TabSwitcher", bundle: nil)
        guard let controller = storyboard.instantiateInitialViewController(creator: { coder in
            TabSwitcherViewController(coder: coder,
                                      bookmarksDatabase: self.bookmarksDatabase,
                                      syncService: self.syncService,
                                      featureFlagger: self.featureFlagger,
                                      tabManager: self.tabManager,
                                      aiChatSettings: self.aiChatSettings,
                                      appSettings: self.appSettings,
                                      productSurfaceTelemetry: self.productSurfaceTelemetry,
                                      historyManager: self.historyManager,
                                      fireproofing: self.fireproofing,
                                      keyValueStore: self.keyValueStore)
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

    func segueToDuckDuckGoSubscription() {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()
        launchSettings(completion: {
            $0.triggerDeepLinkNavigation(to: .subscriptionFlow())
        }, deepLinkTarget: .subscriptionFlow())
    }

    func segueToSubscriptionRestoreFlow() {
        Logger.lifecycle.debug(#function)
        hideAllHighlightsIfNeeded()
        launchSettings(completion: {
            $0.triggerDeepLinkNavigation(to: .restoreFlow)
        }, deepLinkTarget: .restoreFlow)
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
        let launchSync: () -> Void = { [weak self] in
            self?.launchSettings {
                if let source = source {
                    $0.shouldPresentSyncViewWithSource(source)
                } else {
                    $0.presentLegacyView(.sync(pairingInfo))
                }
            }
        }
        if let presentedViewController {
            presentedViewController.dismiss(animated: false, completion: launchSync)
        } else {
            launchSync()
        }
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
                                                            websiteDataManager: websiteDataManager,
                                                            customConfigurationURLProvider: customConfigurationURLProvider,
                                                            keyValueStore: keyValueStore,
                                                            systemSettingsPiPTutorialManager: systemSettingsPiPTutorialManager,
                                                            daxDialogsManager: daxDialogsManager,
                                                            dbpIOSPublicInterface: dbpIOSPublicInterface,
                                                            subscriptionDataReporter: subscriptionDataReporter,
                                                            remoteMessagingDebugHandler: remoteMessagingDebugHandler,
                                                            productSurfaceTelemetry: productSurfaceTelemetry)

        let aiChatSettings = AIChatSettings(privacyConfigurationManager: privacyConfigurationManager)
        let serpSettingsProvider = SERPSettingsProvider(aiChatProvider: aiChatSettings,
                                                        featureFlagger: featureFlagger)
        let whatsNewCoordinator = WhatsNewCoordinator(
            displayContext: .onDemand,
            repository: whatsNewRepository,
            remoteMessageActionHandler: remoteMessagingActionHandler,
            isIPad: UIDevice.current.userInterfaceIdiom == .pad,
            pixelReporter: nil,
            userScriptsDependencies: userScriptsDependencies)

        let settingsViewModel = SettingsViewModel(legacyViewProvider: legacyViewProvider,
                                                  subscriptionManager: AppDependencyProvider.shared.subscriptionManager,
                                                  subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                  voiceSearchHelper: voiceSearchHelper,
                                                  deepLink: deepLinkTarget,
                                                  historyManager: historyManager,
                                                  syncPausedStateManager: syncPausedStateManager,
                                                  subscriptionDataReporter: subscriptionDataReporter,
                                                  textZoomCoordinator: textZoomCoordinator,
                                                  aiChatSettings: aiChatSettings,
                                                  serpSettings: serpSettingsProvider,
                                                  maliciousSiteProtectionPreferencesManager: maliciousSiteProtectionPreferencesManager,
                                                  themeManager: themeManager,
                                                  experimentalAIChatManager: ExperimentalAIChatManager(featureFlagger: featureFlagger),
                                                  privacyConfigurationManager: privacyConfigurationManager,
                                                  keyValueStore: keyValueStore,
                                                  systemSettingsPiPTutorialManager: systemSettingsPiPTutorialManager,
                                                  runPrerequisitesDelegate: dbpIOSPublicInterface,
                                                  dataBrokerProtectionViewControllerProvider: dbpIOSPublicInterface,
                                                  winBackOfferVisibilityManager: winBackOfferVisibilityManager,
                                                  mobileCustomization: mobileCustomization,
                                                  userScriptsDependencies: userScriptsDependencies,
                                                  browsingMenuSheetCapability: BrowsingMenuSheetCapability.create(using: featureFlagger, keyValueStore: keyValueStore),
                                                  whatsNewCoordinator: whatsNewCoordinator)

        settingsViewModel.autoClearActionDelegate = self
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
                settingsController.modalPresentationStyle = UIModalPresentationStyle.automatic

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
            subscriptionDataReporter: self.subscriptionDataReporter,
            remoteMessagingDebugHandler: self.remoteMessagingDebugHandler))

        let controller = UINavigationController(rootViewController: debug)
        controller.modalPresentationStyle = .automatic
        present(controller, animated: true) {
            completion?(debug)
        }
    }

    private func hideAllHighlightsIfNeeded() {
        Logger.lifecycle.debug(#function)
        if !daxDialogsManager.shouldShowFireButtonPulse {
            ViewHighlighter.hideAll()
        }
    }
    
}

// Exists to fire a did disappear notification for settings when the controller did disappear
//  so that we get the event regardless of where in the UI hierarchy it happens.
class SettingsUINavigationController: UINavigationController {

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(rootViewController: SettingsHostingController) {
        super.init(rootViewController: rootViewController)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NotificationCenter.default.post(name: .settingsDidDisappear, object: nil)
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
