//
//  NetworkProtectionRootView.swift
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

import SwiftUI
import VPN
import Subscription
import Core

struct NetworkProtectionRootView: View {

    @StateObject var statusViewModel: NetworkProtectionStatusViewModel
    @StateObject var feedbackFormModel: UnifiedFeedbackFormViewModel

    init(source: VPNConnectionWideEventData.ScreenSource) {
        let subscriptionManager = AppDependencyProvider.shared.subscriptionManager
        let locationListRepository = NetworkProtectionLocationListCompositeRepository()
        let tunnelController = AppDependencyProvider.shared.networkProtectionTunnelController
        _statusViewModel = StateObject(wrappedValue: NetworkProtectionStatusViewModel(
            tunnelController: tunnelController,
            entryContextProvider: {
                VPNConnectionWideEventData.EntryContext(
                    source: source,
                    localTokenState: subscriptionManager.localTokenState()
                )
            },
            settings: AppDependencyProvider.shared.vpnSettings,
            statusObserver: AppDependencyProvider.shared.connectionObserver,
            serverInfoObserver: AppDependencyProvider.shared.serverInfoObserver,
            controllerErrorPublisher: tunnelController.controllerErrorPublisher,
            locationListRepository: locationListRepository,
            enablesUnifiedFeedbackForm: subscriptionManager.isUserAuthenticated))

        _feedbackFormModel = StateObject(wrappedValue: UnifiedFeedbackFormViewModel(
            subscriptionManager: subscriptionManager,
            vpnMetadataCollector: DefaultVPNMetadataCollector(),
            dbpMetadataCollector: DefaultDBPMetadataCollector(),
            isPaidAIChatFeatureEnabled: { AppDependencyProvider.shared.featureFlagger.isFeatureOn(.paidAIChat) },
            isProTierPurchaseEnabled: { AppDependencyProvider.shared.featureFlagger.isFeatureOn(.allowProTierPurchase) },
            source: .vpn))
    }

    var body: some View {
        NetworkProtectionStatusView(statusModel: statusViewModel, feedbackFormModel: feedbackFormModel)
            .navigationTitle(UserText.netPNavTitle)
            .onFirstAppear {
                Pixel.fire(
                    pixel: .subscriptionVPNSettings,
                    withAdditionalParameters: self.statusViewModel.featureDiscovery.addToParams([:], forFeature: .vpn))
            }
    }
}

private extension VPNConnectionWideEventData.EntryContext {

    init(source: VPNConnectionWideEventData.ScreenSource,
         localTokenState: LocalSubscriptionTokenState) {
        let tokenState: VPNConnectionWideEventData.TokenState
        switch localTokenState {
        case .present:
            tokenState = .present
        case .missing:
            tokenState = .missing
        case .readError:
            tokenState = .readError
        }

        self.init(
            source: source,
            tokenState: tokenState
        )
    }
}
