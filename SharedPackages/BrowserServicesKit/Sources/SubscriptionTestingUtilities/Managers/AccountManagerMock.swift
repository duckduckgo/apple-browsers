//
//  AccountManagerMock.swift
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

public final class AccountManagerMock: AccountManager {
    public var delegate: AccountManagerKeychainAccessDelegate?
    public var accessToken: String?
    public var authToken: String?
    public var email: String?
    public var externalID: String?

    public var exchangeAuthTokenToAccessTokenResult: Result<String, Error>?
    public var fetchAccountDetailsResult: Result<AccountDetails, Error>?

    public var onStoreAuthToken: ((String) -> Void)?
    public var onStoreAccount: ((String, String?, String?) -> Void)?
    public var onFetchEntitlements: ((APICachePolicy) -> Void)?
    public var onExchangeAuthTokenToAccessToken: ((String) -> Void)?
    public var onFetchAccountDetails: ((String) -> Void)?
    public var onCheckForEntitlements: ((Double, Int) -> Bool)?

    public var storeAuthTokenCalled: Bool = false
    public var storeAccountCalled: Bool = false
    public var signOutCalled: Bool = false
    public var updateCacheWithEntitlementsCalled: Bool = false
    public var fetchEntitlementsCalled: Bool = false
    public var exchangeAuthTokenToAccessTokenCalled: Bool = false
    public var fetchAccountDetailsCalled: Bool = false
    public var checkForEntitlementsCalled: Bool = false

    public init() { }

    public func storeAuthToken(token: String) {
        storeAuthTokenCalled = true
        onStoreAuthToken?(token)
        self.authToken = token
    }

    public func storeAccount(token: String, email: String?, externalID: String?) {
        storeAccountCalled = true
        onStoreAccount?(token, email, externalID)
        self.accessToken = token
        self.email = email
        self.externalID = externalID
    }

    public func signOut(skipNotification: Bool) {
        signOutCalled = true
        self.authToken = nil
        self.accessToken = nil
        self.email = nil
        self.externalID = nil
    }

    public func signOut() {
        signOutCalled = true
        self.authToken = nil
        self.accessToken = nil
        self.email = nil
        self.externalID = nil
    }

    public func hasEntitlement(forProductName productName: Entitlement.ProductName, cachePolicy: APICachePolicy) async -> Result<Bool, Error> {
        return .success(true)
    }

    public func updateCache(with entitlements: [Entitlement]) {
        updateCacheWithEntitlementsCalled = true
    }

    public func fetchEntitlements(cachePolicy: APICachePolicy) async -> Result<[Entitlement], Error> {
        fetchEntitlementsCalled = true
        onFetchEntitlements?(cachePolicy)
        return .success([])
    }

    public func exchangeAuthTokenToAccessToken(_ authToken: String) async -> Result<String, Error> {
        exchangeAuthTokenToAccessTokenCalled = true
        onExchangeAuthTokenToAccessToken?(authToken)
        return exchangeAuthTokenToAccessTokenResult!
    }

    public func fetchAccountDetails(with accessToken: String) async -> Result<AccountDetails, Error> {
        fetchAccountDetailsCalled = true
        onFetchAccountDetails?(accessToken)
        return fetchAccountDetailsResult!
    }

    public func checkForEntitlements(wait waitTime: Double, retry retryCount: Int) async -> Bool {
        checkForEntitlementsCalled = true
        return onCheckForEntitlements!(waitTime, retryCount)
    }

    public func removeAccessToken() throws {
        accessToken = nil
    }
}
