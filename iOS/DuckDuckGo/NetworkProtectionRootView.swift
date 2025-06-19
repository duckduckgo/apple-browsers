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
import Networking

struct NetworkProtectionRootView: View {

    let statusViewModel: NetworkProtectionStatusViewModel
    let feedbackFormModel: UnifiedFeedbackFormViewModel

    init() {
        let subscriptionManager = AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge
        let locationListRepository = NetworkProtectionLocationListCompositeRepository()
        statusViewModel = NetworkProtectionStatusViewModel(tunnelController: AppDependencyProvider.shared.networkProtectionTunnelController,
                                                           settings: AppDependencyProvider.shared.vpnSettings,
                                                           statusObserver: AppDependencyProvider.shared.connectionObserver,
                                                           serverInfoObserver: AppDependencyProvider.shared.serverInfoObserver,
                                                           locationListRepository: locationListRepository,
                                                           enablesUnifiedFeedbackForm: subscriptionManager.isUserAuthenticated)

        feedbackFormModel = UnifiedFeedbackFormViewModel(subscriptionManager: subscriptionManager,
                                                         apiService: DefaultAPIService(),
                                                         vpnMetadataCollector: DefaultVPNMetadataCollector(),
                                                         source: .vpn)
    }

    var body: some View {
        NetworkProtectionStatusView(statusModel: statusViewModel, feedbackFormModel: feedbackFormModel)
            .navigationTitle(UserText.netPNavTitle)
            .onFirstAppear {
                Pixel.fire(pixel: .privacyProVPNSettings, withAdditionalParameters: self.statusViewModel.featureDiscovery.addToParams([:], forFeature: .vpn))
            }
    }
}
