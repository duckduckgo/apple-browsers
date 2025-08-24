//
//  StripePurchaseFlowV2.swift
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

import Foundation
import StoreKit
import os.log
import Networking
import Common

public enum StripePurchaseFlowError: Swift.Error {
    case noProductsFound
    case accountCreationFailed(Error)
}

// MARK: - Flow Events

public enum StripePurchaseFlowV2Event {
    case started(subscriptionIdentifier: String?)
    case accountCreationStarted
    case accountCreationEnded
    case paymentStarted
    case paymentEnded
    case activationStarted
    case activationEnded
    case succeeded
    case cancelled
    case failed(errorDescription: String)
}

public protocol StripePurchaseFlowV2 {
    func subscriptionOptions() async -> Result<SubscriptionOptionsV2, StripePurchaseFlowError>
    func prepareSubscriptionPurchase(emailAccessToken: String?) async -> Result<PurchaseUpdate, StripePurchaseFlowError>
    func completeSubscriptionPurchase() async
}

public final class DefaultStripePurchaseFlowV2: StripePurchaseFlowV2 {
    private let subscriptionManager: any SubscriptionManagerV2
    private let eventMapping: EventMapping<StripePurchaseFlowV2Event>?

    public init(subscriptionManager: any SubscriptionManagerV2,
                eventMapping: EventMapping<StripePurchaseFlowV2Event>? = nil) {
        self.subscriptionManager = subscriptionManager
        self.eventMapping = eventMapping
    }

    public func subscriptionOptions() async -> Result<SubscriptionOptionsV2, StripePurchaseFlowError> {
        Logger.subscriptionStripePurchaseFlow.log("Getting subscription options for Stripe")

        guard let products = try? await subscriptionManager.getProducts(),
              !products.isEmpty else {
            Logger.subscriptionStripePurchaseFlow.error("Failed to obtain products")
            return .failure(.noProductsFound)
        }

        let currency = products.first?.currency ?? "USD"

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US@currency=\(currency)")

        let options: [SubscriptionOptionV2] = products.map {
            var displayPrice = "\($0.price) \($0.currency)"

            if let price = Float($0.price), let formattedPrice = formatter.string(from: price as NSNumber) {
                 displayPrice = formattedPrice
            }
            let cost = SubscriptionOptionCost(displayPrice: displayPrice, recurrence: $0.billingPeriod.lowercased())
            return SubscriptionOptionV2(id: $0.productId, cost: cost)
        }

        let features: [SubscriptionEntitlement] = [.networkProtection,
                                                   .dataBrokerProtection,
                                                   .identityTheftRestoration,
                                                   .paidAIChat]
        return .success(SubscriptionOptionsV2(platform: SubscriptionPlatformName.stripe,
                                              options: options,
                                              availableEntitlements: features))
    }

    public func prepareSubscriptionPurchase(emailAccessToken: String?) async -> Result<PurchaseUpdate, StripePurchaseFlowError> {
        Logger.subscription.log("Preparing subscription purchase")

        eventMapping?.fire(.started(subscriptionIdentifier: nil))

        await subscriptionManager.signOut(notifyUI: false)

        if subscriptionManager.isUserAuthenticated {
            if let subscriptionExpired = await isSubscriptionExpired(),
               subscriptionExpired == true,
               let tokenContainer = try? await subscriptionManager.getTokenContainer(policy: .localValid) {
                eventMapping?.fire(.paymentStarted)
                eventMapping?.fire(.paymentEnded)
                return .success(PurchaseUpdate.redirect(withToken: tokenContainer.accessToken))
            } else {
                eventMapping?.fire(.paymentStarted)
                eventMapping?.fire(.paymentEnded)
                return .success(PurchaseUpdate.redirect(withToken: ""))
            }
        } else {
            do {
                // Create account
                eventMapping?.fire(.accountCreationStarted)
                let tokenContainer = try await subscriptionManager.getTokenContainer(policy: .createIfNeeded)
                eventMapping?.fire(.accountCreationEnded)
                return .success(PurchaseUpdate.redirect(withToken: tokenContainer.accessToken))
            } catch {
                Logger.subscriptionStripePurchaseFlow.error("Account creation failed: \(error.localizedDescription, privacy: .public)")
                eventMapping?.fire(.accountCreationEnded)
                eventMapping?.fire(
                    .failed(errorDescription: StripePurchaseFlowError.accountCreationFailed(error).localizedDescription),
                    error: StripePurchaseFlowError.accountCreationFailed(error)
                )
                return .failure(.accountCreationFailed(error))
            }
        }
    }

    private func isSubscriptionExpired() async -> Bool? {
        guard let subscription = try? await subscriptionManager.getSubscription(cachePolicy: .remoteFirst) else {
            return nil
        }
        return !subscription.isActive
    }

    public func completeSubscriptionPurchase() async {
        Logger.subscriptionStripePurchaseFlow.log("Completing subscription purchase")

        eventMapping?.fire(.activationStarted)
        subscriptionManager.clearSubscriptionCache()
        _ = try? await subscriptionManager.getTokenContainer(policy: .localForceRefresh)
        eventMapping?.fire(.activationEnded)
        eventMapping?.fire(.succeeded)
    }
}
