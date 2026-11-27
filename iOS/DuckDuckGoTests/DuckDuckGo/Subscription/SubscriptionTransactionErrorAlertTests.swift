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
        "Backend errors close with OK from onboarding and point back to Settings elsewhere",
        .timeLimit(.minutes(1)),
        arguments: [SubscriptionPurchaseError.failedToGetSubscriptionOptions, .generalError]
    )
    func backendError(error: SubscriptionPurchaseError) throws {
        let messageType = try #require(SubscriptionTransactionErrorAlert.displayContent(for: error))

        #expect(messageType == .backend)
        #expect(SubscriptionTransactionErrorAlert.dismissButtonTitle(for: messageType, isPresentedFromOnboarding: true) == UserText.actionOK)
        #expect(SubscriptionTransactionErrorAlert.dismissButtonTitle(for: messageType, isPresentedFromOnboarding: false) == UserText.subscriptionBackendErrorButton)
    }

    @available(iOS 16, macOS 13, *)
    @Test(
        "Other alerts keep their button whether or not the paywall came from onboarding",
        .timeLimit(.minutes(1)),
        arguments: [
            (SubscriptionTransactionErrorAlert.MessageType.appStore, UserText.actionOK),
            (.activeSubscription, UserText.subscriptionFoundCancel),
        ]
    )
    func otherAlerts(messageType: SubscriptionTransactionErrorAlert.MessageType, expectedTitle: String) {
        #expect(SubscriptionTransactionErrorAlert.dismissButtonTitle(for: messageType, isPresentedFromOnboarding: true) == expectedTitle)
        #expect(SubscriptionTransactionErrorAlert.dismissButtonTitle(for: messageType, isPresentedFromOnboarding: false) == expectedTitle)
    }
}
