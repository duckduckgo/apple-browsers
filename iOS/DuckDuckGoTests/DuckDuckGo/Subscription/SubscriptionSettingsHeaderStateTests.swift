//
//  SubscriptionSettingsHeaderStateTests.swift
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

import Testing
import Subscription
@testable import DuckDuckGo

@Suite("Subscription settings header state for active subscriptions")
struct SubscriptionSettingsHeaderStateTests {

    @available(iOS 16, macOS 13, *)
    @Test("A subscription that no longer auto-renews shows the expiring state", .timeLimit(.minutes(1)), arguments: [false, true])
    func notAutoRenewableIsExpiring(isTrial: Bool) {
        #expect(SubscriptionSettingsHeaderView.HeaderState.active(isTrial: isTrial, status: .notAutoRenewable) == .expiring)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Any other status keeps the subscribed or trial state", .timeLimit(.minutes(1)), arguments: [
        DuckDuckGoSubscription.Status.autoRenewable,
        .gracePeriod,
        .unknown,
        nil
    ])
    func otherStatusesKeepActiveState(status: DuckDuckGoSubscription.Status?) {
        #expect(SubscriptionSettingsHeaderView.HeaderState.active(isTrial: false, status: status) == .subscribed)
        #expect(SubscriptionSettingsHeaderView.HeaderState.active(isTrial: true, status: status) == .trial)
    }
}
