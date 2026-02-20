//
//  StripePurchaseFlow.swift
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
    case tieredProductsApiCallFailed(Error)
    case tieredProductsEmptyProductsFromAPI
    case tieredProductsEmptyAfterFiltering
    case tieredProductsTierCreationFailed

    public var description: String {
        switch self {
        case .noProductsFound: "No products found."
        case .accountCreationFailed(let error): "Account creation failed: \(error)"
        case .tieredProductsApiCallFailed(let error): "API call failed: \(error)"
        case .tieredProductsEmptyProductsFromAPI: "API returned empty products."
        case .tieredProductsEmptyAfterFiltering: "No products after filtering."
        case .tieredProductsTierCreationFailed: "Failed to create tiers."
        }
    }

    public static var errorDomain: String { "com.duckduckgo.subscription.StripePurchaseFlowError" }

    public var errorCode: Int {
        switch self {
        case .noProductsFound: 12700
        case .accountCreationFailed: 12701
        case .tieredProductsApiCallFailed: 12702
        case .tieredProductsEmptyProductsFromAPI: 12703
        case .tieredProductsEmptyAfterFiltering: 12704
        case .tieredProductsTierCreationFailed: 12705
        }
    }

    public var underlyingError: (any Error)? {
        switch self {
        case .accountCreationFailed(let error): error
        case .tieredProductsApiCallFailed(let error): error
        default: nil
        }
    }

    public static func == (lhs: StripePurchaseFlowError, rhs: StripePurchaseFlowError) -> Bool {
        switch (lhs, rhs) {
        case (.noProductsFound, .noProductsFound):
            return true
        case let (.accountCreationFailed(lhsError), .accountCreationFailed(rhsError)):
            return String(describing: lhsError) == String(describing: rhsError)
        case let (.tieredProductsApiCallFailed(lhsError), .tieredProductsApiCallFailed(rhsError)):
            return String(describing: lhsError) == String(describing: rhsError)
        case (.tieredProductsEmptyProductsFromAPI, .tieredProductsEmptyProductsFromAPI):
            return true
        case (.tieredProductsEmptyAfterFiltering, .tieredProductsEmptyAfterFiltering):
            return true
        case (.tieredProductsTierCreationFailed, .tieredProductsTierCreationFailed):
            return true
        default:
            return false
        }
    }
}

public protocol StripePurchaseFlow {
    typealias PrepareResult = (purchaseUpdate: PurchaseUpdate, accountCreationDuration: WideEvent.MeasuredInterval?)

    func prepareSubscriptionPurchase(emailAccessToken: String?) async -> Result<PrepareResult, StripePurchaseFlowError>
    func completeSubscriptionPurchase() async
}

public final class DefaultStripePurchaseFlow: StripePurchaseFlow {
    private let subscriptionManager: any SubscriptionManager

    public init(subscriptionManager: any SubscriptionManager) {
        self.subscriptionManager = subscriptionManager
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
                var accountCreation = WideEvent.MeasuredInterval.startingNow()
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
        NotificationCenter.default.post(name: .userDidPurchaseSubscription, object: self)
    }
}
