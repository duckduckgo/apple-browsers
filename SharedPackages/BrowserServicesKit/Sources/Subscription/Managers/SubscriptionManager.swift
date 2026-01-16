//
//  SubscriptionManager.swift
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
import Combine
import Common
import os.log
import Networking
import PixelKit

public enum SubscriptionManagerError: DDGError {
    /// The app has no `TokenContainer`
    case noTokenAvailable
    /// There was a failure wile retrieving, updating or creating the `TokenContainer`
    case errorRetrievingTokenContainer(error: Error?)

    case confirmationHasInvalidSubscription
    case noProductsFound

    public static func == (lhs: SubscriptionManagerError, rhs: SubscriptionManagerError) -> Bool {
        switch (lhs, rhs) {
        case (.errorRetrievingTokenContainer(let lhsError), .errorRetrievingTokenContainer(let rhsError)):
            return String(describing: lhsError) == String(describing: rhsError)
        case (.confirmationHasInvalidSubscription, .confirmationHasInvalidSubscription),
            (.noProductsFound, .noProductsFound),
            (.noTokenAvailable, .noTokenAvailable):
            return true
        default:
            return false
        }
    }

    public var description: String {
        switch self {
        case .noTokenAvailable: "No token available"
        case .errorRetrievingTokenContainer(error: let error): "Error retrieving token container: \(String(describing: error))"
        case .confirmationHasInvalidSubscription: "Confirmation has an invalid subscription"
        case .noProductsFound: "No products found"
        }
    }

    public static var errorDomain: String { "com.duckduckgo.subscription.SubscriptionManagerError" }

    public var errorCode: Int {
        switch self {
        case .noTokenAvailable: 12000
        case .errorRetrievingTokenContainer: 12001
        case .confirmationHasInvalidSubscription: 12002
        case .noProductsFound: 12003
        }
    }

    public var underlyingError: (any Error)? {
        switch self {
        case .errorRetrievingTokenContainer(error: let error):
            return error
        default:
            return nil
        }
    }
}

public enum SubscriptionPixelType: Equatable {
    case invalidRefreshToken
    case subscriptionIsActive
    case getTokensError(AuthTokensCachePolicy, Error)
    case invalidRefreshTokenSignedOut
    case invalidRefreshTokenRecovered
    case purchaseSuccessAfterPendingTransaction
    case pendingTransactionApproved

    public static func == (lhs: SubscriptionPixelType, rhs: SubscriptionPixelType) -> Bool {
        switch (lhs, rhs) {
        case (.invalidRefreshToken, .invalidRefreshToken),
            (.subscriptionIsActive, .subscriptionIsActive),
            (.invalidRefreshTokenSignedOut, .invalidRefreshTokenSignedOut),
            (.invalidRefreshTokenRecovered, .invalidRefreshTokenRecovered),
            (.getTokensError, .getTokensError),
            (.purchaseSuccessAfterPendingTransaction, .purchaseSuccessAfterPendingTransaction),
            (.pendingTransactionApproved, .pendingTransactionApproved):
            return true
        default:
            return false
        }
    }
}

public enum AuthVersion: String {
    // case v1 // removed
    case v2

    public static let key = "auth_version"
}

/// Pixels handler
public protocol SubscriptionPixelHandling {
    func handle(pixel: SubscriptionPixelType)
    func handle(pixel: KeychainManager.Pixel)
}

public protocol SubscriptionManager: SubscriptionTokenProvider, SubscriptionAuthenticationStateProvider {

    // Environment
    static func loadEnvironmentFrom(userDefaults: UserDefaults) -> SubscriptionEnvironment?
    static func save(subscriptionEnvironment: SubscriptionEnvironment, userDefaults: UserDefaults)
    var currentEnvironment: SubscriptionEnvironment { get }

    /// Tries to get an authentication token and the subscription
    func loadInitialData() async

