//
//  EmailConfirmationJobTests.swift
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
import BrowserServicesKit
import Common
import PixelKit
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class EmailConfirmationJobTests: XCTestCase {
    var sut: EmailConfirmationJob!

    let mockDatabase = MockDatabase()
    let mockErrorDelegate = MockEmailConfirmationErrorDelegate()
    lazy var mockBrokerDependencies: MockBrokerProfileJobDependencies = {
        let dependencies = MockBrokerProfileJobDependencies()
        dependencies.database = mockDatabase
        return dependencies
    }()
    lazy var mockDependencies: EmailConfirmationJobDependencyProviding = EmailConfirmationJobDependencies(from: mockBrokerDependencies)
    let mockWebRunner = MockOptOutSubJobWebRunner()
    let mockWebViewHandler = MockWebViewHandler()

    func testRunJobWithInvalidEmailLink() async {
        let jobData = OptOutEmailConfirmationJobData(
            brokerId: 1,
            profileQueryId: 1,
            extractedProfileId: 1,
            generatedEmail: "test@example.com",
            attemptID: "test-attempt",
            emailConfirmationLink: nil
        )
        mockDatabase.brokerToReturn = DataBroker.mock

        sut = EmailConfirmationJob(
            jobData: jobData,
            showWebView: false,
            errorDelegate: mockErrorDelegate,
            jobDependencies: mockDependencies
        )

        let expectation = XCTestExpectation(description: "Job should complete with emailError")
        sut.completionBlock = {
            expectation.fulfill()
        }

        sut.start()
        await fulfillment(of: [expectation], timeout: 0.1)

        XCTAssertTrue(mockErrorDelegate.didCallError)
        XCTAssertTrue(mockErrorDelegate.lastError is EmailError)
        XCTAssertFalse(mockDatabase.wasIncrementAttemptCountCalled)
        XCTAssertEqual(mockDatabase.incrementAttemptCountCallCount, 0)
    }

    func testRunJobWithDataNotInDatabase() async {
        let jobData = OptOutEmailConfirmationJobData(
            brokerId: 1,
            profileQueryId: 1,
            extractedProfileId: 1,
            generatedEmail: "test@example.com",
            attemptID: "test-attempt",
            emailConfirmationLink: "https://example.com/confirm"
        )

        mockDatabase.extractedProfileToReturn = nil

        sut = EmailConfirmationJob(
            jobData: jobData,
            showWebView: false,
            errorDelegate: mockErrorDelegate,
            jobDependencies: mockDependencies
        )

        let expectation = XCTestExpectation(description: "Job should complete with dataNotInDatabase error")
        sut.completionBlock = {
            expectation.fulfill()
        }

        sut.start()
        await fulfillment(of: [expectation], timeout: 0.1)

        XCTAssertTrue(mockErrorDelegate.didCallError)
        XCTAssertEqual(mockErrorDelegate.lastError as? DataBrokerProtectionError, .dataNotInDatabase)
        XCTAssertFalse(mockDatabase.wasIncrementAttemptCountCalled)
        XCTAssertEqual(mockDatabase.incrementAttemptCountCallCount, 0)
    }

    func testSuccessfulJobDeletesEmailConfirmationAndAddHistoryEvent() async {
        let jobData = OptOutEmailConfirmationJobData(
            brokerId: 1,
            profileQueryId: 2,
            extractedProfileId: 3,
            generatedEmail: "test@example.com",
            attemptID: "test-attempt",
            emailConfirmationLink: "https://example.com/confirm"
        )

        mockDatabase.brokerToReturn = DataBroker.mockWithEmailConfirmation
        mockDatabase.profileQueryToReturn = ProfileQuery.mock
        mockDatabase.extractedProfileToReturn = ExtractedProfile.mockWithoutRemovedDate

        sut = EmailConfirmationJob(
            jobData: jobData,
            showWebView: false,
            errorDelegate: mockErrorDelegate,
            jobDependencies: mockDependencies,
            webRunnerForTesting: mockWebRunner,
            webViewHandlerForTesting: mockWebViewHandler
        )

        let expectation = XCTestExpectation(description: "Job should complete successfully")
        sut.completionBlock = {
            expectation.fulfill()
        }

        sut.start()
        await fulfillment(of: [expectation], timeout: 0.1)

        XCTAssertFalse(mockErrorDelegate.didCallError)

        XCTAssertTrue(mockDatabase.wasIncrementAttemptCountCalled)
        XCTAssertEqual(mockDatabase.incrementAttemptCountCallCount, 1)

        XCTAssertTrue(mockDatabase.wasDeleteOptOutEmailConfirmationCalled)
        XCTAssertEqual(mockDatabase.lastDeletedEmailConfirmationBrokerId, 1)
        XCTAssertEqual(mockDatabase.lastDeletedEmailConfirmationProfileQueryId, 2)
        XCTAssertEqual(mockDatabase.lastDeletedEmailConfirmationExtractedProfileId, 3)

        XCTAssertTrue(mockDatabase.wasAddHistoryEventCalled)
        XCTAssertEqual(mockDatabase.lastAddedHistoryEvent?.type, .optOutRequested)
        XCTAssertEqual(mockDatabase.lastAddedHistoryEvent?.brokerId, 1)
        XCTAssertEqual(mockDatabase.lastAddedHistoryEvent?.profileQueryId, 2)
        XCTAssertEqual(mockDatabase.lastAddedHistoryEvent?.extractedProfileId, 3)

        XCTAssertTrue(mockWebRunner.wasOptOutCalled)
        XCTAssertEqual(mockWebRunner.attemptCount, 1)
    }

    func testFailedJobIncrementsAttemptCount() async {
        let jobData = OptOutEmailConfirmationJobData(
            brokerId: 1,
            profileQueryId: 1,
            extractedProfileId: 1,
            generatedEmail: "test@example.com",
            attemptID: "test-attempt",
            emailConfirmationLink: "https://example.com/confirm",
            emailConfirmationAttemptCount: 0
        )

        mockDatabase.brokerToReturn = DataBroker.mockWithEmailConfirmation
        mockDatabase.profileQueryToReturn = ProfileQuery.mock
        mockDatabase.extractedProfileToReturn = ExtractedProfile.mockWithoutRemovedDate

        mockWebRunner.shouldOptOutThrow = { _ in true }

        sut = EmailConfirmationJob(
            jobData: jobData,
            showWebView: false,
            errorDelegate: mockErrorDelegate,
            jobDependencies: mockDependencies,
            webRunnerForTesting: mockWebRunner,
            webViewHandlerForTesting: mockWebViewHandler
        )

        let expectation = XCTestExpectation(description: "Job should fail")

        sut.completionBlock = {
            expectation.fulfill()
        }

        sut.start()
        await fulfillment(of: [expectation], timeout: 0.1)

        XCTAssertTrue(mockErrorDelegate.didCallError)

        XCTAssertTrue(mockDatabase.wasIncrementAttemptCountCalled)
        XCTAssertEqual(mockDatabase.incrementAttemptCountCallCount, 1)

        XCTAssertFalse(mockDatabase.wasDeleteOptOutEmailConfirmationCalled)
        XCTAssertFalse(mockDatabase.wasAddHistoryEventCalled)
    }

    func testMaxRetriesExceeded() async {
        let jobData = OptOutEmailConfirmationJobData(
            brokerId: 1,
            profileQueryId: 1,
            extractedProfileId: 1,
            generatedEmail: "test@example.com",
            attemptID: "test-attempt",
            emailConfirmationLink: "https://example.com/confirm",
            emailConfirmationAttemptCount: 2
        )

        mockDatabase.brokerToReturn = DataBroker.mockWithEmailConfirmation
        mockDatabase.profileQueryToReturn = ProfileQuery.mock
        mockDatabase.extractedProfileToReturn = ExtractedProfile.mockWithoutRemovedDate
        mockWebRunner.shouldOptOutThrow = { _ in true }

        sut = EmailConfirmationJob(
            jobData: jobData,
            showWebView: false,
            errorDelegate: mockErrorDelegate,
            jobDependencies: mockDependencies,
            webRunnerForTesting: mockWebRunner,
            webViewHandlerForTesting: mockWebViewHandler
        )

        let expectation = XCTestExpectation(description: "Job should handle max retries exceeded")
        sut.completionBlock = {
            expectation.fulfill()
        }

        sut.start()
        await fulfillment(of: [expectation], timeout: 0.1)

        XCTAssertTrue(mockErrorDelegate.didCallError)

        XCTAssertEqual(mockDatabase.incrementAttemptCountCallCount, 1)
        XCTAssertTrue(mockDatabase.wasDeleteOptOutEmailConfirmationCalled)
        XCTAssertTrue(mockDatabase.wasAddHistoryEventCalled)
        XCTAssertEqual(mockDatabase.lastAddedHistoryEvent?.type, .error(error: .emailError(.retriesExceeded)))
    }
}

final class MockEmailConfirmationErrorDelegate: EmailConfirmationErrorDelegate {
    var didCallError = false
    var lastError: Error?
    var lastBrokerName: String?
    var lastVersion: String?

    func emailConfirmationOperationDidError(_ error: Error, withBrokerName brokerName: String?, version: String?) {
        didCallError = true
        lastError = error
        lastBrokerName = brokerName
        lastVersion = version
    }
}
