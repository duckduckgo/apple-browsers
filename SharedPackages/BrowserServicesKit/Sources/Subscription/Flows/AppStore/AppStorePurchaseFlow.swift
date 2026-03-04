//
//  AppStorePurchaseFlow.swift
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
    case transactionPendingAuthentication
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
        case .transactionPendingAuthentication: "Transaction is pending authentication (e.g., Ask to Buy)"
        case .missingEntitlements: "Subscription completed but entitlements are missing"
        case .internalError(let error): "An internal error occurred during purchase: \(String(describing: error))"
        }
    }

    public static var errorDomain: String { "com.duckduckgo.subscription.AppStorePurchaseFlowError" }

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
        case .transactionPendingAuthentication: 12908
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
            (.transactionPendingAuthentication, .transactionPendingAuthentication),
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
public protocol AppStorePurchaseFlow {
    typealias TransactionJWS = String
    typealias PurchaseResult = (transactionJWS: TransactionJWS, accountCreationDuration: WideEvent.MeasuredInterval?)

    /// Purchases a new subscription for a user who doesn't have an active subscription.
    /// This method checks for existing subscriptions and creates an account if needed.
    /// - Parameters:
    ///   - subscriptionIdentifier: The identifier of the subscription to purchase.
    ///   - includeProTier: Whether to include Pro tier products when looking up the subscription.
    func purchaseSubscription(with subscriptionIdentifier: String, includeProTier: Bool) async -> Result<PurchaseResult, AppStorePurchaseFlowError>

    /// Completes the subscription purchase by validating the transaction.
    ///
    /// - Parameters:
    ///   - transactionJWS: The JWS representation of the transaction to be validated.
    ///   - additionalParams: Optional additional parameters to send with the transaction validation request.
    /// - Returns: A `Result` containing either a `PurchaseUpdate` object on success or an `AppStorePurchaseFlowError` on failure.
    @discardableResult func completeSubscriptionPurchase(with transactionJWS: TransactionJWS, additionalParams: [String: String]?) async -> Result<PurchaseUpdate, AppStorePurchaseFlowError>

    /// Changes the subscription tier for a user who already has an active subscription.
    /// This method uses the existing account's externalID and bypasses the "check for active subscription" logic.
    ///
    /// - Parameter subscriptionIdentifier: The identifier of the new subscription tier to change to.
    /// - Returns: A `Result` containing the transaction JWS on success or an `AppStorePurchaseFlowError` on failure.
    func changeTier(to subscriptionIdentifier: String) async -> Result<TransactionJWS, AppStorePurchaseFlowError>
}

@available(macOS 12.0, iOS 15.0, *)
public final class DefaultAppStorePurchaseFlow: AppStorePurchaseFlow {
    private let subscriptionManager: any SubscriptionManager
    private let storePurchaseManager: any StorePurchaseManager
    private let appStoreRestoreFlow: any AppStoreRestoreFlow
    private let pendingTransactionHandler: PendingTransactionHandling?

    // Wide Event
    private let wideEvent: WideEventManaging

    public init(subscriptionManager: any SubscriptionManager,
                storePurchaseManager: any StorePurchaseManager,
                appStoreRestoreFlow: any AppStoreRestoreFlow,
                wideEvent: WideEventManaging,
                pendingTransactionHandler: PendingTransactionHandling? = nil
    ) {
        self.subscriptionManager = subscriptionManager
        self.storePurchaseManager = storePurchaseManager
        self.appStoreRestoreFlow = appStoreRestoreFlow
        self.wideEvent = wideEvent
        self.pendingTransactionHandler = pendingTransactionHandler
    }

