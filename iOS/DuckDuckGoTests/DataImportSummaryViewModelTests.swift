//
//  DataImportSummaryViewModelTests.swift
//  DuckDuckGo
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
@testable import DuckDuckGo
import BrowserServicesKit
import Core

class DataImportSummaryViewModelTests: XCTestCase {
    var viewModel: DataImportSummaryViewModel!
    fileprivate var mockDelegate: MockDataImportSummaryViewModelDelegate!
    var mockSyncService: MockDDGSyncing!

    var expectedFullSyncTitle: String {
        String(format: UserText.dataImportSummarySync,
               UserText.dataImportSummarySyncData)
    }

    var expectedPasswordsSyncTitle: String {
        String(format: UserText.dataImportSummarySync,
               UserText.dataImportSummarySyncPasswords)
    }

    var expectedBookmarksSyncTitle: String {
        String(format: UserText.dataImportSummarySync,
               UserText.dataImportSummarySyncBookmarks)
    }

    override func setUp() {
        super.setUp()
        mockDelegate = MockDataImportSummaryViewModelDelegate()
        mockSyncService = MockDDGSyncing(authState: .active, isSyncInProgress: false)
    }
    
    func testInit_WithValidSummary_SetsCorrectState() {
        let summary = createSummary(passwords: true, bookmarks: true, creditCards: true)
        viewModel = DataImportSummaryViewModel(summary: summary, importScreen: .bookmarks, syncService: mockSyncService)

        XCTAssertNotNil(viewModel.passwordsSummary)
        XCTAssertNotNil(viewModel.bookmarksSummary)
        XCTAssertNotNil(viewModel.creditCardsSummary)
    }
    
    func testInit_WithFailedSummary_HandlesErrorsGracefully() {
        let summary = createFailedSummary()
        viewModel = DataImportSummaryViewModel(summary: summary, importScreen: .bookmarks, syncService: mockSyncService)

        XCTAssertNil(viewModel.passwordsSummary)
        XCTAssertNil(viewModel.bookmarksSummary)
        XCTAssertNil(viewModel.creditCardsSummary)
    }
    
    func testIsAllSuccessful_WithPerfectImport_ReturnsTrue() {
        let summary = createPerfectSummary()
        viewModel = DataImportSummaryViewModel(summary: summary, importScreen: .bookmarks, syncService: mockSyncService)

        XCTAssertTrue(viewModel.isAllSuccessful())
    }
    
    func testIsAllSuccessful_WithFailures_ReturnsFalse() {
        let summary = createSummaryWithFailures()
        viewModel = DataImportSummaryViewModel(summary: summary, importScreen: .bookmarks, syncService: mockSyncService)

        XCTAssertFalse(viewModel.isAllSuccessful())
    }
    
    func testSyncButtonTitle_WithBothTypes_ShowsCorrectTitle() {
        let summary = createSummary(passwords: true, bookmarks: true)
        viewModel = DataImportSummaryViewModel(summary: summary, importScreen: .bookmarks, syncService: mockSyncService)

        XCTAssertEqual(viewModel.syncButtonTitle, expectedFullSyncTitle)
    }
    
    func testSyncButtonTitle_WithOnlyPasswords_ShowsPasswordsTitle() {
        let summary = createSummary(passwords: true, bookmarks: false)
        viewModel = DataImportSummaryViewModel(summary: summary, importScreen: .bookmarks, syncService: mockSyncService)

        XCTAssertEqual(viewModel.syncButtonTitle, expectedPasswordsSyncTitle)
    }
    
    func testLaunchSync_NotifiesDelegate() {
        viewModel = DataImportSummaryViewModel(summary: createSummary(), importScreen: .bookmarks, syncService: mockSyncService)
        viewModel.delegate = mockDelegate
        
        viewModel.launchSync()
        
        XCTAssertTrue(mockDelegate.syncRequestCalled)
    }
    
    func testDismiss_NotifiesDelegate() {
        viewModel = DataImportSummaryViewModel(summary: createSummary(), importScreen: .bookmarks, syncService: mockSyncService)
        viewModel.delegate = mockDelegate
        
        viewModel.dismiss()
        
        XCTAssertTrue(mockDelegate.completeCalled)
    }

