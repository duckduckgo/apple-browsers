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
        "From onboarding, backend errors don't point back to Settings",
        .timeLimit(.minutes(1)),
        arguments: [SubscriptionPurchaseError.failedToGetSubscriptionOptions, .generalError]
    )
    func onboardingBackendError(error: SubscriptionPurchaseError) {
        #expect(SubscriptionTransactionErrorAlert.displayContent(for: error, isPresentedFromOnboarding: true) == .onboardingBackend)
    }

    @available(iOS 16, macOS 13, *)
    @Test(
        "From onboarding, every other error keeps its usual message",
        .timeLimit(.minutes(1)),
        arguments: [
            (SubscriptionPurchaseError.purchaseFailed, SubscriptionTransactionErrorAlert.MessageType?.some(.appStore)),
            (.purchasePendingTransaction, .appStore),
            (.failedToRestorePastPurchase, .appStore),
            (.hasActiveSubscription, .activeSubscription),
            (.cancelledByUser, nil),
            (.missingEntitlements, nil),
            (.failedToSetSubscription, nil),
            (.subscriptionExpired, nil),
        ]
    )
    func onboardingOtherErrors(error: SubscriptionPurchaseError, expected: SubscriptionTransactionErrorAlert.MessageType?) {
        #expect(SubscriptionTransactionErrorAlert.displayContent(for: error, isPresentedFromOnboarding: true) == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test(
        "Outside onboarding, the message depends only on the error",
        .timeLimit(.minutes(1)),
        arguments: [
            (SubscriptionPurchaseError.purchaseFailed, SubscriptionTransactionErrorAlert.MessageType.appStore),
            (.generalError, .backend),
            (.failedToGetSubscriptionOptions, .backend),
            (.hasActiveSubscription, .activeSubscription),
        ]
    )
    func outsideOnboarding(error: SubscriptionPurchaseError, expected: SubscriptionTransactionErrorAlert.MessageType) {
        #expect(SubscriptionTransactionErrorAlert.displayContent(for: error, isPresentedFromOnboarding: false) == expected)
    }
}
