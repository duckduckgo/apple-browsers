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
import AIChat

enum Preferences {

    enum Const {
        static var sidebarWidth: CGFloat {
            switch Locale.current.languageCode {
            case "en":
                return 315
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

        var purchaseSubscriptionModel: PreferencesPurchaseSubscriptionModel?
        var personalInformationRemovalModel: PreferencesPersonalInformationRemovalModel?
        var identityTheftRestorationModel: PreferencesIdentityTheftRestorationModel?
        var subscriptionSettingsModel: PreferencesSubscriptionSettingsModelV1?
        let subscriptionManager: SubscriptionManager
        let subscriptionUIHandler: SubscriptionUIHandling
        let visualStyle: VisualStyleProviding

        init(model: PreferencesSidebarModel,
             subscriptionManager: SubscriptionManager,
             subscriptionUIHandler: SubscriptionUIHandling,
             visualStyle: VisualStyleProviding = NSApp.delegateTyped.visualStyle) {
            self.model = model
            self.subscriptionManager = subscriptionManager
            self.subscriptionUIHandler = subscriptionUIHandler
            self.visualStyle = visualStyle
            self.purchaseSubscriptionModel = makePurchaseSubscriptionViewModel()
            self.personalInformationRemovalModel = makePersonalInformationRemovalViewModel()
            self.identityTheftRestorationModel = makeIdentityTheftRestorationViewModel()
            self.subscriptionSettingsModel = makeSubscriptionSettingsViewModel()
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
            .background(Color(visualStyle.colorsProvider.settingsBackgroundColor))
        }

        @ViewBuilder
        var contentView: some View {
            VStack(alignment: .leading) {
                switch model.selectedPane {
                case .defaultBrowser:
                    DefaultBrowserView(defaultBrowserModel: DefaultBrowserPreferences.shared,
                                       dockCustomizer: DockCustomizer(),
                                       protectionStatus: model.protectionStatus(for: .defaultBrowser))
                case .privateSearch:
                    PrivateSearchView(model: SearchPreferences.shared)
                case .webTrackingProtection:
                    WebTrackingProtectionView(model: WebTrackingProtectionPreferences.shared)
                case .threatProtection:
                    ThreatProtectionView(model: MaliciousSiteProtectionPreferences.shared)
                case .cookiePopupProtection:
                    CookiePopupProtectionView(model: CookiePopupProtectionPreferences.shared)
                case .emailProtection:
                    EmailProtectionView(emailManager: EmailManager(),
                                        protectionStatus: model.protectionStatus(for: .emailProtection))
                case .general:
                    GeneralView(startupModel: NSApp.delegateTyped.startupPreferences,
                                downloadsModel: DownloadsPreferences.shared,
                                searchModel: SearchPreferences.shared,
                                tabsModel: TabsPreferences.shared,
                                dataClearingModel: NSApp.delegateTyped.dataClearingPreferences,
                                maliciousSiteDetectionModel: MaliciousSiteProtectionPreferences.shared,
                                dockCustomizer: DockCustomizer())
                case .sync:
                    SyncView()
                case .appearance:
                    AppearanceView(model: NSApp.delegateTyped.appearancePreferences, aiChatModel: AIChatPreferences.shared)
                case .dataClearing:
                    DataClearingView(model: NSApp.delegateTyped.dataClearingPreferences,
                                     startupModel: NSApp.delegateTyped.startupPreferences)
                case .privacyPro:
                    SubscriptionUI.PreferencesPurchaseSubscriptionView(model: purchaseSubscriptionModel!)
                case .vpn:
                    VPNView(model: VPNPreferencesModel(), status: model.vpnProtectionStatus())
                case .personalInformationRemoval:
                    SubscriptionUI.PreferencesPersonalInformationRemovalView(model: personalInformationRemovalModel!)
                case .paidAIChat:
                    EmptyView()
                case .identityTheftRestoration:
                    SubscriptionUI.PreferencesIdentityTheftRestorationView(model: identityTheftRestorationModel!)
                case .subscriptionSettings:
                    SubscriptionUI.PreferencesSubscriptionSettingsViewV1(model: subscriptionSettingsModel!)
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

        private func makePurchaseSubscriptionViewModel() -> PreferencesPurchaseSubscriptionModel {
            let userEventHandler: (PreferencesPurchaseSubscriptionModel.UserEvent) -> Void = { event in
                DispatchQueue.main.async {
                    switch event {
                    case .didClickIHaveASubscription:
                        PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseClick)
                    case .openURL(let url):
                        openURL(subscriptionURL: url)
                    }
                }
            }

            let sheetActionHandler = SubscriptionAccessActionHandlers(
                openActivateViaEmailURL: {
                    let url = subscriptionManager.url(for: .activationFlow)
                    Application.appDelegate.windowControllersManager.showTab(with: .subscription(url))
                    PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseEmailStart, frequency: .legacyDailyAndCount)
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

                            PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseStoreStart, frequency: .legacyDailyAndCount)
                        }
                    }
                })

            return PreferencesPurchaseSubscriptionModel(subscriptionManager: subscriptionManager,
                                                        featureFlagger: NSApp.delegateTyped.featureFlagger,
                                                        userEventHandler: userEventHandler,
                                                        sheetActionHandler: sheetActionHandler)
        }

