//
//  DataBrokerProtectionIOSManagerDebugSeedTests.swift
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

#if DEBUG
import XCTest
@testable import DataBrokerProtection_iOS
import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

@MainActor
final class DataBrokerProtectionIOSManagerDebugSeedTests: XCTestCase {

    private func managedSeed(_ mode: String) throws -> PIRDebugLaunchOptions.ManagedSeed {
        try XCTUnwrap(PIRDebugLaunchOptions.managedSeed(environment: [
            "PIR_SCHEDULER_MODE": mode,
            "PIR_SCHEDULER_INSTANCE_ID": UUID().uuidString,
            "PIR_SCHEDULER_RECEIPT": FileManager.default.temporaryDirectory.appendingPathComponent("receipt-\(UUID().uuidString).json").path,
        ]))
    }

    func testSeedRefusesExistingProfileWithoutSavingOrScanning() async throws {
        let (manager, dependencies) = try await DBPIOSManagerTestUtils.makeTestIOSManager()
        dependencies.database.profile = DBPIOSManagerTestUtils.makeProfile()

        do {
            _ = try await manager.seedProfileForDebugLaunch(DBPIOSManagerTestUtils.makeProfile(), managedSeed: managedSeed("seed"),
                                                            rawAuthenticated: false)
            XCTFail("Expected seed to refuse an existing profile")
        } catch {
            XCTAssertEqual((error as? PIRDebugLaunchOptions.ParseError)?.receiptErrorCode, "profileAlreadyExists")
        }
        XCTAssertFalse(dependencies.database.wasSaveProfileCalled)
        XCTAssertFalse(dependencies.database.wasDeleteProfileDataCalled)
        XCTAssertFalse(dependencies.queueManager.didCallStartImmediateScanOperationsIfPermitted)
    }

    func testSeedRefusesEitherAuthenticatedAccount() async throws {
        for (raw, pir) in [(true, false), (false, true)] {
            let (manager, dependencies) = try await DBPIOSManagerTestUtils.makeTestIOSManager()
            dependencies.authenticationManager.isUserAuthenticatedValue = pir

            do {
                _ = try await manager.seedProfileForDebugLaunch(DBPIOSManagerTestUtils.makeProfile(), managedSeed: managedSeed("seed"),
                                                                rawAuthenticated: raw)
                XCTFail("Expected seed to refuse an authenticated account")
            } catch {
                XCTAssertEqual((error as? PIRDebugLaunchOptions.ParseError)?.receiptErrorCode, "authenticatedAccount")
            }
            XCTAssertFalse(dependencies.database.wasSaveProfileCalled)
        }
    }

    func testReseedReplacesProfileThenReturnsPlanAndStartsInitialScans() async throws {
        let featureFlagger = MockDBPFeatureFlagger(isContinuedProcessingFeatureOn: false)
        let (manager, dependencies) = try await DBPIOSManagerTestUtils.makeTestIOSManager(featureFlagger: featureFlagger)
        dependencies.database.profile = DBPIOSManagerTestUtils.makeProfile()
        dependencies.database.brokerProfileQueryDataToReturn = [
            DBPIOSManagerTestUtils.makeBrokerProfileQueryData(brokerId: 1, profileQueryId: 3)
        ]

        let jobs = try await manager.seedProfileForDebugLaunch(DBPIOSManagerTestUtils.makeProfile(), managedSeed: managedSeed("reseed"),
                                                               rawAuthenticated: false)

        XCTAssertEqual(jobs, [PIRDebugLaunchOptions.DebugScanJob(brokerURL: "testbroker.com", profileQueryId: 3)])
        XCTAssertTrue(dependencies.database.wasDeleteProfileDataCalled)
        XCTAssertEqual(dependencies.freemiumDBPUserStateManager.resetAllStateCallCount, 1)
        XCTAssertTrue(dependencies.database.wasSaveProfileCalled)
        XCTAssertTrue(dependencies.eventsHandler.profileSavedFired)
        XCTAssertTrue(dependencies.queueManager.didCallStartImmediateScanOperationsIfPermitted)
    }
}
#endif