    /// Retrieve the purchased subscription
    /// - Parameter cachePolicy: The cache policy, `remoteFirst` or `cacheFirst`
    /// - Returns: A `DuckDuckGoSubscription` if available, throws `SubscriptionEndpointServiceError.noData` if the subscription is not available or any other errors if the process failed at any point.
    @discardableResult func getSubscription(cachePolicy: SubscriptionCachePolicy) async throws -> DuckDuckGoSubscription

    /// - Returns: true is a subscription (expired or not) is present, false otherwise.
    func isSubscriptionPresent() -> Bool

    /// Tries to activate a subscription using a platform signature
    /// - Parameter lastTransactionJWSRepresentation: A platform signature coming from the AppStore
    /// - Returns: A subscription if found
    /// - Throws: An error if the access token is not available or something goes wrong in the api requests
    func getSubscriptionFrom(lastTransactionJWSRepresentation: String) async throws -> DuckDuckGoSubscription?

    /// If the user can purchase a subscription or not
    var hasAppStoreProductsAvailable: Bool { get }

    /// Publisher that emits a boolean value indicating whether the user can purchase through the App Store.
    var hasAppStoreProductsAvailablePublisher: AnyPublisher<Bool, Never> { get }
    func getProducts() async throws -> [GetProductsItem]
    func getTierProducts(region: String?, platform: String?) async throws -> GetTierProductsResponse

    @available(macOS 12.0, iOS 15.0, *) func storePurchaseManager() -> StorePurchaseManager

    /// Subscription feature related URL that matches current environment
    func url(for type: SubscriptionURL) -> URL

    /// Purchase page URL when launched as a result of intercepted `/pro` navigation.
    /// It is created based on current `SubscriptionURL.purchase` and inherits designated URL components from the source page that triggered redirect.
    func urlForPurchaseFromRedirect(redirectURLComponents: URLComponents, tld: TLD) -> URL

    func getCustomerPortalURL() async throws -> URL

    /// The user email
    var userEmail: String? { get }

    /// Sign out the user, clear and invalidate the access token and clear the subscription cache
    func signOut(notifyUI: Bool, userInitiated: Bool) async

    /// Removes the subscription cache, this will trigger a remote fetch the next time `getSubscription(...)` is called
    func clearSubscriptionCache()

    /// Confirm a purchase with a platform signature
    func confirmPurchase(signature: String, additionalParams: [String: String]?) async throws -> DuckDuckGoSubscription

    /// Closure called when an expired refresh token is detected and the Subscription login is invalid. An attempt to automatically recover it can be performed or the app can ask the user to do it manually
    typealias TokenRecoveryHandler = () async throws -> Void

    var currentStorefrontRegion: SubscriptionRegion { get }

    // MARK: - Features

    /// Returns the features available for the current subscription, a feature is enabled only if the user has the corresponding entitlement
    /// - Parameter forceRefresh: ignore subscription and token cache and re-download everything
    /// - Returns: An Array of SubscriptionFeature where each feature is enabled or disabled based on the user entitlements
    func currentSubscriptionFeatures(forceRefresh: Bool) async throws -> [SubscriptionEntitlement]
    func currentSubscriptionFeatures() async throws -> [Entitlement.ProductName]

    /// Whether a feature is included in the Subscription.
    /// This allows us to know if a feature is included in the current subscription.
    func isFeatureIncludedInSubscription(_ feature: SubscriptionEntitlement) async throws -> Bool

    /// Whether the feature is enabled for use.
    /// This is mostly useful post-purchases.
    func isFeatureEnabled(_ feature: Entitlement.ProductName) async throws -> Bool

    // MARK: - Token Management

    /// Get a token container accordingly to the policy
    /// - Parameter policy: The policy that will be used to get the token, it effects the tokens source and validity
    /// - Returns: The TokenContainer
    /// - Throws: A `SubscriptionManagerError`.
    ///     `noTokenAvailable` if the TokenContainer is not present.
    ///     `errorRetrievingTokenContainer(error:...)` in case of any error retrieving, refreshing or creating the TokenContainer, this can be caused by networking issues or keychain errors etc.
    @discardableResult
    func getTokenContainer(policy: AuthTokensCachePolicy) async throws -> TokenContainer

