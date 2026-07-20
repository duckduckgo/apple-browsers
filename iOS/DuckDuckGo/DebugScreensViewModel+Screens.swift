//
//  DebugScreensViewModel+Screens.swift
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
import SwiftUI
import UIKit
import WebKit
import BareBonesBrowserKit
import Core
import DataBrokerProtection_iOS
import AIChat
import WebExtensions
import DuckUI
import Persistence

extension DebugScreensViewModel {

    /// Just add your view or debug building logic to this array. In the UI this will be ordered by the title.
    /// Note that the storyboard is not passed to the controller builder - ideally we'll mirgate away from that to SwiftUI entirely
    var screens: [DebugScreen] {
        return [
            // MARK: Actions
            .action(title: "Clear WebKit Cache", { _ in
                WKWebsiteDataStore.default().removeData(
                    ofTypes: [WKWebsiteDataTypeDiskCache,
                              WKWebsiteDataTypeMemoryCache,
                              WKWebsiteDataTypeOfflineWebApplicationCache],
                    modifiedSince: .distantPast) { }
            }),
            .action(title: "Clear Cached Scriptlets", { d in
                if #available(iOS 18.4, *) {
                    Task { @MainActor in
                        d.webExtensionManager?.clearCachedScriptlets()
                    }
                }
            }),
            .view(title: "CPM", { d in
                CPMDebugScreensView(keyValueStore: d.keyValueStore)
            }),
            .action(title: "Reset Sync Promos", { d in
                let syncPromoPresenter = SyncPromoManager(syncService: d.syncService)
                syncPromoPresenter.resetPromos()
            }),
            .action(title: "Reset Sync Prompt On Launch", { d in
                try? d.keyValueStore.set(nil, forKey: SyncRecoveryPromptService.Key.hasPerformedSyncRecoveryCheck)
            }),
            .action(title: "Reset TipKit", { d in
                d.tipKitUIActionHandler.resetTipKitTapped()
            }),
            .action(title: "Reset Settings > Complete Setup", { d in
                try? d.keyValueStore.set(nil, forKey: SettingsViewModel.Constants.didDismissSetAsDefaultBrowserKey)
                try? d.keyValueStore.set(nil, forKey: SettingsViewModel.Constants.didDismissImportPasswordsKey)
                try? d.keyValueStore.set(nil, forKey: SettingsViewModel.Constants.shouldCheckIfDefaultBrowserKey)
            }),
            .action(title: "Generate Diagnostic Report", { d in
                guard let controller = UIApplication.shared.firstKeyWindow?.rootViewController?.presentedViewController else { return }

                class Delegate: NSObject, DiagnosticReportDataSourceDelegate {
                    func dataGatheringStarted() {
                        ActionMessageView.present(message: "Data Gathering Started... please wait")
                    }

                    func dataGatheringComplete() {
                        ActionMessageView.present(message: "Data Gathering Complete")
                    }
                }

                controller.presentShareSheet(withItems: [DiagnosticReportDataSource(delegate: Delegate(), tabManager: d.tabManager, fireproofing: d.fireproofing)], fromView: controller.view)
            }),
            .action(title: "Reset Prompts Cooldown Period", resetModalPromptsCooldownPeriod),

            // MARK: SwiftUI Views
            .view(title: "DuckUI", { _ in
                DuckUIDebugMenuView()
            }),
            .view(title: "Ad Blocking", { d in
                AdBlockingDebugView(keyValueStore: d.keyValueStore)
            }),
            .view(title: "AI Chat", { dependencies in
                AIChatDebugView(duckAiNativeStorageHandler: dependencies.duckAiNativeStorageHandler)
            }),
            .view(title: "Duck.ai Toggle Prompt", { _ in
                DuckAIToggleDebugView()
            }),
            .view(title: "Search Token", { _ in
                SearchTokenDebugView()
            }),
            .view(title: "Data Audit", { _ in
                DataAuditDebugScreen()
            }),
            .view(title: "Feature Flags", { _ in
                FeatureFlagsMenuView()
            }),
            .view(title: "UI Test Overrides", { _ in
                UITestOverridesDebugView()
            }),
            .view(title: "ContentScope Experiments", { _ in
                ContentScopeExperimentsDebugView()
            }),
            .view(title: "Crashes", { _ in
                CrashDebugScreen()
            }),
            .view(title: "DuckPlayer", { _ in
                DuckPlayerDebugSettingsView()
            }),
            .view(title: "Idle Return NTP", { _ in
                IdleReturnNTPDebugView()
            }),
            .view(title: "WebView State Restoration", { _ in
                WebViewStateRestorationDebugView()
            }),
            .view(title: "History", { d in
                HistoryDebugRootView(tabManager: d.tabManager)
            }),
            .view(title: "Bookmarks", { _ in
                BookmarksDebugRootView()
            }),
            .view(title: "Remote Messaging", { dependencies in
                RemoteMessagingDebugRootView(remoteMessagingDebugHandler: dependencies.remoteMessagingDebugHandler)
            }),
            .view(title: "Settings Cells Demo", { _ in
                SettingsCellDemoDebugView()
            }),
            .view(title: "Vanilla Web View", { d in
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
                configuration.processPool = WKProcessPool()

                let ddgURL = URL(string: "https://duckduckgo.com/")!
                let tab = d.tabManager.currentTabsModel.currentTab
                let url = tab?.link?.url ?? ddgURL
                return BareBonesBrowserView(initialURL: url,
                                            homeURL: ddgURL,
                                            uiDelegate: nil,
                                            configuration: configuration,
                                            userAgent: DefaultUserAgentManager.duckDuckGoUserAgent)

            }),
            .view(title: "Alert Playground", { _ in
                AlertPlaygroundView()
            }),
            .view(title: "Tab Generator", { d in
                BulkGeneratorView(factory: BulkTabFactory(tabManager: d.tabManager))
            }),
            .view(title: "Default Browser Prompt", { d in
                DefaultBrowserPromptDebugView(model: DefaultBrowserPromptDebugViewModel(keyValueFilesStore: d.keyValueStore))
            }),
            .view(title: "Notifications Playground", { _ in
                LocalNotificationsPlaygroundView()
            }),
            .view(title: "Win-back Offer", { d in
                WinBackOfferDebugView(keyValueStore: d.keyValueStore)
            }),
            .view(title: "Modal Prompt Coordination", { d in
                ModalPromptCoordinationDebugView(keyValueStore: d.keyValueStore)
            }),
            .view(title: "What's New", { dependencies in
                WhatsNewDebugView(keyValueStore: dependencies.keyValueStore, remoteMessagingDebugHandler: dependencies.remoteMessagingDebugHandler)
            }),

            // MARK: Controllers
            .controller(title: "Image Cache", { d in
                return self.debugStoryboard.instantiateViewController(identifier: "ImageCacheDebugViewController") { coder in
                    ImageCacheDebugViewController(coder: coder,
                                                  bookmarksDatabase: d.bookmarksDatabase,
                                                  tabsModel: d.tabManager.allTabsModel,
                                                  fireproofing: d.fireproofing)
                }
            }),
            .controller(title: "Sync", { d in
                return self.debugStoryboard.instantiateViewController(identifier: "SyncDebugViewController") { coder in
                    SyncDebugViewController(coder: coder,
                                            sync: d.syncService,
                                            bookmarksDatabase: d.bookmarksDatabase)
                }
            }),
            .controller(title: "Log Viewer", { d in
                return LogViewerViewController(dependencies: d)
            }),
            .controller(title: "Configuration Refresh Info", { _ in
                return self.debugStoryboard.instantiateViewController(identifier: "ConfigurationDebugViewController") { coder in
                    ConfigurationDebugViewController(coder: coder)
                }
            }),
            .controller(title: "VPN", { _ in
                return self.debugStoryboard.instantiateViewController(identifier: "NetworkProtectionDebugViewController") { coder in
                    NetworkProtectionDebugViewController(coder: coder)
                }
            }),
            AppDependencyProvider.shared.featureFlagger.isFeatureOn(.personalInformationRemoval) ? .controller(title: "PIR", { _ in
                return self.debugStoryboard.instantiateViewController(identifier: "DataBrokerProtectionDebugViewController") { coder in
                    DataBrokerProtectionDebugViewController(coder: coder,
                                                            databaseDelegate: self.dependencies.databaseDelegate,
                                                            debuggingDelegate: self.dependencies.debuggingDelegate,
                                                            runPrequisitesDelegate: self.dependencies.runPrequisitesDelegate,
                                                            freemiumPIRDebugSettings: self.dependencies.freemiumPIRDebugSettings,
                                                            freemiumDBPUserStateManager: self.dependencies.freemiumDBPUserStateManager)
                }
            }) : nil,
            webExtensionsDebugScreen,
            .controller(title: "File Size Inspector", { _ in
                return self.debugStoryboard.instantiateViewController(identifier: "FileSizeDebug") { coder in
                    FileSizeDebugViewController(coder: coder)
                }
            }),
            .controller(title: "Cookies", { d in
                return self.debugStoryboard.instantiateViewController(identifier: "CookieDebugViewController") { coder in
                    CookieDebugViewController(coder: coder, fireproofing: d.fireproofing)
                }
            }),
            .controller(title: "Keychain Items", { _ in
                return self.debugStoryboard.instantiateViewController(identifier: "KeychainItemsDebugViewController") { coder in
                    KeychainItemsDebugViewController(coder: coder)
                }
            }),
            .controller(title: "Autofill", { d in
                let autofillDebugViewController = self.debugStoryboard.instantiateViewController(identifier: "AutofillDebugViewController") { coder in
                    AutofillDebugViewController(coder: coder)
                }
                autofillDebugViewController.keyValueStore = d.keyValueStore
                return autofillDebugViewController
            }),
            .controller(title: "Logging", { _ in
                return LoggingDebugViewController()
            }),
            .controller(title: "Subscription", { dependencies in
                return self.debugStoryboard.instantiateViewController(identifier: "SubscriptionDebugViewController") { coder in
                    SubscriptionDebugViewController(coder: coder, subscriptionDataReporter: dependencies.subscriptionDataReporter)
                }
            }),
            .controller(title: "Configuration URLs", { _ in
                return self.debugStoryboard.instantiateViewController(identifier: "ConfigurationURLDebugViewController") { coder in
                    let viewController = ConfigurationURLDebugViewController(coder: coder)
                    viewController?.viewModel = self
                    return viewController
                }
            }),
            .controller(title: "Onboarding", { d in
                class OnboardingDebugViewController: UIHostingController<OnboardingDebugView>, OnboardingDelegate {

                    func didStartOnboardingInterlude(_ interlude: OnboardingIntroStep.Interlude) {}

                    func onboardingCompleted(controller: UIViewController) {
                        controller.presentingViewController?.dismiss(animated: true)
                    }

                    func openAIChatFromOnboarding(_ query: String?, autoSend: Bool, flowType: AIChatOnboardingFlowType) {}

                    func searchFromOnboarding(for query: String) {}
                }

                weak var capturedController: OnboardingDebugViewController?

                // swiftlint:disable:next empty_parentheses_with_trailing_closure
                let onboardingController = OnboardingDebugViewController(rootView: OnboardingDebugView() {
                    guard let capturedController else { return }

                    let viewModel = OnboardingIntroFactory.makeViewModel(
                        pixelReporter: OnboardingPixelReporter(),
                        systemSettingsPiPTutorialManager: d.systemSettingsPiPTutorialManager,
                        daxDialogsManager: d.daxDialogManager,
                        syncAutoRestoreHandler: d.syncAutoRestoreHandler,
                        onboardingManager: OnboardingManager()
                    )
                    let controller = OnboardingIntroFactory.makeController(
                        viewModel: viewModel,
                        delegate: capturedController
                    )
                    controller.modalPresentationStyle = .overFullScreen
                    capturedController.parent?.present(controller: controller, fromView: capturedController.view)
                })
                capturedController = onboardingController
                return onboardingController
            }),
            .controller(title: "Attributed Metrics", { _ in
                return self.debugStoryboard.instantiateViewController(identifier: "AttributedMetricsDebugViewController") { coder in
                    AttributedMetricsDebugViewController(coder: coder)
                }
            }),
        ].compactMap { $0 }
    }
    
    private func resetModalPromptsCooldownPeriod(_ dependencies: DebugScreen.Dependencies) {
        let store = PromptCooldownKeyValueFilesStore(
            keyValueStore: dependencies.keyValueStore,
            eventMapper: .init(mapping: { _, _, _, _ in })
        )

        store.lastPresentationTimestamp = nil
    }

    private var webExtensionsDebugScreen: DebugScreen? {
        guard #available(iOS 18.4, *),
              AppDependencyProvider.shared.featureFlagger.isFeatureOn(.webExtensions) else {
            return nil
        }

        return .view(title: "Web Extensions") { d in
            if let manager = d.webExtensionManager {
                WebExtensionsDebugView(webExtensionManager: manager)
            } else {
                Text("Web Extensions not available")
            }
        }
    }

}

