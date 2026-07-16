//
//  DataImportUserActivityHandlerTests.swift
//  DuckDuckGoTests
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
import Persistence
import PersistenceTestingUtils
@testable import DuckDuckGo

final class DataImportUserActivityHandlerTests: XCTestCase {

    private let callbackTimeout: TimeInterval = 5.0
    private var importHandler: MockCredentialExchangeImportHandler!
    private var keyValueStore: ThrowingKeyValueStoring!

    override func setUpWithError() throws {
        try super.setUpWithError()
        importHandler = MockCredentialExchangeImportHandler()
        keyValueStore = try MockKeyValueFileStore()
    }

    override func tearDown() {
        importHandler = nil
        keyValueStore = nil
        super.tearDown()
    }

    func testWhenActivityTypeIsUnknownThenHandleReturnsFalse() {
        let sut = DataImportUserActivityHandler(credentialExchangeImportHandler: importHandler, keyValueStore: keyValueStore)
        let userActivity = NSUserActivity(activityType: "com.duckduckgo.test.unknown")

        XCTAssertFalse(sut.handle(userActivity))
        XCTAssertTrue(importHandler.handledTokens.isEmpty)
    }

    func testWhenCredentialExchangeActivityHasNoTokenThenHandleReturnsFalse() {
        let sut = DataImportUserActivityHandler(credentialExchangeImportHandler: importHandler, keyValueStore: keyValueStore)
        let userActivity = NSUserActivity(activityType: DataImportUserActivityHandler.credentialExchangeActivityType)

        XCTAssertFalse(sut.handle(userActivity))
        XCTAssertTrue(importHandler.handledTokens.isEmpty)
    }

    func testWhenCredentialExchangeActivityHasTokenThenImportResultIsSuccess() async {
        let expectedSummary = makeSummary(successful: 3)
        importHandler.summaryToReturn = CredentialExchangeImportResult(summary: expectedSummary, source: "apple.com")

        var receivedResult: Result<DataImportSummary, Error>?
        let completionExpectation = expectation(description: "Import result callback")
        let sut = DataImportUserActivityHandler(credentialExchangeImportHandler: importHandler, keyValueStore: keyValueStore) { result in
            receivedResult = result
            completionExpectation.fulfill()
        }

        let token = UUID()
        let userActivity = NSUserActivity(activityType: DataImportUserActivityHandler.credentialExchangeActivityType)
        userActivity.userInfo = ["ASCredentialImportToken": token]

        XCTAssertTrue(sut.handle(userActivity))
        await fulfillment(of: [completionExpectation], timeout: callbackTimeout)
        XCTAssertEqual(importHandler.handledTokens, [token])

        guard case .success(let summary)? = receivedResult else {
            XCTFail("Expected import success result")
            return
        }

        guard case .success(let passwordSummary)? = summary[.passwords] else {
            XCTFail("Expected password summary in successful result")
            return
        }
        XCTAssertEqual(passwordSummary.successful, 3)
    }

    func testWhenCredentialExchangeImportReturnsNilThenImportResultIsFailure() async {
        importHandler.summaryToReturn = nil

        var receivedResult: Result<DataImportSummary, Error>?
        let completionExpectation = expectation(description: "Import result callback")
        let sut = DataImportUserActivityHandler(credentialExchangeImportHandler: importHandler, keyValueStore: keyValueStore) { result in
            receivedResult = result
            completionExpectation.fulfill()
        }

        let token = UUID()
        let userActivity = NSUserActivity(activityType: DataImportUserActivityHandler.credentialExchangeActivityType)
        userActivity.userInfo = ["ASCredentialImportToken": token]

        XCTAssertTrue(sut.handle(userActivity))
        await fulfillment(of: [completionExpectation], timeout: callbackTimeout)
        XCTAssertEqual(importHandler.handledTokens, [token])

        guard case .failure? = receivedResult else {
            XCTFail("Expected import failure result")
            return
        }
    }

    func testWhenCredentialExchangeActivityIsHandledTwiceThenSecondAttemptIsIgnored() async {
        importHandler.summaryToReturn = CredentialExchangeImportResult(summary: makeSummary(successful: 1), source: "apple.com")

        var callbackCount = 0
        let completionExpectation = expectation(description: "Import result callback")
        completionExpectation.expectedFulfillmentCount = 1

        let sut = DataImportUserActivityHandler(credentialExchangeImportHandler: importHandler, keyValueStore: keyValueStore) { _ in
            callbackCount += 1
            completionExpectation.fulfill()
        }

        let token = UUID()
        let userActivity = NSUserActivity(activityType: DataImportUserActivityHandler.credentialExchangeActivityType)
        userActivity.userInfo = ["ASCredentialImportToken": token]

        XCTAssertTrue(sut.handle(userActivity))
        XCTAssertTrue(sut.handle(userActivity))
        await fulfillment(of: [completionExpectation], timeout: callbackTimeout)

        XCTAssertEqual(importHandler.handledTokens, [token])
        XCTAssertEqual(callbackCount, 1)
    }

    private func makeSummary(successful: Int) -> DataImportSummary {
        [.passwords: .success(DataImport.DataTypeSummary(successful: successful, duplicate: 0, failed: 0))]
    }
}

private final class MockCredentialExchangeImportHandler: CredentialExchangeImportHandling {

    var summaryToReturn: CredentialExchangeImportResult?
    private(set) var handledTokens: [UUID] = []

    func handleImport(token: UUID) async -> CredentialExchangeImportResult? {
        handledTokens.append(token)
        return summaryToReturn
    }
}
