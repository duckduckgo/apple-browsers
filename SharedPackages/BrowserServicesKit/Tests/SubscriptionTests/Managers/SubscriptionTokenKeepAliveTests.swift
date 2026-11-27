//
//  SubscriptionTokenKeepAliveTests.swift
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
import Testing
@testable import Subscription
@_spi(Testing) import Networking

struct SubscriptionTokenKeepAliveTests {

    private let issuedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func token(issuedAt: Date) -> TokenContainer {
        OAuthTokensFactory.makeTokenContainer(refreshTokenIssuedAt: issuedAt, refreshTokenExpiresAt: issuedAt.addingTimeInterval(.days(30)))
    }

    private func makeKeepAlive(provider: FakeTokenProvider, flag: FlagState, now: Date) -> SubscriptionTokenKeepAlive {
        SubscriptionTokenKeepAlive(tokenProvider: provider, isEnabled: { flag.isOn }, now: { now })
    }

    // MARK: - Flag states

    @available(iOS 16, macOS 13, *)
    @Test("Off from the start: nothing is read or refreshed", .timeLimit(.minutes(1)))
    func disabled() async {
        let provider = FakeTokenProvider(token: token(issuedAt: issuedAt))
        let keepAlive = makeKeepAlive(provider: provider, flag: FlagState(isOn: false), now: issuedAt.addingTimeInterval(.days(20)))

        let outcome = await keepAlive.refreshIfNeeded()

        #expect(outcome == .disabled)
        #expect(outcome.nextCheckDate == nil)
        #expect(provider.requestedPolicies.isEmpty)
        #expect(provider.stateReads == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("On from the start with a young token: not refreshed, next check when it reaches 15 days", .timeLimit(.minutes(1)))
    func youngTokenNotDue() async {
        let provider = FakeTokenProvider(token: token(issuedAt: issuedAt))
        let keepAlive = makeKeepAlive(provider: provider, flag: FlagState(isOn: true), now: issuedAt.addingTimeInterval(.days(14)))

        let outcome = await keepAlive.refreshIfNeeded()

        #expect(outcome == .notDue(nextRefresh: issuedAt.addingTimeInterval(.days(15))))
        #expect(provider.requestedPolicies == [.local])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A token 15 days old is refreshed, next check 15 days after the new token was issued", .timeLimit(.minutes(1)))
    func oldTokenRefreshed() async {
        let now = issuedAt.addingTimeInterval(.days(15))
        let provider = FakeTokenProvider(token: token(issuedAt: issuedAt))
        provider.refreshedToken = token(issuedAt: now)
        let keepAlive = makeKeepAlive(provider: provider, flag: FlagState(isOn: true), now: now)

        let outcome = await keepAlive.refreshIfNeeded()

        #expect(outcome == .refreshed(nextRefresh: now.addingTimeInterval(.days(15))))
        #expect(provider.requestedPolicies == [.local, .localForceRefresh])
    }

    @available(iOS 16, macOS 13, *)
    @Test("No token stored: nothing is refreshed and no check is scheduled", .timeLimit(.minutes(1)))
    func noToken() async {
        let provider = FakeTokenProvider(token: nil)
        let keepAlive = makeKeepAlive(provider: provider, flag: FlagState(isOn: true), now: issuedAt)

        let outcome = await keepAlive.refreshIfNeeded()

        #expect(outcome == .noToken)
        #expect(outcome.nextCheckDate == nil)
        #expect(provider.requestedPolicies.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A token store that can't be read is retried 6 hours later, without refreshing", .timeLimit(.minutes(1)))
    func unreadableToken() async {
        let now = issuedAt.addingTimeInterval(.days(20))
        let provider = FakeTokenProvider(token: token(issuedAt: issuedAt))
        provider.stateOverride = .readError
        let keepAlive = makeKeepAlive(provider: provider, flag: FlagState(isOn: true), now: now)

        #expect(await keepAlive.refreshIfNeeded() == .failed(retryAt: now.addingTimeInterval(.hours(6))))
        #expect(provider.requestedPolicies.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A token read that fails is retried 6 hours later, without refreshing", .timeLimit(.minutes(1)))
    func tokenReadFails() async {
        let now = issuedAt.addingTimeInterval(.days(20))
        let provider = FakeTokenProvider(token: token(issuedAt: issuedAt))
        provider.localReadError = URLError(.unknown)
        let keepAlive = makeKeepAlive(provider: provider, flag: FlagState(isOn: true), now: now)

        #expect(await keepAlive.refreshIfNeeded() == .failed(retryAt: now.addingTimeInterval(.hours(6))))
        #expect(provider.requestedPolicies == [.local])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A token removed before it could be read reports no token and schedules nothing", .timeLimit(.minutes(1)))
    func tokenRemovedBeforeRead() async {
        let provider = FakeTokenProvider(token: token(issuedAt: issuedAt))
        provider.localReadError = SubscriptionManagerError.noTokenAvailable
        let keepAlive = makeKeepAlive(provider: provider, flag: FlagState(isOn: true), now: issuedAt.addingTimeInterval(.days(20)))

        let outcome = await keepAlive.refreshIfNeeded()

        #expect(outcome == .noToken)
        #expect(outcome.nextCheckDate == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A failed refresh is retried 6 hours later", .timeLimit(.minutes(1)))
    func refreshFailure() async {
        let now = issuedAt.addingTimeInterval(.days(16))
        let provider = FakeTokenProvider(token: token(issuedAt: issuedAt))
        provider.refreshError = URLError(.notConnectedToInternet)
        let keepAlive = makeKeepAlive(provider: provider, flag: FlagState(isOn: true), now: now)

        #expect(await keepAlive.refreshIfNeeded() == .failed(retryAt: now.addingTimeInterval(.hours(6))))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A refresh that ends the session reports no token and schedules nothing", .timeLimit(.minutes(1)))
    func refreshEndsSession() async {
        let provider = FakeTokenProvider(token: token(issuedAt: issuedAt))
        provider.refreshError = SubscriptionManagerError.noTokenAvailable
        let keepAlive = makeKeepAlive(provider: provider, flag: FlagState(isOn: true), now: issuedAt.addingTimeInterval(.days(16)))

        let outcome = await keepAlive.refreshIfNeeded()

        #expect(outcome == .noToken)
        #expect(outcome.nextCheckDate == nil)
    }

    // MARK: - Backup renewal

    @available(iOS 16, macOS 13, *)
    @Test("A refresh returns only after the backup renewal it started has finished", .timeLimit(.minutes(1)))
    func refreshWaitsForBackupRenewal() async {
        let now = issuedAt.addingTimeInterval(.days(15))
        let provider = FakeTokenProvider(token: token(issuedAt: issuedAt))
        provider.refreshedToken = token(issuedAt: now)
        let renewal = RenewalGate()
        provider.backupRenewal = { await renewal.run() }
        let keepAlive = makeKeepAlive(provider: provider, flag: FlagState(isOn: true), now: now)

        let run = Task { await keepAlive.refreshIfNeeded() }
        await renewal.waitUntilStarted()
        #expect(await renewal.finished == false)
        await renewal.finish()

        #expect(await run.value == .refreshed(nextRefresh: now.addingTimeInterval(.days(15))))
        #expect(await renewal.finished)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Checks that don't refresh don't wait for a backup renewal", .timeLimit(.minutes(1)))
    func noRefreshNoBackupWait() async {
        let provider = FakeTokenProvider(token: token(issuedAt: issuedAt))
        let keepAlive = makeKeepAlive(provider: provider, flag: FlagState(isOn: true), now: issuedAt.addingTimeInterval(.days(1)))

        #expect(await keepAlive.refreshIfNeeded() == .notDue(nextRefresh: issuedAt.addingTimeInterval(.days(15))))
        provider.refreshError = URLError(.notConnectedToInternet)
        provider.token = token(issuedAt: issuedAt.addingTimeInterval(-.days(20)))
        _ = await keepAlive.refreshIfNeeded()

        #expect(provider.backupRenewalWaits == 0)
    }

    // MARK: - Intervals

    @available(iOS 16, macOS 13, *)
    @Test("Intervals are read on every check, so a change applies to the next one", .timeLimit(.minutes(1)))
    func intervalsReadLive() async {
        let intervals = Intervals(maxAge: .days(15), retry: .hours(6))
        let now = issuedAt.addingTimeInterval(.days(14))
        let provider = FakeTokenProvider(token: token(issuedAt: issuedAt))
        let keepAlive = SubscriptionTokenKeepAlive(tokenProvider: provider,
                                                   isEnabled: { true },
                                                   maxRefreshTokenAge: { intervals.maxAge },
                                                   retryInterval: { intervals.retry },
                                                   now: { now })
        #expect(await keepAlive.refreshIfNeeded() == .notDue(nextRefresh: issuedAt.addingTimeInterval(.days(15))))

        intervals.maxAge = .minutes(2)
        intervals.retry = .minutes(1)
        provider.refreshError = URLError(.notConnectedToInternet)
        #expect(await keepAlive.refreshIfNeeded() == .failed(retryAt: now.addingTimeInterval(.minutes(1))))

        provider.refreshError = nil
        provider.refreshedToken = token(issuedAt: now)
        #expect(await keepAlive.refreshIfNeeded() == .refreshed(nextRefresh: now.addingTimeInterval(.minutes(2))))
    }

    // MARK: - Flag transitions

    @available(iOS 16, macOS 13, *)
    @Test("on > off > on: refreshes while on, does nothing while off, refreshes again once back on", .timeLimit(.minutes(1)))
    func onOffOn() async {
        let flag = FlagState(isOn: true)
        var now = issuedAt.addingTimeInterval(.days(15))
        let provider = FakeTokenProvider(token: token(issuedAt: issuedAt))
        let keepAlive = SubscriptionTokenKeepAlive(tokenProvider: provider, isEnabled: { flag.isOn }, now: { now })

        provider.refreshedToken = token(issuedAt: now)
        #expect(await keepAlive.refreshIfNeeded() == .refreshed(nextRefresh: now.addingTimeInterval(.days(15))))

        flag.isOn = false
        let refreshedAt = now
        now = refreshedAt.addingTimeInterval(.days(16))
        #expect(await keepAlive.refreshIfNeeded() == .disabled)
        #expect(provider.requestedPolicies.filter { $0 == .localForceRefresh }.count == 1)

        flag.isOn = true
        provider.refreshedToken = token(issuedAt: now)
        #expect(await keepAlive.refreshIfNeeded() == .refreshed(nextRefresh: now.addingTimeInterval(.days(15))))
        #expect(provider.requestedPolicies.filter { $0 == .localForceRefresh }.count == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test("off > on > off: only the call made while on refreshes", .timeLimit(.minutes(1)))
    func offOnOff() async {
        let flag = FlagState(isOn: false)
        let now = issuedAt.addingTimeInterval(.days(15))
        let provider = FakeTokenProvider(token: token(issuedAt: issuedAt))
        provider.refreshedToken = token(issuedAt: now)
        let keepAlive = SubscriptionTokenKeepAlive(tokenProvider: provider, isEnabled: { flag.isOn }, now: { now })

        #expect(await keepAlive.refreshIfNeeded() == .disabled)

        flag.isOn = true
        #expect(await keepAlive.refreshIfNeeded() == .refreshed(nextRefresh: now.addingTimeInterval(.days(15))))

        flag.isOn = false
        #expect(await keepAlive.refreshIfNeeded() == .disabled)
        #expect(provider.requestedPolicies == [.local, .localForceRefresh])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Sign-out while off: once back on, nothing is refreshed", .timeLimit(.minutes(1)))
    func signOutWhileOff() async {
        let flag = FlagState(isOn: true)
        let now = issuedAt.addingTimeInterval(.days(10))
        let provider = FakeTokenProvider(token: token(issuedAt: issuedAt))
        let keepAlive = SubscriptionTokenKeepAlive(tokenProvider: provider, isEnabled: { flag.isOn }, now: { now })
        #expect(await keepAlive.refreshIfNeeded() == .notDue(nextRefresh: issuedAt.addingTimeInterval(.days(15))))

        flag.isOn = false
        provider.token = nil
        flag.isOn = true

        #expect(await keepAlive.refreshIfNeeded() == .noToken)
        #expect(!provider.requestedPolicies.contains(.localForceRefresh))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Account switch while off: once back on, the new account's token decides", .timeLimit(.minutes(1)))
    func accountSwitchWhileOff() async {
        let flag = FlagState(isOn: true)
        let now = issuedAt.addingTimeInterval(.days(16))
        let provider = FakeTokenProvider(token: token(issuedAt: issuedAt))
        let keepAlive = SubscriptionTokenKeepAlive(tokenProvider: provider, isEnabled: { flag.isOn }, now: { now })

        flag.isOn = false
        #expect(await keepAlive.refreshIfNeeded() == .disabled)
        let newAccountIssuedAt = now.addingTimeInterval(-.days(1))
        provider.token = OAuthTokensFactory.makeTokenContainer(externalID: "other-account", refreshTokenIssuedAt: newAccountIssuedAt)
        flag.isOn = true

        #expect(await keepAlive.refreshIfNeeded() == .notDue(nextRefresh: newAccountIssuedAt.addingTimeInterval(.days(15))))
        #expect(!provider.requestedPolicies.contains(.localForceRefresh))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Flag turned off during a refresh: the refresh completes and the next call does nothing", .timeLimit(.minutes(1)))
    func flagOffDuringRefresh() async {
        let flag = FlagState(isOn: true)
        let now = issuedAt.addingTimeInterval(.days(15))
        let provider = FakeTokenProvider(token: token(issuedAt: issuedAt))
        provider.refreshedToken = token(issuedAt: now)
        provider.onForceRefresh = { flag.isOn = false }
        let keepAlive = SubscriptionTokenKeepAlive(tokenProvider: provider, isEnabled: { flag.isOn }, now: { now })

        #expect(await keepAlive.refreshIfNeeded() == .refreshed(nextRefresh: now.addingTimeInterval(.days(15))))
        #expect(await keepAlive.refreshIfNeeded() == .disabled)
        #expect(provider.requestedPolicies == [.local, .localForceRefresh])
    }
}

/// A mutable flag value read through the keep-alive's `isEnabled` closure.
private final class FlagState: @unchecked Sendable {
    var isOn: Bool
    init(isOn: Bool) { self.isOn = isOn }
}

/// A backup renewal that runs until `finish()` is called.
private actor RenewalGate {
    private(set) var started = false
    private(set) var finished = false
    private var finishContinuation: CheckedContinuation<Void, Never>?

    func run() async {
        started = true
        await withCheckedContinuation { finishContinuation = $0 }
        finished = true
    }

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }

    func finish() {
        finishContinuation?.resume()
        finishContinuation = nil
    }
}

/// Mutable intervals read through the keep-alive's interval closures.
private final class Intervals: @unchecked Sendable {
    var maxAge: TimeInterval
    var retry: TimeInterval
    init(maxAge: TimeInterval, retry: TimeInterval) {
        self.maxAge = maxAge
        self.retry = retry
    }
}

/// Stores one token container and records the policies it was asked for. A forced refresh stores `refreshedToken`.
private final class FakeTokenProvider: SubscriptionTokenRefreshing, @unchecked Sendable {
    var token: TokenContainer?
    var refreshedToken: TokenContainer?
    var refreshError: Error?
    var stateOverride: LocalSubscriptionTokenState?
    var localReadError: Error?
    var onForceRefresh: (() -> Void)?
    var backupRenewal: (() async -> Void)?
    private(set) var requestedPolicies: [AuthTokensCachePolicy] = []
    private(set) var stateReads = 0
    private(set) var backupRenewalWaits = 0

    init(token: TokenContainer?) {
        self.token = token
    }

    func localTokenState() -> LocalSubscriptionTokenState {
        stateReads += 1
        if let stateOverride { return stateOverride }
        return token == nil ? .missing : .present
    }

    func getTokenContainer(policy: AuthTokensCachePolicy) async throws -> TokenContainer {
        requestedPolicies.append(policy)
        if policy == .local, let localReadError { throw localReadError }
        if policy == .localForceRefresh {
            onForceRefresh?()
            if let refreshError { throw refreshError }
            token = refreshedToken ?? token
        }
        guard let token else { throw SubscriptionManagerError.noTokenAvailable }
        return token
    }

    func waitForBackupRenewal() async {
        backupRenewalWaits += 1
        await backupRenewal?()
    }
}
