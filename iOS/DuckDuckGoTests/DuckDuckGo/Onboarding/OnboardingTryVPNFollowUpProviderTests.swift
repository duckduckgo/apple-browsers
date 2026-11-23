//
//  OnboardingTryVPNFollowUpProviderTests.swift
//  DuckDuckGo
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

import Subscription
import SubscriptionTestingUtilities
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("Onboarding Try VPN follow-up provider")
struct OnboardingTryVPNFollowUpProviderTests {

    @available(iOS 16, macOS 13, *)
    @Test("Reads VPN access from the subscription", .timeLimit(.minutes(1)), arguments: [true, false])
    func readsVPNAccessFromSubscription(includesVPN: Bool) async {
        // GIVEN
        let subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.resultFeatures = includesVPN ? [.networkProtection] : []
        let sut = OnboardingTryVPNFollowUpProvider(subscriptionManager: subscriptionManager)
        #expect(sut.hasVPNAccess == nil)

        // WHEN
        await sut.refreshVPNAccess()

        // THEN
        #expect(sut.hasVPNAccess == includesVPN)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancelling before any check finishes means no VPN access", .timeLimit(.minutes(1)))
    func cancellingWithoutAnswerMeansNoAccess() {
        // GIVEN
        let sut = OnboardingTryVPNFollowUpProvider { true }

        // WHEN
        sut.cancelVPNAccessCheck()

        // THEN
        #expect(sut.hasVPNAccess == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancelling keeps the answer of a finished check", .timeLimit(.minutes(1)))
    func cancellingKeepsFinishedAnswer() async {
        // GIVEN
        let sut = OnboardingTryVPNFollowUpProvider { true }
        await sut.refreshVPNAccess()

        // WHEN
        sut.cancelVPNAccessCheck()

        // THEN
        #expect(sut.hasVPNAccess == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A check cancelled while running doesn't change the answer", .timeLimit(.minutes(1)))
    func cancelledCheckIsIgnored() async {
        // GIVEN
        let checks = PendingVPNAccessChecks()
        let sut = OnboardingTryVPNFollowUpProvider(checkVPNAccess: checks.check)
        let refresh = Task { await sut.refreshVPNAccess() }
        await checks.waitForChecks(1)

        // WHEN
        sut.cancelVPNAccessCheck()
        checks.finish(0, returning: true)
        await refresh.value

        // THEN
        #expect(sut.hasVPNAccess == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An older check finishing late doesn't overwrite a newer one", .timeLimit(.minutes(1)))
    func newerCheckWins() async {
        // GIVEN
        let checks = PendingVPNAccessChecks()
        let sut = OnboardingTryVPNFollowUpProvider(checkVPNAccess: checks.check)
        let olderRefresh = Task { await sut.refreshVPNAccess() }
        await checks.waitForChecks(1)
        let newerRefresh = Task { await sut.refreshVPNAccess() }
        await checks.waitForChecks(2)

        // WHEN
        checks.finish(1, returning: true)
        await newerRefresh.value
        checks.finish(0, returning: false)
        await olderRefresh.value

        // THEN
        #expect(sut.hasVPNAccess == true)
    }
}

/// VPN access checks that stay pending until the test finishes them.
@MainActor
private final class PendingVPNAccessChecks {
    private var continuations: [CheckedContinuation<Bool, Never>] = []

    func check() async -> Bool {
        await withCheckedContinuation { continuations.append($0) }
    }

    func waitForChecks(_ count: Int) async {
        while continuations.count < count { await Task.yield() }
    }

    func finish(_ index: Int, returning hasVPNAccess: Bool) {
        continuations[index].resume(returning: hasVPNAccess)
    }
}
