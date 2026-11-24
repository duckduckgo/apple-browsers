//
//  SubscriptionTransactionErrorAlertTests.swift
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
@testable import DuckDuckGo

@Suite("Subscription transaction error alert")
struct SubscriptionTransactionErrorAlertTests {

    @available(iOS 16, macOS 13, *)
    @Test(
        "From onboarding, every purchase failure shows the same message",
        .timeLimit(.minutes(1)),
        arguments: [SubscriptionPurchaseError.purchaseFailed, .purchasePendingTransaction, .failedToRestorePastPurchase, .failedToGetSubscriptionOptions, .generalError]
    )
    func onboardingPurchaseFailure(error: SubscriptionPurchaseError) {
        #expect(SubscriptionTransactionErrorAlert.displayContent(for: error, isOpenedFromOnboarding: true) == .onboardingPurchaseFailed)
    }

    @available(iOS 16, macOS 13, *)
    @Test("From onboarding, an existing subscription still offers to restore it", .timeLimit(.minutes(1)))
    func onboardingActiveSubscription() {
        #expect(SubscriptionTransactionErrorAlert.displayContent(for: .hasActiveSubscription, isOpenedFromOnboarding: true) == .activeSubscription)
    }

    @available(iOS 16, macOS 13, *)
    @Test(
        "From onboarding, errors without an alert still show none",
        .timeLimit(.minutes(1)),
        arguments: [SubscriptionPurchaseError.cancelledByUser, .missingEntitlements, .failedToSetSubscription, .subscriptionExpired]
    )
    func onboardingNoAlert(error: SubscriptionPurchaseError) {
        #expect(SubscriptionTransactionErrorAlert.displayContent(for: error, isOpenedFromOnboarding: true) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test(
        "Outside onboarding, the message depends on the error",
        .timeLimit(.minutes(1)),
        arguments: [
            (SubscriptionPurchaseError.purchaseFailed, SubscriptionTransactionErrorAlert.MessageType.appStore),
            (.generalError, .backend),
            (.hasActiveSubscription, .activeSubscription),
        ]
    )
    func outsideOnboarding(error: SubscriptionPurchaseError, expected: SubscriptionTransactionErrorAlert.MessageType) {
        #expect(SubscriptionTransactionErrorAlert.displayContent(for: error, isOpenedFromOnboarding: false) == expected)
    }
}