        private func makePersonalInformationRemovalViewModel() -> PreferencesPersonalInformationRemovalModel {
            let userEventHandler: (PreferencesPersonalInformationRemovalModel.UserEvent) -> Void = { event in
                DispatchQueue.main.async {
                    switch event {
                    case .openPIR:
                        PixelKit.fire(PrivacyProPixel.privacyProPersonalInformationRemovalSettings)
                        Application.appDelegate.windowControllersManager.showTab(with: .dataBrokerProtection)
                    case .openURL(let url):
                        openURL(subscriptionURL: url)
                    case .didOpenPIRPreferencePane:
                        PixelKit.fire(PrivacyProPixel.privacyProPersonalInformationRemovalSettingsImpression)
                    }
                }
            }

            return PreferencesPersonalInformationRemovalModel(userEventHandler: userEventHandler,
                                                              statusUpdates: model.personalInformationRemovalUpdates)
        }

        private func makeIdentityTheftRestorationViewModel() -> PreferencesIdentityTheftRestorationModel {
            let userEventHandler: (PreferencesIdentityTheftRestorationModel.UserEvent) -> Void = { event in
                DispatchQueue.main.async {
                    switch event {
                    case .openITR:
                        PixelKit.fire(PrivacyProPixel.privacyProIdentityRestorationSettings)
                        let url = subscriptionManager.url(for: .identityTheftRestoration)
                        Application.appDelegate.windowControllersManager.showTab(with: .identityTheftRestoration(url))
                    case .openURL(let url):
                        openURL(subscriptionURL: url)
                    case .didOpenITRPreferencePane:
                        PixelKit.fire(PrivacyProPixel.privacyProIdentityRestorationSettingsImpression)
                    }
                }
            }

            return PreferencesIdentityTheftRestorationModel(userEventHandler: userEventHandler,
                                                            statusUpdates: model.identityTheftRestorationUpdates)
        }

        private func makeSubscriptionSettingsViewModel() -> PreferencesSubscriptionSettingsModelV1 {
            let userEventHandler: (PreferencesSubscriptionSettingsModelV2.UserEvent) -> Void = { event in
                DispatchQueue.main.async {
                    switch event {
                    case .openFeedback:
                        NotificationCenter.default.post(name: .OpenUnifiedFeedbackForm,
                                                        object: self,
                                                        userInfo: UnifiedFeedbackSource.userInfo(source: .ppro))
                    case .openURL(let url):
                        openURL(subscriptionURL: url)
                    case .openManageSubscriptionsInAppStore:
                        NSWorkspace.shared.open(subscriptionManager.url(for: .manageSubscriptionsInAppStore))
                    case .openCustomerPortalURL(let url):
                        Application.appDelegate.windowControllersManager.showTab(with: .url(url, source: .ui))
                    case .didClickManageEmail:
                        PixelKit.fire(PrivacyProPixel.privacyProSubscriptionManagementEmail, frequency: .legacyDailyAndCount)
                    case .didOpenSubscriptionSettings:
                        PixelKit.fire(PrivacyProPixel.privacyProSubscriptionSettings)
                    case .didClickChangePlanOrBilling:
                        PixelKit.fire(PrivacyProPixel.privacyProSubscriptionManagementPlanBilling)
                    case .didClickRemoveSubscription:
                        PixelKit.fire(PrivacyProPixel.privacyProSubscriptionManagementRemoval)
                    }
                }
            }

            return PreferencesSubscriptionSettingsModelV1(userEventHandler: userEventHandler,
                                                          subscriptionManager: subscriptionManager,
                                                          subscriptionStateUpdate: model.$currentSubscriptionState.eraseToAnyPublisher())
        }

