//
//  SubscriptionCookieManagerV2.swift
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

public final class SubscriptionCookieManagerV2: SubscriptionCookieManaging {

    public static let cookieDomain = "subscriptions.duckduckgo.com"
    public static let cookieName = "privacy_pro_access_token"

    private static let defaultRefreshTimeInterval: TimeInterval = .hours(4)

    private let subscriptionManager: SubscriptionManagerV2
    private let currentCookieStore: @MainActor () -> HTTPCookieStore?
    private let eventMapping: EventMapping<SubscriptionCookieManagerEvent>

    public private(set) var lastRefreshDate: Date?
    private let refreshTimeInterval: TimeInterval
    private var isSettingSubscriptionCookieEnabled: Bool = false

    convenience nonisolated public required init(subscriptionManager: SubscriptionManagerV2,
                                                 currentCookieStore: @MainActor @escaping () -> HTTPCookieStore?,
                                                 eventMapping: EventMapping<SubscriptionCookieManagerEvent>) {
        self.init(subscriptionManager: subscriptionManager,
                  currentCookieStore: currentCookieStore,
                  eventMapping: eventMapping,
                  refreshTimeInterval: SubscriptionCookieManagerV2.defaultRefreshTimeInterval)
    }

    nonisolated public required init(subscriptionManager: SubscriptionManagerV2,
                                     currentCookieStore: @MainActor @escaping () -> HTTPCookieStore?,
                                     eventMapping: EventMapping<SubscriptionCookieManagerEvent>,
                                     refreshTimeInterval: TimeInterval) {
        self.subscriptionManager = subscriptionManager
        self.currentCookieStore = currentCookieStore
        self.eventMapping = eventMapping
        self.refreshTimeInterval = refreshTimeInterval

        NotificationCenter.default.addObserver(self, selector: #selector(handleAccountDidSignIn), name: .accountDidSignIn, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAccountDidSignOut), name: .accountDidSignOut, object: nil)
    }

    public func enableSettingSubscriptionCookie() {
        isSettingSubscriptionCookieEnabled = true
    }

    public func disableSettingSubscriptionCookie() async {
        isSettingSubscriptionCookieEnabled = false
        if let cookieStore = await currentCookieStore(),
           let cookie = await cookieStore.fetchCurrentSubscriptionCookie() {
            await cookieStore.deleteCookie(cookie)
        }
    }

    @objc private func handleAccountDidSignIn() {
        Task {
            guard isSettingSubscriptionCookieEnabled,
                  let cookieStore = await currentCookieStore()
            else { return }

            do {
                let accessToken = try await subscriptionManager.getTokenContainer(policy: .localValid).accessToken
                Logger.subscriptionCookieManager.info("Handle .accountDidSignIn - setting cookie")
                try await cookieStore.setSubscriptionCookie(for: accessToken)
                updateLastRefreshDateToNow()
            } catch SubscriptionCookieManagerError.failedToCreateSubscriptionCookie {
                eventMapping.fire(.failedToSetSubscriptionCookie)
            } catch {
                Logger.subscriptionCookieManager.error("Handle .accountDidSignIn - can't set the cookie, token is missing")
                eventMapping.fire(.errorHandlingAccountDidSignInTokenIsMissing)
                return
            }
        }
    }

    @objc private func handleAccountDidSignOut() {
        Task {
            guard isSettingSubscriptionCookieEnabled,
                  let cookieStore = await currentCookieStore()
            else { return }
            Logger.subscriptionCookieManager.info("Handle .accountDidSignOut - deleting cookie")

            do {
                try await cookieStore.setEmptySubscriptionCookie()
                updateLastRefreshDateToNow()
            } catch {
                eventMapping.fire(.failedToSetSubscriptionCookie)
            }
        }
    }

    public func refreshSubscriptionCookie() async {
        guard isSettingSubscriptionCookieEnabled,
              shouldRefreshSubscriptionCookie(),
              let cookieStore = await currentCookieStore() else { return }

        Logger.subscriptionCookieManager.info("Refresh subscription cookie")
        updateLastRefreshDateToNow()

        let accessToken: String? = try? await subscriptionManager.getTokenContainer(policy: .localValid).accessToken
        let subscriptionCookie = await cookieStore.fetchCurrentSubscriptionCookie()

        let noCookieOrWithUnexpectedValue = (accessToken ?? "") != subscriptionCookie?.value

        do {
            if noCookieOrWithUnexpectedValue {
                Logger.subscriptionCookieManager.info("Refresh: No cookie or one with unexpected value")

                if let accessToken {
                    try await cookieStore.setSubscriptionCookie(for: accessToken)
                    eventMapping.fire(.subscriptionCookieRefreshedWithAccessToken)
                } else {
                    try await cookieStore.setEmptySubscriptionCookie()
                    eventMapping.fire(.subscriptionCookieRefreshedWithEmptyValue)
                }
            }
        } catch {
            eventMapping.fire(.failedToSetSubscriptionCookie)
        }
    }

    private func shouldRefreshSubscriptionCookie() -> Bool {
        switch lastRefreshDate {
        case .none:
            return true
        case .some(let previousLastRefreshDate):
            return previousLastRefreshDate.timeIntervalSinceNow < -refreshTimeInterval
        }
    }

    private func updateLastRefreshDateToNow() {
        lastRefreshDate = Date()
    }

    public func resetLastRefreshDate() {
        lastRefreshDate = nil
    }
}

enum SubscriptionCookieManagerError: Error {
    case failedToCreateSubscriptionCookie
}

private extension HTTPCookieStore {

    func fetchCurrentSubscriptionCookie() async -> HTTPCookie? {
        await allCookies().first { $0.domain == SubscriptionCookieManagerV2.cookieDomain && $0.name == SubscriptionCookieManagerV2.cookieName }
    }

    func setEmptySubscriptionCookie() async throws {
        try await setSubscriptionCookie(for: "")
    }

    func setSubscriptionCookie(for token: String) async throws {
        guard let cookie = HTTPCookie(properties: [
            .domain: SubscriptionCookieManagerV2.cookieDomain,
            .path: "/",
            .expires: Date().addingTimeInterval(.days(365)),
            .name: SubscriptionCookieManagerV2.cookieName,
            .value: token,
            .secure: true,
            .init(rawValue: "HttpOnly"): true
        ]) else {
            Logger.subscriptionCookieManager.error("Subscription cookie could not be created")
            assertionFailure("Subscription cookie could not be created")
            throw SubscriptionCookieManagerError.failedToCreateSubscriptionCookie
        }

        Logger.subscriptionCookieManager.info("Setting subscription cookie")
        await setCookie(cookie)
    }
}
