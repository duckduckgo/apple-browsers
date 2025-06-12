//
//  PreferencesSidebarSubscriptionState.swift
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
import Subscription
import Networking
import PreferencesUI_macOS

public struct PreferencesSidebarSubscriptionState: Equatable {
    public let hasSubscription: Bool
    public let subscriptionFeatures: [Entitlement.ProductName]?
    public let userEntitlements: [SubscriptionEntitlement]
    public let shouldHideSubscriptionPurchase: Bool

    public let personalInformationRemovalStatus: StatusIndicator
    public let identityTheftRestorationStatus: StatusIndicator
    public let paidAIChatStatus: StatusIndicator
    public let isPaidAIChatEnabled: Bool

    public init(hasSubscription: Bool,
                subscriptionFeatures: [Entitlement.ProductName]?,
                userEntitlements: [SubscriptionEntitlement],
                shouldHideSubscriptionPurchase: Bool,
                personalInformationRemovalStatus: StatusIndicator,
                identityTheftRestorationStatus: StatusIndicator,
                paidAIChatStatus: StatusIndicator,
                isPaidAIChatEnabled: Bool) {
        self.hasSubscription = hasSubscription
        self.subscriptionFeatures = subscriptionFeatures
        self.userEntitlements = userEntitlements
        self.shouldHideSubscriptionPurchase = shouldHideSubscriptionPurchase
        self.personalInformationRemovalStatus = personalInformationRemovalStatus
        self.identityTheftRestorationStatus = identityTheftRestorationStatus
        self.paidAIChatStatus = paidAIChatStatus
        self.isPaidAIChatEnabled = isPaidAIChatEnabled
    }

    public static var initial: Self {
        .init(hasSubscription: false,
              subscriptionFeatures: nil,
              userEntitlements: [],
              shouldHideSubscriptionPurchase: true,
              personalInformationRemovalStatus: .off,
              identityTheftRestorationStatus: .off,
              paidAIChatStatus: .off,
              isPaidAIChatEnabled: false)
    }
}