        private func openURL(subscriptionURL: SubscriptionURL) {
            DispatchQueue.main.async {
                let url = subscriptionManager.url(for: subscriptionURL)
                    .appendingParameter(name: AttributionParameter.origin,
                                        value: SubscriptionFunnelOrigin.appSettings.rawValue)
                Application.appDelegate.windowControllersManager.showTab(with: .subscription(url))
            }
        }
    }

    struct RootViewV2: View {

        @ObservedObject var model: PreferencesSidebarModel

        var purchaseSubscriptionModel: PreferencesPurchaseSubscriptionModel?
        var personalInformationRemovalModel: PreferencesPersonalInformationRemovalModel?
        var paidAIChatModel: PreferencesPaidAIChatModel?
        var identityTheftRestorationModel: PreferencesIdentityTheftRestorationModel?
        var subscriptionSettingsModel: PreferencesSubscriptionSettingsModelV2?
        let subscriptionManager: SubscriptionManagerV2
        let subscriptionUIHandler: SubscriptionUIHandling
        let visualStyle: VisualStyleProviding
        let featureFlagger: FeatureFlagger
        let showTab: @MainActor (Tab.TabContent) -> Void
        let aiChatURLSettings: AIChatRemoteSettingsProvider

        init(
            model: PreferencesSidebarModel,
            subscriptionManager: SubscriptionManagerV2,
            subscriptionUIHandler: SubscriptionUIHandling,
            featureFlagger: FeatureFlagger,
            aiChatURLSettings: AIChatRemoteSettingsProvider,
            showTab: @escaping @MainActor (Tab.TabContent) -> Void = { Application.appDelegate.windowControllersManager.showTab(with: $0) },
            visualStyle: VisualStyleProviding = NSApp.delegateTyped.visualStyle
        ) {
            self.model = model
            self.subscriptionManager = subscriptionManager
            self.subscriptionUIHandler = subscriptionUIHandler
            self.showTab = showTab
            self.featureFlagger = featureFlagger
            self.visualStyle = visualStyle
            self.aiChatURLSettings = aiChatURLSettings
            self.purchaseSubscriptionModel = makePurchaseSubscriptionViewModel()
            self.personalInformationRemovalModel = makePersonalInformationRemovalViewModel()
            self.paidAIChatModel = makePaidAIChatViewModel()
            self.identityTheftRestorationModel = makeIdentityTheftRestorationViewModel()
            self.subscriptionSettingsModel = makeSubscriptionSettingsViewModel()
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
            .background(Color(visualStyle.colorsProvider.settingsBackgroundColor))
        }

