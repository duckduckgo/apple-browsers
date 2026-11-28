//
//  UserSentOptOutEmailRecorderTests.swift
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
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class UserSentOptOutEmailRecorderTests: XCTestCase {

    private var temporaryDatabase: TemporaryDataBrokerProtectionDatabase!
    private var pixelHandler: MockDataBrokerProtectionPixelsHandler!

    override func setUp() async throws {
        temporaryDatabase = try TemporaryDataBrokerProtectionDatabase()
        try await temporaryDatabase.saveProfile()
        pixelHandler = MockDataBrokerProtectionPixelsHandler()
    }

    override func tearDown() {
        temporaryDatabase = nil
        pixelHandler = nil
    }

    func testUserSendsEmailForAFormBroker_recordIsSubmittedWithANewAttemptAndAnEmailSubmitPixel() throws {
        let record = try saveRecord(fixture: "valid-broker")
        let now = Date()

        try makeRecorder().record(recordIds: [record.extractedProfileId], now: now)

        let optOut = try fetchOptOut(record)
        let attempt = try XCTUnwrap(temporaryDatabase.database.fetchAttemptInformation(for: record.extractedProfileId))
        let submitSuccess = try XCTUnwrap(firedSubmitSuccessParameters())
        XCTAssertEqual(optOut.historyEvents.last?.type, .optOutByUserEmail)
        XCTAssertEqual(optOut.attemptCount, 0)
        XCTAssertNotNil(optOut.submittedSuccessfullyDate)
        XCTAssertEqual(try XCTUnwrap(optOut.preferredRunDate).timeIntervalSince(now), Double(120 * 60 * 60), accuracy: 60)
        XCTAssertEqual(submitSuccess[DataBrokerProtectionSharedPixels.Consts.emailSent], "true")
        XCTAssertEqual(submitSuccess[DataBrokerProtectionSharedPixels.Consts.attemptIdParamKey], attempt.attemptId)
        XCTAssertEqual(submitSuccess[DataBrokerProtectionSharedPixels.Consts.dataBrokerParamKey], "fakebroker.com")
    }

    func testUserSendsEmailForAChildBroker_recordIsSubmittedButNoOptOutRunIsScheduled() throws {
        let record = try saveRecord(fixture: "valid-child-broker")

        try makeRecorder().record(recordIds: [record.extractedProfileId])

        let optOut = try fetchOptOut(record)
        XCTAssertEqual(optOut.historyEvents.last?.type, .optOutByUserEmail)
        XCTAssertNotNil(try temporaryDatabase.database.fetchAttemptInformation(for: record.extractedProfileId))
        XCTAssertEqual(try XCTUnwrap(firedSubmitSuccessParameters())[DataBrokerProtectionSharedPixels.Consts.emailSent], "true")
        XCTAssertNotNil(optOut.submittedSuccessfullyDate)
        XCTAssertNil(optOut.preferredRunDate)
        XCTAssertEqual(optOut.attemptCount, 0)
    }

    func testUserSendsEmail_confirmationScanIsScheduled() throws {
        let record = try saveRecord(fixture: "valid-broker",
                                    confirmOptOutScanHours: 72,
                                    scanPreferredRunDate: Date().addingTimeInterval(30 * 24 * 60 * 60))
        let now = Date()

        try makeRecorder().record(recordIds: [record.extractedProfileId], now: now)

        let queryData = try XCTUnwrap(temporaryDatabase.database.brokerProfileQueryData(for: record.brokerId, and: record.profileQueryId))
        XCTAssertEqual(try XCTUnwrap(queryData.scanJobData.preferredRunDate).timeIntervalSince(now), Double(72 * 60 * 60), accuracy: 60)
    }

    func testUserSendsEmailWithARepeatedRecordId_recordsItOnce() throws {
        let record = try saveRecord(fixture: "valid-broker")

        try makeRecorder().record(recordIds: [record.extractedProfileId, record.extractedProfileId])

        XCTAssertEqual(try fetchOptOut(record).historyEvents.filter { $0.type == .optOutByUserEmail }.count, 1)
        XCTAssertEqual(pixelHandler.firedEvents.filter { $0.name == "dbp_optout_process_submit-success" }.count, 1)
    }

    func testUserSendsEmailThenAScanFindsTheRecordRemoved_successPixelCarriesEmailSent() throws {
        let record = try saveRecord(fixture: "valid-broker")
        try makeRecorder().record(recordIds: [record.extractedProfileId])
        let attempt = try XCTUnwrap(temporaryDatabase.database.fetchAttemptInformation(for: record.extractedProfileId))
        let queryData = try XCTUnwrap(temporaryDatabase.database.brokerProfileQueryData(for: record.brokerId, and: record.profileQueryId))
        let removedProfile = try XCTUnwrap(queryData.optOutJobData.first?.extractedProfile)
        let dependencies = MockBrokerProfileJobDependencies()
        dependencies.database = temporaryDatabase.database
        dependencies.pixelHandler = pixelHandler

        try BrokerProfileScanSubJob(dependencies: dependencies).markSavedProfilesAsRemovedAndNotifyUser(
            removedProfiles: [removedProfile],
            brokerId: record.brokerId,
            profileQueryId: record.profileQueryId,
            brokerProfileQueryData: queryData,
            database: temporaryDatabase.database,
            pixelHandler: pixelHandler,
            eventsHandler: MockOperationEventsHandler()
        )

        let success = try XCTUnwrap(pixelHandler.firedEvents.first { $0.name == "dbp_optout_process_success" }?.params)
        XCTAssertEqual(success[DataBrokerProtectionSharedPixels.Consts.emailSent], "true")
        XCTAssertEqual(success[DataBrokerProtectionSharedPixels.Consts.attemptIdParamKey], attempt.attemptId)
    }

    func testUserSendsEmailForAnUnknownRecord_otherRecordsAreStillRecorded() throws {
        let record = try saveRecord(fixture: "valid-broker")

        XCTAssertThrowsError(try makeRecorder().record(recordIds: [9_999, record.extractedProfileId]))

        XCTAssertEqual(try fetchOptOut(record).historyEvents.last?.type, .optOutByUserEmail)
    }

    func testUserSendsEmailForARecordAlreadyRemoved_nothingIsRecorded() throws {
        let record = try saveRecord(fixture: "valid-broker")
        try temporaryDatabase.database.updateRemovedDate(Date(), on: record.extractedProfileId)

        XCTAssertNoThrow(try makeRecorder().record(recordIds: [record.extractedProfileId]))

        try assertNothingRecorded(for: record)
    }

    func testUserSendsEmailForARecordMarkedThisIsntMe_nothingIsRecorded() throws {
        let record = try saveRecord(fixture: "valid-broker")
        try temporaryDatabase.database.matchRemovedByUser(record.extractedProfileId)

        XCTAssertNoThrow(try makeRecorder().record(recordIds: [record.extractedProfileId]))

        try assertNothingRecorded(for: record)
    }

    func testUserSendsEmailWhileOurOptOutAwaitsItsConfirmationEmail_theConfirmationIsStillFetched() throws {
        let record = try saveRecord(fixture: "valid-broker")
        try temporaryDatabase.database.add(HistoryEvent(extractedProfileId: record.extractedProfileId,
                                                        brokerId: record.brokerId,
                                                        profileQueryId: record.profileQueryId,
                                                        type: .optOutSubmittedAndAwaitingEmailConfirmation,
                                                        date: Date().addingTimeInterval(-60)))

        try makeRecorder().record(recordIds: [record.extractedProfileId])

        let expected = OptOutIdentifier(brokerId: record.brokerId, profileQueryId: record.profileQueryId, extractedProfileId: record.extractedProfileId)
        XCTAssertEqual(try temporaryDatabase.database.fetchIdentifiersForActiveEmailConfirmations(), [expected])
    }

    private struct Record {
        let brokerId: Int64
        let profileQueryId: Int64
        let extractedProfileId: Int64
    }

    private func saveRecord(fixture: String, confirmOptOutScanHours: Int? = nil, scanPreferredRunDate: Date = Date()) throws -> Record {
        let (brokerId, profileQueryId) = try temporaryDatabase.saveBroker(fixture: fixture, confirmOptOutScanHours: confirmOptOutScanHours)
        try temporaryDatabase.database.updatePreferredRunDate(scanPreferredRunDate, brokerId: brokerId, profileQueryId: profileQueryId)
        let extractedProfile = ExtractedProfile(name: "John Doe", profileUrl: "https://example.com/john-doe", identifier: "john-doe")
        try temporaryDatabase.database.saveOptOutJob(optOut: .mock(with: extractedProfile, brokerId: brokerId, profileQueryId: profileQueryId),
                                                     extractedProfile: extractedProfile)
        let extractedProfileId = try XCTUnwrap(temporaryDatabase.database.fetchExtractedProfiles(for: brokerId).first?.id)
        return Record(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
    }

    private func fetchOptOut(_ record: Record) throws -> OptOutJobData {
        try XCTUnwrap(temporaryDatabase.database.fetchOptOut(brokerId: record.brokerId,
                                                             profileQueryId: record.profileQueryId,
                                                             extractedProfileId: record.extractedProfileId))
    }

    private func assertNothingRecorded(for record: Record, file: StaticString = #filePath, line: UInt = #line) throws {
        let historyEvents = try fetchOptOut(record).historyEvents
        XCTAssertFalse(historyEvents.contains { $0.type == .optOutByUserEmail }, file: file, line: line)
        XCTAssertNil(try temporaryDatabase.database.fetchAttemptInformation(for: record.extractedProfileId), file: file, line: line)
        XCTAssertNil(firedSubmitSuccessParameters(), file: file, line: line)
    }

    private func firedSubmitSuccessParameters() -> [String: String]? {
        pixelHandler.firedEvents.first { $0.name == "dbp_optout_process_submit-success" }?.params
    }

    private func makeRecorder() -> UserSentOptOutEmailRecorder {
        UserSentOptOutEmailRecorder(database: temporaryDatabase.database,
                                    pixelHandler: pixelHandler,
                                    featureFlagger: MockDBPFeatureFlagger())
    }
}
