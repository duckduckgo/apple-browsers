//
//  SubscriptionFeatureAvailability.swift
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

public protocol SubscriptionFeatureAvailability {
    var isSubscriptionPurchaseAllowed: Bool { get }
    var isPaidAIChatEnabled: Bool { get }
    /// Indicates whether the alternate Stripe payment flow is supported for subscriptions.
    var isSupportsAlternateStripePaymentFlowEnabled: Bool { get }
    var isSubscriptionPurchaseWidePixelMeasurementEnabled: Bool { get }
}

public final class DefaultSubscriptionFeatureAvailability: SubscriptionFeatureAvailability {

    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let purchasePlatform: SubscriptionEnvironment.PurchasePlatform
    private let paidAIChatFlagStatusProvider: () -> Bool
    private let supportsAlternateStripePaymentFlowStatusProvider: () -> Bool
    private let isSubscriptionPurchaseWidePixelMeasurementEnabledProvider: () -> Bool

    /// Initializes a new instance of `DefaultSubscriptionFeatureAvailability`.
    ///
    /// - Parameters:
    ///   - privacyConfigurationManager: The privacy configuration manager used to check feature availability.
    ///   - purchasePlatform: The platform through which purchases are made (App Store or Stripe).
    ///   - paidAIChatFlagStatusProvider: A closure that returns whether paid AI chat features are enabled.
    ///   - supportsAlternateStripePaymentFlowStatusProvider: A closure that returns whether the alternate Stripe payment flow is supported.
    public init(privacyConfigurationManager: PrivacyConfigurationManaging,
                purchasePlatform: SubscriptionEnvironment.PurchasePlatform,
                paidAIChatFlagStatusProvider: @escaping () -> Bool,
                supportsAlternateStripePaymentFlowStatusProvider: @escaping () -> Bool,
                isSubscriptionPurchaseWidePixelMeasurementEnabledProvider: @escaping () -> Bool) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.purchasePlatform = purchasePlatform
        self.paidAIChatFlagStatusProvider = paidAIChatFlagStatusProvider
        self.supportsAlternateStripePaymentFlowStatusProvider = supportsAlternateStripePaymentFlowStatusProvider
        self.isSubscriptionPurchaseWidePixelMeasurementEnabledProvider = isSubscriptionPurchaseWidePixelMeasurementEnabledProvider
    }

    public var isSubscriptionPurchaseAllowed: Bool {
        let isPurchaseAllowed: Bool

        switch purchasePlatform {
        case .appStore:
            isPurchaseAllowed = privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchase)
        case .stripe:
            isPurchaseAllowed = privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(PrivacyProSubfeature.allowPurchaseStripe)
        }

        return isPurchaseAllowed || isInternalUser
    }

    public var isPaidAIChatEnabled: Bool {
        return paidAIChatFlagStatusProvider()
    }

    /// Indicates whether the alternate Stripe payment flow is supported for subscriptions.
    /// This property delegates to the `supportsAlternateStripePaymentFlowStatusProvider` function provided during initialization.
    ///
    /// - Returns: `true` if the alternate Stripe payment flow is supported, `false` otherwise.
    public var isSupportsAlternateStripePaymentFlowEnabled: Bool {
        supportsAlternateStripePaymentFlowStatusProvider()
    }

    public var isSubscriptionPurchaseWidePixelMeasurementEnabled: Bool {
        isSubscriptionPurchaseWidePixelMeasurementEnabledProvider()
    }

    // MARK: - Conditions

    private var isInternalUser: Bool {
        privacyConfigurationManager.internalUserDecider.isInternalUser
    }
}
