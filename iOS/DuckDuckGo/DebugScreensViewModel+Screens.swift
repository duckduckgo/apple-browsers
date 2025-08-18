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

extension DebugScreensViewModel {

    /// Just add your view or debug building logic to this array. In the UI this will be ordered by the title.
    /// Note that the storyboard is not passed to the controller builder - ideally we'll mirgate away from that to SwiftUI entirely
    var screens: [DebugScreen] {
        return [
            // MARK: Actions
            .action(title: "Reset Autoconsent Prompt", { _ in
                AppUserDefaults().clearAutoconsentUserSetting()
            }),
            .action(title: "Reset Sync Promos", { d in
                let syncPromoPresenter = SyncPromoManager(syncService: d.syncService)
                syncPromoPresenter.resetPromos()
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
                guard let controller = UIApplication.shared.window?.rootViewController?.presentedViewController else { return }

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

            // MARK: SwiftUI Views
            .view(title: "AI Chat", { _ in
                AIChatDebugView()
            }),
            .view(title: "Feature Flags", { _ in
                FeatureFlagsMenuView()
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
            .view(title: "New Tab Page", { _ in
                NewTabPageSectionsDebugView()
            }),
            .view(title: "WebView State Restoration", { _ in
                WebViewStateRestorationDebugView()
            }),
            .view(title: "History", { _ in
                HistoryDebugRootView()
            }),
            .view(title: "Bookmarks", { _ in
                BookmarksDebugRootView()
            }),
            .view(title: "Remote Messaging", { _ in
                RemoteMessagingDebugRootView()
            }),
            .view(title: "Settings Cells Demo", { _ in
                SettingsCellDemoDebugView()
            }),
            .view(title: "Vanilla Web View", { d in
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
                configuration.processPool = WKProcessPool()

                let ddgURL = URL(string: "https://duckduckgo.com/")!
                let tab = d.tabManager.model.safeGetTabAt(d.tabManager.model.currentIndex)
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

            // MARK: Controllers
            .controller(title: "Image Cache", { d in
                let storyboard = UIStoryboard(name: "Debug", bundle: nil)
                return storyboard.instantiateViewController(identifier: "ImageCacheDebugViewController") { coder in
                    ImageCacheDebugViewController(coder: coder,
                                                  bookmarksDatabase: d.bookmarksDatabase,
                                                  tabsModel: d.tabManager.model,
                                                  fireproofing: d.fireproofing)
                }
            }),
            .controller(title: "Sync", { d in
                let storyboard = UIStoryboard(name: "Debug", bundle: nil)
                return storyboard.instantiateViewController(identifier: "SyncDebugViewController") { coder in
                    SyncDebugViewController(coder: coder,
                                            sync: d.syncService,
                                            bookmarksDatabase: d.bookmarksDatabase)
                }
            }),
            .controller(title: "Log Viewer", { d in
                return LogViewerViewController(dependencies: d)
            }),
            .controller(title: "Configuration Refresh Info", { _ in
                let storyboard = UIStoryboard(name: "Debug", bundle: nil)
                return storyboard.instantiateViewController(identifier: "ConfigurationDebugViewController") { coder in
                    ConfigurationDebugViewController(coder: coder)
                }
            }),
            .controller(title: "VPN", { _ in
                let storyboard = UIStoryboard(name: "Debug", bundle: nil)
                return storyboard.instantiateViewController(identifier: "NetworkProtectionDebugViewController") { coder in
                    NetworkProtectionDebugViewController(coder: coder)
                }
            }),
            AppDependencyProvider.shared.featureFlagger.isFeatureOn(.personalInformationRemoval) ? .controller(title: "PIR", { _ in
                let storyboard = UIStoryboard(name: "Debug", bundle: nil)
                return storyboard.instantiateViewController(identifier: "DataBrokerProtectionDebugViewController") { coder in
                    DataBrokerProtectionDebugViewController(coder: coder)
                }
            }) : nil,
            .controller(title: "File Size Inspector", { _ in
                let storyboard = UIStoryboard(name: "Debug", bundle: nil)
                return storyboard.instantiateViewController(identifier: "FileSizeDebug") { coder in
                    FileSizeDebugViewController(coder: coder)
                }
            }),
            .controller(title: "Cookies", { d in
                let storyboard = UIStoryboard(name: "Debug", bundle: nil)
                return storyboard.instantiateViewController(identifier: "CookieDebugViewController") { coder in
                    CookieDebugViewController(coder: coder, fireproofing: d.fireproofing)
                }
            }),
            .controller(title: "Keychain Items", { _ in
                let storyboard = UIStoryboard(name: "Debug", bundle: nil)
                return storyboard.instantiateViewController(identifier: "KeychainItemsDebugViewController") { coder in
                    KeychainItemsDebugViewController(coder: coder)
                }
            }),
            .controller(title: "Autofill", { d in
                let storyboard = UIStoryboard(name: "Debug", bundle: nil)
                let autofillDebugViewController = storyboard.instantiateViewController(identifier: "AutofillDebugViewController") { coder in
                    AutofillDebugViewController(coder: coder)
                }
                autofillDebugViewController.keyValueStore = d.keyValueStore
                return autofillDebugViewController
            }),
            .controller(title: "Subscription", { _ in
                let storyboard = UIStoryboard(name: "Debug", bundle: nil)
                return storyboard.instantiateViewController(identifier: "SubscriptionDebugViewController") { coder in
                    SubscriptionDebugViewController(coder: coder)
                }
            }),
            .controller(title: "Configuration URLs", { _ in
                let storyboard = UIStoryboard(name: "Debug", bundle: nil)
                return storyboard.instantiateViewController(identifier: "ConfigurationURLDebugViewController") { coder in
                    let viewController = ConfigurationURLDebugViewController(coder: coder)
                    viewController?.viewModel = self
                    return viewController
                }
            }),
            .controller(title: "Onboarding", { d in
                class OnboardingDebugViewController: UIHostingController<OnboardingDebugView>, OnboardingDelegate {
                    func onboardingCompleted(controller: UIViewController) {
                        controller.presentingViewController?.dismiss(animated: true)
                    }
                }

                weak var capturedController: OnboardingDebugViewController?
                let onboardingController = OnboardingDebugViewController(rootView: OnboardingDebugView {
                    guard let capturedController else { return }
                    let controller = OnboardingIntroViewController(onboardingPixelReporter: OnboardingPixelReporter(), systemSettingsPiPTutorialManager: d.systemSettingsPiPTutorialManager, daxDialogsManager: d.daxDialogManager)
                    controller.delegate = capturedController
                    controller.modalPresentationStyle = .overFullScreen
                    capturedController.parent?.present(controller: controller, fromView: capturedController.view)
                })
                capturedController = onboardingController
                return onboardingController
            }),
        ].compactMap { $0 }
    }

}
