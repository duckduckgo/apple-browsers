//
//  WebNotificationClickHandlerTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

@testable import DuckDuckGo_Privacy_Browser

// MARK: - Mock Tab Finder

@MainActor
final class MockWebNotificationTabFinder: WebNotificationTabFinding {

    var tabToReturn: Tab?
    private(set) var findTabCalledWithUUID: String?
    private(set) var focusTabCalledWithTab: Tab?
    private(set) var focusBrowserCalled = false

    func findTab(byUUID uuid: String) -> Tab? {
        findTabCalledWithUUID = uuid
        return tabToReturn
    }

    func focusTab(_ tab: Tab) {
        focusTabCalledWithTab = tab
    }

    func focusBrowser() {
        focusBrowserCalled = true
    }
}

// MARK: - Mock Web Notifications Protocol

final class MockWebNotificationsProtocol: WebNotificationsProtocol {

    private(set) var sendClickEventCalledWithId: String?

    func sendClickEvent(notificationId: String) {
        sendClickEventCalledWithId = notificationId
    }
}

// MARK: - Tests

@MainActor
final class WebNotificationClickHandlerTests: XCTestCase {

    var mockTabFinder: MockWebNotificationTabFinder!
    var handler: WebNotificationClickHandler!

    override func setUp() {
        super.setUp()
        mockTabFinder = MockWebNotificationTabFinder()
        handler = WebNotificationClickHandler(tabFinder: mockTabFinder)
    }

    override func tearDown() {
        handler = nil
        mockTabFinder = nil
        super.tearDown()
    }

    // MARK: - Tab Found Tests

    func testWhenTabExistsThenFindsTabByUUID() {
        let tab = Tab(content: .newtab)
        mockTabFinder.tabToReturn = tab

        handler.handleClick(tabUUID: "test-uuid-123", notificationId: "notif-1")

        XCTAssertEqual(mockTabFinder.findTabCalledWithUUID, "test-uuid-123")
    }

    func testWhenTabExistsThenFocusesTab() {
        let tab = Tab(content: .newtab)
        mockTabFinder.tabToReturn = tab

        handler.handleClick(tabUUID: "test-uuid", notificationId: "notif-1")

        XCTAssertTrue(mockTabFinder.focusTabCalledWithTab === tab)
    }

    func testWhenTabExistsThenDoesNotFocusBrowser() {
        let tab = Tab(content: .newtab)
        mockTabFinder.tabToReturn = tab

        handler.handleClick(tabUUID: "test-uuid", notificationId: "notif-1")

        XCTAssertFalse(mockTabFinder.focusBrowserCalled)
    }

    // MARK: - Tab Not Found Tests

    func testWhenTabNotFoundThenFocusesBrowser() {
        mockTabFinder.tabToReturn = nil

        handler.handleClick(tabUUID: "missing-uuid", notificationId: "notif-1")

        XCTAssertTrue(mockTabFinder.focusBrowserCalled)
    }

    func testWhenTabNotFoundThenDoesNotFocusTab() {
        mockTabFinder.tabToReturn = nil

        handler.handleClick(tabUUID: "missing-uuid", notificationId: "notif-1")

        XCTAssertNil(mockTabFinder.focusTabCalledWithTab)
    }
}
