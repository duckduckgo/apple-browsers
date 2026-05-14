//
//  DataClearingWideEventServiceTests.swift
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

import BrowserServicesKit
import PixelKit
import PixelKitTestingUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class DataClearingWideEventServiceTests: XCTestCase {

    private var wideEventMock: WideEventMock!
    private var sut: DataClearingWideEventService!

    override func setUp() {
        super.setUp()
        wideEventMock = WideEventMock()
        sut = DataClearingWideEventService(wideEvent: wideEventMock)
    }

    override func tearDown() {
        wideEventMock = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Event Lifecycle Tests

    func testStart_createsNewWideEvent() {
        // Given
        let options = FireDialogResult(
            clearingOption: .currentTab,
            includeHistory: true,
            includeTabsAndWindows: true,
            includeCookiesAndSiteData: true,
            includeChatHistory: false
        )

        // When
        sut.start(options: options, path: .burnEntity, isAutoClear: false)

        // Then
        XCTAssertEqual(wideEventMock.started.count, 1)
        guard let eventData = wideEventMock.started.first as? DataClearingWideEventData else {
            XCTFail("Expected DataClearingWideEventData to be started")
            return
        }
        XCTAssertEqual(eventData.options, .currentTab)
        XCTAssertEqual(eventData.trigger, .manual)
        XCTAssertEqual(eventData.path, .burnEntity)
        XCTAssertEqual(eventData.includedDomains, "History,TabsAndWindows,CookiesAndSiteData")
        XCTAssertNotNil(eventData.overallDuration?.start)
        XCTAssertNil(eventData.overallDuration?.end)
    }

    func testStart_withAutoClear_setsTriggerToAutoClear() {
        // Given
        let options = FireDialogResult(
            clearingOption: .allData,
            includeHistory: true,
            includeTabsAndWindows: true,
            includeCookiesAndSiteData: true,
            includeChatHistory: true
        )

        // When
        sut.start(options: options, path: .burnAll, isAutoClear: true)

        // Then
        guard let eventData = wideEventMock.started.first as? DataClearingWideEventData else {
            XCTFail("Expected DataClearingWideEventData to be started")
            return
        }
        XCTAssertEqual(eventData.trigger, .autoClear)
    }

    func testStart_withIncludeChatHistory_includesChatHistoryInDomains() {
        // Given
        let options = FireDialogResult(
            clearingOption: .currentWindow,
            includeHistory: true,
            includeTabsAndWindows: true,
            includeCookiesAndSiteData: true,
            includeChatHistory: true
        )

        // When
        sut.start(options: options, path: .burnEntity, isAutoClear: false)

        // Then
        guard let eventData = wideEventMock.started.first as? DataClearingWideEventData else {
            XCTFail("Expected DataClearingWideEventData to be started")
            return
        }
        XCTAssertEqual(eventData.includedDomains, "History,TabsAndWindows,CookiesAndSiteData,ChatHistory")
    }

    // MARK: - Action Tracking Tests

    func testStartAction_initializesDuration() {
        // Given
        let options = FireDialogResult(
            clearingOption: .allData,
            includeHistory: true,
            includeTabsAndWindows: true,
            includeCookiesAndSiteData: true,
            includeChatHistory: false
        )
        sut.start(options: options, path: .burnAll, isAutoClear: false)

        // When
        sut.start(.clearTabs)

        // Then
        guard let eventData = wideEventMock.started.first as? DataClearingWideEventData else {
            XCTFail("Expected DataClearingWideEventData")
            return
        }
        XCTAssertNotNil(eventData.clearTabsDuration?.start)
        XCTAssertNil(eventData.clearTabsDuration?.end)
    }

    func testUpdateAction_withSuccess_recordsSuccessStatus() {
        // Given
        let options = FireDialogResult(
            clearingOption: .allData,
            includeHistory: true,
            includeTabsAndWindows: true,
            includeCookiesAndSiteData: true,
            includeChatHistory: false
        )
        sut.start(options: options, path: .burnAll, isAutoClear: false)
        sut.start(.clearTabs)

        // When
        sut.update(.clearTabs, result: .success(()))

        // Then
        guard let eventData = wideEventMock.started.first as? DataClearingWideEventData else {
            XCTFail("Expected DataClearingWideEventData")
            return
        }
        XCTAssertEqual(eventData.clearTabsStatus, .success)
        XCTAssertNotNil(eventData.clearTabsDuration?.end)
        XCTAssertNil(eventData.clearTabsError)
    }

    func testUpdateAction_withFailure_recordsFailureStatusAndError() {
        // Given
        let options = FireDialogResult(
            clearingOption: .allData,
            includeHistory: true,
            includeTabsAndWindows: true,
            includeCookiesAndSiteData: true,
            includeChatHistory: false
        )
        sut.start(options: options, path: .burnAll, isAutoClear: false)
        sut.start(.clearAllHistory)

        let error = NSError(domain: "TestDomain", code: 42, userInfo: nil)

        // When
        sut.update(.clearAllHistory, result: .failure(error))

        // Then
        guard let eventData = wideEventMock.started.first as? DataClearingWideEventData else {
            XCTFail("Expected DataClearingWideEventData")
            return
        }
        XCTAssertEqual(eventData.clearAllHistoryStatus, .failure)
        XCTAssertNotNil(eventData.clearAllHistoryDuration?.end)
        XCTAssertEqual(eventData.clearAllHistoryError?.domain, "TestDomain")
        XCTAssertEqual(eventData.clearAllHistoryError?.code, 42)
    }

    // MARK: - Event Completion Tests

    func testComplete_completesOverallDurationAndMarksSuccess() {
        // Given
        let options = FireDialogResult(
            clearingOption: .allData,
            includeHistory: true,
            includeTabsAndWindows: true,
            includeCookiesAndSiteData: true,
            includeChatHistory: false
        )
        sut.start(options: options, path: .burnAll, isAutoClear: false)
        sut.start(.clearTabs)
        sut.update(.clearTabs, result: .success(()))

        // When
        sut.complete()

        // Then
        XCTAssertEqual(wideEventMock.completions.count, 1)
        guard let (completedData, status) = wideEventMock.completions.first else {
            XCTFail("Expected flow to be completed")
            return
        }
        guard let eventData = completedData as? DataClearingWideEventData else {
            XCTFail("Expected DataClearingWideEventData")
            return
        }
        XCTAssertNotNil(eventData.overallDuration?.end)
        if case .success = status {
            // Success
        } else {
            XCTFail("Expected status to be .success")
        }
    }

    func testComplete_withoutStarting_doesNotCrash() {
        // When - complete without starting
        sut.complete()

        // Then - should not crash
        XCTAssertEqual(wideEventMock.completions.count, 0)
    }
}
