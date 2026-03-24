//
//  DBPUIViewModelTests.swift
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
import BrowserServicesKit
import Common
import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils
@testable import DataBrokerProtection_iOS

@MainActor
final class DBPUIViewModelTests: XCTestCase {

    func testWhenSaveProfile_thenUsesContinuedProcessingDelegate() async throws {
        // Given
        let delegate = MockDBPUIViewModelDelegate()
        let sut = DBPUIViewModel(
            authenticationDelegate: delegate,
            databaseDelegate: delegate,
            continuedProcessingDelegate: delegate,
            feedbackFormDelegate: MockDBPUIViewModelFeedbackDelegate(),
            userEventsDelegate: delegate,
            webUISettings: DataBrokerProtectionWebUIURLSettings(.dbp),
            pixelHandler: MockDataBrokerProtectionPixelsHandler(),
            privacyConfigManager: PrivacyConfigurationManagingMock(),
            contentScopeProperties: ContentScopeProperties(
                gpcEnabled: false,
                sessionKey: "",
                messageSecret: "",
                featureToggles: .allTogglesOn
            )
        )

        XCTAssertTrue(sut.addNameToCurrentUserProfile(DBPUIUserProfileName(first: "A", last: "B")))
        XCTAssertTrue(sut.addAddressToCurrentUserProfile(DBPUIUserProfileAddress(city: "C", state: "D")))
        XCTAssertTrue(sut.setBirthYearForCurrentUserProfile(DBPUIBirthYear(year: 1980)))

        // When
        try await sut.saveProfile()

        // Then
        XCTAssertFalse(delegate.didCallSaveProfile)
        XCTAssertTrue(delegate.didCallSaveProfileAndStartContinuedProcessingInitialRun)
    }
}

private final class MockDBPUIViewModelDelegate:
    DBPIOSInterface.AuthenticationDelegate,
    DBPIOSInterface.DatabaseDelegate,
    DBPIOSInterface.ContinuedProcessingDelegate,
    DBPIOSInterface.UserEventsDelegate
{
    var didCallSaveProfile = false
    var didCallSaveProfileAndStartContinuedProcessingInitialRun = false

    func isUserAuthenticated() async -> Bool { false }

    func dashboardDidOpen() {}
    func dashboardDidClose() {}

    func getUserProfile() throws -> DataBrokerProtectionProfile? { nil }
    func getAllDataBrokers() throws -> [DataBroker] { [] }
    func getAllBrokerProfileQueryData() throws -> [BrokerProfileQueryData] { [] }
    func getAllAttempts() throws -> [AttemptInformation] { [] }
    func getAllOptOutEmailConfirmations() throws -> [OptOutEmailConfirmationJobData] { [] }
    func getBackgroundTaskEvents(since date: Date) throws -> [BackgroundTaskEvent] { [] }

    func saveProfile(_ profile: DataBrokerProtectionProfile) async throws {
        didCallSaveProfile = true
    }

    func saveProfileAndStartContinuedProcessingInitialRunIfSupported(_ profile: DataBrokerProtectionProfile) async throws {
        didCallSaveProfileAndStartContinuedProcessingInitialRun = true
    }

    func deleteAllUserProfileData() throws {}
    func matchRemovedByUser(with id: Int64) throws {}
}

private final class MockDBPUIViewModelFeedbackDelegate: DBPUIViewModelOpenFeedbackFormDelegate {
    func openSendFeedbackForm() {}
}
