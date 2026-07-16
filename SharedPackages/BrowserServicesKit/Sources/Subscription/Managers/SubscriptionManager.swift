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
import FoundationExtensions
import os.log
import Networking
import PixelKit

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

    /// Retrieve the purchased subscription.
    /// - Parameter forceRefresh: When `true`, skips the cache and fetches the subscription from the remote backend. When `false`, returns the cached subscription if available, otherwise fetches remotely.
    /// - Returns: The subscription if available, or `nil` if no subscription exists on the backend.
    /// - Throws: `SubscriptionManagerError.noTokenAvailable` if the user is not authenticated. `SubscriptionManagerError.noLocalSubscription` if the token is invalid and no cached subscription is available.
    /// - Note: This method may post `.subscriptionDidChange` notifications from an arbitrary async context. Subscribers must dispatch to the main thread if needed (e.g. `.receive(on: DispatchQueue.main)`).
    @discardableResult func getSubscription(forceRefresh: Bool) async throws -> DuckDuckGoSubscription?

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
    func getTierProducts(region: String?, platform: String?) async throws -> GetTierProductsResponse

    /// Returns subscription tier options (plans and pricing) for the appropriate platform.
    func subscriptionTierOptions(includeProTier: Bool) async -> Result<SubscriptionTierOptions, Error>

    @available(iOS 15.0, *) func storePurchaseManager() -> StorePurchaseManager

    /// Subscription feature related URL that matches current environment
    func url(for type: SubscriptionURL) -> URL

    /// Purchase page URL when launched as a result of intercepted `/pro` navigation.
    /// It is created based on current `SubscriptionURL.purchase` and inherits designated URL components from the source page that triggered redirect.
    func urlForPurchaseFromRedirect(redirectURLComponents: URLComponents, tld: TLD) -> URL

    func getCustomerPortalURL() async throws -> URL

    /// The user email
    var userEmail: String? { get }

    /// Returns a non-mutating snapshot of the locally stored account state.
    /// This does not refresh tokens, update caches, or fall back to cached authentication state.
    func localAccountSnapshot() -> LocalSubscriptionAccountSnapshot

    /// Sign out the user, clear and invalidate the access token and clear the subscription cache
    func signOut(notifyUI: Bool, userInitiated: Bool) async

    /// Removes the subscription cache, this will trigger a remote fetch the next time `getSubscription(...)` is called
    func clearSubscriptionCache()

    /// Ingests a subscription by enriching it with tier features, caching it, and posting a change notification.
    func ingestSubscription(_ subscription: DuckDuckGoSubscription) async throws -> DuckDuckGoSubscription

    /// Confirm a purchase with a platform signature
    func confirmPurchase(signature: String, additionalParams: [String: String]?) async throws -> DuckDuckGoSubscription

    /// Closure called when an expired refresh token is detected and the Subscription login is invalid. An attempt to automatically recover it can be performed or the app can ask the user to do it manually
    typealias TokenRecoveryHandler = () async throws -> Void

    var currentStorefrontRegion: SubscriptionRegion { get }

    // MARK: - Features

    /// Returns the features available for the current subscription, a feature is enabled only if the user has the corresponding entitlement.
    /// - Parameter forceRefresh: When `true`, ignores the subscription and token cache and re-downloads everything.
    /// - Returns: The subscription entitlements, or an empty array if no subscription is available.
    func currentSubscriptionFeatures(forceRefresh: Bool) async throws -> [SubscriptionEntitlement]

    /// Whether a feature is included in the Subscription.
    /// This allows us to know if a feature is included in the current subscription.
    func isFeatureIncludedInSubscription(_ feature: SubscriptionEntitlement) async throws -> Bool

    /// Whether the feature is enabled for use.
    /// This is mostly useful post-purchases.
    func isFeatureEnabled(_ feature: SubscriptionEntitlement) async throws -> Bool

    /// Returns the enabled status of all entitlements in a single token fetch.
    /// This is more efficient than calling `isFeatureEnabled` multiple times.
    func getAllEntitlementStatus() async -> EntitlementStatus

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

    /// Convenience for ``getSubscription(forceRefresh:)`` that returns the cached subscription when available.
    @discardableResult
    public func getSubscription() async throws -> DuckDuckGoSubscription? {
        try await getSubscription(forceRefresh: false)
    }

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
}

