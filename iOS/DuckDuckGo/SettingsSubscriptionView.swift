//
//  SettingsSubscriptionView.swift
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

import Core
import Subscription
import DataBrokerProtection_iOS
import SwiftUI
import UIKit
import DesignResourcesKit
import DesignResourcesKitIcons

struct SettingsSubscriptionView: View {

    enum ViewConstants {
        static let purchaseDescriptionPadding = 5.0
        static let topCellPadding = 3.0
        static let noEntitlementsIconWidth = 20.0
        static let navigationDelay = 0.3
        static let privacyPolicyURL = URL(string: "https://duckduckgo.com/pro/privacy-terms")!
    }

    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var subscriptionNavigationCoordinator: SubscriptionNavigationCoordinator
    @State var isShowingDBP = false
    @State var isShowingITP = false
    @State var isShowingVPN = false
    @State var isShowingPaidAIChat = false
    @State var isShowingRestoreFlow = false
    @State var isShowingGoogleView = false
    @State var isShowingStripeView = false
    @State var isShowingPrivacyPro = false

    var subscriptionRestoreView: some View {
        SubscriptionContainerViewFactory.makeRestoreFlow(navigationCoordinator: subscriptionNavigationCoordinator,
                                                         subscriptionManager: AppDependencyProvider.shared.subscriptionManager!,
                                                         subscriptionFeatureAvailability: settingsViewModel.subscriptionFeatureAvailability,
                                                         internalUserDecider: AppDependencyProvider.shared.internalUserDecider)
    }

    var subscriptionRestoreViewV2: some View {
        SubscriptionContainerViewFactory.makeRestoreFlowV2(navigationCoordinator: subscriptionNavigationCoordinator,
                                                           subscriptionManager: AppDependencyProvider.shared.subscriptionManagerV2!,
                                                           subscriptionFeatureAvailability: settingsViewModel.subscriptionFeatureAvailability,
                                                           internalUserDecider: AppDependencyProvider.shared.internalUserDecider)
    }

    private var manageSubscriptionView: some View {
        SettingsCellView(
            label: UserText.settingsPProManageSubscription,
            image: Image(uiImage: DesignSystemImages.Color.Size24.privacyPro)
        )
    }

    var currentStorefrontRegion: SubscriptionRegion {
        if !settingsViewModel.isAuthV2Enabled {
            return AppDependencyProvider.shared.subscriptionManager!.storePurchaseManager().currentStorefrontRegion
        } else {
            return AppDependencyProvider.shared.subscriptionManagerV2!.storePurchaseManager().currentStorefrontRegion
        }
    }

    @ViewBuilder
    private var purchaseSubscriptionView: some View {
        Group {
            let isPaidAIChatEnabled = settingsViewModel.isPaidAIChatEnabled
            let titleText: String = UserText.settingsSubscription(isPaidAIChatEnabled: isPaidAIChatEnabled)
            let subtitleText: String = {
                switch currentStorefrontRegion {
                case .usa:
                    return UserText.settingsSubscriptionDescription(isPaidAIChatEnabled: isPaidAIChatEnabled, isUS: true)
                case .restOfWorld:
                    return UserText.settingsSubscriptionDescription(isPaidAIChatEnabled: isPaidAIChatEnabled, isUS: false)
                }
            }()

            SettingsCellView(label: titleText,
                             subtitle: subtitleText,
                             image: Image(uiImage: DesignSystemImages.Color.Size24.privacyPro))
            .disabled(true)

            // Get privacy pro
            let getText = settingsViewModel.state.subscription.isEligibleForTrialOffer ? UserText.trySubscriptionButton(isSubscriptionRebrandingOn: settingsViewModel.isSubscriptionRebrandingEnabled) : UserText.getSubscriptionButton(isSubscriptionRebrandingOn: settingsViewModel.isSubscriptionRebrandingEnabled)
            SettingsCustomCell(content: {
                Text(getText)
                    .daxBodyRegular()
                    .foregroundColor(Color.init(designSystemColor: .accent))
                    .padding(.leading, 32.0)
            }, action: {
                subscriptionNavigationCoordinator.shouldPushSubscriptionWebView = true
            }, isButton: true)

            // Restore subscription
            if !settingsViewModel.isAuthV2Enabled {
                let restoreView = subscriptionRestoreView
                    .navigationViewStyle(.stack)
                    .onFirstAppear {
                        Pixel.fire(pixel: .privacyProRestorePurchaseClick)
                    }
                NavigationLink(destination: restoreView,
                               isActive: $isShowingRestoreFlow) {
                    SettingsCellView(label: UserText.settingsPProIHaveASubscription).padding(.leading, 32.0)
                }
            } else {
                let restoreView = subscriptionRestoreViewV2
                    .navigationViewStyle(.stack)
                    .onFirstAppear {
                        Pixel.fire(pixel: .privacyProRestorePurchaseClick)
                    }
                NavigationLink(destination: restoreView,
                               isActive: $isShowingRestoreFlow) {
                    SettingsCellView(label: UserText.settingsPProIHaveASubscription).padding(.leading, 32.0)
                }
            }
        }
    }

