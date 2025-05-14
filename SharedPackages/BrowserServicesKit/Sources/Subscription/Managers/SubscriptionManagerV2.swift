//
//  SubscriptionManagerV2.swift
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
import Common
import os.log
import Networking

public enum SubscriptionManagerError: Error, Equatable, LocalizedError {
    case tokenUnavailable(error: Error?)
    case confirmationHasInvalidSubscription
    case noProductsFound
    case tokenRefreshFailed(error: Error?)

    public static func == (lhs: SubscriptionManagerError, rhs: SubscriptionManagerError) -> Bool {
        switch (lhs, rhs) {
        case (.tokenUnavailable(let lhsError), .tokenUnavailable(let rhsError)):
            return lhsError?.localizedDescription == rhsError?.localizedDescription
        case (.tokenRefreshFailed(let lhsError), .tokenRefreshFailed(let rhsError)):
            return lhsError?.localizedDescription == rhsError?.localizedDescription
        case (.confirmationHasInvalidSubscription, .confirmationHasInvalidSubscription),
            (.noProductsFound, .noProductsFound):
            return true
        default:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .tokenUnavailable(error: let error):
            "Token unavailable: \(String(describing: error))"
        case .confirmationHasInvalidSubscription:
            "Confirmation has an invalid subscription"
        case .noProductsFound:
            "No products found"
        case .tokenRefreshFailed(error: let error):
            "Token is not refreshable: \(String(describing: error))"
        }
    }
}

public enum SubscriptionPixelType {
    case invalidRefreshToken
    case migrationSucceeded
    case migrationFailed(Error)
    case subscriptionIsActive
    case getTokensError(AuthTokensCachePolicy, Error)
}

/// Pixels handler
public protocol SubscriptionPixelHandler {
    func handle(pixelType: SubscriptionPixelType)
}

public protocol SubscriptionManagerV2: SubscriptionTokenProvider, SubscriptionAuthenticationStateProvider, SubscriptionAuthV1toV2Bridge {

    // Environment
    static func loadEnvironmentFrom(userDefaults: UserDefaults) -> SubscriptionEnvironment?
    static func save(subscriptionEnvironment: SubscriptionEnvironment, userDefaults: UserDefaults)
    var currentEnvironment: SubscriptionEnvironment { get }

    /// Tries to get an authentication token and request the subscription
    func loadInitialData() async

    // Subscription
    @discardableResult func getSubscription(cachePolicy: SubscriptionCachePolicy) async throws -> PrivacyProSubscription

    func isSubscriptionPresent() -> Bool

    /// Tries to activate a subscription using a platform signature
    /// - Parameter lastTransactionJWSRepresentation: A platform signature coming from the AppStore
    /// - Returns: A subscription if found
    /// - Throws: An error if the access token is not available or something goes wrong in the api requests
    func getSubscriptionFrom(lastTransactionJWSRepresentation: String) async throws -> PrivacyProSubscription?

    var canPurchase: Bool { get }
    func getProducts() async throws -> [GetProductsItem]

    @available(macOS 12.0, iOS 15.0, *) func storePurchaseManager() -> StorePurchaseManagerV2

    /// Subscription feature related URL that matches current environment
    func url(for type: SubscriptionURL) -> URL

    /// Purchase page URL when launched as a result of intercepted `/pro` navigation.
    /// It is created based on current `SubscriptionURL.purchase` and inherits designated URL components from the source page that triggered redirect.
    func urlForPurchaseFromRedirect(redirectURLComponents: URLComponents, tld: TLD) -> URL

    func getCustomerPortalURL() async throws -> URL

    // User
    var userEmail: String? { get }

    /// Sign out the user and clear all the tokens and subscription cache
    func signOut(notifyUI: Bool) async

    func clearSubscriptionCache()

    /// Confirm a purchase with a platform signature
    func confirmPurchase(signature: String, additionalParams: [String: String]?) async throws -> PrivacyProSubscription