    /// Adopt a token provided by the FE during a Subscription purchase
    func adopt(accessToken: String, refreshToken: String) async throws

    /// Adopt a token provided by an external entity, typically the main app when this is used by the VPN
    func adopt(tokenContainer: TokenContainer) async throws

    /// Remove the stored token container and the legacy token
    func removeLocalAccount() throws

    /// Checks if the user is eligible for a free trial.
    func isUserEligibleForFreeTrial() -> Bool
}

// MARK: -  Utilities

extension SubscriptionManager {

    public func signOut(notifyUI: Bool) async {
        await signOut(notifyUI: notifyUI, userInitiated: false)
    }

    /// Checks whether the user is eligible to purchase the subscription, regardless of purchase platform.
    public var isSubscriptionPurchaseEligible: Bool {
        switch currentEnvironment.purchasePlatform {
        case .appStore:
            return hasAppStoreProductsAvailable
        case .stripe:
            return true
        }
    }

    public func currentSubscriptionFeatures() async throws -> [Entitlement.ProductName] {
        try await currentSubscriptionFeatures(forceRefresh: false).compactMap { subscriptionFeatureV2 in
            subscriptionFeatureV2.entitlement.product
        }
    }
}

// MARK: -  Default implementation

/// Single entry point for everything related to Subscription. This manager is disposable, every time something related to the environment changes this need to be recreated.
public final class DefaultSubscriptionManager: SubscriptionManager {

    var oAuthClient: any OAuthClient
    private let _storePurchaseManager: StorePurchaseManager?
    private let subscriptionEndpointService: SubscriptionEndpointService
    private let pixelHandler: SubscriptionPixelHandling
    public var tokenRecoveryHandler: TokenRecoveryHandler?
    public let currentEnvironment: SubscriptionEnvironment
    private let isInternalUserEnabled: () -> Bool
    private let userDefaults: UserDefaults
    private let hasAppStoreProductsAvailableSubject = PassthroughSubject<Bool, Never>()
    private var cancellables = Set<AnyCancellable>()
    private let wideEvent: WideEventManaging?
    private let isAuthV2WideEventEnabled: () -> Bool

