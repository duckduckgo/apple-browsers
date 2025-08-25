//
//  SubscriptionContainerViewFactory.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import SwiftUI
import Subscription
import Common
import BrowserServicesKit
import PixelKit

enum SubscriptionContainerViewFactory {

    static func makeSubscribeFlow(redirectURLComponents: URLComponents?,
                                  navigationCoordinator: SubscriptionNavigationCoordinator,
                                  subscriptionManager: SubscriptionManager,
                                  subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                  privacyProDataReporter: PrivacyProDataReporting?,
                                  tld: TLD,
                                  internalUserDecider: InternalUserDecider) -> some View {
        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: subscriptionManager.accountManager,
                                                             storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                             subscriptionEndpointService: subscriptionManager.subscriptionEndpointService,
                                                             authEndpointService: subscriptionManager.authEndpointService)
        let appStorePurchaseFlow = DefaultAppStorePurchaseFlow(subscriptionEndpointService: subscriptionManager.subscriptionEndpointService,
                                                               storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                               accountManager: subscriptionManager.accountManager,
                                                               appStoreRestoreFlow: appStoreRestoreFlow,
                                                               authEndpointService: subscriptionManager.authEndpointService)
        let appStoreAccountManagementFlow = DefaultAppStoreAccountManagementFlow(authEndpointService: subscriptionManager.authEndpointService,
                                                                                 storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                                 accountManager: subscriptionManager.accountManager)

        let redirectPurchaseURL: URL? = {
            guard let redirectURLComponents else { return nil }
            return subscriptionManager.urlForPurchaseFromRedirect(redirectURLComponents: redirectURLComponents, tld: tld)
        }()

        let origin = redirectURLComponents?.url?.getParameter(named: AttributionParameter.origin)

