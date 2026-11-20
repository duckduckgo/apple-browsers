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
import MessageUI
import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils
@testable import DataBrokerProtection_iOS

final class DBPUIViewModelHandshakeTests: XCTestCase {

    private var authenticationDelegate: MockAuthenticationDelegate!
    private var databaseDelegate: MockDatabaseDelegate!
    private var feedbackFormDelegate: MockOpenFeedbackFormDelegate!
    private var userEventsDelegate: MockUserEventsDelegate!
    private var featureFlagger: MockDBPFeatureFlagger!
    private var emailComposer: MockOptOutEmailComposer!
    private var sut: DBPUIViewModel!

    override func setUp() {
        super.setUp()

        // DBPUIViewModel holds its delegates weakly, so the test must own them.
        authenticationDelegate = MockAuthenticationDelegate()
        databaseDelegate = MockDatabaseDelegate()
        feedbackFormDelegate = MockOpenFeedbackFormDelegate()
        userEventsDelegate = MockUserEventsDelegate()
        featureFlagger = MockDBPFeatureFlagger(isEmailOptOutEnabled: true)
        emailComposer = MockOptOutEmailComposer()

        sut = DBPUIViewModel(authenticationDelegate: authenticationDelegate,
                             databaseDelegate: databaseDelegate,
                             feedbackFormDelegate: feedbackFormDelegate,
                             userEventsDelegate: userEventsDelegate,
                             webUISettings: MockWebUIURLSettings(),
                             pixelHandler: MockDataBrokerProtectionPixelsHandler(),
                             privacyConfigManager: PrivacyConfigurationManagingMock(),
                             contentScopeProperties: .mock,
                             emailOptOutFeatureFlagger: featureFlagger,
                             emailComposer: emailComposer)
    }

    override func tearDown() {
        sut = nil
        authenticationDelegate = nil
        databaseDelegate = nil
        feedbackFormDelegate = nil
        userEventsDelegate = nil
        featureFlagger = nil
        emailComposer = nil
        super.tearDown()
    }

    func testGetHandshakeUserData_forwardsBothFieldsFromDelegate() async {
        authenticationDelegate.isUserAuthenticatedValue = false
        authenticationDelegate.isUserEligibleForFreeTrialValue = true

        let userData = await sut.getHandshakeUserData()

        XCTAssertEqual(userData, DBPUIHandshakeUserData(isAuthenticatedUser: false,
                                                        isUserEligibleForFreeTrial: true))
    }

    func testEmailOptOutEnabled_followsTheFlagWhileTheDashboardIsOpen() {
        featureFlagger.isEmailOptOutEnabled = false
        XCTAssertFalse(sut.isEmailOptOutEnabled())

        featureFlagger.isEmailOptOutEnabled = true
        XCTAssertTrue(sut.isEmailOptOutEnabled())
    }

    func testCanSendEmail_whenMailHasAnAccount_isTrue() {
        emailComposer.canSendMail = true

        XCTAssertTrue(sut.canSendEmail())
    }

    func testCanSendEmail_whenMailHasNoAccount_isFalse() {
        emailComposer.canSendMail = false

        XCTAssertFalse(sut.canSendEmail())
    }

    func testOpenOptOutEmail_whenUserTapsSendInMail_returnsSent() async {
        emailComposer.canSendMail = true
        emailComposer.composeResult = .sent

        let result = await sut.openOptOutEmail(Self.removalEmail)

        XCTAssertEqual(result, DBPUIOpenOptOutEmailResult(sent: true))
        XCTAssertEqual(emailComposer.composedEmails, [Self.removalEmail])
    }

    func testOpenOptOutEmail_whenUserCancelsSavesOrMailFails_returnsNotSent() async {
        emailComposer.canSendMail = true

        for composeResult in [MFMailComposeResult.cancelled, .saved, .failed] {
            emailComposer.composeResult = composeResult

            let result = await sut.openOptOutEmail(Self.removalEmail)

            XCTAssertEqual(result, DBPUIOpenOptOutEmailResult(sent: false), "\(composeResult.rawValue)")
        }
    }

    func testOpenOptOutEmail_whenMailHasNoAccount_returnsNotSentWithoutShowingAnything() async {
        emailComposer.canSendMail = false

        let result = await sut.openOptOutEmail(Self.removalEmail)

        XCTAssertEqual(result, DBPUIOpenOptOutEmailResult(sent: false))
        XCTAssertTrue(emailComposer.composedEmails.isEmpty)
    }

    func testConfirmOptOutEmailSent_passesTheRecordIdsToTheManager() async {
        await sut.confirmOptOutEmailSent(recordIds: [12, 34])

        XCTAssertEqual(databaseDelegate.confirmedOptOutEmailRecordIds, [[12, 34]])
    }

    func testEmailOptOutTurnedOffWhileTheDashboardIsOpen_neitherOpensMailNorRecordsTheSend() async {
        featureFlagger.isEmailOptOutEnabled = false
        emailComposer.canSendMail = true
        emailComposer.composeResult = .sent

        let result = await sut.openOptOutEmail(Self.removalEmail)
        await sut.confirmOptOutEmailSent(recordIds: [12, 34])

        XCTAssertEqual(result, DBPUIOpenOptOutEmailResult(sent: false))
        XCTAssertTrue(emailComposer.composedEmails.isEmpty)
        XCTAssertTrue(databaseDelegate.confirmedOptOutEmailRecordIds.isEmpty)
    }

    private static let removalEmail = DBPUIOpenOptOutEmailRequest(to: "support@privatereports.com",
                                                                  subject: "Removal request",
                                                                  body: "Please remove my records.")
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

    var confirmedOptOutEmailRecordIds: [[Int64]] = []
    func confirmOptOutEmailSent(recordIds: [Int64]) throws {
        confirmedOptOutEmailRecordIds.append(recordIds)
    }
}

private final class MockOpenFeedbackFormDelegate: DBPUIViewModelOpenFeedbackFormDelegate {
    func openSendFeedbackForm() {}
}

private final class MockUserEventsDelegate: DBPIOSInterface.UserEventsDelegate {
    func dashboardDidOpen() {}
    func dashboardDidClose() {}
}

private final class MockOptOutEmailComposer: DBPOptOutEmailComposing {
    var canSendMail = false
    var composeResult = MFMailComposeResult.cancelled
    private(set) var composedEmails: [DBPUIOpenOptOutEmailRequest] = []

    @MainActor
    func compose(_ email: DBPUIOpenOptOutEmailRequest) async -> MFMailComposeResult {
        // Like the real composer, nothing is shown when Mail can't send.
        guard canSendMail else { return .failed }
        composedEmails.append(email)
        return composeResult
    }
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
