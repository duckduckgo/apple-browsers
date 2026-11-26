//
//  SubscriptionTokenKeepAlive.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import FoundationExtensions
import Networking
import os.log

/// Reads and refreshes the current subscription token container. `SubscriptionManager` provides it.
public protocol SubscriptionTokenRefreshing {

    /// The state of the locally stored token, read without refreshing it or changing any account state.
    func localTokenState() -> LocalSubscriptionTokenState

    /// Returns the token container according to `policy`. See `SubscriptionManager.getTokenContainer(policy:)`.
    @discardableResult
    func getTokenContainer(policy: AuthTokensCachePolicy) async throws -> TokenContainer
}

/// Refreshes the current token container once its refresh token reaches a maximum age, so that a session the app doesn't use
/// for a long time is renewed before its refresh token expires.
public struct SubscriptionTokenKeepAlive {

    /// The result of `refreshIfNeeded()`.
    public enum Outcome: Equatable, CustomStringConvertible {
        /// The keep-alive is disabled. Nothing was read or refreshed.
        case disabled
        /// No token container is stored, or the session ended during the check or the refresh.
        case noToken
        /// The refresh token is younger than the maximum age. Nothing was refreshed.
        /// - Parameter nextRefresh: When the refresh token reaches the maximum age.
        case notDue(nextRefresh: Date)
        /// The token container was refreshed.
        /// - Parameter nextRefresh: When the new refresh token reaches the maximum age.
        case refreshed(nextRefresh: Date)
        /// The token couldn't be read or refreshed, and can be tried again.
        /// - Parameter retryAt: When to try again.
        case failed(retryAt: Date)

        /// When `refreshIfNeeded()` should run next, or nil when it shouldn't run until a new session starts or the keep-alive is enabled.
        public var nextCheckDate: Date? {
            switch self {
            case .disabled, .noToken:
                return nil
            case .notDue(let date), .refreshed(let date), .failed(let date):
                return date
            }
        }

        /// A short name for the outcome, without its date.
        public var description: String {
            switch self {
            case .disabled: return "disabled"
            case .noToken: return "no token"
            case .notDue: return "not due"
            case .refreshed: return "refreshed"
            case .failed: return "failed"
            }
        }
    }

    /// The default age of the refresh token after which the token container is refreshed.
    public static let defaultMaxRefreshTokenAge: TimeInterval = .days(15)

    /// The default delay before trying again after a failed refresh.
    public static let defaultRetryInterval: TimeInterval = .hours(6)

    private let tokenProvider: any SubscriptionTokenRefreshing
    private let isEnabled: () -> Bool
    private let maxRefreshTokenAge: () -> TimeInterval
    private let retryInterval: () -> TimeInterval
    private let now: () -> Date

    /// - Parameters:
    ///   - tokenProvider: Reads and refreshes the current token container.
    ///   - isEnabled: Whether the keep-alive is enabled, read at the start of every `refreshIfNeeded()` call.
    ///   - maxRefreshTokenAge: The refresh token age, measured from its `iat`, after which the token container is refreshed.
    ///     Read on every `refreshIfNeeded()` call.
    ///   - retryInterval: The delay before trying again after a failed refresh. Read on every `refreshIfNeeded()` call.
    ///   - now: The current date.
    public init(tokenProvider: any SubscriptionTokenRefreshing,
                isEnabled: @escaping () -> Bool,
                maxRefreshTokenAge: @escaping () -> TimeInterval = { Self.defaultMaxRefreshTokenAge },
                retryInterval: @escaping () -> TimeInterval = { Self.defaultRetryInterval },
                now: @escaping () -> Date = Date.init) {
        self.tokenProvider = tokenProvider
        self.isEnabled = isEnabled
        self.maxRefreshTokenAge = maxRefreshTokenAge
        self.retryInterval = retryInterval
        self.now = now
    }

    /// Refreshes the current token container when its refresh token is at least `maxRefreshTokenAge` old.
    /// The refresh goes through `getTokenContainer(policy: .localForceRefresh)`, so its failures are handled as for any other refresh.
    /// - Returns: What happened, and when to check again.
    public func refreshIfNeeded() async -> Outcome {
        guard isEnabled() else {
            Logger.subscriptionTokenKeepAlive.log("Check skipped: the keep-alive is disabled")
            return .disabled
        }

        let maxAge = maxRefreshTokenAge()
        let retryInterval = retryInterval()
        Logger.subscriptionTokenKeepAlive.log("Check started, max refresh token age \(Int(maxAge), privacy: .public)s, retry interval \(Int(retryInterval), privacy: .public)s")

        switch tokenProvider.localTokenState() {
        case .present:
            break
        case .missing:
            Logger.subscriptionTokenKeepAlive.log("Check ended: no token stored")
            return .noToken
        case .readError:
            let retryAt = now().addingTimeInterval(retryInterval)
            Logger.subscriptionTokenKeepAlive.error("Check ended: the token store couldn't be read, retrying at \(retryAt, privacy: .public)")
            return .failed(retryAt: retryAt)
        }

        let current: TokenContainer
        do {
            current = try await tokenProvider.getTokenContainer(policy: .local)
        } catch SubscriptionManagerError.noTokenAvailable {
            Logger.subscriptionTokenKeepAlive.log("Check ended: the token was removed before it could be read")
            return .noToken
        } catch {
            let retryAt = now().addingTimeInterval(retryInterval)
            Logger.subscriptionTokenKeepAlive.error("Check ended: failed to read the token, retrying at \(retryAt, privacy: .public): \(String(describing: error), privacy: .public)")
            return .failed(retryAt: retryAt)
        }

        let issuedAt = current.decodedRefreshToken.issuedAtDate
        let expiresAt = current.decodedRefreshToken.expirationDate
        let refreshDate = issuedAt.addingTimeInterval(maxAge)
        Logger.subscriptionTokenKeepAlive.log("Refresh token issued \(issuedAt, privacy: .public), expires \(expiresAt, privacy: .public), refresh due \(refreshDate, privacy: .public)")

        guard now() >= refreshDate else {
            Logger.subscriptionTokenKeepAlive.log("Check ended: refresh not due until \(refreshDate, privacy: .public)")
            return .notDue(nextRefresh: refreshDate)
        }

        do {
            Logger.subscriptionTokenKeepAlive.log("Refreshing the token")
            let refreshed = try await tokenProvider.getTokenContainer(policy: .localForceRefresh)
            let newIssuedAt = refreshed.decodedRefreshToken.issuedAtDate
            let nextRefresh = newIssuedAt.addingTimeInterval(maxAge)
            Logger.subscriptionTokenKeepAlive.log("Token refreshed: new refresh token issued \(newIssuedAt, privacy: .public), expires \(refreshed.decodedRefreshToken.expirationDate, privacy: .public), next refresh due \(nextRefresh, privacy: .public)")
            return .refreshed(nextRefresh: nextRefresh)
        } catch SubscriptionManagerError.noTokenAvailable {
            Logger.subscriptionTokenKeepAlive.log("Check ended: the session ended during the refresh")
            return .noToken
        } catch {
            let retryAt = now().addingTimeInterval(retryInterval)
            Logger.subscriptionTokenKeepAlive.error("Refresh failed, retrying at \(retryAt, privacy: .public): \(String(describing: error), privacy: .public)")
            return .failed(retryAt: retryAt)
        }
    }
}
