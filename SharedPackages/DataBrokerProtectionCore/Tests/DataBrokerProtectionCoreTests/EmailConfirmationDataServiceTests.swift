//
//  EmailConfirmationDataServiceTests.swift
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
import Foundation
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class EmailConfirmationDataServiceTests: XCTestCase {

    private let mockDatabase = MockDatabase()
    private let mockEmailServiceV0 = MockEmailService()
    private let mockEmailServiceV1 = MockEmailServiceV1()
    private let mockFeatureFlagger = MockDBPFeatureFlagger(isEmailConfirmationDecouplingFeatureOn: true)

    private lazy var sut = EmailConfirmationDataService(database: mockDatabase,
                                                        emailServiceV0: mockEmailServiceV0,
                                                        emailServiceV1: mockEmailServiceV1,
                                                        featureFlagger: mockFeatureFlagger,
                                                        pixelHandler: nil)

    func testCheckForEmailConfirmationDataWith50Items() async throws {
        let records = createOptOutEmailConfirmationRecords(count: 50)
        mockDatabase.recordsAwaitingLink = records
        mockEmailServiceV1.responses = [createEmailDataResponse(for: records)]

        try await sut.checkForEmailConfirmationData()

        XCTAssertEqual(mockEmailServiceV1.fetchCallCount, 1)
        XCTAssertEqual(mockEmailServiceV1.fetchCallItems[0].count, 50)
        XCTAssertEqual(mockEmailServiceV1.deleteCallCount, 1)
    }

    func testCheckForEmailConfirmationDataWith100Items() async throws {
        let records = createOptOutEmailConfirmationRecords(count: 100)
        mockDatabase.recordsAwaitingLink = records
        mockEmailServiceV1.responses = [createEmailDataResponse(for: records)]

        try await sut.checkForEmailConfirmationData()

        XCTAssertEqual(mockEmailServiceV1.fetchCallCount, 1)
        XCTAssertEqual(mockEmailServiceV1.fetchCallItems[0].count, 100)
        XCTAssertEqual(mockEmailServiceV1.deleteCallCount, 1)
    }

    func testCheckForEmailConfirmationDataWith150Items() async throws {
        let records = createOptOutEmailConfirmationRecords(count: 150)
        mockDatabase.recordsAwaitingLink = records
        let chunk1 = Array(records.prefix(100))
        let chunk2 = Array(records.suffix(50))
        mockEmailServiceV1.responses = [
            createEmailDataResponse(for: chunk1),
            createEmailDataResponse(for: chunk2)
        ]

        try await sut.checkForEmailConfirmationData()

        XCTAssertEqual(mockEmailServiceV1.fetchCallCount, 2)
        XCTAssertEqual(mockEmailServiceV1.fetchCallItems[0].count, 100)
        XCTAssertEqual(mockEmailServiceV1.fetchCallItems[1].count, 50)
        XCTAssertEqual(mockEmailServiceV1.deleteCallCount, 1)
        XCTAssertEqual(mockEmailServiceV1.deleteCallItems.count, 150)
    }

    func testCheckForEmailConfirmationDataWith250Items() async throws {
        let records = createOptOutEmailConfirmationRecords(count: 250)
        mockDatabase.recordsAwaitingLink = records
        let chunk1 = Array(records[0..<100])
        let chunk2 = Array(records[100..<200])
        let chunk3 = Array(records[200..<250])
        mockEmailServiceV1.responses = [
            createEmailDataResponse(for: chunk1),
            createEmailDataResponse(for: chunk2),
            createEmailDataResponse(for: chunk3)
        ]

        try await sut.checkForEmailConfirmationData()

        XCTAssertEqual(mockEmailServiceV1.fetchCallCount, 3)
        XCTAssertEqual(mockEmailServiceV1.fetchCallItems[0].count, 100)
        XCTAssertEqual(mockEmailServiceV1.fetchCallItems[1].count, 100)
        XCTAssertEqual(mockEmailServiceV1.fetchCallItems[2].count, 50)
        XCTAssertEqual(mockEmailServiceV1.deleteCallCount, 1)
        XCTAssertEqual(mockEmailServiceV1.deleteCallItems.count, 250)
    }

    func testCheckForEmailConfirmationDataOnlyDeletesReadyAndErrorItems() async throws {
        let records = createOptOutEmailConfirmationRecords(count: 120)
        mockDatabase.recordsAwaitingLink = records
        let chunk1 = Array(records[0..<100])
        let chunk2 = Array(records[100..<120])

        let chunk1Response = createMixedStatusEmailDataResponse(for: chunk1,
                                                                readyCount: 40,
                                                                pendingCount: 30,
                                                                errorCount: 20,
                                                                unknownCount: 10)
        let chunk2Response = createMixedStatusEmailDataResponse(for: chunk2,
                                                                readyCount: 10,
                                                                pendingCount: 5,
                                                                errorCount: 5,
                                                                unknownCount: 0)

        mockEmailServiceV1.responses = [chunk1Response, chunk2Response]

        try await sut.checkForEmailConfirmationData()

        XCTAssertEqual(mockEmailServiceV1.fetchCallCount, 2)
        XCTAssertEqual(mockEmailServiceV1.deleteCallCount, 1)

        let expectedDeleteCount = 40 + 20 + 10 + 5
        XCTAssertEqual(mockEmailServiceV1.deleteCallItems.count, expectedDeleteCount)

        let deletedEmails = Set(mockEmailServiceV1.deleteCallItems.map { $0.email })
        let chunk1Items = chunk1Response.items.filter { $0.status == .ready || $0.status == .error }
        let chunk2Items = chunk2Response.items.filter { $0.status == .ready || $0.status == .error }
        let expectedEmails = Set(chunk1Items.map { $0.email } + chunk2Items.map { $0.email })

        XCTAssertEqual(deletedEmails, expectedEmails)
    }

    private func createOptOutEmailConfirmationRecords(count: Int) -> [OptOutEmailConfirmationJobData] {
        (1...count).map { index in
            OptOutEmailConfirmationJobData(brokerId: Int64(index),
                                           profileQueryId: Int64(index),
                                           extractedProfileId: Int64(index),
                                           generatedEmail: "test\(index)@example.com",
                                           attemptID: UUID().uuidString,
                                           emailConfirmationLink: nil,
                                           emailConfirmationLinkObtainedOnBEDate: nil)
        }
    }

    private func createEmailDataResponse(for records: [OptOutEmailConfirmationJobData]) -> EmailDataResponseV1 {
        let items = records.map { record in
            EmailDataResponseItemV1(email: record.generatedEmail,
                                    attemptId: record.attemptID,
                                    status: .ready,
                                    errorCode: nil,
                                    data: [EmailDatumV1(name: "link", value: "https://example.com/confirm/\(record.attemptID)")],
                                    emailReceivedAt: Date().timeIntervalSince1970)
        }
        return EmailDataResponseV1(items: items)
    }

    private func createMixedStatusEmailDataResponse(for records: [OptOutEmailConfirmationJobData],
                                                    readyCount: Int,
                                                    pendingCount: Int,
                                                    errorCount: Int,
                                                    unknownCount: Int) -> EmailDataResponseV1 {
        var items: [EmailDataResponseItemV1] = []
        var index = 0

        for _ in 0..<readyCount {
            let record = records[index]
            items.append(EmailDataResponseItemV1(email: record.generatedEmail,
                                                 attemptId: record.attemptID,
                                                 status: .ready,
                                                 errorCode: nil,
                                                 data: [EmailDatumV1(name: "link", value: "https://example.com/confirm/\(record.attemptID)")],
                                                 emailReceivedAt: Date().timeIntervalSince1970))
            index += 1
        }

        for _ in 0..<pendingCount {
            let record = records[index]
            items.append(EmailDataResponseItemV1(email: record.generatedEmail,
                                                 attemptId: record.attemptID,
                                                 status: .pending,
                                                 errorCode: nil,
                                                 data: [],
                                                 emailReceivedAt: nil))
            index += 1
        }

        for _ in 0..<errorCount {
            let record = records[index]
            items.append(EmailDataResponseItemV1(email: record.generatedEmail,
                                                 attemptId: record.attemptID,
                                                 status: .error,
                                                 errorCode: .extractionError,
                                                 data: [],
                                                 emailReceivedAt: nil))
            index += 1
        }

        for _ in 0..<unknownCount {
            let record = records[index]
            items.append(EmailDataResponseItemV1(email: record.generatedEmail,
                                                 attemptId: record.attemptID,
                                                 status: .unknown,
                                                 errorCode: nil,
                                                 data: [],
                                                 emailReceivedAt: nil))
            index += 1
        }

        return EmailDataResponseV1(items: items)
    }
}

