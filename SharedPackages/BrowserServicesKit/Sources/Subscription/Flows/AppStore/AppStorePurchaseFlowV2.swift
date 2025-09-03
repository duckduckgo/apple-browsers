//
//  AppStorePurchaseFlowV2.swift
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

public enum AppStorePurchaseFlowError: DDGError {
    case noProductsFound
    case activeSubscriptionAlreadyPresent
    case authenticatingWithTransactionFailed
    case accountCreationFailed(Error)
    case purchaseFailed(Error)
    case cancelledByUser
    case missingEntitlements
    case internalError(Error?)

    public var description: String {
        switch self {
        case .noProductsFound: "No subscription products found in the App Store"
        case .activeSubscriptionAlreadyPresent: "An active subscription is already present on this account"
        case .authenticatingWithTransactionFailed: "Failed to authenticate the subscription transaction"
        case .accountCreationFailed(let subError): "Failed to create subscription account: \(String(describing: subError))"
        case .purchaseFailed(let subError): "Subscription purchase failed: \(String(describing: subError))"
        case .cancelledByUser: "Subscription purchase was cancelled by user"
        case .missingEntitlements: "Subscription completed but entitlements are missing"
        case .internalError(let error): "An internal error occurred during purchase: \(String(describing: error))"
        }
    }

    public var errorDomain: String { "com.duckduckgo.subscription.AppStorePurchaseFlowError" }

    public var errorCode: Int {
        switch self {
        case .noProductsFound: 12900
        case .activeSubscriptionAlreadyPresent: 12901
        case .authenticatingWithTransactionFailed: 12902
        case .accountCreationFailed: 12903
        case .purchaseFailed: 12904
        case .cancelledByUser: 12905
        case .missingEntitlements: 12906
        case .internalError: 12907
        }
    }

    public var underlyingError: (any Error)? {
        switch self {
        case .accountCreationFailed(let error): error
        case .purchaseFailed(let error): error
        case .internalError(let error): error
        default: nil
        }
    }

