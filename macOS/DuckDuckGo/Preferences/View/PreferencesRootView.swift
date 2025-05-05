//
//  PreferencesRootView.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import PreferencesUI_macOS
import SwiftUI
import SwiftUIExtensions
import SyncUI_macOS
import BrowserServicesKit
import PixelKit
import Subscription
import SubscriptionUI

enum Preferences {

    enum Const {
        static var sidebarWidth: CGFloat {
            switch Locale.current.languageCode {
            case "en":
                return 310
            default:
                return 355
            }
        }
        static let paneContentWidth: CGFloat = 544
        static let panePaddingHorizontal: CGFloat = 24
        static let panePaddingVertical: CGFloat = 32
        static let minSidebarWidth: CGFloat = 128
        static let minContentWidth: CGFloat = 416
    }

    struct RootView: View {

        @ObservedObject var model: PreferencesSidebarModel

        var subscriptionModel: PreferencesSubscriptionModel?
        let subscriptionManager: SubscriptionManager
        let subscriptionUIHandler: SubscriptionUIHandling

        init(model: PreferencesSidebarModel,
             subscriptionManager: SubscriptionManager,
             subscriptionUIHandler: SubscriptionUIHandling) {
            self.model = model
            self.subscriptionManager = subscriptionManager
            self.subscriptionUIHandler = subscriptionUIHandler
            self.subscriptionModel = makeSubscriptionViewModel()
        }

        var body: some View {
            HStack(spacing: 0) {
                Sidebar().environmentObject(model).frame(minWidth: Const.minSidebarWidth, maxWidth: Const.sidebarWidth)
                    .layoutPriority(1)
                Color(NSColor.separatorColor).frame(width: 1)
                ScrollView(.vertical) {
                    HStack(spacing: 0) {
                        contentView
                        Spacer()
                    }
                }
                .frame(minWidth: Const.minContentWidth, maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.preferencesBackground)
        }

        @ViewBuilder
        var contentView: some View {
            VStack(alignment: .leading) {
                switch model.selectedPane {
                case .defaultBrowser:
                    DefaultBrowserView(defaultBrowserModel: DefaultBrowserPreferences.shared,
                                       dockCustomizer: DockCustomizer(),
                                       status: PrivacyProtectionStatus.status(for: .defaultBrowser))
                case .privateSearch:
                    PrivateSearchView(model: SearchPreferences.shared)
                case .webTrackingProtection:
                    WebTrackingProtectionView(model: WebTrackingProtectionPreferences.shared)
                case .cookiePopupProtection:
                    CookiePopupProtectionView(model: CookiePopupProtectionPreferences.shared)
                case .emailProtection:
                    EmailProtectionView(emailManager: EmailManager())
                case .general:
                    GeneralView(startupModel: StartupPreferences.shared,
                                downloadsModel: DownloadsPreferences.shared,
                                searchModel: SearchPreferences.shared,
                                tabsModel: TabsPreferences.shared,
                                dataClearingModel: DataClearingPreferences.shared,
                                maliciousSiteDetectionModel: MaliciousSiteProtectionPreferences.shared,
                                dockCustomizer: DockCustomizer())
                case .sync:
                    SyncView()
                case .appearance:
                    AppearanceView(model: .shared)
                case .dataClearing:
                    DataClearingView(model: DataClearingPreferences.shared)
                case .vpn:
                    VPNView(model: VPNPreferencesModel(), status: model.vpnProtectionStatus())
                case .subscription:
                    SubscriptionUI.PreferencesSubscriptionViewV1(model: subscriptionModel!,
                                                                 subscriptionFeatureAvailability: DefaultSubscriptionFeatureAvailability())
                case .autofill:
                    AutofillView(model: AutofillPreferencesModel())
                case .accessibility:
                    AccessibilityView(model: AccessibilityPreferences.shared)
                case .duckPlayer:
                    DuckPlayerView(model: .shared)
                case .otherPlatforms:
                    // Opens a new tab
                    Spacer()
                case .about:
                    AboutView(model: AboutPreferences.shared)
                case .aiChat:
                    AIChatView(model: AIChatPreferences.shared)
                }
            }
            .frame(maxWidth: Const.paneContentWidth, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, Const.panePaddingVertical)
            .padding(.horizontal, Const.panePaddingHorizontal)
        }

        private func makeSubscriptionViewModel() -> PreferencesSubscriptionModel {
            let openURL: (URL) -> Void = { url in
                DispatchQueue.main.async {
                    WindowControllersManager.shared.showTab(with: .subscription(url.appendingParameter(name: AttributionParameter.origin, value: SubscriptionFunnelOrigin.appSettings.rawValue)))
                }
            }

            let handleUIEvent: (PreferencesSubscriptionModel.UserEvent) -> Void = { event in
                DispatchQueue.main.async {
                    switch event {
                    case .openVPN:
                        PixelKit.fire(PrivacyProPixel.privacyProVPNSettings)
                        NotificationCenter.default.post(name: .ToggleNetworkProtectionInMainWindow, object: self, userInfo: nil)
                    case .openFeedback:
                        NotificationCenter.default.post(name: .OpenUnifiedFeedbackForm,
                                                        object: self,
                                                        userInfo: UnifiedFeedbackSource.userInfo(source: .ppro))
                    case .openDB:
                        PixelKit.fire(PrivacyProPixel.privacyProPersonalInformationRemovalSettings)
                        WindowControllersManager.shared.showTab(with: .dataBrokerProtection)
                    case .openITR:
                        PixelKit.fire(PrivacyProPixel.privacyProIdentityRestorationSettings)
                        let url = subscriptionManager.url(for: .identityTheftRestoration)
                        WindowControllersManager.shared.showTab(with: .identityTheftRestoration(url))
                    case .iHaveASubscriptionClick:
                        PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseClick)
                    case .activateSubscriptionViaEmailClick:
                        PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseEmailStart, frequency: .legacyDailyAndCount)
                    case .activateSubscriptionViaRestoreAppStorePurchaseClick:
                        PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseStoreStart, frequency: .legacyDailyAndCount)
                    case .manageEmailClick:
                        PixelKit.fire(PrivacyProPixel.privacyProSubscriptionManagementEmail, frequency: .uniqueByName)
                    case .addToDeviceActivationFlow:
                        // Handled on web
                        break
                    case .openSubscriptionSettingsClick:
                        PixelKit.fire(PrivacyProPixel.privacyProSubscriptionSettings)
                    case .changePlanOrBillingClick:
                        PixelKit.fire(PrivacyProPixel.privacyProSubscriptionManagementPlanBilling)
                    case .removeSubscriptionClick:
                        PixelKit.fire(PrivacyProPixel.privacyProSubscriptionManagementRemoval)
                    }
                }
            }

