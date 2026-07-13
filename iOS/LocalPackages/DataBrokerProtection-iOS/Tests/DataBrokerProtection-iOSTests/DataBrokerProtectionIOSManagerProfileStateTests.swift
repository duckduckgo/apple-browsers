//
//  DataBrokerProtectionIOSManagerProfileStateTests.swift
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
import DataBrokerProtectionCoreTestsUtils
@testable import DataBrokerProtection_iOS

@MainActor
final class DataBrokerProtectionIOSManagerProfileStateTests: XCTestCase {

    func test_saveProfileAndPrepareForInitialScans_recordsProfileSaved_afterDatabaseSaveSucceeds() async throws {
        let (manager, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()

        try await manager.saveProfileAndPrepareForInitialScans(DBPContinuedProcessingTestUtils.makeProfile())

        XCTAssertEqual(dependencies.profileStateManager.profileState, .hasProfile)
    }

    func test_saveProfileAndPrepareForInitialScans_doesNotRecordProfileSaved_whenDatabaseSaveFails() async {
        let (manager, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()
        dependencies.database.saveResult = .failure(MockDatabase.MockError.saveFailed)

        do {
            try await manager.saveProfileAndPrepareForInitialScans(DBPContinuedProcessingTestUtils.makeProfile())
            XCTFail("Expected profile save to fail")
        } catch {
            XCTAssertEqual(dependencies.profileStateManager.profileState, .unknown)
        }
    }

    func test_deleteAllUserProfileData_recordsProfileDeleted_afterDatabaseDeleteSucceeds() throws {
        let (manager, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()
        dependencies.profileStateManager.recordProfileSaved()

        try manager.deleteAllUserProfileData()

        XCTAssertEqual(dependencies.profileStateManager.profileState, .noProfile)
    }

    func test_recordProfileStateUnknown_clearsStaleProfileState() {
        let (_, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()
        dependencies.profileStateManager.recordProfileSaved()

        dependencies.profileStateManager.recordProfileStateUnknown()

        XCTAssertEqual(dependencies.profileStateManager.profileState, .unknown)
    }
}