        @ViewBuilder
        var contentView: some View {
            VStack(alignment: .leading) {
                switch model.selectedPane {
                case .defaultBrowser:
                    DefaultBrowserView(defaultBrowserModel: DefaultBrowserPreferences.shared,
                                       dockCustomizer: DockCustomizer(),
                                       protectionStatus: model.protectionStatus(for: .defaultBrowser))
                case .privateSearch:
                    PrivateSearchView(model: SearchPreferences.shared)
                case .webTrackingProtection:
                    WebTrackingProtectionView(model: WebTrackingProtectionPreferences.shared)
                case .threatProtection:
                    ThreatProtectionView(model: MaliciousSiteProtectionPreferences.shared)
                case .cookiePopupProtection:
                    CookiePopupProtectionView(model: CookiePopupProtectionPreferences.shared)
                case .emailProtection:
                    EmailProtectionView(emailManager: EmailManager(),
                                        protectionStatus: model.protectionStatus(for: .emailProtection))
                case .general:
                    GeneralView(startupModel: NSApp.delegateTyped.startupPreferences,
                                downloadsModel: DownloadsPreferences.shared,
                                searchModel: SearchPreferences.shared,
                                tabsModel: TabsPreferences.shared,
                                dataClearingModel: NSApp.delegateTyped.dataClearingPreferences,
                                maliciousSiteDetectionModel: MaliciousSiteProtectionPreferences.shared,
                                dockCustomizer: DockCustomizer())
                case .sync:
                    SyncView()
                case .appearance:
                    AppearanceView(model: NSApp.delegateTyped.appearancePreferences, aiChatModel: AIChatPreferences.shared)
                case .dataClearing:
                    DataClearingView(model: NSApp.delegateTyped.dataClearingPreferences, startupModel: NSApp.delegateTyped.startupPreferences)
                case .privacyPro:
                    SubscriptionUI.PreferencesPurchaseSubscriptionView(model: purchaseSubscriptionModel!)
                case .vpn:
                    VPNView(model: VPNPreferencesModel(), status: model.vpnProtectionStatus())
                case .personalInformationRemoval:
                    SubscriptionUI.PreferencesPersonalInformationRemovalView(model: personalInformationRemovalModel!)
                case .paidAIChat:
                    SubscriptionUI.PreferencesPaidAIChatView(model: paidAIChatModel!)
                case .identityTheftRestoration:
                    SubscriptionUI.PreferencesIdentityTheftRestorationView(model: identityTheftRestorationModel!)
                case .subscriptionSettings:
                    SubscriptionUI.PreferencesSubscriptionSettingsViewV2(model: subscriptionSettingsModel!, isSubscriptionRebrandingOn: { featureFlagger.isFeatureOn(.subscriptionRebranding) }, isPaidAIChatOn: { featureFlagger.isFeatureOn(.paidAIChat) })
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

        private func makePurchaseSubscriptionViewModel() -> PreferencesPurchaseSubscriptionModel {
            let userEventHandler: (PreferencesPurchaseSubscriptionModel.UserEvent) -> Void = { event in
                DispatchQueue.main.async {
                    switch event {
                    case .didClickIHaveASubscription:
                        PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseClick)
                    case .openURL(let url):
                        openURL(subscriptionURL: url)
                    }
                }
            }

            let sheetActionHandler = SubscriptionAccessActionHandlers(
                openActivateViaEmailURL: {
                    let url = subscriptionManager.url(for: .activationFlow)
                    showTab(.subscription(url))
                    PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseEmailStart, frequency: .legacyDailyAndCount)
                }, restorePurchases: {
                    if #available(macOS 12.0, *) {
                        Task {
                            let appStoreRestoreFlow = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManager,
                                                                                   storePurchaseManager: subscriptionManager.storePurchaseManager())
                            let subscriptionAppStoreRestorer = DefaultSubscriptionAppStoreRestorerV2(subscriptionManager: subscriptionManager,
                                                                                                     appStoreRestoreFlow: appStoreRestoreFlow,
                                                                                                     uiHandler: subscriptionUIHandler)
                            await subscriptionAppStoreRestorer.restoreAppStoreSubscription()

                            PixelKit.fire(PrivacyProPixel.privacyProRestorePurchaseStoreStart, frequency: .legacyDailyAndCount)
                        }
                    }
                })

            return PreferencesPurchaseSubscriptionModel(subscriptionManager: subscriptionManager,
                                                        featureFlagger: featureFlagger,
                                                        userEventHandler: userEventHandler,
                                                        sheetActionHandler: sheetActionHandler)
        }

        private func makePersonalInformationRemovalViewModel() -> PreferencesPersonalInformationRemovalModel {
            let userEventHandler: (PreferencesPersonalInformationRemovalModel.UserEvent) -> Void = { event in
                DispatchQueue.main.async {
                    switch event {
                    case .openPIR:
                        PixelKit.fire(PrivacyProPixel.privacyProPersonalInformationRemovalSettings)
                        showTab(.dataBrokerProtection)
                    case .openURL(let url):
                        openURL(subscriptionURL: url)
                    case .didOpenPIRPreferencePane:
                        PixelKit.fire(PrivacyProPixel.privacyProPersonalInformationRemovalSettingsImpression)
                    }
                }
            }

            return PreferencesPersonalInformationRemovalModel(userEventHandler: userEventHandler,
                                                              statusUpdates: model.personalInformationRemovalUpdates)
        }