            let sheetActionHandler = SubscriptionAccessActionHandlers(
                openActivateViaEmailURL: {
                    let url = subscriptionManager.url(for: .activationFlow)
                    WindowControllersManager.shared.showTab(with: .subscription(url))
                }, restorePurchases: {
                    if #available(macOS 12.0, *) {
                        Task {
                            let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: subscriptionManager.accountManager,
                                                                                 storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                                 subscriptionEndpointService: subscriptionManager.subscriptionEndpointService,
                                                                                 authEndpointService: subscriptionManager.authEndpointService)
                            let subscriptionAppStoreRestorer = DefaultSubscriptionAppStoreRestorer(
                                subscriptionManager: subscriptionManager,
                                appStoreRestoreFlow: appStoreRestoreFlow,
                                uiHandler: subscriptionUIHandler)
                            await subscriptionAppStoreRestorer.restoreAppStoreSubscription()
                        }
                    }
                }, uiActionHandler: handleUIEvent)

            return PreferencesSubscriptionModel(openURLHandler: openURL,
                                                userEventHandler: handleUIEvent,
                                                sheetActionHandler: sheetActionHandler,
                                                subscriptionManager: subscriptionManager,
                                                featureFlagger: NSApp.delegateTyped.featureFlagger)
        }
    }

    struct RootViewV2: View {

        @ObservedObject var model: PreferencesSidebarModel

        var subscriptionModel: PreferencesSubscriptionModelV2?
        let subscriptionManager: SubscriptionManagerV2
        let subscriptionUIHandler: SubscriptionUIHandling

        init(
            model: PreferencesSidebarModel,
            subscriptionManager: SubscriptionManagerV2,
            subscriptionUIHandler: SubscriptionUIHandling
        ) {
            self.model = model
            self.subscriptionManager = subscriptionManager
            self.subscriptionUIHandler = subscriptionUIHandler
            self.subscriptionModel = makeSubscriptionViewModel()
        }

        var body: some View {
            HStack(spacing: 0) {
                Sidebar().environmentObject(model).frame(minWidth: Const.minSidebarWidth, maxWidth: Const.sidebarWidth)
                    .layoutPriority(1)
                Color(NSColor.separatorColor).frame(width: 1)
                ScrollView(.vertical) {
                    HStack(spacing: 0) {
                        contentView
                        Spacer()
                    }
                }
                .frame(minWidth: Const.minContentWidth, maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.preferencesBackground)
        }

        @ViewBuilder
        var contentView: some View {
            VStack(alignment: .leading) {
                switch model.selectedPane {
                case .defaultBrowser:
                    DefaultBrowserView(defaultBrowserModel: DefaultBrowserPreferences.shared,
                                       dockCustomizer: DockCustomizer(),
                                       status: PrivacyProtectionStatus.status(for: .defaultBrowser))
                case .privateSearch:
                    PrivateSearchView(model: SearchPreferences.shared)
                case .webTrackingProtection:
                    WebTrackingProtectionView(model: WebTrackingProtectionPreferences.shared)
                case .cookiePopupProtection:
                    CookiePopupProtectionView(model: CookiePopupProtectionPreferences.shared)
                case .emailProtection:
                    EmailProtectionView(emailManager: EmailManager())
                case .general:
                    GeneralView(startupModel: StartupPreferences.shared,
                                downloadsModel: DownloadsPreferences.shared,
                                searchModel: SearchPreferences.shared,
                                tabsModel: TabsPreferences.shared,
                                dataClearingModel: DataClearingPreferences.shared,
                                maliciousSiteDetectionModel: MaliciousSiteProtectionPreferences.shared,
                                dockCustomizer: DockCustomizer())
                case .sync:
                    SyncView()
                case .appearance:
                    AppearanceView(model: .shared)
                case .dataClearing:
                    DataClearingView(model: DataClearingPreferences.shared)
                case .vpn:
                    VPNView(model: VPNPreferencesModel(), status: model.vpnProtectionStatus())
                case .subscription:
                    SubscriptionUI.PreferencesSubscriptionViewV2(model: subscriptionModel!,
                                                                 subscriptionFeatureAvailability: DefaultSubscriptionFeatureAvailability())
                case .autofill:
                    AutofillView(model: AutofillPreferencesModel())
                case .accessibility:
                    AccessibilityView(model: AccessibilityPreferences.shared)
                case .duckPlayer:
                    DuckPlayerView(model: .shared)
                case .otherPlatforms:
                    // Opens a new tab
                    Spacer()
                case .about:
                    AboutView(model: AboutPreferences.shared)
                case .aiChat:
                    AIChatView(model: AIChatPreferences.shared)
                }
            }
            .frame(maxWidth: Const.paneContentWidth, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, Const.panePaddingVertical)
            .padding(.horizontal, Const.panePaddingHorizontal)
        }

        private func makeSubscriptionViewModel() -> PreferencesSubscriptionModelV2 {
            let openURL: (URL) -> Void = { url in
                DispatchQueue.main.async {
                    WindowControllersManager.shared.showTab(with: .subscription(url))
                }
            }

            let handleUIEvent: (PreferencesSubscriptionModel.UserEvent) -> Void = { event in
                DispatchQueue.main.async {
                    switch event {
                    case .openVPN:
                        PixelKit.fire(PrivacyProPixel.privacyProVPNSettings)
                        NotificationCenter.default.post(name: .ToggleNetworkProtectionInMainWindow, object: self, userInfo: nil)
                    case .openFeedback:
                        NotificationCenter.default.post(name: .OpenUnifiedFeedbackForm,
                                                        object: self,
                                                        userInfo: UnifiedFeedbackSource.userInfo(source: .ppro))
                    case .openDB:
                        PixelKit.fire(PrivacyProPixel.privacyProPersonalInformationRemovalSettings)
                        WindowControllersManager.shared.showTab(with: .dataBrokerProtection)
                    case .openITR:
                        PixelKit.fire(PrivacyProPixel.privacyProIdentityRestorationSettings)
                        let url = subscriptionManager.url(for: .identityTheftRestoration)
                        WindowControllersManager.shared.showTab(with: .identityTheftRestoration(url))
                    case .iHaveASubscriptionClick:
                        PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseClick)
                    case .activateSubscriptionViaEmailClick:
                        PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseEmailStart, frequency: .legacyDailyAndCount)
                    case .activateSubscriptionViaRestoreAppStorePurchaseClick:
                        PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseStoreStart, frequency: .legacyDailyAndCount)
                    case .manageEmailClick:
                        PixelKit.fire(PrivacyProPixel.privacyProSubscriptionManagementEmail, frequency: .uniqueByName)
                    case .addToDeviceActivationFlow:
                        // Handled on web
                        break
                    case .openSubscriptionSettingsClick:
                        PixelKit.fire(PrivacyProPixel.privacyProSubscriptionSettings)
                    case .changePlanOrBillingClick:
                        PixelKit.fire(PrivacyProPixel.privacyProSubscriptionManagementPlanBilling)
                    case .removeSubscriptionClick:
                        PixelKit.fire(PrivacyProPixel.privacyProSubscriptionManagementRemoval)
                    }
                }
            }

            let sheetActionHandler = SubscriptionAccessActionHandlers(
                openActivateViaEmailURL: {
                    let url = subscriptionManager.url(for: .activationFlow)
                    WindowControllersManager.shared.showTab(with: .subscription(url))
                }, restorePurchases: {
                    if #available(macOS 12.0, *) {
                        Task {
                            let appStoreRestoreFlow = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManager,
                                                                                 storePurchaseManager: subscriptionManager.storePurchaseManager())
                            let subscriptionAppStoreRestorer = DefaultSubscriptionAppStoreRestorerV2(subscriptionManager: subscriptionManager,
                                                                                                     appStoreRestoreFlow: appStoreRestoreFlow,
                                                                                                     uiHandler: subscriptionUIHandler)
                            await subscriptionAppStoreRestorer.restoreAppStoreSubscription()
                        }
                    }
                }, uiActionHandler: handleUIEvent)

            return PreferencesSubscriptionModelV2(openURLHandler: openURL,
                                                  userEventHandler: handleUIEvent,
                                                  sheetActionHandler: sheetActionHandler,
                                                  subscriptionManager: subscriptionManager,
                                                  featureFlagger: NSApp.delegateTyped.featureFlagger)
        }
    }

}
