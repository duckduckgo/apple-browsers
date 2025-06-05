//
//  MockSubscriptionManagerV2.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@testable import Subscription
import JWTKit
@testable import Networking
import Common

class MockSubscriptionManagerV2: SubscriptionManagerV2 {

    init() {}

    static func loadEnvironmentFrom(userDefaults: UserDefaults) -> SubscriptionEnvironment? {
        return nil
    }

    static func save(subscriptionEnvironment: SubscriptionEnvironment, userDefaults: UserDefaults) {
    }

    var currentEnvironment: Subscription.SubscriptionEnvironment = .init(serviceEnvironment: .production, purchasePlatform: .appStore)

    func loadInitialData() async {}

    func getSubscription(cachePolicy: SubscriptionCachePolicy) async throws -> PrivacyProSubscription {
        PrivacyProSubscription(productId: "", name: "", billingPeriod: .monthly, startedAt: Date(), expiresOrRenewsAt: Date(), platform: .apple, status: .autoRenewable, activeOffers: [], features: [])
    }

    func isSubscriptionPresent() -> Bool {
        return true
    }

    func getSubscriptionFrom(lastTransactionJWSRepresentation: String) async throws -> PrivacyProSubscription? {
        return nil
    }

    var canPurchase: Bool = true

    func getProducts() async throws -> [GetProductsItem] {
        return []
    }

    func storePurchaseManager() -> any StorePurchaseManagerV2 {
        return MockStorePurchaseManagerV2()
    }

    func url(for type: SubscriptionURL) -> URL {
        return URL(string: "subscription.url")!
    }

    func urlForPurchaseFromRedirect(redirectURLComponents: URLComponents, tld: Common.TLD) -> URL {
        return URL(string: "purchase.url")!
    }

    func getCustomerPortalURL() async throws -> URL {
        return URL(string: "custom.url")!
    }

    var userEmail: String?

    func signOut(notifyUI: Bool) async {
    }

    func clearSubscriptionCache() {
    }

    func confirmPurchase(signature: String, additionalParams: [String : String]?) async throws -> PrivacyProSubscription {
        return PrivacyProSubscription(productId: "", name: "", billingPeriod: .monthly, startedAt: Date(), expiresOrRenewsAt: Date(), platform: .apple, status: .autoRenewable, activeOffers: [], features: [])
    }

    func currentSubscriptionFeatures(forceRefresh: Bool) async throws -> [SubscriptionFeatureV2] {
        return []
    }

    func isFeatureAvailableForUser(_ entitlement: SubscriptionEntitlement) async throws -> Bool {
        return true
    }

    func getTokenContainer(policy: Networking.AuthTokensCachePolicy) async throws -> TokenContainer {
        return TokenContainer(accessToken: "", refreshToken: "", decodedAccessToken: JWTAccessToken(exp: ExpirationClaim(value: Date()), iat: IssuedAtClaim(value: Date()), sub: SubjectClaim(value: ""), aud: AudienceClaim(value: []), iss: IssuerClaim(value: ""), jti: IDClaim(value: ""), scope: "", api: "", email: nil, entitlements: []), decodedRefreshToken: JWTRefreshToken(exp: ExpirationClaim(value: Date()), iat: IssuedAtClaim(value: Date()), sub: SubjectClaim(value: ""), aud: AudienceClaim(value: []), iss: IssuerClaim(value: ""), jti: IDClaim(value: ""), scope: "", api: ""))
    }

    func exchange(tokenV1: String) async throws -> TokenContainer {
        return TokenContainer(accessToken: "", refreshToken: "", decodedAccessToken: JWTAccessToken(exp: ExpirationClaim(value: Date()), iat: IssuedAtClaim(value: Date()), sub: SubjectClaim(value: ""), aud: AudienceClaim(value: []), iss: IssuerClaim(value: ""), jti: IDClaim(value: ""), scope: "", api: "", email: nil, entitlements: []), decodedRefreshToken: JWTRefreshToken(exp: ExpirationClaim(value: Date()), iat: IssuedAtClaim(value: Date()), sub: SubjectClaim(value: ""), aud: AudienceClaim(value: []), iss: IssuerClaim(value: ""), jti: IDClaim(value: ""), scope: "", api: ""))
    }

    func adopt(accessToken: String, refreshToken: String) async throws {
    }

    func adopt(tokenContainer: Networking.TokenContainer) async throws {
    }

    func removeLocalAccount() {
    }

    func getAccessToken() async throws -> String {
        return ""
    }

    func removeAccessToken() {
    }

    var isUserAuthenticated: Bool = true

    func isEnabled(feature: Entitlement.ProductName, cachePolicy: Subscription.APICachePolicy) async throws -> Bool {
        return true
    }

    func currentSubscriptionFeatures() async -> [Entitlement.ProductName] {
        return []
    }

    var email: String?

}
