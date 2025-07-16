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

    func test_recoveryRunsOnceForAppStore() async throws {
        let recoverer = DeadTokenRecoverer()
        let manager = SubscriptionManagerMockV2()
        manager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .appStore)

        let restoreFlow = AppStoreRestoreFlowMockV2()

        try await recoverer.attemptRecoveryFromPastPurchase(purchasePlatform: manager.currentEnvironment.purchasePlatform, restoreFlow: restoreFlow)

        XCTAssertTrue(restoreFlow.restoreSubscriptionAfterExpiredRefreshTokenCalled)
    }

    func test_recoveryThrowsForStripePlatform() async {
        let recoverer = DeadTokenRecoverer()
        let manager = SubscriptionManagerMockV2()
        manager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .stripe)

        let restoreFlow = AppStoreRestoreFlowMockV2()

        do {
            _ = try await recoverer.attemptRecoveryFromPastPurchase(purchasePlatform: manager.currentEnvironment.purchasePlatform, restoreFlow: restoreFlow)
            XCTFail("Expected error was not thrown")
        } catch let error as SubscriptionManagerError {
            XCTAssertEqual(error, .noTokenAvailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(restoreFlow.restoreSubscriptionAfterExpiredRefreshTokenCalled)
    }

    func test_recoveryAttemptResetsAfterCompletion() async throws {
        let recoverer = DeadTokenRecoverer()
        let manager = SubscriptionManagerMockV2()
        manager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .appStore)

        let restoreFlow = AppStoreRestoreFlowMockV2()

        try await recoverer.attemptRecoveryFromPastPurchase(purchasePlatform: manager.currentEnvironment.purchasePlatform, restoreFlow: restoreFlow)
        XCTAssertTrue(restoreFlow.restoreSubscriptionAfterExpiredRefreshTokenCalled)

        // reset the mock and retry — should run again due to defer-based reset
        restoreFlow.restoreSubscriptionAfterExpiredRefreshTokenCalled = false
        try await recoverer.attemptRecoveryFromPastPurchase(purchasePlatform: manager.currentEnvironment.purchasePlatform, restoreFlow: restoreFlow)
        XCTAssertTrue(restoreFlow.restoreSubscriptionAfterExpiredRefreshTokenCalled)
    }

    func test_restoreFailsWithError() async {
        let recoverer = DeadTokenRecoverer()
        let manager = SubscriptionManagerMockV2()
        manager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .appStore)

        let restoreFlow = AppStoreRestoreFlowMockV2()
        restoreFlow.restoreSubscriptionAfterExpiredRefreshTokenError = TestError.restoreFailed

        do {
            try await recoverer.attemptRecoveryFromPastPurchase(purchasePlatform: manager.currentEnvironment.purchasePlatform, restoreFlow: restoreFlow)
            XCTFail("Expected error was not thrown")
        } catch {
            XCTAssertEqual(error as? TestError, .restoreFailed)
        }

        XCTAssertTrue(restoreFlow.restoreSubscriptionAfterExpiredRefreshTokenCalled)
    }

    enum TestError: Error, Equatable {
        case restoreFailed
    }

    func test_concurrentRecoveryCallsAreSerialized() async throws {
        let recoverer = DeadTokenRecoverer()
        let manager = SubscriptionManagerMockV2()
        manager.currentEnvironment = .init(serviceEnvironment: .staging, purchasePlatform: .appStore)
        let restoreFlow = AppStoreRestoreFlowMockV2()
        restoreFlow.restoreAccountFromPastPurchaseResult = .success("some")

        actor TestCoordinator {
            private var callCount = 0
            private var completedTasks = 0

            func recordCall() {
                callCount += 1
            }

            func recordCompletion() {
                completedTasks += 1
            }

            func getStats() -> (calls: Int, completions: Int) {
                (callCount, completedTasks)
            }
        }

        let coordinator = TestCoordinator()

        restoreFlow.restoreSubscriptionAfterExpiredRefreshTokenHandler = {
            await coordinator.recordCall()
            try await Task.sleep(nanoseconds: 100_000_000) // simulate some delay
        }

        let results = await withTaskGroup(of: Result<Void, Error>.self, returning: [Result<Void, Error>].self) { group in
            for _ in 0..<3 {
                group.addTask {
                    do {
                        try await recoverer.attemptRecoveryFromPastPurchase(
                            purchasePlatform: manager.currentEnvironment.purchasePlatform,
                            restoreFlow: restoreFlow)
                        await coordinator.recordCompletion()
                        return .success(())
                    } catch {
                        await coordinator.recordCompletion()
                        return .failure(error)
                    }
                }
            }

            var results: [Result<Void, Error>] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        let stats = await coordinator.getStats()

        XCTAssertEqual(stats.calls, 1, "Expected only one actual restore call to be made")
        XCTAssertEqual(stats.completions, 3, "Expected all 3 tasks to complete")
        XCTAssertEqual(results.count, 3, "Expected results for all 3 concurrent calls")

        // Verify all tasks succeeded
        for (index, result) in results.enumerated() {
            switch result {
            case .success:
                break // Good
            case .failure(let error):
                XCTFail("Task \(index) failed unexpectedly: \(error)")
            }
        }
    }
}