    @ViewBuilder
    private var disabledFeaturesView: some View {
        let subscriptionFeatures = settingsViewModel.state.subscription.subscriptionFeatures

        if subscriptionFeatures.contains(.networkProtection) {
            SettingsCellView(label: UserText.settingsPProVPNTitle,
                             image: Image(uiImage: DesignSystemImages.Color.Size24.vpn),
                             statusIndicator: StatusIndicatorView(status: .off),
                             isGreyedOut: true
            )
        }

        if subscriptionFeatures.contains(.dataBrokerProtection) {
            SettingsCellView(
                label: UserText.settingsPProDBPTitle,
                image: Image(uiImage: DesignSystemImages.Color.Size24.databroker),
                statusIndicator: StatusIndicatorView(status: .off),
                isGreyedOut: true
            )
        }

        if subscriptionFeatures.contains(.paidAIChat) && settingsViewModel.isPaidAIChatEnabled {
            SettingsCellView(
                label: UserText.settingsSubscriptionAiChatTitle,
                image: Image(uiImage: DesignSystemImages.Color.Size24.aiChat),
                statusIndicator: StatusIndicatorView(status: .off),
                isGreyedOut: true,
                isNew: true
            )
        }

        if subscriptionFeatures.contains(.identityTheftRestoration) || subscriptionFeatures.contains(.identityTheftRestorationGlobal) {
            SettingsCellView(
                label: UserText.settingsPProITRTitle,
                image: Image(uiImage: DesignSystemImages.Color.Size24.identityTheftRestoration),
                statusIndicator: StatusIndicatorView(status: .off),
                isGreyedOut: true
            )
        }
    }

    @ViewBuilder
    private var subscriptionExpiredView: some View {
        disabledFeaturesView

        // Renew Subscription (Expired)
        if !settingsViewModel.isAuthV2Enabled {
            let settingsView = SubscriptionSettingsView(configuration: SubscriptionSettingsViewConfiguration.expired,
                                                        settingsViewModel: settingsViewModel,
                                                        viewPlans: {
                subscriptionNavigationCoordinator.shouldPushSubscriptionWebView = true
            })
                .environmentObject(subscriptionNavigationCoordinator)
            NavigationLink(destination: settingsView) {
                SettingsCellView(
                    label: UserText.settingsPProManageSubscription,
                    subtitle: UserText.settingsPProSubscriptionExpiredTitle(isRebrandingOn: settingsViewModel.isSubscriptionRebrandingEnabled),
                    image: Image(uiImage: DesignSystemImages.Color.Size24.privacyPro),
                    accessory: .image(Image(uiImage: DesignSystemImages.Color.Size16.exclamation))
                )
            }
        } else {
            let settingsView = SubscriptionSettingsViewV2(configuration: SubscriptionSettingsViewConfiguration.expired,
                                                          settingsViewModel: settingsViewModel,
                                                          viewPlans: {
                subscriptionNavigationCoordinator.shouldPushSubscriptionWebView = true
            })
                .environmentObject(subscriptionNavigationCoordinator)
            NavigationLink(destination: settingsView) {
                SettingsCellView(
                    label: UserText.settingsPProManageSubscription,
                    subtitle: UserText.settingsPProSubscriptionExpiredTitle(isRebrandingOn: settingsViewModel.isSubscriptionRebrandingEnabled),
                    image: Image(uiImage: DesignSystemImages.Color.Size24.privacyPro),
                    accessory: .image(Image(uiImage: DesignSystemImages.Color.Size16.exclamation))
                )
            }
        }
    }

