//
//  AIChatSidebarTests.swift
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
import Combine
import AIChat
@testable import DuckDuckGo_Privacy_Browser

final class AIChatSidebarTests: XCTestCase {

    var sidebar: AIChatSidebar!

    override func setUp() {
        super.setUp()
        sidebar = AIChatSidebar(burnerMode: .regular)
    }

    override func tearDown() {
        sidebar = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInit_setsDefaultProperties() {
        // Given & When
        let sidebar = AIChatSidebar(burnerMode: .regular)

        // Then
        XCTAssertNil(sidebar.restorationData)
        XCTAssertFalse(sidebar.isPresented)
        XCTAssertNil(sidebar.hiddenAt)
        XCTAssertNil(sidebar.sidebarViewController)
    }

    // MARK: - Unload View Controller Tests

    func testUnloadViewController_withPersistingState_clearsViewController() {
        // Given
        let aiChatRemoteSettings = AIChatRemoteSettings()
        let initialAIChatURL = aiChatRemoteSettings.aiChatURL.forAIChatSidebar()
        let viewController = AIChatSidebarViewController(currentAIChatURL: initialAIChatURL, burnerMode: .regular)
        sidebar.sidebarViewController = viewController
        XCTAssertNotNil(sidebar.sidebarViewController)

        // When
        sidebar.unloadViewController(persistingState: true)

        // Then
        XCTAssertNil(sidebar.sidebarViewController)
        XCTAssertFalse(sidebar.isPresented)
        XCTAssertNotNil(sidebar.hiddenAt)
    }

    func testUnloadViewController_withoutPersistingState_clearsViewController() {
        // Given
        let aiChatRemoteSettings = AIChatRemoteSettings()
        let initialAIChatURL = aiChatRemoteSettings.aiChatURL.forAIChatSidebar()
        let viewController = AIChatSidebarViewController(currentAIChatURL: initialAIChatURL, burnerMode: .regular)
        sidebar.sidebarViewController = viewController
        XCTAssertNotNil(sidebar.sidebarViewController)

        // When
        sidebar.unloadViewController(persistingState: false)

        // Then
        XCTAssertNil(sidebar.sidebarViewController)
        XCTAssertFalse(sidebar.isPresented)
        XCTAssertNotNil(sidebar.hiddenAt)
    }

    func testUnloadViewController_setsHiddenState() {
        // Given
        let aiChatRemoteSettings = AIChatRemoteSettings()
        let initialAIChatURL = aiChatRemoteSettings.aiChatURL.forAIChatSidebar()
        let viewController = AIChatSidebarViewController(currentAIChatURL: initialAIChatURL, burnerMode: .regular)
        sidebar.sidebarViewController = viewController
        sidebar.setRevealed()
        XCTAssertTrue(sidebar.isPresented)
        XCTAssertNil(sidebar.hiddenAt)

        // When
        sidebar.unloadViewController(persistingState: true)

        // Then
        XCTAssertFalse(sidebar.isPresented)
        XCTAssertNotNil(sidebar.hiddenAt)
    }

    // MARK: - State Management Tests

    func testSetRevealed_clearsHiddenAt() {
        // Given
        sidebar.setHidden()
        XCTAssertNotNil(sidebar.hiddenAt)

        // When
        sidebar.setRevealed()

        // Then
        XCTAssertTrue(sidebar.isPresented)
        XCTAssertNil(sidebar.hiddenAt)
    }

    func testSetHidden_setsHiddenAt() {
        // Given
        sidebar.setRevealed()
        XCTAssertTrue(sidebar.isPresented)
        XCTAssertNil(sidebar.hiddenAt)

        // When
        sidebar.setHidden()

        // Then
        XCTAssertFalse(sidebar.isPresented)
        XCTAssertNotNil(sidebar.hiddenAt)
    }

    // MARK: - Session Expiry Tests

    func testIsSessionExpired_withNilHiddenAt_returnsFalse() {
        // Given - sidebar starts with nil hiddenAt
        XCTAssertNil(sidebar.hiddenAt)

        // When & Then
        XCTAssertFalse(sidebar.isSessionExpired)
    }

    func testIsSessionExpired_withRecentHiddenAt_returnsFalse() {
        // Given - sidebar hidden 30 minutes ago (within default 60 minute timeout)
        let recentDate = Date().addingTimeInterval(-1800) // 30 minutes ago
        sidebar.updateHiddenAt(recentDate)

        // When & Then
        XCTAssertFalse(sidebar.isSessionExpired)
    }

    func testIsSessionExpired_withOldHiddenAt_returnsTrue() {
        // Given - sidebar hidden 70 minutes ago (exceeds default 60 minute timeout)
        let oldDate = Date().addingTimeInterval(-4200) // 70 minutes ago
        sidebar.updateHiddenAt(oldDate)

        // When & Then
        XCTAssertTrue(sidebar.isSessionExpired)
    }

    func testIsSessionExpired_afterSetRevealed_returnsFalse() {
        // Given - sidebar was hidden long ago
        let oldDate = Date().addingTimeInterval(-4200) // 70 minutes ago
        sidebar.updateHiddenAt(oldDate)
        XCTAssertTrue(sidebar.isSessionExpired)

        // When - sidebar is revealed
        sidebar.setRevealed()

        // Then - session is no longer expired (hiddenAt is cleared)
        XCTAssertFalse(sidebar.isSessionExpired)
    }
}
