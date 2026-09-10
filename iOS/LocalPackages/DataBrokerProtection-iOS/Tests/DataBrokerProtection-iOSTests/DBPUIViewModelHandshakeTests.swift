//
//  DBPUIViewModelHandshakeTests.swift
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
import SwiftUI
import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils
@testable import DataBrokerProtection_iOS

final class DBPUIViewModelHandshakeTests: XCTestCase {

    private var authenticationDelegate: MockAuthenticationDelegate!
    private var databaseDelegate: MockDatabaseDelegate!
    private var feedbackFormDelegate: MockOpenFeedbackFormDelegate!
    private var userEventsDelegate: MockUserEventsDelegate!
    private var sut: DBPUIViewModel!

    override func setUp() {
        super.setUp()

        // DBPUIViewModel holds its delegates weakly, so the test must own them.
        authenticationDelegate = MockAuthenticationDelegate()
        databaseDelegate = MockDatabaseDelegate()
        feedbackFormDelegate = MockOpenFeedbackFormDelegate()
        userEventsDelegate = MockUserEventsDelegate()

        sut = DBPUIViewModel(authenticationDelegate: authenticationDelegate,
                             databaseDelegate: databaseDelegate,
                             feedbackFormDelegate: feedbackFormDelegate,
                             userEventsDelegate: userEventsDelegate,
                             webUISettings: MockWebUIURLSettings(),
                             pixelHandler: MockDataBrokerProtectionPixelsHandler(),
                             privacyConfigManager: PrivacyConfigurationManagingMock(),
                             contentScopeProperties: .mock)
    }

    override func tearDown() {
        sut = nil
        authenticationDelegate = nil
        databaseDelegate = nil
        feedbackFormDelegate = nil
        userEventsDelegate = nil
        super.tearDown()
    }

    /// Mixed values on purpose: opposite values for the two fields prove each is forwarded from its
    /// own delegate call rather than hardcoded or crossed with the other. This is also the case the
    /// feature exists for -- a free-scan user who has never used a trial.
    func testGetHandshakeUserData_forwardsBothFieldsFromDelegate() async {
        authenticationDelegate.isUserAuthenticatedValue = false
        authenticationDelegate.isUserEligibleForFreeTrialValue = true

        let userData = await sut.getHandshakeUserData()

        XCTAssertEqual(userData, DBPUIHandshakeUserData(isAuthenticatedUser: false,
                                                        isUserEligibleForFreeTrial: true))
    }
}

private final class MockAuthenticationDelegate: DBPIOSInterface.AuthenticationDelegate {
    var isUserAuthenticatedValue = false
    var isUserEligibleForFreeTrialValue = false

    func isUserAuthenticated() async -> Bool { isUserAuthenticatedValue }
    func isUserEligibleForFreeTrial() -> Bool { isUserEligibleForFreeTrialValue }
}

private final class MockDatabaseDelegate: DBPIOSInterface.DatabaseDelegate {
    func prepareDatabaseAccess() async throws {}
    func getUserProfile() throws -> DataBrokerProtectionProfile? { nil }
    func getAllDataBrokers() throws -> [DataBroker] { [] }
    func getAllBrokerProfileQueryData() throws -> [BrokerProfileQueryData] { [] }
    func getAllAttempts() throws -> [AttemptInformation] { [] }
    func getAllOptOutEmailConfirmations() throws -> [OptOutEmailConfirmationJobData] { [] }
    func getBackgroundTaskEvents(since date: Date) throws -> [BackgroundTaskEvent] { [] }
    func saveProfile(_ profile: DataBrokerProtectionProfile) async throws {}
    func deleteAllUserProfileData() throws {}
    func matchRemovedByUser(with id: Int64) throws {}
}

private final class MockOpenFeedbackFormDelegate: DBPUIViewModelOpenFeedbackFormDelegate {
    func openSendFeedbackForm() {}
}

private final class MockUserEventsDelegate: DBPIOSInterface.UserEventsDelegate {
    func dashboardDidOpen() {}
    func dashboardDidClose() {}
}

private final class MockWebUIURLSettings: DataBrokerProtectionWebUIURLSettingsRepresentable {
    var customURL: String?
    var productionURL: String = ""
    var selectedURL: String = ""
    var selectedURLType: DataBrokerProtectionWebUIURLType = .production
    var selectedURLHostname: String = ""

    func setCustomURL(_ url: String) {}
    func setURLType(_ type: DataBrokerProtectionWebUIURLType) {}
}