    /// Closure called when an expired refresh token is detected and the Subscription login is invalid. An attempt to automatically recover it can be performed or the app can ask the user to do it manually
    typealias TokenRecoveryHandler = () async throws -> Void

    // MARK: - Features

    /// Get the current subscription features
    /// A feature is based on an entitlement and can be enabled or disabled
    /// A user cant have an entitlement without the feature, if a user is missing an entitlement the feature is disabled
    func currentSubscriptionFeatures(forceRefresh: Bool) async throws -> [SubscriptionFeatureV2]

    /// True if the feature can be used by the user, false otherwise
    func isFeatureAvailableForUser(_ entitlement: SubscriptionEntitlement) async throws -> Bool

    // MARK: - Token Management

    /// Get a token container accordingly to the policy
    /// - Parameter policy: The policy that will be used to get the token, it effects the tokens source and validity
    /// - Returns: The TokenContainer
    /// - Throws: A `SubscriptionManagerError`.
    ///     `tokenRefreshFailed` if the token cannot be refreshed, typically due to an expired refresh token.
    ///     `tokenUnavailable` if the token is not available for the reason specified by the underlying error.
    @discardableResult
    func getTokenContainer(policy: AuthTokensCachePolicy) async throws -> TokenContainer

    /// Exchange access token v1 for a access token v2
    /// - Parameter tokenV1: The Auth v1 access token
    /// - Returns: An auth v2 TokenContainer
    func exchange(tokenV1: String) async throws -> TokenContainer

    func adopt(accessToken: String, refreshToken: String) async throws

    func adopt(tokenContainer: TokenContainer) async throws

    /// Remove the stored token container and the legacy token
    func removeLocalAccount()
}

/// Single entry point for everything related to Subscription. This manager is disposable, every time something related to the environment changes this need to be recreated.
public final class DefaultSubscriptionManagerV2: SubscriptionManagerV2 {

    var oAuthClient: any OAuthClient
    private let _storePurchaseManager: StorePurchaseManagerV2?
    private let subscriptionEndpointService: SubscriptionEndpointServiceV2
    private let pixelHandler: SubscriptionPixelHandler
    public var tokenRecoveryHandler: TokenRecoveryHandler?
    public let currentEnvironment: SubscriptionEnvironment
    private let isInternalUserEnabled: () -> Bool
    private var v1MigrationNeeded: Bool = true
    private let legacyAccountStorage: AccountKeychainStorage?

