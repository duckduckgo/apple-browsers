//
//  SubscriptionTierOptionsProvider.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import Common
import os.log

public protocol SubscriptionTierOptionsProviding {
    func subscriptionTierOptions(includeProTier: Bool, currentSubscription: DuckDuckGoSubscription?) async -> Result<SubscriptionTierOptions, Error>
}

public enum SubscriptionTierOptionsProviderError: Error {
    case tierOptionsNotAvailableForPlatform
}

public final class DefaultSubscriptionTierOptionsProvider: SubscriptionTierOptionsProviding {

    private let subscriptionEnvironmentPlatform: SubscriptionEnvironment.PurchasePlatform
    private let storePurchaseManager: StorePurchaseManager?
    private let subscriptionEndpointService: SubscriptionEndpointService

    init(subscriptionEnvironmentPlatform: SubscriptionEnvironment.PurchasePlatform, storePurchaseManager: StorePurchaseManager?, subscriptionEndpointService: SubscriptionEndpointService) {
        self.subscriptionEnvironmentPlatform = subscriptionEnvironmentPlatform
        self.storePurchaseManager = storePurchaseManager
        self.subscriptionEndpointService = subscriptionEndpointService
    }

    public func subscriptionTierOptions(includeProTier: Bool, currentSubscription: DuckDuckGoSubscription?) async -> Result<SubscriptionTierOptions, Error> {
        let effectivePlatform: EffectivePlatform
        if let currentSubscription,
           currentSubscription.isActive {
            effectivePlatform = .subscription(currentSubscription.platform)
        } else {
            effectivePlatform = .app(subscriptionEnvironmentPlatform)
        }

        switch effectivePlatform {
        case .subscription(.stripe), .app(.stripe):
            return await fetchStripeTierOptions(includeProTier: includeProTier)
        case .subscription(.apple):
            // Apple subscription on non–App Store app (e.g. Sparkle): we cannot show tier options;
            // the app has no StoreKit. UI should redirect user to App Store / subscription settings.
            guard subscriptionEnvironmentPlatform == .appStore else {
                return .failure(SubscriptionTierOptionsProviderError.tierOptionsNotAvailableForPlatform)
            }
            return await fetchAppleTierOptions(includeProTier: includeProTier)
        case .app(.appStore):
            return await fetchAppleTierOptions(includeProTier: includeProTier)
        case .subscription(.google), .subscription(.unknown):
            return .failure(SubscriptionTierOptionsProviderError.tierOptionsNotAvailableForPlatform)
        }
    }

    private enum EffectivePlatform {
        case subscription(DuckDuckGoSubscription.Platform)
        case app(SubscriptionEnvironment.PurchasePlatform)
    }

    // MARK: - Apple path

    private func fetchAppleTierOptions(includeProTier: Bool) async -> Result<SubscriptionTierOptions, Error> {
        guard subscriptionEnvironmentPlatform == .appStore else {
            return .failure(SubscriptionTierOptionsProviderError.tierOptionsNotAvailableForPlatform)
        }
        guard #available(macOS 12.0, iOS 15.0, *) else {
            return .failure(SubscriptionTierOptionsProviderError.tierOptionsNotAvailableForPlatform)
        }
        guard let storePurchaseManager else {
            return .failure(SubscriptionTierOptionsProviderError.tierOptionsNotAvailableForPlatform)
        }
        let result = await storePurchaseManager
            .subscriptionTierOptions(includeProTier: includeProTier)
        return result.mapError { $0 as Error }
    }

    // MARK: - Stripe path

    private func fetchStripeTierOptions(includeProTier: Bool) async -> Result<SubscriptionTierOptions, Error> {
        Logger.subscriptionStripePurchaseFlow.log("Getting subscription tier options for Stripe (includeProTier: \(includeProTier))")
        let regionParameter = "us"
        let productsResponse: GetTierProductsResponse
        do {
            productsResponse = try await subscriptionEndpointService.getTierProducts(
                region: regionParameter,
                platform: SubscriptionPlatformName.stripe.rawValue
            )
        } catch {
            Logger.subscription.error("Tier options provider: API call failed: \(String(describing: error), privacy: .public)")
            return .failure(error)
        }

        guard !productsResponse.products.isEmpty else {
            Logger.subscription.error("Tier options provider: API returned empty products")
            return .failure(SubscriptionTierOptionsProviderError.tierOptionsNotAvailableForPlatform)
        }

        let filteredProducts = includeProTier
            ? productsResponse.products
            : productsResponse.products.filter { $0.tier != .pro }

        guard !filteredProducts.isEmpty else {
            Logger.subscription.error("Tier options provider: No products after filtering")
            return .failure(SubscriptionTierOptionsProviderError.tierOptionsNotAvailableForPlatform)
        }

        var tiers: [SubscriptionTier] = []
        for product in filteredProducts {
            guard let tier = createTier(from: product) else {
                Logger.subscription.warning("Tier options provider: Failed to create tier for \(product.tier.rawValue)")
                continue
            }
            tiers.append(tier)
        }

        guard !tiers.isEmpty else {
            Logger.subscription.error("Tier options provider: No tiers created")
            return .failure(SubscriptionTierOptionsProviderError.tierOptionsNotAvailableForPlatform)
        }

        return .success(SubscriptionTierOptions(platform: .stripe, products: tiers))
    }

    private func createTier(from product: TierProduct) -> SubscriptionTier? {
        var options: [SubscriptionOption] = []
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        formatter.currencyCode = product.billingCycles.first?.currency ?? "USD"

        for billingCycle in product.billingCycles {
            var displayPrice = "\(billingCycle.price) \(billingCycle.currency)"
            if let price = Float(billingCycle.price), let formattedPrice = formatter.string(from: price as NSNumber) {
                displayPrice = formattedPrice
            }
            let cost = SubscriptionOptionCost(
                displayPrice: displayPrice,
                recurrence: billingCycle.period.lowercased()
            )
            let option = SubscriptionOption(
                id: billingCycle.productId,
                cost: cost,
                offer: nil
            )
            options.append(option)
        }

        guard !options.isEmpty else { return nil }

        return SubscriptionTier(
            tier: product.tier,
            features: product.entitlements,
            options: options
        )
    }
}
