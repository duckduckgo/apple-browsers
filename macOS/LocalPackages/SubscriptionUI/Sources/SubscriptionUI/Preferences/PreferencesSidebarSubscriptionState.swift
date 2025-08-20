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
    public let shouldHideSubscriptionPurchase: Bool

    // If the menu item is clickable or greyed out
    public let isNetworkProtectionRemovalEnabled: Bool
    public let isPersonalInformationRemovalEnabled: Bool
    public let isIdentityTheftRestorationEnabled: Bool
    public let isPaidAIChatEnabled: Bool

    // If the menu item is visible or not
    public let isNetworkProtectionRemovalAvailable: Bool
    public let isPersonalInformationRemovalAvailable: Bool
    public let isIdentityTheftRestorationAvailable: Bool
    public let isPaidAIChatAvailable: Bool

    public init(hasSubscription: Bool = false,
                shouldHideSubscriptionPurchase: Bool = true,
                isNetworkProtectionRemovalEnabled: Bool = false,
                isPersonalInformationRemovalEnabled: Bool = false,
                isIdentityTheftRestorationEnabled: Bool = false,
                isPaidAIChatEnabled: Bool = false,
                isNetworkProtectionRemovalAvailable: Bool = false,
                isPersonalInformationRemovalAvailable: Bool = false,
                isIdentityTheftRestorationAvailable: Bool = false,
                isPaidAIChatAvailable: Bool = false) {
        self.hasSubscription = hasSubscription
        self.shouldHideSubscriptionPurchase = shouldHideSubscriptionPurchase
        self.isNetworkProtectionRemovalEnabled = isNetworkProtectionRemovalEnabled
        self.isPersonalInformationRemovalEnabled = isPersonalInformationRemovalEnabled
        self.isIdentityTheftRestorationEnabled = isIdentityTheftRestorationEnabled
        self.isPaidAIChatEnabled = isPaidAIChatEnabled
        self.isNetworkProtectionRemovalAvailable = isNetworkProtectionRemovalAvailable
        self.isPersonalInformationRemovalAvailable = isPersonalInformationRemovalAvailable
        self.isIdentityTheftRestorationAvailable = isIdentityTheftRestorationAvailable
        self.isPaidAIChatAvailable = isPaidAIChatAvailable
    }

    public var hasAnyEntitlement: Bool {
        return isNetworkProtectionRemovalEnabled
        || isPersonalInformationRemovalEnabled
        || isIdentityTheftRestorationEnabled
        || isPaidAIChatEnabled
    }
}

extension PreferencesSidebarSubscriptionState: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "PreferencesSidebarSubscriptionState(hasSubscription: \(hasSubscription), shouldHideSubscriptionPurchase: \(shouldHideSubscriptionPurchase), isNetworkProtectionRemovalEnabled: \(isNetworkProtectionRemovalEnabled), isPersonalInformationRemovalEnabled: \(isPersonalInformationRemovalEnabled), isIdentityTheftRestorationEnabled: \(isIdentityTheftRestorationEnabled), isPaidAIChatEnabled: \(isPaidAIChatEnabled), isNetworkProtectionRemovalAvailable: \(isNetworkProtectionRemovalAvailable), isPersonalInformationRemovalAvailable: \(isPersonalInformationRemovalAvailable), isIdentityTheftRestorationAvailable: \(isIdentityTheftRestorationAvailable), isPaidAIChatAvailable: \(isPaidAIChatAvailable))"
    }
}
