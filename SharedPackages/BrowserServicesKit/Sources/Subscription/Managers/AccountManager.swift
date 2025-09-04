//
//  AccountManager.swift
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
import Common
import os.log

public protocol AccountManagerKeychainAccessDelegate: AnyObject {
    func accountManagerKeychainAccessFailed(accessType: AccountKeychainAccessType, error: any Error)
}

public protocol AccountManager {

    var delegate: AccountManagerKeychainAccessDelegate? { get set }
    /// The `accessToken` is long lasting and is used to authenticate API requests and VPN connections
    var accessToken: String? { get }
    /// The `authToken` is short lasting and is obtained when the user purchases the subscription, is immediately exchanged for a long lasting `accessToken`
    var authToken: String? { get }
    var email: String? { get }
    var externalID: String? { get }

    func storeAuthToken(token: String)
    func storeAccount(token: String, email: String?, externalID: String?)
    func signOut(skipNotification: Bool, userInitiated: Bool)
    func signOut()
    func removeAccessToken() throws

    // Entitlements
    func hasEntitlement(forProductName productName: Entitlement.ProductName, cachePolicy: APICachePolicy) async -> Result<Bool, Error>

    func updateCache(with entitlements: [Entitlement])
    @discardableResult func fetchEntitlements(cachePolicy: APICachePolicy) async -> Result<[Entitlement], Error>
    func exchangeAuthTokenToAccessToken(_ authToken: String) async -> Result<String, Error>

    typealias AccountDetails = (email: String?, externalID: String)
    func fetchAccountDetails(with accessToken: String) async -> Result<AccountDetails, Error>

    @discardableResult func checkForEntitlements(wait waitTime: Double, retry retryCount: Int) async -> Bool
}

extension AccountManager {

    public func hasEntitlement(forProductName productName: Entitlement.ProductName) async -> Result<Bool, Error> {
        await hasEntitlement(forProductName: productName, cachePolicy: .returnCacheDataElseLoad)
    }

    public func fetchEntitlements() async -> Result<[Entitlement], Error> {
        await fetchEntitlements(cachePolicy: .returnCacheDataElseLoad)
    }

    public var isUserAuthenticated: Bool { accessToken != nil }

    func signOut(skipNotification: Bool) {
        signOut(skipNotification: skipNotification, userInitiated: false)
    }

}

public final class DefaultAccountManager: AccountManager {

    private let storage: AccountStoring
    private let entitlementsCache: UserDefaultsCache<[Entitlement]>
    private let accessTokenStorage: SubscriptionTokenStoring
    private let subscriptionEndpointService: SubscriptionEndpointService
    private let authEndpointService: AuthEndpointService

    public weak var delegate: AccountManagerKeychainAccessDelegate?

    // MARK: - Initialisers

    public init(storage: AccountStoring = AccountKeychainStorage(),
                accessTokenStorage: SubscriptionTokenStoring,
                entitlementsCache: UserDefaultsCache<[Entitlement]>,
                subscriptionEndpointService: SubscriptionEndpointService,
                authEndpointService: AuthEndpointService) {
        self.storage = storage
        self.entitlementsCache = entitlementsCache
        self.accessTokenStorage = accessTokenStorage
        self.subscriptionEndpointService = subscriptionEndpointService
        self.authEndpointService = authEndpointService
    }

    // MARK: -

    public var authToken: String? {
        do {
            return try storage.getAuthToken()
        } catch {
            delegate?.accountManagerKeychainAccessFailed(accessType: .getAuthToken, error: error)
            return nil
        }
    }

    public var accessToken: String? {
        do {
            return try accessTokenStorage.getAccessToken()
        } catch {
            delegate?.accountManagerKeychainAccessFailed(accessType: .getAccessToken, error: error)
            return nil
        }
    }

    public var email: String? {
        do {
            return try storage.getEmail()
        } catch {
            delegate?.accountManagerKeychainAccessFailed(accessType: .getEmail, error: error)
            return nil
        }
    }

    public var externalID: String? {
        do {
            return try storage.getExternalID()
        } catch {
            delegate?.accountManagerKeychainAccessFailed(accessType: .getExternalID, error: error)
            return nil
        }
    }

    public func storeAuthToken(token: String) {
        Logger.subscription.info("[AccountManager] storeAuthToken")

        do {
            try storage.store(authToken: token)
        } catch {
            delegate?.accountManagerKeychainAccessFailed(accessType: .storeAuthToken, error: error)
        }
    }

    public func storeAccessToken(token: String) {
        Logger.subscription.info("[AccountManager] storeAccessToken")

        do {
            try accessTokenStorage.store(accessToken: token)
        } catch {
            delegate?.accountManagerKeychainAccessFailed(accessType: .storeAccessToken, error: error)
        }
    }

