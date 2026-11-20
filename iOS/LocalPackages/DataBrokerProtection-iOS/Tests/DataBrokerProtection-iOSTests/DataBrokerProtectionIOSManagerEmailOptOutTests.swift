//
//  DataBrokerProtectionIOSManagerEmailOptOutTests.swift
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

@MainActor
final class DataBrokerProtectionIOSManagerEmailOptOutTests: XCTestCase {

    func testConfirmOptOutEmailSent_recordsTheEmailOnTheRecordAndFiresSubmitSuccessWithEmailSent() async throws {
        let (sut, dependencies) = try await DBPIOSManagerTestUtils.makeTestIOSManager()
        dependencies.database.extractedProfileToReturn = .mockWithoutRemovedDate
        dependencies.database.brokerToReturn = .mock
        MockDataBrokerProtectionPixelsHandler.lastPixelsFired = []

        try sut.confirmOptOutEmailSent(recordIds: [1])

        let submitSuccess = MockDataBrokerProtectionPixelsHandler.lastPixelsFired.first { $0.name == "dbp_optout_process_submit-success" }
        XCTAssertEqual(dependencies.database.lastAddedHistoryEvent?.type, .optOutByUserEmail)
        XCTAssertEqual(dependencies.database.lastAddedHistoryEvent?.extractedProfileId, 1)
        XCTAssertEqual(submitSuccess?.params?[DataBrokerProtectionSharedPixels.Consts.emailSent], "true")
    }

    func testConfirmOptOutEmailSent_whenTheRecordIsUnknown_throwsAndRecordsNothing() async throws {
        let (sut, dependencies) = try await DBPIOSManagerTestUtils.makeTestIOSManager()

        XCTAssertThrowsError(try sut.confirmOptOutEmailSent(recordIds: [1]))

        XCTAssertNil(dependencies.database.lastAddedHistoryEvent)
    }
}
