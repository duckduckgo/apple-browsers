//
//  AppStoreRestoreFlow.swift
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

public enum AppStoreRestoreFlowError: Swift.Error, Equatable {
    case missingAccountOrTransactions
    case pastTransactionAuthenticationError
    case failedToObtainAccessToken
    case failedToFetchAccountDetails
    case failedToFetchSubscriptionDetails
    case subscriptionExpired(accountDetails: RestoredAccountDetails)
}

public struct RestoredAccountDetails: Equatable {
    let authToken: String
    let accessToken: String
    let externalID: String
    let email: String?
}

@available(macOS 12.0, iOS 15.0, *)
public protocol AppStoreRestoreFlow {
    @discardableResult func restoreAccountFromPastPurchase() async -> Result<Void, AppStoreRestoreFlowError>
}

@available(macOS 12.0, iOS 15.0, *)
public final class DefaultAppStoreRestoreFlow: AppStoreRestoreFlow {
    private let accountManager: AccountManager
    private let storePurchaseManager: StorePurchaseManager
    private let subscriptionEndpointService: SubscriptionEndpointService
    private let authEndpointService: AuthEndpointService

    public init(accountManager: any AccountManager,
                storePurchaseManager: any StorePurchaseManager,
                subscriptionEndpointService: any SubscriptionEndpointService,
                authEndpointService: any AuthEndpointService) {
        self.accountManager = accountManager
        self.storePurchaseManager = storePurchaseManager
        self.subscriptionEndpointService = subscriptionEndpointService
        self.authEndpointService = authEndpointService
    }

    @discardableResult
    public func restoreAccountFromPastPurchase() async -> Result<Void, AppStoreRestoreFlowError> {

        // Clear subscription Cache
        subscriptionEndpointService.signOut()

        Logger.subscription.info("[AppStoreRestoreFlow] restoreAccountFromPastPurchase")

        guard let lastTransactionJWSRepresentation = await storePurchaseManager.mostRecentTransaction() else {
            Logger.subscription.error("[AppStoreRestoreFlow] Error: missingAccountOrTransactions")
            return .failure(.missingAccountOrTransactions)
        }

        // Do the store login to get short-lived token
        let authToken: String

        switch await authEndpointService.storeLogin(signature: lastTransactionJWSRepresentation) {
        case .success(let response):
            authToken = response.authToken
        case .failure:
            Logger.subscription.error("[AppStoreRestoreFlow] Error: pastTransactionAuthenticationError")
            return .failure(.pastTransactionAuthenticationError)
        }

        let accessToken: String
        let email: String?
        let externalID: String

        switch await accountManager.exchangeAuthTokenToAccessToken(authToken) {
        case .success(let exchangedAccessToken):
            accessToken = exchangedAccessToken
        case .failure:
            Logger.subscription.error("[AppStoreRestoreFlow] Error: failedToObtainAccessToken")
            return .failure(.failedToObtainAccessToken)
        }

        switch await accountManager.fetchAccountDetails(with: accessToken) {
        case .success(let accountDetails):
            email = accountDetails.email
            externalID = accountDetails.externalID
        case .failure:
            Logger.subscription.error("[AppStoreRestoreFlow] Error: failedToFetchAccountDetails")
            return .failure(.failedToFetchAccountDetails)
        }

        var isSubscriptionActive = false

        switch await subscriptionEndpointService.getSubscription(accessToken: accessToken, cachePolicy: .reloadIgnoringLocalCacheData) {
        case .success(let subscription):
            isSubscriptionActive = subscription.isActive
        case .failure:
            Logger.subscription.error("[AppStoreRestoreFlow] Error: failedToFetchSubscriptionDetails")
            return .failure(.failedToFetchSubscriptionDetails)
        }

        if isSubscriptionActive {
            accountManager.storeAuthToken(token: authToken)
            accountManager.storeAccount(token: accessToken, email: email, externalID: externalID)
            return .success(())
        } else {
            let details = RestoredAccountDetails(authToken: authToken, accessToken: accessToken, externalID: externalID, email: email)
            Logger.subscription.error("[AppStoreRestoreFlow] Error: subscriptionExpired")
            return .failure(.subscriptionExpired(accountDetails: details))
        }
    }
}