// MARK: -  Default implementation

/// Deduplicates concurrent async calls that share the same key, so only one in-flight
/// request runs at a time per key. Subsequent callers suspend and receive the same result.
actor SubscriptionRequestCoalescer {
    private enum FetchMode: Hashable {
        case cached
        case forceRefresh
    }

    // Keyed by FetchMode. Presence signals "work is in flight"; the array holds joiners waiting
    // for the result. Using continuations instead of Task.value prevents joiner cancellation
    // from propagating to the shared work or to other joiners.
    private var inFlight: [FetchMode: [CheckedContinuation<DuckDuckGoSubscription?, Error>]] = [:]

    /// If work for `forceRefresh` is already in flight, suspends until it completes and returns
    /// its result. Otherwise, runs `work`, resolves all waiting joiners, and returns the result.
    /// Cancelling any individual joiner does not affect the shared work or other joiners.
    func coalesce(forceRefresh: Bool, work: @Sendable @escaping () async throws -> DuckDuckGoSubscription?) async throws -> DuckDuckGoSubscription? {
        let mode: FetchMode = forceRefresh ? .forceRefresh : .cached
        if inFlight[mode] != nil {
            return try await withCheckedThrowingContinuation { continuation in
                inFlight[mode]?.append(continuation)
            }
        }

        inFlight[mode] = []

        let result: Result<DuckDuckGoSubscription?, Error>
        do {
            result = .success(try await work())
        } catch {
            result = .failure(error)
        }

        let waiters = inFlight.removeValue(forKey: mode) ?? []
        for continuation in waiters {
            continuation.resume(with: result)
        }
        return try result.get()
    }
}

/// Single entry point for everything related to Subscription. This manager is disposable, every time something related to the environment changes this need to be recreated.
public final class DefaultSubscriptionManager: SubscriptionManager {

    var oAuthClient: any OAuthClient
    private let _storePurchaseManager: StorePurchaseManager?
    private let subscriptionEndpointService: SubscriptionEndpointService
    private let subscriptionCachingService: SubscriptionCachingService
    private let pixelHandler: SubscriptionPixelHandling
    public var tokenRecoveryHandler: TokenRecoveryHandler?
    public let currentEnvironment: SubscriptionEnvironment
    private let isInternalUserEnabled: () -> Bool
    private let userDefaults: UserDefaults
    private let hasAppStoreProductsAvailableSubject = PassthroughSubject<Bool, Never>()
    private var cancellables = Set<AnyCancellable>()
    private let requestCoalescer = SubscriptionRequestCoalescer()
    private let wideEvent: WideEventManaging?
    private let isAuthV2WideEventEnabled: () -> Bool
    private let authV2TokenRefreshInstrumentation: AuthV2TokenRefreshInstrumenting?
    private let tierOptionsProvider: SubscriptionTierOptionsProviding

