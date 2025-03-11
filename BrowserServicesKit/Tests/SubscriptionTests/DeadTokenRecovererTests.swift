//
//  DeadTokenRecovererTests.swift
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

import XCTest
@testable import Subscription
@testable import Networking
import NetworkingTestingUtils
import SubscriptionTestingUtilities

final class DeadTokenRecovererTests: XCTestCase {

    var subscriptionManager: SubscriptionManagerMockV2!
    var restoreFlow: AppStoreRestoreFlowMockV2!

    override func setUpWithError() throws {
        subscriptionManager = SubscriptionManagerMockV2()
        restoreFlow = AppStoreRestoreFlowMockV2()
    }

    override func tearDownWithError() throws {
        subscriptionManager = nil
        restoreFlow = nil
    }

    func testRecoverSuccess() async throws {
        subscriptionManager.resultTokenContainer = OAuthTokensFactory.makeDeadTokenContainer()
        subscriptionManager.resultSubscription = SubscriptionMockFactory.appleSubscription
        restoreFlow.restoreAccountFromPastPurchaseResult = .success("something")

        try await DeadTokenRecoverer.attemptRecoveryFromPastPurchase(subscriptionManager: subscriptionManager, restoreFlow: restoreFlow)

        XCTAssertTrue(restoreFlow.restoreAccountFromPastPurchaseCalled)
    }

    func testRecoverExpiredSubscription() async throws {
        subscriptionManager.resultTokenContainer = OAuthTokensFactory.makeDeadTokenContainer()
        subscriptionManager.resultSubscription = SubscriptionMockFactory.expiredSubscription
        restoreFlow.restoreAccountFromPastPurchaseResult = .failure(AppStoreRestoreFlowErrorV2.subscriptionExpired)

        do {
            try await DeadTokenRecoverer.attemptRecoveryFromPastPurchase(subscriptionManager: subscriptionManager, restoreFlow: restoreFlow)
            XCTFail("Should throw an error")
        } catch {}
    }
}