    public static func == (lhs: AppStorePurchaseFlowError, rhs: AppStorePurchaseFlowError) -> Bool {
        switch (lhs, rhs) {
        case (.noProductsFound, .noProductsFound),
            (.activeSubscriptionAlreadyPresent, .activeSubscriptionAlreadyPresent),
            (.authenticatingWithTransactionFailed, .authenticatingWithTransactionFailed),
            (.cancelledByUser, .cancelledByUser),
            (.missingEntitlements, .missingEntitlements),
            (.internalError, .internalError):
            return true
        case let (.accountCreationFailed(lhsError), .accountCreationFailed(rhsError)):
            return String(describing: lhsError) == String(describing: rhsError)
        case let (.purchaseFailed(lhsError), .purchaseFailed(rhsError)):
            return String(describing: lhsError) == String(describing: rhsError)
        default:
            return false
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
public protocol AppStorePurchaseFlowV2 {
    typealias TransactionJWS = String
    typealias PurchaseResult = (transactionJWS: TransactionJWS, accountCreationDuration: WidePixel.MeasuredInterval?)

    func purchaseSubscription(with subscriptionIdentifier: String) async -> Result<PurchaseResult, AppStorePurchaseFlowError>

    /// Completes the subscription purchase by validating the transaction.
    ///
    /// - Parameters:
    ///   - transactionJWS: The JWS representation of the transaction to be validated.
    ///   - additionalParams: Optional additional parameters to send with the transaction validation request.
    /// - Returns: A `Result` containing either a `PurchaseUpdate` object on success or an `AppStorePurchaseFlowError` on failure.
    @discardableResult func completeSubscriptionPurchase(with transactionJWS: TransactionJWS, additionalParams: [String: String]?) async -> Result<PurchaseUpdate, AppStorePurchaseFlowError>
}

@available(macOS 12.0, iOS 15.0, *)
public final class DefaultAppStorePurchaseFlowV2: AppStorePurchaseFlowV2 {
    private let subscriptionManager: any SubscriptionManagerV2
    private let storePurchaseManager: any StorePurchaseManagerV2
    private let appStoreRestoreFlow: any AppStoreRestoreFlowV2

    public init(subscriptionManager: any SubscriptionManagerV2,
                storePurchaseManager: any StorePurchaseManagerV2,
                appStoreRestoreFlow: any AppStoreRestoreFlowV2
    ) {
        self.subscriptionManager = subscriptionManager
        self.storePurchaseManager = storePurchaseManager
        self.appStoreRestoreFlow = appStoreRestoreFlow
    }

    public func purchaseSubscription(with subscriptionIdentifier: String) async -> Result<PurchaseResult, AppStorePurchaseFlowError> {
        Logger.subscriptionAppStorePurchaseFlow.log("Purchasing Subscription")

        var externalID: String?
        var accountCreationDuration: WidePixel.MeasuredInterval?

        if let existingExternalID = await getExpiredSubscriptionID() {
            Logger.subscriptionAppStorePurchaseFlow.log("External ID retrieved from expired subscription")
            externalID = existingExternalID
        } else {
            Logger.subscriptionAppStorePurchaseFlow.log("Try to retrieve an expired Apple subscription or create a new one")

            // Try to restore an account from a past purchase
            switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
            case .success:
                Logger.subscriptionAppStorePurchaseFlow.log("An active subscription is already present")
                return .failure(.activeSubscriptionAlreadyPresent)
            case .failure(let error):
                Logger.subscriptionAppStorePurchaseFlow.log("Failed to restore an account from a past purchase: \(String(describing: error), privacy: .public)")
                do {
                    var creationStart = WidePixel.MeasuredInterval.startingNow()
                    externalID = try await subscriptionManager.getTokenContainer(policy: .createIfNeeded).decodedAccessToken.externalID
                    creationStart.complete()
                    accountCreationDuration = creationStart
                } catch Networking.OAuthClientError.missingTokenContainer {
                    Logger.subscriptionStripePurchaseFlow.error("Failed to create a new account: \(String(describing: error), privacy: .public)")
                    return .failure(.accountCreationFailed(error))
                } catch {
                    Logger.subscriptionStripePurchaseFlow.fault("Failed to create a new account: \(String(describing: error), privacy: .public), the operation is unrecoverable")
                    return .failure(.internalError(error))
                }
            }
        }

        guard let externalID else {
            Logger.subscriptionAppStorePurchaseFlow.fault("Missing external ID, subscription purchase failed")
            return .failure(.internalError(nil))
        }

        // Make the purchase
        switch await storePurchaseManager.purchaseSubscription(with: subscriptionIdentifier, externalID: externalID) {
        case .success(let transactionJWS):
            return .success((transactionJWS: transactionJWS, accountCreationDuration: accountCreationDuration))
        case .failure(let error):
            Logger.subscriptionAppStorePurchaseFlow.error("purchaseSubscription error: \(String(describing: error), privacy: .public)")

            await subscriptionManager.signOut(notifyUI: false)

            switch error {
            case .purchaseCancelledByUser:
                return .failure(.cancelledByUser)
            case .purchaseFailed(let underlyingError):
                return .failure(.purchaseFailed(underlyingError))
            default:
                return .failure(.purchaseFailed(error))
            }
        }
    }

    @discardableResult
    public func completeSubscriptionPurchase(with transactionJWS: TransactionJWS, additionalParams: [String: String]?) async -> Result<PurchaseUpdate, AppStorePurchaseFlowError> {
        Logger.subscriptionAppStorePurchaseFlow.log("Completing Subscription Purchase")
        subscriptionManager.clearSubscriptionCache()

        do {
            let subscription = try await subscriptionManager.confirmPurchase(signature: transactionJWS, additionalParams: additionalParams)
            let refreshedToken = try await subscriptionManager.getTokenContainer(policy: .localForceRefresh) // fetch new entitlements
            if subscription.isActive {
                if refreshedToken.decodedAccessToken.subscriptionEntitlements.isEmpty {
                    Logger.subscriptionAppStorePurchaseFlow.error("Missing entitlements")
                    return .failure(.missingEntitlements)
                } else {
                    return .success(.completed)
                }
            } else {
                Logger.subscriptionAppStorePurchaseFlow.error("Subscription expired")
                return .failure(.purchaseFailed(AppStoreRestoreFlowErrorV2.subscriptionExpired))
            }
        } catch {
            Logger.subscriptionAppStorePurchaseFlow.error("Purchase Failed: \(error)")
            return .failure(.purchaseFailed(error))
        }
    }

    private func getExpiredSubscriptionID() async -> String? {
        do {
            let subscription = try await subscriptionManager.getSubscription(cachePolicy: .remoteFirst)
            // Only return an externalID if the subscription is expired so to prevent creating multiple subscriptions in the same account
            if !subscription.isActive,
               subscription.platform != .apple {
                return try await subscriptionManager.getTokenContainer(policy: .localValid).decodedAccessToken.externalID
            }
            return nil
        } catch {
            Logger.subscription.error("Failed to retrieve the current subscription ID: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    public func recoverSubscriptionFromDeadToken() async throws {
        Logger.subscriptionAppStorePurchaseFlow.log("Recovering Subscription From Dead Token")

        // Clear everything, the token is unrecoverable
        await subscriptionManager.signOut(notifyUI: true)

        switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
        case .success:
            Logger.subscriptionAppStorePurchaseFlow.log("Subscription recovered")
        case .failure(let error):
            Logger.subscriptionAppStorePurchaseFlow.fault("Failed to recover Apple subscription: \(String(describing: error), privacy: .public)")
            throw error
        }
    }
}