    func testInit_WithCreditCardsSummary_SetsCreditCardsProperty() {
        let summary = createSummary(creditCards: true)
        viewModel = DataImportSummaryViewModel(summary: summary, importScreen: .bookmarks, syncService: mockSyncService)

        XCTAssertNotNil(viewModel.creditCardsSummary)
        XCTAssertEqual(viewModel.creditCardsSummary?.successful, 3)
        XCTAssertEqual(viewModel.creditCardsSummary?.duplicate, 0)
        XCTAssertEqual(viewModel.creditCardsSummary?.failed, 0)
    }

    func testInit_WithAllDataTypes_SetsAllProperties() {
        let summary = createSummary(passwords: true, bookmarks: true, creditCards: true)
        viewModel = DataImportSummaryViewModel(summary: summary, importScreen: .bookmarks, syncService: mockSyncService)

        XCTAssertNotNil(viewModel.passwordsSummary)
        XCTAssertNotNil(viewModel.bookmarksSummary)
        XCTAssertNotNil(viewModel.creditCardsSummary)
    }

}

private class MockDataImportSummaryViewModelDelegate: DataImportSummaryViewModelDelegate {

    private(set) var syncRequestCalled = false
    private(set) var completeCalled = false

    private(set) var syncRequestCallCount = 0
    private(set) var completeCallCount = 0

    let syncRequestExpectation = XCTestExpectation(description: "Sync request made")
    let completeExpectation = XCTestExpectation(description: "Complete called")

    func dataImportSummaryViewModelDidRequestLaunchSync(_ viewModel: DataImportSummaryViewModel) {
        syncRequestCalled = true
        syncRequestCallCount += 1
        syncRequestExpectation.fulfill()
    }

    func dataImportSummaryViewModelComplete(_ viewModel: DataImportSummaryViewModel) {
        completeCalled = true
        completeCallCount += 1
        completeExpectation.fulfill()
    }

    func reset() {
        syncRequestCalled = false
        completeCalled = false
        syncRequestCallCount = 0
        completeCallCount = 0
    }

    func verifyNoInteractions() -> Bool {
        return syncRequestCallCount == 0 && completeCallCount == 0
    }

    func verifySyncRequestCalledOnce() -> Bool {
        return syncRequestCallCount == 1
    }

    func verifyCompleteCalledOnce() -> Bool {
        return completeCallCount == 1
    }
}

private extension DataImportSummaryViewModelTests {

    struct TestError: DataImportError {
        var action: DataImportAction = .generic
        var type = SimpleOperation.test
        var underlyingError: Error?
        var errorType: DataImport.ErrorType = .other

        enum SimpleOperation: Int {
            case test
        }
    }

    func createSummary(passwords: Bool = false, bookmarks: Bool = false, creditCards: Bool = false) -> DataImportSummary {
        var summary: DataImportSummary = [:]

        if passwords {
            let passwordsSummary = DataImport.DataTypeSummary(successful: 10, duplicate: 0, failed: 0)
            summary[.passwords] = .success(passwordsSummary)
        }

        if bookmarks {
            let bookmarksSummary = DataImport.DataTypeSummary(successful: 5, duplicate: 0, failed: 0)
            summary[.bookmarks] = .success(bookmarksSummary)
        }

        if creditCards {
            let creditCardsSummary = DataImport.DataTypeSummary(successful: 3, duplicate: 0, failed: 0)
            summary[.creditCards] = .success(creditCardsSummary)
        }

        return summary
    }

    func createPerfectSummary() -> DataImportSummary {
        createSummary(passwords: true, bookmarks: true, creditCards: true)
    }

    func createSummaryWithFailures() -> DataImportSummary {
        var summary = createSummary(passwords: true, bookmarks: true)
        let failedPasswordsSummary = DataImport.DataTypeSummary(successful: 8, duplicate: 1, failed: 1)
        summary[.passwords] = .success(failedPasswordsSummary)
        return summary
    }

    func createFailedSummary() -> DataImportSummary {
        var summary: DataImportSummary = [:]
        summary[.passwords] = .failure(TestError())
        summary[.bookmarks] = .failure(TestError())
        summary[.creditCards] = .failure(TestError())
        return summary
    }
}
