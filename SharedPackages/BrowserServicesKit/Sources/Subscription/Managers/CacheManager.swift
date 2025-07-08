//
//  File.swift
//  BrowserServicesKit
//
//  Created by Federico Cappelli on 08/07/2025.
//

import Foundation
import Networking
import os.log

@globalActor
struct CacheManager {
    public actor ActorType { }
    public static let shared: ActorType = ActorType()

    let userDefaults: UserDefaults

    // MARK: - Authentication State

    private static let isUserAuthenticatedKey = "com.duckduckgo.subscription.isUserAuthenticated"

    @CacheManager
    func getIsUserAuthenticated() -> Bool {
        return userDefaults.bool(forKey: Self.isUserAuthenticatedKey)
    }

    @CacheManager
    func setIsUserAuthenticated(_ isUserAuthenticated: Bool, notify: Bool) {
        let currentCachedIsAuthenticated = getIsUserAuthenticated()

        userDefaults.set(isUserAuthenticated, forKey: Self.isUserAuthenticatedKey)

        if notify {
            // Send notification when the login changes
            switch (currentCachedIsAuthenticated, isUserAuthenticated) {
            case (false, true):
                Logger.subscription.debug("Login detected")
                NotificationCenter.default.post(name: .accountDidSignIn, object: self, userInfo: nil)
            case (true, false):
                Logger.subscription.debug("Logout detected")
                NotificationCenter.default.post(name: .accountDidSignOut, object: self, userInfo: nil)
            default:
                Logger.subscription.debug("Login state unchanged - Current: \(currentCachedIsAuthenticated), new: \(isUserAuthenticated)")
            }

            if isUserAuthenticated == false {
                setUserEntitlements([], notify: false)
            }
        }
    }

    // MARK: - Entitlements

    private static let userEntitlementsKey = "com.duckduckgo.subscription.userEntitlements"

    @CacheManager
    func getUserEntitlements() -> [SubscriptionEntitlement] {
        guard let data = userDefaults.data(forKey: Self.userEntitlementsKey) else {
            return []
        }
        guard let entitlements = try? JSONDecoder().decode([SubscriptionEntitlement].self, from: data) else {
            assertionFailure("Error decoding user entitlements")
            Logger.subscription.fault("Error decoding user entitlements")
            return []
        }
        return entitlements
    }

    @CacheManager
    func setUserEntitlements(_ entitlements: [SubscriptionEntitlement], notify: Bool) {

        let currentCachedUserEntitlements = getUserEntitlements()

        guard let data = try? JSONEncoder().encode(entitlements)  else {
            assertionFailure("Error encoding user entitlements")
            Logger.subscription.fault("Error encoding user entitlements")
            return
        }
        userDefaults.set(data, forKey: Self.userEntitlementsKey)

        if notify {
            // Send notification when entitlements change
            if !SubscriptionEntitlement.areEntitlementsEqual(currentCachedUserEntitlements, entitlements) {
                Logger.subscription.debug("Entitlements changed - New \(String(describing: entitlements)) Old \(String(describing: currentCachedUserEntitlements))")
                let payload = EntitlementsDidChangePayload(entitlements: entitlements)
                NotificationCenter.default.post(name: .entitlementsDidChange, object: self, userInfo: payload.notificationUserInfo)
            }
        }
    }
}
