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

@available(macOS 12.0, iOS 15.0, *)
public protocol AppStorePurchaseFlow {
    typealias TransactionJWS = String
    func purchaseSubscription(with subscriptionIdentifier: String, emailAccessToken: String?) async -> Result<AppStorePurchaseFlow.TransactionJWS, AppStorePurchaseFlowError>

    /// Completes the subscription purchase by validating the transaction.
      ///
      /// - Parameters:
      ///   - transactionJWS: The JWS representation of the transaction to be validated.
      ///   - additionalParams: Optional additional parameters to send with the transaction validation request.
      /// - Returns: A `Result` containing either a `PurchaseUpdate` object on success or an `AppStorePurchaseFlowError` on failure.
      @discardableResult
      func completeSubscriptionPurchase(
          with transactionJWS: TransactionJWS,
          additionalParams: [String: String]?
      ) async -> Result<PurchaseUpdate, AppStorePurchaseFlowError>
  }

  @available(macOS 12.0, iOS 15.0, *)
  public extension AppStorePurchaseFlow {

      /// Completes the subscription purchase by validating the transaction without additional parameters.
      ///
      /// This is a convenience method that calls the main `completeSubscriptionPurchase(with:additionalParams:)` method
      /// with `nil` as the value for `additionalParams`.
      ///
      /// - Parameters:
      ///   - transactionJWS: The JWS representation of the transaction to be validated.
      /// - Returns: A `Result` containing either a `PurchaseUpdate` object on success or an `AppStorePurchaseFlowError` on failure.
      func completeSubscriptionPurchase(
          with transactionJWS: TransactionJWS
      ) async -> Result<PurchaseUpdate, AppStorePurchaseFlowError> {
          await completeSubscriptionPurchase(with: transactionJWS, additionalParams: nil)
      }
  }

@available(macOS 12.0, iOS 15.0, *)
public final class DefaultAppStorePurchaseFlow: AppStorePurchaseFlow {
    private let subscriptionEndpointService: SubscriptionEndpointService
    private let storePurchaseManager: StorePurchaseManager
    private let accountManager: AccountManager
    private let appStoreRestoreFlow: AppStoreRestoreFlow
    private let authEndpointService: AuthEndpointService

    public init(subscriptionEndpointService: any SubscriptionEndpointService,
                storePurchaseManager: any StorePurchaseManager,
                accountManager: any AccountManager,
                appStoreRestoreFlow: any AppStoreRestoreFlow,
                authEndpointService: any AuthEndpointService) {
        self.subscriptionEndpointService = subscriptionEndpointService
        self.storePurchaseManager = storePurchaseManager
        self.accountManager = accountManager
        self.appStoreRestoreFlow = appStoreRestoreFlow
        self.authEndpointService = authEndpointService
    }

    public func purchaseSubscription(with subscriptionIdentifier: String, emailAccessToken: String?) async -> Result<TransactionJWS, AppStorePurchaseFlowError> {
        Logger.subscription.info("[AppStorePurchaseFlow] purchaseSubscription")
        let externalID: String

        // If the current account is a third party expired account, we want to purchase and attach subs to it
        if let existingExternalID = await getExpiredSubscriptionID() {
            externalID = existingExternalID

        // Otherwise, try to retrieve an expired Apple subscription or create a new one
        } else {
            // Check for past transactions most recent
            switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
            case .success:
                Logger.subscription.info("[AppStorePurchaseFlow] purchaseSubscription -> restoreAccountFromPastPurchase: activeSubscriptionAlreadyPresent")
                return .failure(.activeSubscriptionAlreadyPresent)
            case .failure(let error):
                Logger.subscription.info("[AppStorePurchaseFlow] purchaseSubscription -> restoreAccountFromPastPurchase: \(error.localizedDescription, privacy: .public)")
                switch error {
                case .subscriptionExpired(let expiredAccountDetails):
                    externalID = expiredAccountDetails.externalID
                    accountManager.storeAuthToken(token: expiredAccountDetails.authToken)
                    accountManager.storeAccount(token: expiredAccountDetails.accessToken, email: expiredAccountDetails.email, externalID: expiredAccountDetails.externalID)
                default:
                    switch await authEndpointService.createAccount(emailAccessToken: emailAccessToken) {
                    case .success(let response):
                        externalID = response.externalID

                        if case let .success(accessToken) = await accountManager.exchangeAuthTokenToAccessToken(response.authToken),
                           case let .success(accountDetails) = await accountManager.fetchAccountDetails(with: accessToken) {
                            accountManager.storeAuthToken(token: response.authToken)
                            accountManager.storeAccount(token: accessToken, email: accountDetails.email, externalID: accountDetails.externalID)
                        }
                    case .failure(let error):
                        Logger.subscription.error("[AppStorePurchaseFlow] createAccount error: \(error.localizedDescription, privacy: .public)")
                        return .failure(.accountCreationFailed(error))
                    }
                }
            }
        }

        // Make the purchase
        switch await storePurchaseManager.purchaseSubscription(with: subscriptionIdentifier, externalID: externalID) {
        case .success(let transactionJWS):
            return .success(transactionJWS)
        case .failure(let error):
            Logger.subscription.error("[AppStorePurchaseFlow] purchaseSubscription error: \(error.localizedDescription, privacy: .public)")
            accountManager.signOut(skipNotification: true)
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

        // Clear subscription Cache
        subscriptionEndpointService.signOut()

        Logger.subscription.info("[AppStorePurchaseFlow] completeSubscriptionPurchase")

        guard let accessToken = accountManager.accessToken else { return .failure(.missingEntitlements) }

        let result = await callWithRetries(retry: 5, wait: 2.0) {
            switch await subscriptionEndpointService.confirmPurchase(accessToken: accessToken, signature: transactionJWS, additionalParams: additionalParams) {
            case .success(let confirmation):
                subscriptionEndpointService.updateCache(with: confirmation.subscription)
                accountManager.updateCache(with: confirmation.entitlements)
                return true
            case .failure:
                return false
            }
        }

        return result ? .success(PurchaseUpdate.completed) : .failure(.missingEntitlements)
    }

    private func callWithRetries(retry retryCount: Int, wait waitTime: Double, conditionToCheck: () async -> Bool) async -> Bool {
        var count = 0
        var successful = false

        repeat {
            successful = await conditionToCheck()

            if successful {
                break
            } else {
                count += 1
                try? await Task.sleep(seconds: waitTime)
            }
        } while !successful && count < retryCount

        return successful
    }

    private func getExpiredSubscriptionID() async -> String? {
        guard accountManager.isUserAuthenticated,
              let externalID = accountManager.externalID,
              let token = accountManager.accessToken
        else { return nil }

        let subscriptionInfo = await subscriptionEndpointService.getSubscription(accessToken: token, cachePolicy: .reloadIgnoringLocalCacheData)

        // Only return an externalID if the subscription is expired
        // To prevent creating multiple subscriptions in the same account
        if case .success(let subscription) = subscriptionInfo,
           !subscription.isActive,
            subscription.platform != .apple {
            return externalID
        }
        return nil
    }
}
