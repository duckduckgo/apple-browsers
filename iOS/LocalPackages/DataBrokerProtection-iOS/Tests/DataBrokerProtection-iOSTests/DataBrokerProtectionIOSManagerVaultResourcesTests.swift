//
//  DataBrokerProtectionIOSManagerVaultResourcesTests.swift
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

import XCTest
@testable import DataBrokerProtection_iOS

@MainActor
final class DataBrokerProtectionIOSManagerVaultResourcesTests: XCTestCase {

    private enum TestError: Error {
        case initializationFailed
    }

    func testPrepareSecureVaultResourcesAtLaunch_concurrentCallsShareInitialization() async throws {
        let expectation = expectation(description: "Vault init started")
        let semaphore = DispatchSemaphore(value: 0)
        let initAttemptCount = LockedCount()

        let (sut, _) = DBPIOSManagerTestUtils.makeDeferredTestIOSManager { resources in
            {
                initAttemptCount.increment()
                expectation.fulfill() // The first initialization attempt is now in flight.
                semaphore.wait() // Hold it while second caller starts
                return resources
            }
        }

        let firstTask = Task {
            try await sut.prepareSecureVaultResourcesAtLaunch() // Start initialization.
        }
        await fulfillment(of: [expectation], timeout: 1) // The first initialization attempt has started.

        let secondTask = Task {
            try await sut.prepareSecureVaultResourcesAtLaunch() // Should join the in-flight initialization.
        }

        // Allow second to reach the manager and join before initialization completes.
        try await Task.sleep(nanoseconds: 1_000_000)

        semaphore.signal() // Allow initialization to finish.
        try await firstTask.value
        try await secondTask.value

        XCTAssertEqual(initAttemptCount.value, 1)
    }

    func testPrepareSecureVaultResourcesAtLaunch_afterFailureRetriesInitialization() async throws {
        let initAttemptCount = LockedCount()

        let (sut, _) = DBPIOSManagerTestUtils.makeDeferredTestIOSManager { resources in
            {
                let attemptNumber = initAttemptCount.increment()

                if attemptNumber == 1 {
                    throw TestError.initializationFailed // Intentionally fails the first attempt
                }

                return resources
            }
        }

        do {
            try await sut.prepareSecureVaultResourcesAtLaunch()
            XCTFail("Expected first initialization attempt to fail")
        } catch TestError.initializationFailed {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        try await sut.prepareSecureVaultResourcesAtLaunch()

        XCTAssertEqual(initAttemptCount.value, 2) // Second attempt succeeds
    }
}