    public init(storePurchaseManager: StorePurchaseManager? = nil,
                oAuthClient: any OAuthClient,
                userDefaults: UserDefaults,
                subscriptionEndpointService: SubscriptionEndpointService,
                subscriptionCachingService: SubscriptionCachingService = DefaultSubscriptionCachingService(),
                subscriptionEnvironment: SubscriptionEnvironment,
                pixelHandler: SubscriptionPixelHandling,
                tokenRecoveryHandler: TokenRecoveryHandler? = nil,
                initForPurchase: Bool = true,
                isInternalUserEnabled: @escaping () -> Bool = { false },
                wideEvent: WideEventManaging? = nil,
                isAuthV2WideEventEnabled: @escaping () -> Bool = { false },
                authV2TokenRefreshInstrumentation: AuthV2TokenRefreshInstrumenting? = nil,
                tierOptionsProvider: SubscriptionTierOptionsProviding? = nil) {
        self._storePurchaseManager = storePurchaseManager
        self.oAuthClient = oAuthClient
        self.userDefaults = userDefaults
        self.subscriptionEndpointService = subscriptionEndpointService
        self.subscriptionCachingService = subscriptionCachingService
        self.currentEnvironment = subscriptionEnvironment
        self.pixelHandler = pixelHandler
        self.tokenRecoveryHandler = tokenRecoveryHandler
        self.isInternalUserEnabled = isInternalUserEnabled
        self.wideEvent = wideEvent
        self.isAuthV2WideEventEnabled = isAuthV2WideEventEnabled
        self.authV2TokenRefreshInstrumentation = authV2TokenRefreshInstrumentation
        self.tierOptionsProvider = tierOptionsProvider ?? DefaultSubscriptionTierOptionsProvider(
            subscriptionEnvironmentPlatform: subscriptionEnvironment.purchasePlatform,
            storePurchaseManager: storePurchaseManager,
            subscriptionEndpointService: subscriptionEndpointService
        )
        if initForPurchase {
            switch currentEnvironment.purchasePlatform {
            case .appStore:
                setupForAppStore()
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

    @available(iOS 15.0, *)
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

    @available(iOS 15.0, *) private func setupForAppStore() {
        storePurchaseManager().areProductsAvailablePublisher
            .sink { [weak self] value in
                self?.hasAppStoreProductsAvailableSubject.send(value)
            }
            .store(in: &cancellables)

        Task {
            await storePurchaseManager().updateAvailableProducts()
        }
    }

    // MARK: - Subscription Retrieval and Caching

    public func loadInitialData() async {
        Logger.subscription.log("Loading initial data...")

        do {
            if let subscription = try await getSubscription(forceRefresh: true) {
                Logger.subscription.log("Subscription is \(subscription.isActive ? "active" : "not active", privacy: .public)")
            } else {
                Logger.subscription.log("No Subscription available")
            }
        } catch SubscriptionManagerError.noTokenAvailable {
            Logger.subscription.log("No Subscription available")
            subscriptionCachingService.reset()
        } catch {
            Logger.subscription.error("Failed to load initial subscription data: \(error, privacy: .public)")
        }
    }

    /// Returns the cached subscription if available, firing the isActive pixel as a side effect.
    /// When no cache exists, throws `fallbackError` so callers propagate the appropriate error.
    private func cachedSubscriptionOrThrow(_ fallbackError: Error) async throws -> DuckDuckGoSubscription {
        guard let cached = await subscriptionCachingService.get() else {
            throw fallbackError
        }
        if cached.isActive {
            pixelHandler.handle(pixel: .subscriptionIsActive)
            pixelHandler.handle(pixel: .osDistributionActiveSubscription)
        }
        return cached
    }

    @discardableResult
    public func getSubscription(forceRefresh: Bool = false) async throws -> DuckDuckGoSubscription? {
        try await requestCoalescer.coalesce(forceRefresh: forceRefresh) { [self] in
            try await fetchSubscription(forceRefresh: forceRefresh)
        }
    }

    /// The actual subscription-fetching logic, invoked at most once per `forceRefresh` value
    /// at any given time thanks to `requestCoalescer`.
    private func fetchSubscription(forceRefresh: Bool) async throws -> DuckDuckGoSubscription? {

        var subscription: DuckDuckGoSubscription

        // Return cached subscription when available and refresh not forced
        if !forceRefresh,
            let cachedSubscription = await subscriptionCachingService.get() {
            subscription = cachedSubscription
        } else {
            let previousSubscription = await subscriptionCachingService.get()

            // Obtain a valid token for the remote request
            var tokenContainer: TokenContainer
            do {
                tokenContainer = try await getTokenContainer(policy: .localValid)
            } catch SubscriptionManagerError.noTokenAvailable {
                subscriptionCachingService.reset()
                throw SubscriptionManagerError.noTokenAvailable
            } catch {
                // Token refresh failed — fall back to cache if available
                return try await cachedSubscriptionOrThrow(SubscriptionManagerError.noLocalSubscription)
            }

            // Fetch subscription from backend
            let remoteSubscription: DuckDuckGoSubscription
            do {
                remoteSubscription = try await subscriptionEndpointService.getSubscription(accessToken: tokenContainer.accessToken)
            } catch SubscriptionEndpointServiceError.noData {
                // No subscription on backend — clear cache and notify if state changed
                subscriptionCachingService.reset()
                if previousSubscription != nil {
                    NotificationCenter.default.post(name: .subscriptionDidChange, object: self, userInfo: nil)
                }
                return nil
            } catch {
                // Transient error (network failure, HTTP 500, etc.) — fall back to cache if available
                return try await cachedSubscriptionOrThrow(error)
            }

            // Enrich with features
            let finalSubscription: DuckDuckGoSubscription
            do {
                finalSubscription = try await enrichSubscriptionWithFeatures(remoteSubscription)
            } catch {
                // Tier-features endpoint failed — fall back to cache if available
                return try await cachedSubscriptionOrThrow(error)
            }

            // Update cache
            await subscriptionCachingService.set(finalSubscription)

            // Notify only if the subscription actually changed
            if finalSubscription != previousSubscription {
                NotificationCenter.default.post(name: .subscriptionDidChange, object: self, userInfo: [UserDefaultsCacheKey.subscription: finalSubscription])
            }
            subscription = finalSubscription
        }

        if subscription.isActive {
            pixelHandler.handle(pixel: .subscriptionIsActive)
            pixelHandler.handle(pixel: .osDistributionActiveSubscription)
        }
        return subscription
    }

    public func isSubscriptionPresent() -> Bool {
        subscriptionCachingService.isPresent
    }

    public func ingestSubscription(_ subscription: DuckDuckGoSubscription) async throws -> DuckDuckGoSubscription {
        let enrichedSubscription: DuckDuckGoSubscription
        do {
            enrichedSubscription = try await enrichSubscriptionWithFeatures(subscription)
        } catch {
            // Enrichment failed (e.g. transient tier-features error) — cache the raw subscription
            // so isSubscriptionPresent() stays truthful for a caller that just confirmed a purchase.
            await subscriptionCachingService.set(subscription)
            NotificationCenter.default.post(name: .subscriptionDidChange, object: self, userInfo: [UserDefaultsCacheKey.subscription: subscription])
            throw error
        }
        await subscriptionCachingService.set(enrichedSubscription)
        NotificationCenter.default.post(name: .subscriptionDidChange, object: self, userInfo: [UserDefaultsCacheKey.subscription: enrichedSubscription])
        return enrichedSubscription
    }

    public func getSubscriptionFrom(lastTransactionJWSRepresentation: String) async throws -> DuckDuckGoSubscription? {
        do {
            let tokenContainer = try await oAuthClient.activate(withPlatformSignature: lastTransactionJWSRepresentation)
            let remoteSubscription = try await subscriptionEndpointService.getSubscription(accessToken: tokenContainer.accessToken)
            return try await ingestSubscription(remoteSubscription)
        } catch SubscriptionEndpointServiceError.noData {
            return nil
        } catch {
            throw error
        }
    }

    public func getTierProducts(region: String?, platform: String?) async throws -> GetTierProductsResponse {
        try await subscriptionEndpointService.getTierProducts(region: region, platform: platform)
    }

    public func subscriptionTierOptions(includeProTier: Bool) async -> Result<SubscriptionTierOptions, Error> {
        let subscription = try? await getSubscription(forceRefresh: false)
        return await tierOptionsProvider.subscriptionTierOptions(includeProTier: includeProTier, currentSubscription: subscription)
    }

    public func clearSubscriptionCache() {
        subscriptionCachingService.reset()
    }

    /// Enriches a subscription with tier features fetched from the backend.
    private func enrichSubscriptionWithFeatures(_ subscription: DuckDuckGoSubscription) async throws -> DuckDuckGoSubscription {
        Logger.subscription.log("Getting features for subscription: \(subscription.productId, privacy: .public)")
        let featuresResponse = try await subscriptionEndpointService.getSubscriptionTierFeatures(for: [subscription.productId])
        let features = featuresResponse.features[subscription.productId]?.map { $0.product } ?? []
        var enrichedSubscription = subscription
        enrichedSubscription.features = features
        return enrichedSubscription
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
            throw SubscriptionManagerError.noTokenAvailable
        }

        let tokenContainer = try await getTokenContainer(policy: .localValid)
        // Get Stripe Customer Portal URL and update the model
        let serviceResponse = try await subscriptionEndpointService.getCustomerPortalURL(accessToken: tokenContainer.accessToken, externalID: tokenContainer.decodedAccessToken.externalID)
        guard let url = URL(string: serviceResponse.customerPortalUrl) else {
            throw SubscriptionManagerError.invalidPortalURL
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

    public func localAccountSnapshot() -> LocalSubscriptionAccountSnapshot {
        do {
            guard let tokenContainer = try oAuthClient.currentTokenContainer() else {
                return LocalSubscriptionAccountSnapshot(tokenState: .missing, entitlements: [])
            }

            return LocalSubscriptionAccountSnapshot(
                tokenState: .present,
                entitlements: tokenContainer.decodedAccessToken.subscriptionEntitlements
            )
        } catch {
            return LocalSubscriptionAccountSnapshot(tokenState: .readError, entitlements: nil)
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
        Logger.subscriptionTokensManagement.debug("Get tokens \(policy.description, privacy: .public)")

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
            pixelHandler.handle(pixel: SubscriptionPixelType.getTokensError(policy, error))
            Logger.subscriptionTokensManagement.error("Getting token \(policy, privacy: .public) failed: \(error, privacy: .public)")

            switch error {
            case OAuthClientError.unknownAccount:
                await signOut(notifyUI: true, userInitiated: false)
                throw SubscriptionManagerError.noTokenAvailable

            case OAuthClientError.invalidTokenRequest:
                pixelHandler.handle(pixel: .invalidRefreshToken)
                do {
                    let recoveredTokenContainer = try await attemptTokenRecovery()
                    pixelHandler.handle(pixel: .invalidRefreshTokenRecovered)
                    authV2TokenRefreshInstrumentation?.completeInvalidTokenRecovery(outcome: .succeeded, error: nil)
                    return recoveredTokenContainer
                } catch SubscriptionManagerError.tokenRecoveryNotAttempted {
                    // No restore ran (no handler, or the platform can't restore): record the refresh
                    // as a failure whose recovery was never attempted, keeping its invalid-token error.
                    await signOut(notifyUI: false, userInitiated: false)
                    pixelHandler.handle(pixel: .invalidRefreshTokenSignedOut)
                    authV2TokenRefreshInstrumentation?.completeInvalidTokenRecovery(outcome: .notAttempted, error: nil)
                    throw SubscriptionManagerError.noTokenAvailable
                } catch {
                    // A restore ran but did not yield a valid token.
                    await signOut(notifyUI: false, userInitiated: false)
                    pixelHandler.handle(pixel: .invalidRefreshTokenSignedOut)
                    authV2TokenRefreshInstrumentation?.completeInvalidTokenRecovery(outcome: .failed, error: error)
                    throw SubscriptionManagerError.noTokenAvailable
                }

            default:
                throw SubscriptionManagerError.errorRetrievingTokenContainer(error: error)
            }
        }
    }

    func attemptTokenRecovery() async throws -> TokenContainer {

        Logger.subscriptionTokensManagement.log("Attempting token recovery...")

        guard let tokenRecoveryHandler else {
            Logger.subscription.log("Recovery not possible, no handler configured.")
            throw SubscriptionManagerError.tokenRecoveryNotAttempted
        }

        try await tokenRecoveryHandler()

        guard let currentTokenContainer = try oAuthClient.currentTokenContainer(),
              !currentTokenContainer.decodedRefreshToken.isExpired() else {
            Logger.subscriptionTokensManagement.log("Recovery failed: the refresh token is missing or still expired after the recovery attempt.")
            throw SubscriptionManagerError.noTokenAvailable
        }
        return currentTokenContainer
    }

    public func adopt(accessToken: String, refreshToken: String) async throws {
        Logger.subscriptionTokensManagement.log("Adopting and decoding token container")
        let tokenContainer = try await oAuthClient.decode(accessToken: accessToken, refreshToken: refreshToken, refreshID: nil)
        // This entry point is the subscription page email-restore flow.
        try await adopt(tokenContainer: tokenContainer, source: .webRestore)
    }

    public func adopt(tokenContainer: TokenContainer) async throws {
        try await adopt(tokenContainer: tokenContainer, source: nil)
    }

    public func adopt(tokenContainer: TokenContainer, source: AuthV2TokenAdoptionWideEventData.AdoptionSource?) async throws {
        let adoptionID = UUID().uuidString

        if isAuthV2WideEventEnabled(), let wideEvent {
            let globalData = WideEventGlobalData(id: adoptionID)
            let data = AuthV2TokenAdoptionWideEventData(globalData: globalData)
            data.failingStep = .adoptingToken
            data.adoptionSource = source
            wideEvent.startFlow(data)
        }

        do {
            Logger.subscriptionTokensManagement.log("Adopting token container")

            try oAuthClient.adopt(tokenContainer: tokenContainer)

            if isAuthV2WideEventEnabled(), let wideEvent {
                wideEvent.updateFlow(globalID: adoptionID) { (event: inout AuthV2TokenAdoptionWideEventData) in
                    event.failingStep = .refreshingToken
                }
            }

            // It’s important to force refresh the token to immediately branch from the one received.
            // See discussion https://app.asana.com/0/1199230911884351/1208785842165508/f
            let refreshedTokenContainer = try await oAuthClient.getTokens(policy: .localForceRefresh, trigger: .tokenAdoption)

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
        Logger.subscriptionTokensManagement.log("Removing local account")
            updateCachedIsUserAuthenticated(false)
        try oAuthClient.removeLocalAccount()
    }

    public func signOut(notifyUI: Bool, userInitiated: Bool) async {
        Logger.subscriptionTokensManagement.log("SignOut: Removing all traces of the subscription and account. Notify UI: \(notifyUI ? "true" : "false"), User Initiated: \(userInitiated ? "true" : "false")")

        try? await oAuthClient.logout()
        subscriptionCachingService.reset()

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
        let subscription = try await ingestSubscription(confirmation.subscription)
        Logger.subscription.log("Purchase confirmed!")
        return subscription
    }

    public var currentStorefrontRegion: SubscriptionRegion {
        switch currentEnvironment.purchasePlatform {
        case .appStore:
            return storePurchaseManager().currentStorefrontRegion
        case .stripe:
            return .usa
        }
    }

    // MARK: - Features

    public func currentSubscriptionFeatures(forceRefresh: Bool) async throws -> [SubscriptionEntitlement] {
        guard let currentSubscription = try await getSubscription(forceRefresh: forceRefresh) else { return [] }
        return currentSubscription.features ?? []
    }

    public func isFeatureIncludedInSubscription(_ feature: SubscriptionEntitlement) async throws -> Bool {
        try await currentSubscriptionFeatures(forceRefresh: false).contains(feature)
    }

    public func isFeatureEnabled(_ feature: SubscriptionEntitlement) async throws -> Bool {
        do {
            guard isUserAuthenticated else { return false }
            let tokenContainer = try await getTokenContainer(policy: .localValid)
            return tokenContainer.decodedAccessToken.subscriptionEntitlements.contains(feature)
        } catch {
            // Fallback to the cached user entitlements in case of keychain reading error
            Logger.subscription.debug("Failed to read user entitlements from keychain: \(error, privacy: .public)")
            return self.cachedUserEntitlements.contains(feature)
        }
    }

    public func getAllEntitlementStatus() async -> EntitlementStatus {
        do {
            guard isUserAuthenticated else { return .empty }
            let tokenContainer = try await getTokenContainer(policy: .localValid)
            let entitlements = tokenContainer.decodedAccessToken.subscriptionEntitlements
            return EntitlementStatus(enabledEntitlements: entitlements)
        } catch {
            // Fallback to the cached user entitlements in case of keychain reading error
            Logger.subscription.debug("Failed to read user entitlements from keychain: \(error, privacy: .public)")
            return EntitlementStatus(enabledEntitlements: self.cachedUserEntitlements)
        }
    }

    /// Checks if the user is eligible for a free trial.
    ///
    /// Returns `true` for Stripe-based purchases
    /// or delegates to the store purchase manager for App Store purchases.
    ///
    /// - Returns:
    ///   - `true` for Stripe platform
    ///   - `storePurchaseManager().isUserEligibleForFreeTrial()` for App Store.
    public func isUserEligibleForFreeTrial() -> Bool {
        if currentEnvironment.purchasePlatform == .stripe {
            return true
        }
        return storePurchaseManager().isUserEligibleForFreeTrial()
    }

}

extension DefaultSubscriptionManager: SubscriptionTokenProvider {
    public func getAccessToken() async throws -> String {
        try await getTokenContainer(policy: .localValid).accessToken
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
