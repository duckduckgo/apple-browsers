//
//  DataBrokerProtectionIOSManagerVaultInitReasonTests.swift
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
import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils
@testable import DataBrokerProtection_iOS

/// Covers the Secure Vault init gate's decision matrix: which init reasons skip
/// when the user has no profile, and which always initialize. Each reason is driven
/// through its real public entry point; the private gate cannot be called directly.
@MainActor
final class DataBrokerProtectionIOSManagerVaultInitReasonTests: XCTestCase {

    // MARK: - launch (skips when no profile)

    func test_launch_noProfile_skipsInitialization() async throws {
        let initAttemptCount = LockedCount()
        let (sut, dependencies) = makeDeferredManager(countingInto: initAttemptCount)
        dependencies.profileStateManager.recordProfileDeleted()

        try await sut.prepareSecureVaultResourcesAtLaunch()

        XCTAssertEqual(initAttemptCount.value, 0)
        XCTAssertEqual(sut.iOSRuntimeStatus?.vault.initialized, false)
        XCTAssertEqual(sut.iOSRuntimeStatus?.vault.lastInitReason, "launch")
    }

    func test_launch_hasProfile_initializes() async throws {
        let initAttemptCount = LockedCount()
        let (sut, dependencies) = makeDeferredManager(countingInto: initAttemptCount)
        dependencies.profileStateManager.recordProfileSaved()

        try await sut.prepareSecureVaultResourcesAtLaunch()

        XCTAssertEqual(initAttemptCount.value, 1)
        XCTAssertEqual(sut.iOSRuntimeStatus?.vault.initialized, true)
    }

    func test_launch_unknownProfile_initializes() async throws {
        let initAttemptCount = LockedCount()
        let (sut, dependencies) = makeDeferredManager(countingInto: initAttemptCount)
        dependencies.profileStateManager.recordProfileStateUnknown()

        try await sut.prepareSecureVaultResourcesAtLaunch()

        XCTAssertEqual(initAttemptCount.value, 1)
        XCTAssertEqual(sut.iOSRuntimeStatus?.vault.initialized, true)
    }

    // MARK: - appActive (skips when no profile, starts no operations)

    func test_appActive_noProfile_skipsInitializationAndStartsNoOperations() async {
        let initAttemptCount = LockedCount()
        let (sut, dependencies) = makeDeferredManager(countingInto: initAttemptCount)
        dependencies.profileStateManager.recordProfileDeleted()

        await sut.appDidBecomeActive()

        XCTAssertEqual(initAttemptCount.value, 0)
        XCTAssertEqual(sut.iOSRuntimeStatus?.vault.initialized, false)
        XCTAssertFalse(dependencies.queueManager.didCallStartImmediateScanOperationsIfPermitted)
        XCTAssertFalse(dependencies.queueManager.didCallStartScheduledScanOperationsIfPermitted)
        XCTAssertFalse(dependencies.queueManager.didCallStartScheduledAllOperationsIfPermitted)
    }

    // MARK: - dashboard (never skips, even with no profile)

    func test_dashboard_noProfile_initializesAnyway() async throws {
        let initAttemptCount = LockedCount()
        let (sut, dependencies) = makeDeferredManager(countingInto: initAttemptCount)
        dependencies.profileStateManager.recordProfileDeleted()

        try await sut.prepareDatabaseAccess()

        XCTAssertEqual(initAttemptCount.value, 1)
        XCTAssertEqual(sut.iOSRuntimeStatus?.vault.initialized, true)
        XCTAssertEqual(sut.iOSRuntimeStatus?.vault.lastInitReason, "dashboard")
    }

    // MARK: - Helpers

    private func makeDeferredManager(
        countingInto initAttemptCount: LockedCount
    ) -> (DataBrokerProtectionIOSManager, IOSManagerTestDependencies) {
        DBPIOSManagerTestUtils.makeDeferredTestIOSManager { resources in
            {
                initAttemptCount.increment()
                return resources
            }
        }
    }
}
