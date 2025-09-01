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
import PixelKit

public enum StripePurchaseFlowError: DDGError {
    case noProductsFound
    case accountCreationFailed(Error)

    public var description: String {
        switch self {
        case .noProductsFound: "No products found."
        case .accountCreationFailed(let error): "Account creation failed: \(error)"
        }
    }

    public var errorDomain: String { "com.duckduckgo.subscription.StripePurchaseFlowError" }

    public var errorCode: Int {
        switch self {
        case .noProductsFound: 12700
        case .accountCreationFailed: 12701
        }
    }

    public var underlyingError: (any Error)? {
        switch self {
        case .accountCreationFailed(let error): error
        default: nil
        }
    }

    public static func == (lhs: StripePurchaseFlowError, rhs: StripePurchaseFlowError) -> Bool {
        switch (lhs, rhs) {
        case (.noProductsFound, .noProductsFound):
            return true
        case let (.accountCreationFailed(lhsError), .accountCreationFailed(rhsError)):
            return String(describing: lhsError) == String(describing: rhsError)
        default:
            return false
        }
    }
}

public protocol StripePurchaseFlowV2 {
    typealias PrepareResult = (purchaseUpdate: PurchaseUpdate, accountCreationDuration: WidePixel.MeasuredInterval?)

    func subscriptionOptions() async -> Result<SubscriptionOptionsV2, StripePurchaseFlowError>
    func prepareSubscriptionPurchase(emailAccessToken: String?) async -> Result<PrepareResult, StripePurchaseFlowError>
    func completeSubscriptionPurchase() async
}

public final class DefaultStripePurchaseFlowV2: StripePurchaseFlowV2 {
    private let subscriptionManager: any SubscriptionManagerV2

    public init(subscriptionManager: any SubscriptionManagerV2) {
        self.subscriptionManager = subscriptionManager
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

    public func prepareSubscriptionPurchase(emailAccessToken: String?) async -> Result<PrepareResult, StripePurchaseFlowError> {
        Logger.subscription.log("Preparing subscription purchase")

        await subscriptionManager.signOut(notifyUI: false)

        if subscriptionManager.isUserAuthenticated {
            if let subscriptionExpired = await isSubscriptionExpired(),
               subscriptionExpired == true,
               let tokenContainer = try? await subscriptionManager.getTokenContainer(policy: .localValid) {
                return .success((purchaseUpdate: PurchaseUpdate.redirect(withToken: tokenContainer.accessToken), accountCreationDuration: nil))
            } else {
                return .success((purchaseUpdate: PurchaseUpdate.redirect(withToken: ""), accountCreationDuration: nil))
            }
        } else {
            do {
                // Create account
                var accountCreation = WidePixel.MeasuredInterval.startingNow()
                let tokenContainer = try await subscriptionManager.getTokenContainer(policy: .createIfNeeded)
                accountCreation.complete()

                return .success((purchaseUpdate: PurchaseUpdate.redirect(withToken: tokenContainer.accessToken), accountCreationDuration: accountCreation))
            } catch {
                Logger.subscriptionStripePurchaseFlow.error("Account creation failed: \(String(describing: error), privacy: .public)")
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
        subscriptionManager.clearSubscriptionCache()
        _ = try? await subscriptionManager.getTokenContainer(policy: .localForceRefresh)
    }
}