        let viewModel = SubscriptionContainerViewModel(
            subscriptionManager: subscriptionManager,
            redirectPurchaseURL: redirectPurchaseURL,
            isInternalUser: internalUserDecider.isInternalUser,
            userScript: SubscriptionPagesUserScript(),
            subFeature: DefaultSubscriptionPagesUseSubscriptionFeature(subscriptionManager: subscriptionManager,
                                                                       subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                                       subscriptionAttributionOrigin: origin,
                                                                       appStorePurchaseFlow: appStorePurchaseFlow,
                                                                       appStoreRestoreFlow: appStoreRestoreFlow,
                                                                       appStoreAccountManagementFlow: appStoreAccountManagementFlow,
                                                                       privacyProDataReporter: privacyProDataReporter)
        )
        viewModel.email.setEmailFlowMode(.restoreFlow)
        return SubscriptionContainerView(currentView: .subscribe, viewModel: viewModel)
            .environmentObject(navigationCoordinator)
    }

    static func makeRestoreFlow(navigationCoordinator: SubscriptionNavigationCoordinator,
                                subscriptionManager: SubscriptionManager,
                                subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                internalUserDecider: InternalUserDecider) -> some View {
        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: subscriptionManager.accountManager,
                                                             storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                             subscriptionEndpointService: subscriptionManager.subscriptionEndpointService,
                                                             authEndpointService: subscriptionManager.authEndpointService)
        let appStorePurchaseFlow = DefaultAppStorePurchaseFlow(subscriptionEndpointService: subscriptionManager.subscriptionEndpointService,
                                                               storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                               accountManager: subscriptionManager.accountManager,
                                                               appStoreRestoreFlow: appStoreRestoreFlow,
                                                               authEndpointService: subscriptionManager.authEndpointService)
        let appStoreAccountManagementFlow = DefaultAppStoreAccountManagementFlow(authEndpointService: subscriptionManager.authEndpointService,
                                                                                 storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                                 accountManager: subscriptionManager.accountManager)

        let viewModel = SubscriptionContainerViewModel(
            subscriptionManager: subscriptionManager,
            isInternalUser: internalUserDecider.isInternalUser,
            userScript: SubscriptionPagesUserScript(),
            subFeature: DefaultSubscriptionPagesUseSubscriptionFeature(subscriptionManager: subscriptionManager,
                                                                       subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                                       subscriptionAttributionOrigin: nil,
                                                                       appStorePurchaseFlow: appStorePurchaseFlow,
                                                                       appStoreRestoreFlow: appStoreRestoreFlow,
                                                                       appStoreAccountManagementFlow: appStoreAccountManagementFlow)
        )
        viewModel.email.setEmailFlowMode(.restoreFlow)
        return SubscriptionContainerView(currentView: .restore, viewModel: viewModel)
            .environmentObject(navigationCoordinator)
    }

    static func makeEmailFlow(navigationCoordinator: SubscriptionNavigationCoordinator,
                              subscriptionManager: SubscriptionManager,
                              subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                              internalUserDecider: InternalUserDecider,
                              emailFlow: SubscriptionEmailViewModel.EmailViewFlow = .activationFlow,
                              onDisappear: @escaping () -> Void) -> some View {
        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: subscriptionManager.accountManager,
                                                             storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                             subscriptionEndpointService: subscriptionManager.subscriptionEndpointService,
                                                             authEndpointService: subscriptionManager.authEndpointService)
        let appStorePurchaseFlow = DefaultAppStorePurchaseFlow(subscriptionEndpointService: subscriptionManager.subscriptionEndpointService,
                                                               storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                               accountManager: subscriptionManager.accountManager,
                                                               appStoreRestoreFlow: appStoreRestoreFlow,
                                                               authEndpointService: subscriptionManager.authEndpointService)
        let appStoreAccountManagementFlow = DefaultAppStoreAccountManagementFlow(authEndpointService: subscriptionManager.authEndpointService,
                                                                                 storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                                 accountManager: subscriptionManager.accountManager)
        let viewModel = SubscriptionContainerViewModel(
            subscriptionManager: subscriptionManager,
            isInternalUser: internalUserDecider.isInternalUser,
            userScript: SubscriptionPagesUserScript(),
            subFeature: DefaultSubscriptionPagesUseSubscriptionFeature(subscriptionManager: subscriptionManager,
                                                                       subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                                       subscriptionAttributionOrigin: nil,
                                                                       appStorePurchaseFlow: appStorePurchaseFlow,
                                                                       appStoreRestoreFlow: appStoreRestoreFlow,
                                                                       appStoreAccountManagementFlow: appStoreAccountManagementFlow)
        )

        viewModel.email.setEmailFlowMode(emailFlow)

        return SubscriptionContainerView(currentView: .email, viewModel: viewModel)
            .environmentObject(navigationCoordinator)
            .onDisappear(perform: { onDisappear() })
    }

    // MARK: - V2

    static func makeSubscribeFlowV2(redirectURLComponents: URLComponents?,
                                    navigationCoordinator: SubscriptionNavigationCoordinator,
                                    subscriptionManager: SubscriptionManagerV2,
                                    subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                    privacyProDataReporter: PrivacyProDataReporting?,
                                    tld: TLD,
                                    internalUserDecider: InternalUserDecider,
                                    widePixelManager: WidePixelManaging = WidePixel()) -> some View {
        let redirectPurchaseURL: URL? = {
            guard let redirectURLComponents else { return nil }
            return subscriptionManager.urlForPurchaseFromRedirect(redirectURLComponents: redirectURLComponents, tld: tld)
        }()

        let origin = redirectURLComponents?.url?.getParameter(named: AttributionParameter.origin)

        let appStoreRestoreFlow = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManager,
                                                               storePurchaseManager: subscriptionManager.storePurchaseManager())

        let eventMapping: EventMapping<AppStorePurchaseFlowV2Event>
        if subscriptionFeatureAvailability.isSubscriptionPurchaseWidePixelMeasurementEnabled {
            eventMapping = SubscriptionAppStoreWidePixelEventMapping(widePixelManager: widePixelManager,
                                                                     origin: origin,
                                                                     internalUserDecider: internalUserDecider)
        } else {
            // Use a no-op event mapper if the feature flag is disabled
            eventMapping = EventMapping<AppStorePurchaseFlowV2Event> { _, _, _, _ in }
        }

        let appStorePurchaseFlow = DefaultAppStorePurchaseFlowV2(subscriptionManager: subscriptionManager,
                                                                 storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                 appStoreRestoreFlow: appStoreRestoreFlow,
                                                                 eventMapping: eventMapping)

        let viewModel = SubscriptionContainerViewModel(
            subscriptionManager: subscriptionManager,
            redirectPurchaseURL: redirectPurchaseURL,
            isInternalUser: internalUserDecider.isInternalUser,
            userScript: SubscriptionPagesUserScript(),
            subFeature: DefaultSubscriptionPagesUseSubscriptionFeatureV2(subscriptionManager: subscriptionManager,
                                                                         subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                                         subscriptionAttributionOrigin: origin,
                                                                         appStorePurchaseFlow: appStorePurchaseFlow,
                                                                         appStoreRestoreFlow: appStoreRestoreFlow,
                                                                         privacyProDataReporter: privacyProDataReporter)
        )
        viewModel.email.setEmailFlowMode(.restoreFlow)
        return SubscriptionContainerView(currentView: .subscribe, viewModel: viewModel)
            .environmentObject(navigationCoordinator)
    }


    static func makeRestoreFlowV2(navigationCoordinator: SubscriptionNavigationCoordinator,
                                  subscriptionManager: SubscriptionManagerV2,
                                  subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                  internalUserDecider: InternalUserDecider) -> some View {
        let appStoreRestoreFlow = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManager,
                                                               storePurchaseManager: subscriptionManager.storePurchaseManager())
        let eventMapping = EventMapping<AppStorePurchaseFlowV2Event> { _, _, _, _ in }

        let appStorePurchaseFlow = DefaultAppStorePurchaseFlowV2(subscriptionManager: subscriptionManager,
                                                                 storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                 appStoreRestoreFlow: appStoreRestoreFlow,
                                                                 eventMapping: eventMapping)
        let subscriptionPagesUseSubscriptionFeature = DefaultSubscriptionPagesUseSubscriptionFeatureV2(subscriptionManager: subscriptionManager,
                                                                                                       subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                                                                       subscriptionAttributionOrigin: nil,
                                                                                                       appStorePurchaseFlow: appStorePurchaseFlow,
                                                                                                       appStoreRestoreFlow: appStoreRestoreFlow)
        let viewModel = SubscriptionContainerViewModel(subscriptionManager: subscriptionManager,
                                                       isInternalUser: internalUserDecider.isInternalUser,
                                                       userScript: SubscriptionPagesUserScript(),
                                                       subFeature: subscriptionPagesUseSubscriptionFeature)
        viewModel.email.setEmailFlowMode(.restoreFlow)
        return SubscriptionContainerView(currentView: .restore, viewModel: viewModel)
            .environmentObject(navigationCoordinator)
    }

    static func makeEmailFlowV2(navigationCoordinator: SubscriptionNavigationCoordinator,
                                subscriptionManager: SubscriptionManagerV2,
                                subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
                                internalUserDecider: InternalUserDecider,
                                emailFlow: SubscriptionEmailViewModel.EmailViewFlow = .activationFlow,
                                onDisappear: @escaping () -> Void) -> some View {
        let appStoreRestoreFlow: AppStoreRestoreFlowV2 = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManager,
                                                                                      storePurchaseManager: subscriptionManager.storePurchaseManager())
        let appStorePurchaseFlow = DefaultAppStorePurchaseFlowV2(subscriptionManager: subscriptionManager,
                                                                 storePurchaseManager: subscriptionManager.storePurchaseManager(),
                                                                 appStoreRestoreFlow: appStoreRestoreFlow)
        let viewModel = SubscriptionContainerViewModel(
            subscriptionManager: subscriptionManager,
            isInternalUser: internalUserDecider.isInternalUser,
            userScript: SubscriptionPagesUserScript(),
            subFeature: DefaultSubscriptionPagesUseSubscriptionFeatureV2(subscriptionManager: subscriptionManager,
                                                                         subscriptionFeatureAvailability: subscriptionFeatureAvailability,
                                                                         subscriptionAttributionOrigin: nil,
                                                                         appStorePurchaseFlow: appStorePurchaseFlow,
                                                                         appStoreRestoreFlow: appStoreRestoreFlow)
        )

        viewModel.email.setEmailFlowMode(emailFlow)
        
        return SubscriptionContainerView(currentView: .email, viewModel: viewModel)
            .environmentObject(navigationCoordinator)
            .onDisappear(perform: { onDisappear() })
    }
}