/// Sub-screen grouping the CPM (Cookie Pop-up Protection) debug actions.
private struct CPMDebugScreensView: View {

    let keyValueStore: ThrowingKeyValueStoring

    var body: some View {
        List {
            Section("Opt-in dialog") {
                Button("Show opt-in dialog") {
                    Self.presentOptInDialog()
                }
                Button("Reset app launch flag") {
                    // Clears the shown flag + shown count.
                    CookiePopupProtectionOptInPromptStore(keyValueStore: keyValueStore).reset()
                    // Also lift the global modal cooldown — otherwise the queue suppresses all prompts on launch until it expires.
                    try? keyValueStore.set(nil, forKey: PromptCooldownKeyValueFilesStore.StorageKey.lastPromptShownTimestamp)
                    ActionMessageView.present(message: "Reset opt-in dialog launch state - DONE")
                }
            }
            Section {
                Button("Reset Autoconsent Prompt") {
                    AppUserDefaults().clearAutoconsentUserSetting()
                    ActionMessageView.present(message: "Reset Autoconsent Prompt - DONE")
                }
            }
        }
        .navigationTitle("CPM")
    }

    /// Presents the Cookie Pop-up Protection opt-in dialog as a sheet over the browser.
    private static func presentOptInDialog() {
        guard let window = UIApplication.shared.firstKeyWindow else { return }

        let present = {
            let controller = CookiePopupProtectionOptInModalPromptProvider.makeViewController()
            window.rootViewController?.present(controller, animated: true)
        }

        // Dismiss the Settings/debug stack first so the dialog appears over the browser.
        if let presented = window.rootViewController?.presentedViewController {
            presented.dismiss(animated: true, completion: present)
        } else {
            present()
        }
    }
}
