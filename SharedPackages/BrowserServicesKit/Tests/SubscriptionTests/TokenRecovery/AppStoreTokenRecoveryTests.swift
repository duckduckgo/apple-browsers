//
//  AppStoreTokenRecoveryTests.swift
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
@_spi(Testing) @testable import Networking
import SubscriptionTestingUtilities

final class AppStoreTokenRecoveryTests: XCTestCase {

    private let context = TokenRecoveryContext(trigger: .invalidToken, deadPrimary: nil)

    func test_appStore_runsTheExpiredTokenRestore() async {
        let restoreFlow = AppStoreRestoreFlowMock()
        let recovery = AppStoreTokenRecovery(purchasePlatform: .appStore, restoreFlow: restoreFlow)

        let result = await recovery.recover(context)

        XCTAssertEqual(result.outcome, .recovered)
        XCTAssertTrue(restoreFlow.restoreSubscriptionAfterExpiredRefreshTokenCalled)
    }

    func test_stripe_isNotApplicable() async {
        let restoreFlow = AppStoreRestoreFlowMock()
        let recovery = AppStoreTokenRecovery(purchasePlatform: .stripe, restoreFlow: restoreFlow)

        let result = await recovery.recover(context)

        XCTAssertEqual(result.outcome, .notApplicable)
        XCTAssertFalse(restoreFlow.restoreSubscriptionAfterExpiredRefreshTokenCalled)
    }

    func test_restoreRunsAgainAfterThePreviousOneCompleted() async {
        let restoreFlow = AppStoreRestoreFlowMock()
        let recovery = AppStoreTokenRecovery(purchasePlatform: .appStore, restoreFlow: restoreFlow)

        _ = await recovery.recover(context)
        XCTAssertTrue(restoreFlow.restoreSubscriptionAfterExpiredRefreshTokenCalled)

        restoreFlow.restoreSubscriptionAfterExpiredRefreshTokenCalled = false
        _ = await recovery.recover(context)
        XCTAssertTrue(restoreFlow.restoreSubscriptionAfterExpiredRefreshTokenCalled)
    }

    func test_restoreFailure_isReturned() async {
        let restoreFlow = AppStoreRestoreFlowMock()
        restoreFlow.restoreSubscriptionAfterExpiredRefreshTokenError = TestError.restoreFailed
        let recovery = AppStoreTokenRecovery(purchasePlatform: .appStore, restoreFlow: restoreFlow)

        let result = await recovery.recover(context)

        XCTAssertEqual(result.failure as? TestError, .restoreFailed)
        XCTAssertTrue(restoreFlow.restoreSubscriptionAfterExpiredRefreshTokenCalled)
    }

    func test_concurrentRecoveries_shareOneRestore() async {
        let restoreFlow = AppStoreRestoreFlowMock()
        let recovery = AppStoreTokenRecovery(purchasePlatform: .appStore, restoreFlow: restoreFlow)
        let counter = CallCounter()
        restoreFlow.restoreSubscriptionAfterExpiredRefreshTokenHandler = {
            await counter.increment()
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let outcomes = await withTaskGroup(of: TokenRecoveryResult.Outcome.self, returning: [TokenRecoveryResult.Outcome].self) { group in
            for _ in 0..<3 {
                group.addTask {
                    await recovery.recover(self.context).outcome
                }
            }
            var outcomes: [TokenRecoveryResult.Outcome] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes
        }

        let calls = await counter.count
        XCTAssertEqual(calls, 1, "Expected only one restore for concurrent recoveries")
        XCTAssertEqual(outcomes, [.recovered, .recovered, .recovered])
    }

    private enum TestError: Error, Equatable {
        case restoreFailed
    }

    private actor CallCounter {
        private(set) var count = 0

        func increment() {
            count += 1
        }
    }
}