    @ViewBuilder
    private var missingSubscriptionOrEntitlementsView: some View {
        disabledFeaturesView

        // Renew Subscription (Expired)
        if !settingsViewModel.isAuthV2Enabled {
            let settingsView = SubscriptionSettingsView(configuration: SubscriptionSettingsViewConfiguration.activating,
                                                        settingsViewModel: settingsViewModel,
                                                        viewPlans: {
                subscriptionNavigationCoordinator.shouldPushSubscriptionWebView = true
            })
                .environmentObject(subscriptionNavigationCoordinator)
            NavigationLink(destination: settingsView) {
                SettingsCellView(
                    label: UserText.settingsPProManageSubscription,
                    subtitle: UserText.settingsPProActivating,
                    image: Image(uiImage: DesignSystemImages.Color.Size24.privacyPro)
                )
            }
        } else {
            let settingsView = SubscriptionSettingsViewV2(configuration: SubscriptionSettingsViewConfiguration.activating,
                                                          settingsViewModel: settingsViewModel,
                                                          viewPlans: {
                subscriptionNavigationCoordinator.shouldPushSubscriptionWebView = true
            })
                .environmentObject(subscriptionNavigationCoordinator)
            NavigationLink(destination: settingsView) {
                SettingsCellView(
                    label: UserText.settingsPProManageSubscription,
                    subtitle: UserText.settingsPProActivating,
                    image: Image(uiImage: DesignSystemImages.Color.Size24.privacyPro)
                )
            }
        }
    }

    @ViewBuilder
    private var subscriptionDetailsView: some View {
        let subscriptionFeatures = settingsViewModel.state.subscription.subscriptionFeatures
        let userEntitlements = settingsViewModel.state.subscription.entitlements

        if subscriptionFeatures.contains(.networkProtection) {
            let hasVPNEntitlement = userEntitlements.contains(.networkProtection)
            let isVPNConnected = settingsViewModel.state.networkProtectionConnected

            NavigationLink(destination: LazyView(NetworkProtectionRootView()), isActive: $isShowingVPN) {
                SettingsCellView(
                    label: UserText.settingsPProVPNTitle,
                    image: Image(uiImage: DesignSystemImages.Color.Size24.vpn),
                    statusIndicator: StatusIndicatorView(status: isVPNConnected ? .on : .off),
                    isGreyedOut: !hasVPNEntitlement
                )
            }
            .disabled(!hasVPNEntitlement)
        }

        if subscriptionFeatures.contains(.dataBrokerProtection) {
            let hasDBPEntitlement = userEntitlements.contains(.dataBrokerProtection)
            let hasValidStoredProfile = settingsViewModel.dataBrokerProtectionIOSManager
                .flatMap { try? $0.meetsProfileRunPrequisite } ?? false
            var statusIndicator: StatusIndicator = hasDBPEntitlement && hasValidStoredProfile ? .on : .off

            let destination: LazyView<AnyView> = {
                if settingsViewModel.isPIREnabled,
                   let dbpManager = settingsViewModel.dataBrokerProtectionIOSManager {
                    return LazyView(AnyView(DataBrokerProtectionViewControllerRepresentation(dbpViewControllerProvider: dbpManager)))
                } else {
                    statusIndicator = .on
                    return LazyView(AnyView(SubscriptionPIRMoveToDesktopView()))
                }
            }()

            NavigationLink(destination: destination, isActive: $isShowingDBP) {
                SettingsCellView(
                    label: UserText.settingsPProDBPTitle,
                    image: Image(uiImage: DesignSystemImages.Color.Size24.identity),
                    statusIndicator: StatusIndicatorView(status: statusIndicator),
                    isGreyedOut: !hasDBPEntitlement
                )
            }
            .disabled(!hasDBPEntitlement)
        }

        if subscriptionFeatures.contains(.paidAIChat) && settingsViewModel.isPaidAIChatEnabled {
            let hasAIChatEntitlement = userEntitlements.contains(.paidAIChat)

            NavigationLink(destination: LazyView(SubscriptionAIChatView(viewModel: settingsViewModel)), isActive: $isShowingPaidAIChat) {
                SettingsCellView(
                    label: UserText.settingsSubscriptionAiChatTitle,
                    image: Image(uiImage: DesignSystemImages.Color.Size24.aiChat),
                    statusIndicator: StatusIndicatorView(status: hasAIChatEntitlement ? .on : .off),
                    isGreyedOut: !hasAIChatEntitlement,
                    isNew: true
                )
            }
            .disabled(!hasAIChatEntitlement)
        }

        if subscriptionFeatures.contains(.identityTheftRestoration) || subscriptionFeatures.contains(.identityTheftRestorationGlobal) {
            let hasITREntitlement = userEntitlements.contains(.identityTheftRestoration) || userEntitlements.contains(.identityTheftRestorationGlobal)

            NavigationLink(destination: LazyView(SubscriptionITPView()), isActive: $isShowingITP) {
                SettingsCellView(
                    label: UserText.settingsPProITRTitle,
                    image: Image(uiImage: DesignSystemImages.Color.Size24.identityTheftRestoration),
                    statusIndicator: StatusIndicatorView(status: hasITREntitlement ? .on : .off),
                    isGreyedOut: !hasITREntitlement
                )
            }
            .disabled(!hasITREntitlement)
        }

        let isActiveTrialOffer = settingsViewModel.state.subscription.isActiveTrialOffer
        let configuration: SubscriptionSettingsViewConfiguration = isActiveTrialOffer ? .trial : .subscribed

        if !settingsViewModel.isAuthV2Enabled {
            NavigationLink(destination: LazyView(SubscriptionSettingsView(configuration: configuration, settingsViewModel: settingsViewModel))
                .environmentObject(subscriptionNavigationCoordinator)
            ) {
                SettingsCustomCell(content: { manageSubscriptionView })
            }
        } else {
            NavigationLink(destination: LazyView(SubscriptionSettingsViewV2(configuration: configuration, settingsViewModel: settingsViewModel))
                .environmentObject(subscriptionNavigationCoordinator)
            ) {
                SettingsCustomCell(content: { manageSubscriptionView })
            }
        }
    }
        
