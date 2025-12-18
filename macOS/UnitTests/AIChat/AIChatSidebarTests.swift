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

    // MARK: - Reset Tests

    func testWhenResetCalledThenCurrentAIChatURLFallsBackToInitialURL() {
        // Given - Create sidebar with base URL (no chatID)
        let aiChatRemoteSettings = AIChatRemoteSettings()
        let baseURL = aiChatRemoteSettings.aiChatURL.forAIChatSidebar()
        let sidebar = AIChatSidebar(initialAIChatURL: baseURL, burnerMode: .regular)

        // Simulate that the sidebar was used and URL with chatID was saved
        let urlWithChatID = baseURL.appendingParameter(name: "chatID", value: "test-chat-id")
        let viewController = AIChatSidebarViewController(currentAIChatURL: urlWithChatID, burnerMode: .regular)
        sidebar.sidebarViewController = viewController
        sidebar.unloadViewController(persistingState: true)

        // Verify URL with chatID was saved
        XCTAssertTrue(sidebar.currentAIChatURL.absoluteString.contains("chatID"))

        // When
        sidebar.reset()

        // Then - currentAIChatURL should fall back to baseURL (no chatID)
        XCTAssertEqual(sidebar.currentAIChatURL, baseURL)
        XCTAssertFalse(sidebar.currentAIChatURL.absoluteString.contains("chatID"))
    }

    func testWhenResetCalledThenRestorationDataIsCleared() {
        // Given
        sidebar.updateRestorationData("test-restoration-data")
        XCTAssertNotNil(sidebar.restorationData)

        // When
        sidebar.reset()

        // Then
        XCTAssertNil(sidebar.restorationData)
    }

    func testWhenResetCalledThenBothURLAndRestorationDataAreCleared() {
        // Given - Create sidebar with base URL (no chatID)
        let aiChatRemoteSettings = AIChatRemoteSettings()
        let baseURL = aiChatRemoteSettings.aiChatURL.forAIChatSidebar()
        let sidebar = AIChatSidebar(initialAIChatURL: baseURL, burnerMode: .regular)

        // Simulate sidebar usage with chatID URL and restoration data
        let urlWithChatID = baseURL.appendingParameter(name: "chatID", value: "test-chat-id")
        let viewController = AIChatSidebarViewController(currentAIChatURL: urlWithChatID, burnerMode: .regular)
        sidebar.sidebarViewController = viewController
        sidebar.unloadViewController(persistingState: true)
        sidebar.updateRestorationData("test-restoration-data")

        XCTAssertTrue(sidebar.currentAIChatURL.absoluteString.contains("chatID"))
        XCTAssertNotNil(sidebar.restorationData)

        // When
        sidebar.reset()

        // Then
        XCTAssertEqual(sidebar.currentAIChatURL, baseURL)
        XCTAssertFalse(sidebar.currentAIChatURL.absoluteString.contains("chatID"))
        XCTAssertNil(sidebar.restorationData)
    }

    func testWhenResetCalledThenPresentedStateIsNotAffected() {
        // Given
        sidebar.setRevealed()
        XCTAssertTrue(sidebar.isPresented)

        // When
        sidebar.reset()

        // Then - isPresented should not be affected
        XCTAssertTrue(sidebar.isPresented)
    }

    func testWhenResetCalledThenHiddenAtIsNotAffected() {
        // Given
        sidebar.setHidden()
        XCTAssertNotNil(sidebar.hiddenAt)

        // When
        sidebar.reset()

        // Then - hiddenAt should not be affected
        XCTAssertNotNil(sidebar.hiddenAt)
    }
}