    public func purchaseSubscription(with subscriptionIdentifier: String, includeProTier: Bool) async -> Result<PurchaseResult, AppStorePurchaseFlowError> {
        Logger.subscriptionAppStorePurchaseFlow.log("Purchasing Subscription")

        let subscriptionRestoreWideEventData = SubscriptionRestoreWideEventData(
            restorePlatform: .purchaseBackgroundTask,
            funnelName: "funnel_onpurchasecheck_multiple"
        )

        var externalID: String?
        var accountCreationDuration: WideEvent.MeasuredInterval?

        if let existingExternalID = await getExpiredSubscriptionID() {
            Logger.subscriptionAppStorePurchaseFlow.log("External ID retrieved from expired subscription")
            externalID = existingExternalID
        } else {
            Logger.subscriptionAppStorePurchaseFlow.log("Try to retrieve an expired Apple subscription or create a new one")
            subscriptionRestoreWideEventData.appleAccountRestoreDuration = WideEvent.MeasuredInterval.startingNow()
            wideEvent.startFlow(subscriptionRestoreWideEventData)
            // Try to restore an account from a past purchase
            switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
            case .success:
                Logger.subscriptionAppStorePurchaseFlow.log("An active subscription is already present")
                subscriptionRestoreWideEventData.appleAccountRestoreDuration?.complete()
                wideEvent.completeFlow(subscriptionRestoreWideEventData, status: .success, onComplete: { _, _ in })
                return .failure(.activeSubscriptionAlreadyPresent)
            case .failure(let error):
                subscriptionRestoreWideEventData.appleAccountRestoreDuration?.complete()
                subscriptionRestoreWideEventData.errorData = .init(error: error)
                wideEvent.completeFlow(subscriptionRestoreWideEventData, status: .failure, onComplete: { _, _ in })
                Logger.subscriptionAppStorePurchaseFlow.log("Failed to restore an account from a past purchase: \(String(describing: error), privacy: .public)")
                do {
                    var creationStart = WideEvent.MeasuredInterval.startingNow()
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
        switch await storePurchaseManager.purchaseSubscription(with: subscriptionIdentifier, externalID: externalID, includeProTier: includeProTier) {
        case .success(let transactionJWS):
            NotificationCenter.default.post(name: .userDidPurchaseSubscription, object: self)
            return .success((transactionJWS: transactionJWS, accountCreationDuration: accountCreationDuration))
        case .failure(let error):
            Logger.subscriptionAppStorePurchaseFlow.error("purchaseSubscription error: \(String(describing: error), privacy: .public)")

            await subscriptionManager.signOut(notifyUI: false)

            switch error {
            case .purchaseCancelledByUser:
                return .failure(.cancelledByUser)
            case .transactionPendingAuthentication:
                return .failure(.transactionPendingAuthentication)
            case .purchaseFailed(let underlyingError):
                return .failure(.purchaseFailed(underlyingError))
            default:
                return .failure(.purchaseFailed(error))
            }
        }
    }

    public func changeTier(to subscriptionIdentifier: String) async -> Result<TransactionJWS, AppStorePurchaseFlowError> {
        Logger.subscriptionAppStorePurchaseFlow.log("Changing Subscription Tier")

        // Get the externalID from the existing token (user already has an active subscription)
        let externalID: String
        do {
            let tokenContainer = try await subscriptionManager.getTokenContainer(policy: .localValid)
            externalID = tokenContainer.decodedAccessToken.externalID
            Logger.subscriptionAppStorePurchaseFlow.log("Retrieved externalID from existing subscription")
        } catch {
            Logger.subscriptionAppStorePurchaseFlow.error("Failed to get token container for tier change: \(String(describing: error), privacy: .public)")
            return .failure(.internalError(error))
        }

        // Make the purchase with the existing account's externalID
        // Always include Pro tier - tier change UI is only visible when Pro is enabled
        switch await storePurchaseManager.purchaseSubscription(with: subscriptionIdentifier, externalID: externalID, includeProTier: true) {
        case .success(let transactionJWS):
            NotificationCenter.default.post(name: .userDidPurchaseSubscription, object: self)
            return .success(transactionJWS)
        case .failure(let error):
            Logger.subscriptionAppStorePurchaseFlow.error("Tier change purchase error: \(String(describing: error), privacy: .public)")

            switch error {
            case .purchaseCancelledByUser:
                return .failure(.cancelledByUser)
            case .transactionPendingAuthentication:
                return .failure(.transactionPendingAuthentication)
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
                    pendingTransactionHandler?.handleSubscriptionActivated()
                    return .success(.completed)
                }
            } else {
                Logger.subscriptionAppStorePurchaseFlow.error("Subscription expired")
                return .failure(.purchaseFailed(AppStoreRestoreFlowError.subscriptionExpired))
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