    var body: some View {
        Group {
            if isShowingPrivacyPro {

                let isSignedIn = settingsViewModel.state.subscription.isSignedIn
                let hasSubscription = settingsViewModel.state.subscription.hasSubscription
                let hasActiveSubscription = settingsViewModel.state.subscription.hasActiveSubscription
                let hasAnyEntitlements = !settingsViewModel.state.subscription.entitlements.isEmpty

                let footerLink = Link(UserText.settingsPProSectionFooter,
                                      destination: ViewConstants.privacyPolicyURL)
                    .daxFootnoteRegular().accentColor(Color.init(designSystemColor: .accent))

                Section(header: Text(UserText.settingsSubscriptionSection(isSubscriptionRebrandingOn: settingsViewModel.isSubscriptionRebrandingEnabled)),
                        footer: !isSignedIn ? footerLink : nil
                ) {

                    switch (isSignedIn, hasSubscription, hasActiveSubscription, hasAnyEntitlements) {

                    // Signed out
                    case (false, _, _, _):
                        purchaseSubscriptionView

                    // Signed In, Subscription Missing
                    case (true, false, _, _):
                        missingSubscriptionOrEntitlementsView

                    // Signed In, Subscription Present & Not Active
                    case (true, true, false, _):
                        subscriptionExpiredView

                    // Signed in, Subscription Present & Active, Missing Entitlements
                    case (true, true, true, false):
                        missingSubscriptionOrEntitlementsView

                    // Signed in, Subscription Present & Active, Valid entitlements
                    case (true, true, true, true):
                        subscriptionDetailsView
                    }
                }
                .onReceive(subscriptionNavigationCoordinator.$shouldPopToAppSettings) { shouldDismiss in
                    if shouldDismiss {
                        isShowingRestoreFlow = false
                        subscriptionNavigationCoordinator.shouldPushSubscriptionWebView = false
                    }
                }
            }
        }
        .onReceive(settingsViewModel.$state) { state in
            isShowingPrivacyPro = (state.subscription.isSignedIn || state.subscription.canPurchase)
        }
    }
}