    public init(storePurchaseManager: StorePurchaseManagerV2? = nil,
                oAuthClient: any OAuthClient,
                subscriptionEndpointService: SubscriptionEndpointServiceV2,
                subscriptionEnvironment: SubscriptionEnvironment,
                pixelHandler: SubscriptionPixelHandler,
                tokenRecoveryHandler: TokenRecoveryHandler? = nil,
                initForPurchase: Bool = true,
                legacyAccountStorage: AccountKeychainStorage? = nil,
                isInternalUserEnabled: @escaping () -> Bool =  { false }) {
        self._storePurchaseManager = storePurchaseManager
        self.oAuthClient = oAuthClient
        self.subscriptionEndpointService = subscriptionEndpointService
        self.currentEnvironment = subscriptionEnvironment
        self.pixelHandler = pixelHandler
        self.tokenRecoveryHandler = tokenRecoveryHandler
        self.isInternalUserEnabled = isInternalUserEnabled
        self.legacyAccountStorage = legacyAccountStorage
        if initForPurchase {
            switch currentEnvironment.purchasePlatform {
            case .appStore:
                if #available(macOS 12.0, iOS 15.0, *) {
                    setupForAppStore()
                } else {
                    assertionFailure("Trying to setup AppStore where not supported")
                }
            case .stripe:
                break
            }
        }
    }

    public var canPurchase: Bool {
        guard let storePurchaseManager = _storePurchaseManager else { return false }
        return storePurchaseManager.areProductsAvailable
    }

    @available(macOS 12.0, iOS 15.0, *)
    public func storePurchaseManager() -> StorePurchaseManagerV2 {
        return _storePurchaseManager!
    }

    // MARK: Load and Save SubscriptionEnvironment

    static private let subscriptionEnvironmentStorageKey = "com.duckduckgo.subscription.environment"
    static public func loadEnvironmentFrom(userDefaults: UserDefaults) -> SubscriptionEnvironment? {
        if let savedData = userDefaults.object(forKey: Self.subscriptionEnvironmentStorageKey) as? Data {
            let decoder = JSONDecoder()
            if let loadedData = try? decoder.decode(SubscriptionEnvironment.self, from: savedData) {
                return loadedData
            }
        }
        return nil
    }

    static public func save(subscriptionEnvironment: SubscriptionEnvironment, userDefaults: UserDefaults) {
        let encoder = JSONEncoder()
        if let encodedData = try? encoder.encode(subscriptionEnvironment) {
            userDefaults.set(encodedData, forKey: Self.subscriptionEnvironmentStorageKey)
        }
    }

    // MARK: - Environment

    @available(macOS 12.0, iOS 15.0, *) private func setupForAppStore() {
        Task {
            await storePurchaseManager().updateAvailableProducts()
        }
    }

    // MARK: - Subscription

    func migrateAuthV1toAuthV2IfNeeded() async {

        guard v1MigrationNeeded, // stops multiple attempts in a session, even in case of unrecoverable failures
        isUserAuthenticated == false else { // Already migrated
            return
        }

        // Attempting V1 token migration
        do {
            try await oAuthClient.migrateV1Token()
            pixelHandler.handle(pixelType: .migrationSucceeded)
            v1MigrationNeeded = false

            // we want only a subscription that has been generated by AuthV2
            clearSubscriptionCache()

            Logger.subscription.log("V1 token migration completed")
        } catch OAuthClientError.authMigrationNotPerformed {
            Logger.subscription.log("V1 token migration not needed")
        } catch {
            Logger.subscription.error("Failed to migrate V1 token: \(error, privacy: .public)")
            pixelHandler.handle(pixelType: .migrationFailed(error))
            switch error {
            case OAuthServiceError.authAPIError(let code) where code ==  OAuthRequest.BodyErrorCode.invalidToken:
                // Case where the token is not valid anymore, probably because the BE deleted the account: https://app.asana.com/0/1205842942115003/1209427500692943/f
                v1MigrationNeeded = false
                await signOut(notifyUI: true)
            default:
                break
            }
        }
    }

    public func loadInitialData() async {
        Logger.subscription.log("Loading initial data...")
        do {
            let subscription = try await getSubscription(cachePolicy: .reloadIgnoringLocalCacheData)
            Logger.subscription.log("Subscription is \(subscription.isActive ? "active" : "not active", privacy: .public)")
        } catch SubscriptionEndpointServiceError.noData {
            Logger.subscription.log("No Subscription available")
            clearSubscriptionCache()
        } catch {
            Logger.subscription.error("Failed to load initial subscription data: \(error, privacy: .public)")
        }
    }

    @discardableResult
    public func getSubscription(cachePolicy: SubscriptionCachePolicy) async throws -> PrivacyProSubscription {
        guard await isUserAuthenticated() else {
            throw SubscriptionEndpointServiceError.noData
        }

        var subscription: PrivacyProSubscription
        // NOTE: This is ugly, the subscription cache will be moved from the endpoint service to here and handled properly https://app.asana.com/0/0/1209015691872191
        switch cachePolicy {
        case .reloadIgnoringLocalCacheData:
            let tokenContainer = try await getTokenContainer(policy: .localValid)
            subscription = try await subscriptionEndpointService.getSubscription(accessToken: tokenContainer.accessToken,
                                                                                 cachePolicy: cachePolicy)
        case .returnCacheDataElseLoad:
            if let tokenContainer = try? await getTokenContainer(policy: .localValid) {
                subscription = try await subscriptionEndpointService.getSubscription(accessToken: tokenContainer.accessToken,
                                                                                     cachePolicy: .returnCacheDataElseLoad)
            } else {
                subscription = try await getSubscription(cachePolicy: .returnCacheDataDontLoad)
            }
        case .returnCacheDataDontLoad:
            subscription = try await subscriptionEndpointService.getSubscription(accessToken: "",
                                                                                 cachePolicy: .returnCacheDataDontLoad)
        }

        if subscription.isActive {
            pixelHandler.handle(pixelType: .subscriptionIsActive)
        }
        return subscription
    }

    public func isSubscriptionPresent() -> Bool {
        subscriptionEndpointService.getCachedSubscription() != nil
    }

    public func getSubscriptionFrom(lastTransactionJWSRepresentation: String) async throws -> PrivacyProSubscription? {
        do {
            let tokenContainer = try await oAuthClient.activate(withPlatformSignature: lastTransactionJWSRepresentation)
            return try await subscriptionEndpointService.getSubscription(accessToken: tokenContainer.accessToken, cachePolicy: .reloadIgnoringLocalCacheData)
        } catch SubscriptionEndpointServiceError.noData {
            return nil
        } catch {
            throw error
        }
    }

    public func getProducts() async throws -> [GetProductsItem] {
        try await subscriptionEndpointService.getProducts()
    }

    public func clearSubscriptionCache() {
        subscriptionEndpointService.clearSubscription()
    }

    // MARK: - URLs

    public func url(for type: SubscriptionURL) -> URL {
        if let customBaseSubscriptionURL = currentEnvironment.customBaseSubscriptionURL,
           isInternalUserEnabled() {
            return type.subscriptionURL(withCustomBaseURL: customBaseSubscriptionURL, environment: currentEnvironment.serviceEnvironment)
        }

        return type.subscriptionURL(environment: currentEnvironment.serviceEnvironment)
    }

    public func urlForPurchaseFromRedirect(redirectURLComponents: URLComponents, tld: TLD) -> URL {
        let defaultPurchaseURL = url(for: .purchase)

        if var purchaseURLComponents = URLComponents(url: defaultPurchaseURL, resolvingAgainstBaseURL: true) {

            purchaseURLComponents.addingSubdomain(from: redirectURLComponents, tld: tld)
            purchaseURLComponents.addingPort(from: redirectURLComponents)
            purchaseURLComponents.addingFragment(from: redirectURLComponents)
            purchaseURLComponents.addingQueryItems(from: redirectURLComponents)

            return purchaseURLComponents.url ?? defaultPurchaseURL
        }

        return defaultPurchaseURL
    }

    public func getCustomerPortalURL() async throws -> URL {
        guard await isUserAuthenticated() else {
            throw SubscriptionEndpointServiceError.noData
        }

        let tokenContainer = try await getTokenContainer(policy: .localValid)
        // Get Stripe Customer Portal URL and update the model
        let serviceResponse = try await subscriptionEndpointService.getCustomerPortalURL(accessToken: tokenContainer.accessToken, externalID: tokenContainer.decodedAccessToken.externalID)
        guard let url = URL(string: serviceResponse.customerPortalUrl) else {
            throw SubscriptionEndpointServiceError.noData
        }
        return url
    }

    // MARK: - User
    public var isUserAuthenticated: Bool {
        return (try? oAuthClient.currentTokenContainer())?.accessToken != nil
    }

    private func isUserAuthenticated() async -> Bool {
        let tokenContainer = try? await getTokenContainer(policy: .local)
        return tokenContainer != nil
    }

    public var userEmail: String? {
        return (try? oAuthClient.currentTokenContainer())?.decodedAccessToken.email
    }

    // MARK: -

    @discardableResult public func getTokenContainer(policy: AuthTokensCachePolicy) async throws -> TokenContainer {
        Logger.subscription.debug("Get tokens \(policy.description, privacy: .public)")

        do {
            let currentCachedTokenContainer = try oAuthClient.currentTokenContainer()
            let currentCachedEntitlements = currentCachedTokenContainer?.decodedAccessToken.subscriptionEntitlements

            await migrateAuthV1toAuthV2IfNeeded()

            let resultTokenContainer = try await oAuthClient.getTokens(policy: policy)
            let newEntitlements = resultTokenContainer.decodedAccessToken.subscriptionEntitlements

            // Send "accountDidSignIn" notification when login changes
            if currentCachedTokenContainer == nil {
                Logger.subscription.debug("New login detected")
                NotificationCenter.default.post(name: .accountDidSignIn, object: self, userInfo: nil)
            }

            // Send notification when entitlements change
            if !SubscriptionEntitlement.areEntitlementsEqual(currentCachedEntitlements, newEntitlements) {
                Logger.subscription.debug("Entitlements changed - New \(newEntitlements) Old \(String(describing: currentCachedEntitlements))")

                // TMP: Convert to Entitlement (authV1)
                let entitlements = newEntitlements.map { $0.entitlement }
                NotificationCenter.default.post(name: .entitlementsDidChange, object: self, userInfo: [UserDefaultsCacheKey.subscriptionEntitlements: entitlements])
            }

            return resultTokenContainer
        } catch OAuthClientError.missingTokenContainer {
            // Expected when no tokens are available
            throw SubscriptionManagerError.tokenUnavailable(error: OAuthClientError.missingTokenContainer)
        } catch {
            pixelHandler.handle(pixelType: .getTokensError(policy, error))

            switch error {

            case OAuthClientError.unknownAccount:
                Logger.subscription.error("Refresh failed, the account is unknown. Logging out...")
                await signOut(notifyUI: true)
                throw SubscriptionManagerError.tokenUnavailable(error: error)

            case OAuthClientError.refreshTokenExpired,
                OAuthClientError.invalidTokenRequest:
                do {
                    return try await attemptTokenRecovery()
                } catch {
                    throw SubscriptionManagerError.tokenUnavailable(error: error)
                }

            default:
                throw SubscriptionManagerError.tokenUnavailable(error: error)
            }
        }
    }

    func attemptTokenRecovery() async throws -> TokenContainer {
        guard let tokenRecoveryHandler else {
            throw SubscriptionManagerError.tokenUnavailable(error: nil)
        }

        Logger.subscription.log("The refresh token is expired, attempting subscription recovery...")
        pixelHandler.handle(pixelType: .invalidRefreshToken)
        await signOut(notifyUI: false)

        try await tokenRecoveryHandler()

        return try await getTokenContainer(policy: .local)
    }

    public func exchange(tokenV1: String) async throws -> TokenContainer {
        let tokenContainer = try await oAuthClient.exchange(accessTokenV1: tokenV1)
        NotificationCenter.default.post(name: .accountDidSignIn, object: self, userInfo: nil)
        return tokenContainer
    }

    public func adopt(accessToken: String, refreshToken: String) async throws {
        Logger.subscription.log("Adopting and decoding token container")
        let tokenContainer = try await oAuthClient.decode(accessToken: accessToken, refreshToken: refreshToken)
        try await adopt(tokenContainer: tokenContainer)
    }

    public func adopt(tokenContainer: TokenContainer) async throws {
        Logger.subscription.log("Adopting token container")
        oAuthClient.adopt(tokenContainer: tokenContainer)
        // It’s important to force refresh the token to immediately branch from the one received.
        // See discussion https://app.asana.com/0/1199230911884351/1208785842165508/f
        _ = try await oAuthClient.getTokens(policy: .localForceRefresh)
        NotificationCenter.default.post(name: .accountDidSignIn, object: self, userInfo: nil)
    }

    public func removeLocalAccount() {
        Logger.subscription.log("Removing local account")
        oAuthClient.removeLocalAccount()
    }

    public func signOut(notifyUI: Bool) async {
        Logger.subscription.log("SignOut: Removing all traces of the subscription and account")
        try? await oAuthClient.logout()
        clearSubscriptionCache()
        if notifyUI {
            Logger.subscription.log("SignOut: Notifying the UI")
            NotificationCenter.default.post(name: .accountDidSignOut, object: self, userInfo: nil)
        }
        Logger.subscription.log("Removing V1 Account")
        try? legacyAccountStorage?.clearAuthenticationState()
    }

    public func confirmPurchase(signature: String, additionalParams: [String: String]?) async throws -> PrivacyProSubscription {
        Logger.subscription.log("Confirming Purchase...")
        let accessToken = try await getTokenContainer(policy: .localValid).accessToken
        let confirmation = try await subscriptionEndpointService.confirmPurchase(accessToken: accessToken,
                                                                                 signature: signature,
                                                                                 additionalParams: additionalParams)
        try await subscriptionEndpointService.ingestSubscription(confirmation.subscription)
        Logger.subscription.log("Purchase confirmed!")
        return confirmation.subscription
    }

    // MARK: - Features

    /// Returns the features available for the current subscription, a feature is enabled only if the user has the corresponding entitlement
    /// - Parameter forceRefresh: ignore subscription and token cache and re-download everything
    /// - Returns: An Array of SubscriptionFeature where each feature is enabled or disabled based on the user entitlements
    public func currentSubscriptionFeatures(forceRefresh: Bool) async throws -> [SubscriptionFeatureV2] {
        guard await isUserAuthenticated() else { return [] }

        var userEntitlements: [SubscriptionEntitlement]
        var availableFeatures: [SubscriptionEntitlement]
        if forceRefresh {
            let tokenContainer = try await getTokenContainer(policy: .localForceRefresh) // Refresh entitlements if requested
            let currentSubscription = try await getSubscription(cachePolicy: .reloadIgnoringLocalCacheData)
            userEntitlements = tokenContainer.decodedAccessToken.subscriptionEntitlements // What the user has access to
            availableFeatures = currentSubscription.features ?? [] // what the subscription is capable to provide
        } else {
            let currentSubscription = try? await getSubscription(cachePolicy: .returnCacheDataElseLoad)
            let tokenContainer = try? await getTokenContainer(policy: .local)
            userEntitlements = tokenContainer?.decodedAccessToken.subscriptionEntitlements ?? []
            availableFeatures = currentSubscription?.features ?? []
        }

        let result: [SubscriptionFeatureV2] = availableFeatures.compactMap({ featureEntitlement in
            guard featureEntitlement != .unknown else { return nil }
            let enabled = userEntitlements.contains(featureEntitlement)
            return SubscriptionFeatureV2(entitlement: featureEntitlement, isAvailableForUser: enabled)
        })
        Logger.subscription.log("""
                User entitlements: \(userEntitlements, privacy: .public)
                Available Features: \(availableFeatures, privacy: .public)
                Subscription features: \(result, privacy: .public)
            """)
        return result
    }

    public func isFeatureAvailableForUser(_ entitlement: SubscriptionEntitlement) async throws -> Bool {
        guard await isUserAuthenticated() else { return false }

        let currentFeatures = try await currentSubscriptionFeatures(forceRefresh: false)
        return currentFeatures.contains { feature in
            feature.entitlement == entitlement && feature.isAvailableForUser
        }
    }
}

extension DefaultSubscriptionManagerV2: SubscriptionTokenProvider {
    public func getAccessToken() async throws -> String {
        try await getTokenContainer(policy: .localValid).accessToken
    }

    public func removeAccessToken() {
        removeLocalAccount()
    }
}

extension SubscriptionEntitlement {

    var entitlement: Entitlement {
        switch self {
        case .networkProtection:
            return Entitlement(product: .networkProtection)
        case .dataBrokerProtection:
            return Entitlement(product: .dataBrokerProtection)
        case .identityTheftRestoration:
            return Entitlement(product: .identityTheftRestoration)
        case .identityTheftRestorationGlobal:
            return Entitlement(product: .identityTheftRestorationGlobal)
        case .unknown:
            return Entitlement(product: .unknown)
        }
    }
}
