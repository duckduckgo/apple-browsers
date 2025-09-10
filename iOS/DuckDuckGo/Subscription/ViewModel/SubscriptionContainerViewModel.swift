//
//  SubscriptionContainerViewModel.swift
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

import Foundation
import Subscription
import Combine
import DataBrokerProtection_iOS

final class SubscriptionContainerViewModel: ObservableObject {

    let userScript: SubscriptionPagesUserScript
    let subFeature: any SubscriptionPagesUseSubscriptionFeature

    let flow: SubscriptionFlowViewModel
    let restore: SubscriptionRestoreViewModel
    let email: SubscriptionEmailViewModel

    init(subscriptionManager: SubscriptionAuthV1toV2Bridge,
         redirectPurchaseURL: URL? = nil,
         isInternalUser: Bool = false,
         userScript: SubscriptionPagesUserScript,
         subFeature: any SubscriptionPagesUseSubscriptionFeature,
         dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?) {

        self.userScript = userScript

        subFeature.cleanup()
        self.subFeature = subFeature

        self.flow = SubscriptionFlowViewModel(purchaseURL: redirectPurchaseURL ?? subscriptionManager.url(for: .purchase),
                                              isInternalUser: isInternalUser,
                                              userScript: userScript,
                                              subFeature: subFeature,
                                              subscriptionManager: subscriptionManager,
                                              dataBrokerProtectionViewControllerProvider: dataBrokerProtectionViewControllerProvider)
        self.restore = SubscriptionRestoreViewModel(userScript: userScript,
                                                    subFeature: subFeature)
        self.email = SubscriptionEmailViewModel(isInternalUser: isInternalUser,
                                                userScript: userScript,
                                                subFeature: subFeature,
                                                subscriptionManager: subscriptionManager,
                                                dataBrokerProtectionViewControllerProvider: dataBrokerProtectionViewControllerProvider)
    }

}