    public init(storePurchaseManager: StorePurchaseManager? = nil,
                oAuthClient: any OAuthClient,
                userDefaults: UserDefaults,
                subscriptionEndpointService: SubscriptionEndpointService,
                subscriptionEnvironment: SubscriptionEnvironment,
                pixelHandler: SubscriptionPixelHandling,
                tokenRecoveryHandler: TokenRecoveryHandler? = nil,
                initForPurchase: Bool = true,
                isInternalUserEnabled: @escaping () -> Bool = { false },
                wideEvent: WideEventManaging? = nil,
                isAuthV2WideEventEnabled: @escaping () -> Bool = { false }) {
        self._storePurchaseManager = storePurchaseManager
        self.oAuthClient = oAuthClient
        self.userDefaults = userDefaults
        self.subscriptionEndpointService = subscriptionEndpointService
        self.currentEnvironment = subscriptionEnvironment
        self.pixelHandler = pixelHandler
        self.tokenRecoveryHandler = tokenRecoveryHandler
        self.isInternalUserEnabled = isInternalUserEnabled
        self.wideEvent = wideEvent
        self.isAuthV2WideEventEnabled = isAuthV2WideEventEnabled
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

    public var hasAppStoreProductsAvailable: Bool {
        guard let storePurchaseManager = _storePurchaseManager else { return false }
        return storePurchaseManager.areProductsAvailable
    }

    /// Publisher that emits a boolean value indicating whether the user can purchase through the App Store.
    /// The value is updated whenever the `areProductsAvailablePublisher` of the underlying StorePurchaseManager emits a new value.
    public var hasAppStoreProductsAvailablePublisher: AnyPublisher<Bool, Never> {
        hasAppStoreProductsAvailableSubject.eraseToAnyPublisher()
    }

    @available(macOS 12.0, iOS 15.0, *)
    public func storePurchaseManager() -> StorePurchaseManager {
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
        storePurchaseManager().areProductsAvailablePublisher
            .sink { [weak self] value in
                self?.hasAppStoreProductsAvailableSubject.send(value)
            }
            .store(in: &cancellables)

        Task {
            await storePurchaseManager().updateAvailableProducts()
        }
    }

    // MARK: - Subscription

    public func loadInitialData() async {
        Logger.subscription.log("Loading initial data...")

        do {
            _ = try? await getTokenContainer(policy: .localValid)
            let subscription = try await getSubscription(cachePolicy: .remoteFirst)
            Logger.subscription.log("Subscription is \(subscription.isActive ? "active" : "not active", privacy: .public)")
        } catch SubscriptionEndpointServiceError.noData {
            Logger.subscription.log("No Subscription available")
            clearSubscriptionCache()
        } catch {
            Logger.subscription.error("Failed to load initial subscription data: \(error, privacy: .public)")
        }
    }

    @discardableResult
    public func getSubscription(cachePolicy: SubscriptionCachePolicy) async throws -> DuckDuckGoSubscription {

        // NOTE: This is ugly, the subscription cache will be moved from the endpoint service to here and handled properly https://app.asana.com/0/0/1209015691872191

        guard isUserAuthenticated else {
            throw SubscriptionEndpointServiceError.noData
        }

        var subscription: DuckDuckGoSubscription

        switch cachePolicy {

        case .remoteFirst, .cacheFirst:
            if cachePolicy == .cacheFirst {
                // We skip ahead and try to get the cached subscription, useful with slow/no connections where we don't want to wait for a get token timeout
                do {
                    subscription = try await subscriptionEndpointService.getSubscription(accessToken: nil, cachePolicy: cachePolicy)
                    break
                } catch {}
            }

            var tokenContainer: TokenContainer
            do {
                tokenContainer = try await getTokenContainer(policy: .localValid)
            } catch SubscriptionManagerError.noTokenAvailable {
                throw SubscriptionEndpointServiceError.noData
            } catch {
                // Failed to get a valid token, fall back on cache
                subscription = try await subscriptionEndpointService.getSubscription(accessToken: nil, cachePolicy: .cacheFirst)
                break
            }
            subscription = try await subscriptionEndpointService.getSubscription(accessToken: tokenContainer.accessToken, cachePolicy: cachePolicy)
        }

        if subscription.isActive {
            pixelHandler.handle(pixel: .subscriptionIsActive)
        }

        return subscription
    }

    public func isSubscriptionPresent() -> Bool {
        subscriptionEndpointService.getCachedSubscription() != nil
    }

    public func getSubscriptionFrom(lastTransactionJWSRepresentation: String) async throws -> DuckDuckGoSubscription? {
        do {
            let tokenContainer = try await oAuthClient.activate(withPlatformSignature: lastTransactionJWSRepresentation)
            return try await subscriptionEndpointService.getSubscription(accessToken: tokenContainer.accessToken, cachePolicy: .remoteFirst)
        } catch SubscriptionEndpointServiceError.noData {
            return nil
        } catch {
            throw error
        }
    }

    public func getProducts() async throws -> [GetProductsItem] {
        try await subscriptionEndpointService.getProducts()
    }

    public func getTierProducts(region: String?, platform: String?) async throws -> GetTierProductsResponse {
        try await subscriptionEndpointService.getTierProducts(region: region, platform: platform)
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
        guard isUserAuthenticated else {
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
        do {
            let tokenContainer = try oAuthClient.currentTokenContainer()
            return tokenContainer != nil
        } catch {
            return cachedIsUserAuthenticated
        }
    }

    public var userEmail: String? {
        return (try? oAuthClient.currentTokenContainer())?.decodedAccessToken.email
    }

    var cachedUserEntitlements: [SubscriptionEntitlement] {
        userDefaults.userEntitlements
    }

    private func updateCachedUserEntitlements(_ newEntitlements: [SubscriptionEntitlement], userInitiated: Bool = false) {
        let currentCachedUserEntitlements = self.userDefaults.userEntitlements
        self.userDefaults.userEntitlements = newEntitlements

        // Send notification when entitlements change
        if !SubscriptionEntitlement.areEntitlementsEqual(currentCachedUserEntitlements, newEntitlements) {
            Logger.subscription.debug("Entitlements changed - New \(String(describing: newEntitlements)) Old \(String(describing: currentCachedUserEntitlements))")
            let payload = EntitlementsDidChangePayload(entitlements: newEntitlements)

            var userInfo = payload.notificationUserInfo
            userInfo[EntitlementsDidChangePayload.userInitiatedEntitlementChangeKey] = userInitiated
            NotificationCenter.default.post(name: .entitlementsDidChange, object: self, userInfo: userInfo)
        }
    }

    var cachedIsUserAuthenticated: Bool {
        userDefaults.isUserAuthenticated
    }

    private func updateCachedIsUserAuthenticated(_ newValue: Bool, userInitiated: Bool = false) {
        let currentCachedIsAuthenticated = self.userDefaults.isUserAuthenticated
        self.userDefaults.isUserAuthenticated = newValue

        // Send notification when the login changes
        switch (currentCachedIsAuthenticated, newValue) {
        case (false, true):
            Logger.subscription.debug("Login detected")
            NotificationCenter.default.post(name: .accountDidSignIn, object: self, userInfo: nil)
        case (true, false):
            Logger.subscription.debug("Logout detected")
            NotificationCenter.default.post(name: .accountDidSignOut, object: self, userInfo: nil)
        default:
            Logger.subscription.debug("Login state unchanged - Current: \(currentCachedIsAuthenticated), new: \(newValue)")
        }

        if newValue == false {
            self.updateCachedUserEntitlements([], userInitiated: userInitiated)
        }
    }

    @discardableResult public func getTokenContainer(policy: AuthTokensCachePolicy) async throws -> TokenContainer {
        Logger.subscription.debug("Get tokens \(policy.description, privacy: .public)")

        do {
            let resultTokenContainer = try await oAuthClient.getTokens(policy: policy)
            let newEntitlements = resultTokenContainer.decodedAccessToken.subscriptionEntitlements

            self.updateCachedUserEntitlements(newEntitlements)
            self.updateCachedIsUserAuthenticated(true)
            return resultTokenContainer
        } catch OAuthClientError.missingTokenContainer {
            // Expected when no tokens are available
            self.updateCachedUserEntitlements([])
            throw SubscriptionManagerError.noTokenAvailable
        } catch {
            pixelHandler.handle(pixel: .getTokensError(policy, error))

            switch error {

            case OAuthClientError.unknownAccount:

                Logger.subscription.error("Refresh failed, the account is unknown. Logging out...")
                await signOut(notifyUI: true, userInitiated: false)
                throw SubscriptionManagerError.noTokenAvailable

            case OAuthClientError.invalidTokenRequest:

                pixelHandler.handle(pixel: .invalidRefreshToken)
                Logger.subscription.error("Refresh failed, invalid token request")
                do {
                    let recoveredTokenContainer = try await attemptTokenRecovery()
                    pixelHandler.handle(pixel: .invalidRefreshTokenRecovered)
                    return recoveredTokenContainer
                } catch {
                    await signOut(notifyUI: false, userInitiated: false)
                    pixelHandler.handle(pixel: .invalidRefreshTokenSignedOut)
                    throw SubscriptionManagerError.noTokenAvailable
                }

            default:
                throw SubscriptionManagerError.errorRetrievingTokenContainer(error: error)
            }
        }
    }

    func attemptTokenRecovery() async throws -> TokenContainer {

        Logger.subscription.log("Attempting token recovery...")

        guard let tokenRecoveryHandler else {
            Logger.subscription.log("Recovery not possible, no handler configured.")
            throw SubscriptionManagerError.noTokenAvailable
        }

        try await tokenRecoveryHandler()

        guard let currentTokenContainer = try oAuthClient.currentTokenContainer(),
              !currentTokenContainer.decodedRefreshToken.isExpired() else {
            Logger.subscription.log("Recovery failed: the refresh token is missing or still expired after the recovery attempt.")
            throw SubscriptionManagerError.noTokenAvailable
        }
        return currentTokenContainer
    }

    public func adopt(accessToken: String, refreshToken: String) async throws {
        Logger.subscription.log("Adopting and decoding token container")
        let tokenContainer = try await oAuthClient.decode(accessToken: accessToken, refreshToken: refreshToken, refreshID: nil)
        try await adopt(tokenContainer: tokenContainer)
    }

    public func adopt(tokenContainer: TokenContainer) async throws {
        let adoptionID = UUID().uuidString

        if isAuthV2WideEventEnabled(), let wideEvent {
            let globalData = WideEventGlobalData(id: adoptionID)
            let data = AuthV2TokenAdoptionWideEventData(globalData: globalData)
            data.failingStep = .adoptingToken
            wideEvent.startFlow(data)
        }

        do {
            Logger.subscription.log("Adopting token container")

            try oAuthClient.adopt(tokenContainer: tokenContainer)

            if isAuthV2WideEventEnabled(), let wideEvent {
                wideEvent.updateFlow(globalID: adoptionID) { (event: inout AuthV2TokenAdoptionWideEventData) in
                    event.failingStep = .refreshingToken
                }
            }

            // It’s important to force refresh the token to immediately branch from the one received.
            // See discussion https://app.asana.com/0/1199230911884351/1208785842165508/f
            let refreshedTokenContainer = try await oAuthClient.getTokens(policy: .localForceRefresh)

            updateCachedIsUserAuthenticated(true)
            updateCachedUserEntitlements(refreshedTokenContainer.decodedAccessToken.subscriptionEntitlements)

            if isAuthV2WideEventEnabled(), let wideEvent, let data = wideEvent.getFlowData(AuthV2TokenAdoptionWideEventData.self, globalID: adoptionID) {
                data.failingStep = nil
                wideEvent.completeFlow(data, status: .success(reason: nil), onComplete: { _, _ in })
            }
        } catch {
            if isAuthV2WideEventEnabled(), let wideEvent, let data = wideEvent.getFlowData(AuthV2TokenAdoptionWideEventData.self, globalID: adoptionID) {
                data.errorData = WideEventErrorData(error: error)
                wideEvent.completeFlow(data, status: .failure, onComplete: { _, _ in })
            }

            throw error
        }
    }

    public func removeLocalAccount() throws {
        Logger.subscription.log("Removing local account")
            updateCachedIsUserAuthenticated(false)
        try oAuthClient.removeLocalAccount()
    }

    public func signOut(notifyUI: Bool, userInitiated: Bool) async {
        Logger.subscription.log("SignOut: Removing all traces of the subscription and account. Notify UI: \(notifyUI ? "true" : "false"), User Initiated: \(userInitiated ? "true" : "false")")

        try? await oAuthClient.logout()
        clearSubscriptionCache()

        if notifyUI {
                updateCachedIsUserAuthenticated(false, userInitiated: userInitiated)
        } else {
            // skipping cached setter for avoiding notification
            userDefaults.isUserAuthenticated = false
            userDefaults.userEntitlements = []
        }
    }

    public func confirmPurchase(signature: String, additionalParams: [String: String]?) async throws -> DuckDuckGoSubscription {
        Logger.subscription.log("Confirming Purchase...")
        let accessToken = try await getTokenContainer(policy: .localValid).accessToken
        let confirmation = try await subscriptionEndpointService.confirmPurchase(accessToken: accessToken,
                                                                                 signature: signature,
                                                                                 additionalParams: additionalParams)
        try await subscriptionEndpointService.ingestSubscription(confirmation.subscription)
        Logger.subscription.log("Purchase confirmed!")
        return confirmation.subscription
    }

    public var currentStorefrontRegion: SubscriptionRegion {
        switch currentEnvironment.purchasePlatform {
        case .appStore:
            if #available(macOS 12.0, iOS 15.0, *) {
                return storePurchaseManager().currentStorefrontRegion
            } else {
                return .usa
            }
        case .stripe:
            return .usa
        }
    }

    // MARK: - Features

    public func currentSubscriptionFeatures(forceRefresh: Bool) async throws -> [SubscriptionEntitlement] {
        guard isUserAuthenticated else { return [] }

        let availableFeatures: [SubscriptionEntitlement]

        if forceRefresh {
            let currentSubscription = try await getSubscription(cachePolicy: .remoteFirst)
            availableFeatures = currentSubscription.features ?? []
        } else {
            let currentSubscription = try await getSubscription(cachePolicy: .cacheFirst)
            availableFeatures = currentSubscription.features ?? []
        }

        return availableFeatures
    }

    public func isFeatureIncludedInSubscription(_ feature: SubscriptionEntitlement) async throws -> Bool {
        try await currentSubscriptionFeatures(forceRefresh: false).contains(feature)
    }

    public func isFeatureEnabled(_ feature: Entitlement.ProductName) async throws -> Bool {
        do {
            guard isUserAuthenticated else { return false }
            let tokenContainer = try await getTokenContainer(policy: .localValid)
            return tokenContainer.decodedAccessToken.subscriptionEntitlements.contains(feature.subscriptionEntitlement)
        } catch {
            // Fallback to the cached user entitlements in case of keychain reading error
            Logger.subscription.debug("Failed to read user entitlements from keychain: \(error, privacy: .public)")
            return self.cachedUserEntitlements.contains(feature.subscriptionEntitlement)
        }
    }

    /// Checks if the user is eligible for a free trial.
    ///
    /// Returns `true` for Stripe-based purchases (on all macOS versions)
    /// or delegates to the store purchase manager for App Store purchases (requires macOS 12.0+).
    ///
    /// - Returns:
    ///   - `true` for Stripe platform regardless of macOS version
    ///   - `storePurchaseManager().isUserEligibleForFreeTrial()` for App Store on macOS 12.0+
    ///   - `false` for App Store on macOS < 12.0
    public func isUserEligibleForFreeTrial() -> Bool {
        if currentEnvironment.purchasePlatform == .stripe {
            return true
        }
        guard #available(macOS 12.0, iOS 15.0, *) else { return false }
        return storePurchaseManager().isUserEligibleForFreeTrial()
    }

}

extension DefaultSubscriptionManager: SubscriptionTokenProvider {
    public func getAccessToken() async throws -> String {
        try await getTokenContainer(policy: .localValid).accessToken
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
        case .paidAIChat:
            return Entitlement(product: .paidAIChat)
        case .unknown:
            return Entitlement(product: .unknown)
        }
    }
}

fileprivate extension UserDefaults {

    private static let isUserAuthenticatedKey = "com.duckduckgo.subscription.isUserAuthenticated"
    var isUserAuthenticated: Bool {
        get {
            return bool(forKey: Self.isUserAuthenticatedKey)
        }
        set {
            set(newValue, forKey: Self.isUserAuthenticatedKey)
        }
    }

    private static let userEntitlementsKey = "com.duckduckgo.subscription.userEntitlements"
    var userEntitlements: [SubscriptionEntitlement] {
        get {
            guard let data = self.data(forKey: Self.userEntitlementsKey) else {
                return []
            }
            guard let entitlements = try? JSONDecoder().decode([SubscriptionEntitlement].self, from: data) else {
                assertionFailure("Error decoding user entitlements")
                Logger.subscription.fault("Error decoding user entitlements")
                return []
            }
            return entitlements
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue)  else {
                assertionFailure("Error encoding user entitlements")
                Logger.subscription.fault("Error encoding user entitlements")
                return
            }
            self.set(data, forKey: Self.userEntitlementsKey)
        }
    }
}