class MockEmailServiceV1: EmailServiceV1Protocol {
    var fetchCallCount = 0
    var fetchCallItems: [[EmailDataRequestItemV1]] = []
    var deleteCallCount = 0
    var deleteCallItems: [EmailDataRequestItemV1] = []
    var responses: [EmailDataResponseV1] = []

    func fetchEmailData(items: [EmailDataRequestItemV1]) async throws -> EmailDataResponseV1 {
        fetchCallCount += 1
        fetchCallItems.append(items)
        guard fetchCallCount <= responses.count else {
            throw EmailErrorV1.invalidResponse
        }
        return responses[fetchCallCount - 1]
    }

    func deleteEmailData(items: [EmailDataRequestItemV1]) async throws {
        deleteCallCount += 1
        deleteCallItems += items
    }
}

class MockEmailService: EmailServiceProtocol {
    func getEmail(dataBrokerURL: String, attemptId: UUID) async throws -> EmailData {
        EmailData(pattern: nil, emailAddress: "test@example.com")
    }

    func getConfirmationLink(from email: String,
                             numberOfRetries: Int,
                             pollingInterval: TimeInterval,
                             attemptId: UUID,
                             shouldRunNextStep: @escaping () -> Bool) async throws -> URL {
        URL(string: "https://example.com/confirm")!
    }
}