    public func storeAccount(token: String, email: String?, externalID: String?) {
        Logger.subscription.info("[AccountManager] storeAccount")

        do {
            try accessTokenStorage.store(accessToken: token)
        } catch {
            delegate?.accountManagerKeychainAccessFailed(accessType: .storeAccessToken, error: error)
        }

        do {
            try storage.store(email: email)
        } catch {
            delegate?.accountManagerKeychainAccessFailed(accessType: .storeEmail, error: error)
        }

        do {
            try storage.store(externalID: externalID)
        } catch {
            delegate?.accountManagerKeychainAccessFailed(accessType: .storeExternalID, error: error)
        }
        NotificationCenter.default.post(name: .accountDidSignIn, object: self, userInfo: nil)
    }

    public func signOut() {
        signOut(skipNotification: false, userInitiated: false)
    }

    public func signOut(skipNotification: Bool = false, userInitiated: Bool = false) {
        Logger.subscription.info("[AccountManager] signOut")

        do {
            try storage.clearAuthenticationState()
            try accessTokenStorage.removeAccessToken()
            subscriptionEndpointService.signOut()
            entitlementsCache.reset()
        } catch {
            delegate?.accountManagerKeychainAccessFailed(accessType: .clearAuthenticationData, error: error)
        }

        if !skipNotification {
            NotificationCenter.default.post(name: .accountDidSignOut, object: self, userInfo: nil)
        }
    }

    public func removeAccessToken() throws {
        try accessTokenStorage.removeAccessToken()
    }

    // MARK: -
    public func hasEntitlement(forProductName productName: Entitlement.ProductName, cachePolicy: APICachePolicy) async -> Result<Bool, Error> {
        switch await fetchEntitlements(cachePolicy: cachePolicy) {
        case .success(let entitlements):
            return .success(entitlements.compactMap { $0.product }.contains(productName))
        case .failure(let error):
            return .failure(error)
        }
    }

    private func fetchRemoteEntitlements() async -> Result<[Entitlement], Error> {
        guard let accessToken else {
            entitlementsCache.reset()
            return .success([])
        }

        switch await authEndpointService.validateToken(accessToken: accessToken) {
        case .success(let response):
            let entitlements = response.account.entitlements
            updateCache(with: entitlements)
            return .success(entitlements)

        case .failure(let error):
            Logger.subscription.error("[AccountManager] fetchEntitlements error: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    public func updateCache(with entitlements: [Entitlement]) {
        let cachedEntitlements: [Entitlement] = entitlementsCache.get() ?? []

        if Set(entitlements) != Set(cachedEntitlements) {
            if entitlements.isEmpty {
                entitlementsCache.reset()
            } else {
                entitlementsCache.set(entitlements)
            }
            let payload = EntitlementsDidChangePayload(entitlements: EntitlementsBridging.v2EntitlementsFrom(v1Entitlements: entitlements))
            NotificationCenter.default.post(name: .entitlementsDidChange, object: self, userInfo: payload.notificationUserInfo)
        }
    }

    public enum EntitlementsError: Error {
        case noAccessToken
        case noCachedData
    }

    @discardableResult
    public func fetchEntitlements(cachePolicy: APICachePolicy) async -> Result<[Entitlement], Error> {

        switch cachePolicy {
        case .reloadIgnoringLocalCacheData:
            return await fetchRemoteEntitlements()

        case .returnCacheDataElseLoad:
            if let cachedEntitlements: [Entitlement] = entitlementsCache.get() {
                return .success(cachedEntitlements)
            } else {
                return await fetchRemoteEntitlements()
            }
        }

    }

    public func exchangeAuthTokenToAccessToken(_ authToken: String) async -> Result<String, Error> {
        switch await authEndpointService.getAccessToken(token: authToken) {
        case .success(let response):
            return .success(response.accessToken)
        case .failure(let error):
            Logger.subscription.error("[AccountManager] exchangeAuthTokenToAccessToken error: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    public func fetchAccountDetails(with accessToken: String) async -> Result<AccountDetails, Error> {
        switch await authEndpointService.validateToken(accessToken: accessToken) {
        case .success(let response):
            return .success(AccountDetails(email: response.account.email, externalID: response.account.externalID))
        case .failure(let error):
            Logger.subscription.error("[AccountManager] fetchAccountDetails error: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    @discardableResult
    public func checkForEntitlements(wait waitTime: Double, retry retryCount: Int) async -> Bool {
        var count = 0
        var hasEntitlements = false

        repeat {
            switch await fetchEntitlements() {
            case .success(let entitlements):
                hasEntitlements = !entitlements.isEmpty
            case .failure:
                hasEntitlements = false
            }

            if hasEntitlements {
                break
            } else {
                count += 1
                try? await Task.sleep(seconds: waitTime)
            }
        } while !hasEntitlements && count < retryCount

        return hasEntitlements
    }
}

extension Task where Success == Never, Failure == Never {
    static func sleep(seconds: Double) async throws {
        let duration = UInt64(seconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: duration)
    }
}
