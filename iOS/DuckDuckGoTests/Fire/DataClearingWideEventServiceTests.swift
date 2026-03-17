//
//  DataClearingWideEventServiceTests.swift
//  DuckDuckGo
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

@testable import DuckDuckGo
@testable import Core

@MainActor
final class DataClearingWideEventServiceTests: XCTestCase {

    private var wideEventMock: WideEventMock!
    private var sut: DataClearingWideEventService!
    private var mockHistoryManager: MockHistoryManager!

    override func setUp() {
        super.setUp()
        wideEventMock = WideEventMock()
        mockHistoryManager = MockHistoryManager()
        sut = DataClearingWideEventService(wideEvent: wideEventMock)
    }

    override func tearDown() {
        wideEventMock = nil
        mockHistoryManager = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Event Lifecycle Tests

    func testStart_createsNewWideEvent() {
        // Given
        let request = FireRequest(
            options: .all,
            trigger: .manualFire,
            scope: .all,
            source: .settings
        )

        // When
        sut.start(request: request)

        // Then
        XCTAssertEqual(wideEventMock.started.count, 1)
        guard let eventData = wideEventMock.started.first as? DataClearingWideEventData else {
            XCTFail("Expected DataClearingWideEventData to be started")
            return
        }
        XCTAssertEqual(eventData.includedOptions, "tabs,data,aiChats")
        XCTAssertEqual(eventData.trigger, .manualFire)
        XCTAssertEqual(eventData.scope, .all)
        XCTAssertEqual(eventData.source, .settings)
        XCTAssertNotNil(eventData.overallDuration?.start)
        XCTAssertNil(eventData.overallDuration?.end)
    }

    func testStart_withAutoClearOnLaunch_setsTriggerToAutoClearOnLaunch() {
        // Given
        let request = FireRequest(
            options: .all,
            trigger: .autoClearOnLaunch,
            scope: .all,
            source: .autoClear
        )

        // When
        sut.start(request: request)

        // Then
        guard let eventData = wideEventMock.started.first as? DataClearingWideEventData else {
            XCTFail("Expected DataClearingWideEventData to be started")
            return
        }
        XCTAssertEqual(eventData.trigger, .autoClearOnLaunch)
        XCTAssertEqual(eventData.source, .autoClear)
    }

    func testStart_withAutoClearOnForeground_setsTriggerToAutoClearOnForeground() {
        // Given
        let request = FireRequest(
            options: .all,
            trigger: .autoClearOnForeground,
            scope: .all,
            source: .autoClear
        )

        // When
        sut.start(request: request)

        // Then
        guard let eventData = wideEventMock.started.first as? DataClearingWideEventData else {
            XCTFail("Expected DataClearingWideEventData to be started")
            return
        }
        XCTAssertEqual(eventData.trigger, .autoClearOnForeground)
    }

    func testStart_withTabScope_setsScopeToTab() {
        // Given
        let tab = Tab(uid: "test-tab-uid")
        let mockTabViewModel = TabViewModel(tab: tab, historyManager: mockHistoryManager)
        let request = FireRequest(
            options: .all,
            trigger: .manualFire,
            scope: .tab(viewModel: mockTabViewModel),
            source: .browsing
        )

        // When
        sut.start(request: request)

        // Then
        guard let eventData = wideEventMock.started.first as? DataClearingWideEventData else {
            XCTFail("Expected DataClearingWideEventData to be started")
            return
        }
        XCTAssertEqual(eventData.scope, .tab)
        XCTAssertEqual(eventData.source, .browsing)
    }

    func testStart_withDifferentSources_mapsSourcesToWideEvent() {
        // Test all source cases
        let sources: [(FireRequest.Source, DataClearingWideEventData.Source)] = [
            (.browsing, .browsing),
            (.tabSwitcher, .tabSwitcher),
            (.settings, .settings),
            (.quickFire, .quickFire),
            (.deeplink, .deeplink),
            (.autoClear, .autoClear)
        ]

        for (requestSource, expectedSource) in sources {
            // Given
            let request = FireRequest(
                options: .all,
                trigger: .manualFire,
                scope: .all,
                source: requestSource
            )

            // When
            sut.start(request: request)

            // Then
            guard let eventData = wideEventMock.started.last as? DataClearingWideEventData else {
                XCTFail("Expected DataClearingWideEventData for source \(requestSource)")
                return
            }
            XCTAssertEqual(eventData.source, expectedSource, "Source \(requestSource) should map to \(expectedSource)")
        }
    }

    func testStart_withDifferentOptions_mapsIncludedOptionsToWideEvent() {
        // Test included options mappings (iOS uses comma-separated list)
        let optionMappings: [(FireRequest.Options, String)] = [
            (.all, "tabs,data,aiChats"),
            (.tabs, "tabs"),
            (.data, "data"),
            (.aiChats, "aiChats"),
            ([.tabs, .data], "tabs,data"),
            ([.data, .aiChats], "data,aiChats"),
            ([.tabs, .aiChats], "tabs,aiChats")
        ]

        for (requestOptions, expectedIncludedOptions) in optionMappings {
            // Given
            let request = FireRequest(
                options: requestOptions,
                trigger: .manualFire,
                scope: .all,
                source: .settings
            )

            // When
            sut.start(request: request)

            // Then
            guard let eventData = wideEventMock.started.last as? DataClearingWideEventData else {
                XCTFail("Expected DataClearingWideEventData for options \(requestOptions)")
                return
            }
            XCTAssertEqual(eventData.includedOptions, expectedIncludedOptions, "Options \(requestOptions) should map to includedOptions '\(expectedIncludedOptions)'")
        }
    }

    // MARK: - Action Tracking Tests

    func testStartAction_initializesDuration() {
        // Given
        let request = FireRequest(
            options: .all,
            trigger: .manualFire,
            scope: .all,
            source: .settings
        )
        sut.start(request: request)

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
        let request = FireRequest(
            options: .all,
            trigger: .manualFire,
            scope: .all,
            source: .settings
        )
        sut.start(request: request)
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
        let request = FireRequest(
            options: .all,
            trigger: .manualFire,
            scope: .all,
            source: .settings
        )
        sut.start(request: request)
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

    func testUpdateAction_withiOSOnlyActions_recordsCorrectly() {
        // Given
        let request = FireRequest(
            options: .all,
            trigger: .manualFire,
            scope: .all,
            source: .settings
        )
        sut.start(request: request)

        // Test iOS-only actions
        let iOSActions: [DataClearingWideEventData.Action] = [
            .clearURLCaches,
            .clearDaxDialogsHeldURLData,
            .removeObservationsData,
            .removeAllContainersAfterDelay
        ]

        for action in iOSActions {
            // When
            sut.start(action)
            sut.update(action, result: .success(()))

            // Then
            guard let eventData = wideEventMock.started.first as? DataClearingWideEventData else {
                XCTFail("Expected DataClearingWideEventData")
                return
            }
            let status = eventData[keyPath: action.statusPath]
            XCTAssertEqual(status, .success, "iOS action \(action) should record success")
        }
    }

    // MARK: - Event Completion Tests

    func testComplete_completesOverallDurationAndMarksSuccess() {
        // Given
        let request = FireRequest(
            options: .all,
            trigger: .manualFire,
            scope: .all,
            source: .settings
        )
        sut.start(request: request)
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