private class SubscriptionAppStoreWidePixelEventMapping: EventMapping<AppStorePurchaseFlowV2Event> {
    private let widePixelManager: WidePixelManaging
    private let origin: String?
    private let internalUserDecider: InternalUserDecider
    private var widePixelData: SubscriptionPurchaseWidePixelData?
    private var lastFailingStep: SubscriptionPurchaseWidePixelData.FailingStep = .flowStart

    init(widePixelManager: WidePixelManaging, origin: String?, internalUserDecider: InternalUserDecider) {
        self.widePixelManager = widePixelManager
        self.origin = origin
        self.internalUserDecider = internalUserDecider

        super.init { _, _, _, _ in }

        self.eventMapper = { [weak self] event, error, _, _ in
            guard let self else { return }
            switch event {
            case let .started(subscriptionIdentifier, freeTrialEligible):
                var data = SubscriptionPurchaseWidePixelData(
                    purchasePlatform: .appStore,
                    subscriptionIdentifier: subscriptionIdentifier,
                    freeTrialEligible: freeTrialEligible,
                    contextData: WidePixelContextData(id: "subscription-purchase", name: origin)
                )

                data.appData.internalUser = self.internalUserDecider.isInternalUser
                self.widePixelData = data
                self.widePixelManager.startFlow(data)
                self.lastFailingStep = .flowStart

            case .accountCreationStarted:
                self.lastFailingStep = .accountCreate
                self.widePixelData?.createAccountDuration = WidePixel.MeasuredInterval(start: Date())

            case .accountCreationEnded:
                self.widePixelData?.createAccountDuration?.end = Date()
                if let data = self.widePixelData { self.widePixelManager.updateFlow(data) }

            case .paymentStarted:
                self.lastFailingStep = .accountPayment
                self.widePixelData?.completePurchaseDuration = WidePixel.MeasuredInterval(start: Date())

            case .paymentEnded:
                self.widePixelData?.completePurchaseDuration?.end = Date()
                if let data = self.widePixelData { self.widePixelManager.updateFlow(data) }

            case .activationStarted:
                self.lastFailingStep = .accountActivation
                self.widePixelData?.activateAccountDuration = WidePixel.MeasuredInterval(start: Date())

            case .activationEnded:
                self.widePixelData?.activateAccountDuration?.end = Date()
                if let data = self.widePixelData { self.widePixelManager.updateFlow(data) }

            case .succeeded:
                if let data = self.widePixelData {
                    self.widePixelManager.completeFlow(data, status: .success) { _, _ in }
                }
                self.widePixelData = nil
                self.lastFailingStep = .flowStart

            case .cancelled:
                if let data = self.widePixelData {
                    self.widePixelManager.completeFlow(data, status: .cancelled) { _, _ in }
                }
                self.widePixelData = nil
                self.lastFailingStep = .flowStart

            case let .failed(errorDescription):
                guard var data = self.widePixelData else { break }

                data.failingStep = self.lastFailingStep

                if let error {
                    data.errorData = WidePixelErrorData(error: error)
                }

                self.widePixelManager.completeFlow(data, status: .failure) { _, _ in }
                self.widePixelData = nil
                self.lastFailingStep = .flowStart
            }
        }
    }
}