        private func makePaidAIChatViewModel() -> PreferencesPaidAIChatModel {
             let userEventHandler: (PreferencesPaidAIChatModel.UserEvent) -> Void = { event in
                 DispatchQueue.main.async {
                     switch event {
                     case .openAIC:
                         PixelKit.fire(PrivacyProPixel.privacyProPaidAIChatSettings)
                         let aiChatURL = aiChatURLSettings.aiChatURL
                         showTab(.url(aiChatURL, source: .ui))
                     case .openURL(let url):
                         openURL(subscriptionURL: url)
                     case .didOpenAICPreferencePane:
                         PixelKit.fire(PrivacyProPixel.privacyProPaidAIChatSettingsImpression)
                     }
                 }
             }

             return PreferencesPaidAIChatModel(userEventHandler: userEventHandler,
                                                             statusUpdates: model.paidAIChatUpdates)
         }

        private func makeIdentityTheftRestorationViewModel() -> PreferencesIdentityTheftRestorationModel {
            let userEventHandler: (PreferencesIdentityTheftRestorationModel.UserEvent) -> Void = { event in
                DispatchQueue.main.async {
                    switch event {
                    case .openITR:
                        PixelKit.fire(PrivacyProPixel.privacyProIdentityRestorationSettings)
                        let url = subscriptionManager.url(for: .identityTheftRestoration)
                        showTab(.identityTheftRestoration(url))
                    case .openURL(let url):
                        openURL(subscriptionURL: url)
                    case .didOpenITRPreferencePane:
                        PixelKit.fire(PrivacyProPixel.privacyProIdentityRestorationSettingsImpression)
                    }
                }
            }

            return PreferencesIdentityTheftRestorationModel(userEventHandler: userEventHandler,
                                                            statusUpdates: model.identityTheftRestorationUpdates)
        }

        private func makeSubscriptionSettingsViewModel() -> PreferencesSubscriptionSettingsModelV2 {
            let userEventHandler: (PreferencesSubscriptionSettingsModelV2.UserEvent) -> Void = { event in
                DispatchQueue.main.async {
                    switch event {
                    case .openFeedback:
                        NotificationCenter.default.post(name: .OpenUnifiedFeedbackForm,
                                                        object: self,
                                                        userInfo: UnifiedFeedbackSource.userInfo(source: .ppro))
                    case .openURL(let url):
                        openURL(subscriptionURL: url)
                    case .openManageSubscriptionsInAppStore:
                        NSWorkspace.shared.open(subscriptionManager.url(for: .manageSubscriptionsInAppStore))
                    case .openCustomerPortalURL(let url):
                        showTab(.url(url, source: .ui))
                    case .didClickManageEmail:
                        PixelKit.fire(PrivacyProPixel.privacyProSubscriptionManagementEmail, frequency: .legacyDailyAndCount)
                    case .didOpenSubscriptionSettings:
                        PixelKit.fire(PrivacyProPixel.privacyProSubscriptionSettings)
                    case .didClickChangePlanOrBilling:
                        PixelKit.fire(PrivacyProPixel.privacyProSubscriptionManagementPlanBilling)
                    case .didClickRemoveSubscription:
                        PixelKit.fire(PrivacyProPixel.privacyProSubscriptionManagementRemoval)
                    }
                }
            }

            return PreferencesSubscriptionSettingsModelV2(userEventHandler: userEventHandler,
                                                          subscriptionManager: subscriptionManager,
                                                          subscriptionStateUpdate: model.$currentSubscriptionState.eraseToAnyPublisher(),
                                                          keyValueStore: NSApp.delegateTyped.keyValueStore,
                                                          isRebrandingOn: { featureFlagger.isFeatureOn(.subscriptionRebranding) })
        }

        private func openURL(subscriptionURL: SubscriptionURL) {
            DispatchQueue.main.async {
                let url = subscriptionManager.url(for: subscriptionURL)
                    .appendingParameter(name: AttributionParameter.origin,
                                        value: SubscriptionFunnelOrigin.appSettings.rawValue)
                showTab(.subscription(url))
            }
        }
    }
}
