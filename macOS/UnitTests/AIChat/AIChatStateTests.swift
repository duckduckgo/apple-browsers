//
//  AIChatStateTests.swift
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
import Combine
import AIChat
@testable import DuckDuckGo_Privacy_Browser

final class AIChatStateTests: XCTestCase {

    var chatState: AIChatState!

    override func setUp() {
        super.setUp()
        chatState = AIChatState()
    }

    override func tearDown() {
        chatState = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInit_setsDefaultProperties() {
        // Given & When
        let state = AIChatState()

        // Then
        XCTAssertNil(state.restorationData)
        XCTAssertEqual(state.presentationMode, .hidden)
        XCTAssertEqual(state.presentationMode, .hidden)
        XCTAssertNil(state.hiddenAt)
    }

    // MARK: - State Management Tests

    func testSetSidebar_clearsHiddenAt() {
        // Given
        chatState.setHidden()
        XCTAssertNotNil(chatState.hiddenAt)

        // When
        chatState.setSidebar()

        // Then
        XCTAssertEqual(chatState.presentationMode, .sidebar)
        XCTAssertNil(chatState.hiddenAt)
    }

    func testSetHidden_setsHiddenAt() {
        // Given
        chatState.setSidebar()
        XCTAssertEqual(chatState.presentationMode, .sidebar)
        XCTAssertNil(chatState.hiddenAt)

        // When
        chatState.setHidden()

        // Then
        XCTAssertEqual(chatState.presentationMode, .hidden)
        XCTAssertNotNil(chatState.hiddenAt)
    }

    func testSetHidden_doesNotOverwriteExistingHiddenAt() {
        // Given
        let firstDate = Date().addingTimeInterval(-100)
        chatState.setHidden(at: firstDate)
        XCTAssertEqual(chatState.hiddenAt, firstDate)

        // When
        chatState.setHidden(at: Date())

        // Then - original date preserved
        XCTAssertEqual(chatState.hiddenAt, firstDate)
    }

    // MARK: - Session Expiry Tests

    func testIsSessionExpired_withNilHiddenAt_returnsFalse() {
        XCTAssertNil(chatState.hiddenAt)
        XCTAssertFalse(chatState.isSessionExpired)
    }

    func testIsSessionExpired_withRecentHiddenAt_returnsFalse() {
        let recentDate = Date().addingTimeInterval(-1800) // 30 minutes ago
        chatState.updateHiddenAt(recentDate)

        XCTAssertFalse(chatState.isSessionExpired)
    }

    func testIsSessionExpired_withOldHiddenAt_returnsTrue() {
        let oldDate = Date().addingTimeInterval(-4200) // 70 minutes ago
        chatState.updateHiddenAt(oldDate)

        XCTAssertTrue(chatState.isSessionExpired)
    }

    func testIsSessionExpired_afterSetSidebar_returnsFalse() {
        // Given - hidden long ago
        let oldDate = Date().addingTimeInterval(-4200)
        chatState.updateHiddenAt(oldDate)
        XCTAssertTrue(chatState.isSessionExpired)

        // When
        chatState.setSidebar()

        // Then - hiddenAt cleared, no longer expired
        XCTAssertFalse(chatState.isSessionExpired)
    }

    // MARK: - Presentation Mode Transition Tests

    func testSetSidebar_setsPresentationModeToSidebar() {
        chatState.setSidebar()
        XCTAssertEqual(chatState.presentationMode, .sidebar)
    }

    func testSetFloating_setsPresentationModeToFloating() {
        chatState.setFloating()
        XCTAssertEqual(chatState.presentationMode, .floating)
    }

    func testSetFloating_clearsHiddenAt() {
        // Given
        chatState.setHidden()
        XCTAssertNotNil(chatState.hiddenAt)

        // When
        chatState.setFloating()

        // Then
        XCTAssertEqual(chatState.presentationMode, .floating)
        XCTAssertNil(chatState.hiddenAt)
    }

    func testSetSidebar_fromFloating_setsPresentationModeToSidebar() {
        chatState.setFloating()
        XCTAssertEqual(chatState.presentationMode, .floating)

        chatState.setSidebar()
        XCTAssertEqual(chatState.presentationMode, .sidebar)
    }

    func testSetHidden_setsPresentationModeToHidden() {
        chatState.setSidebar()
        XCTAssertEqual(chatState.presentationMode, .sidebar)

        chatState.setHidden()
        XCTAssertEqual(chatState.presentationMode, .hidden)
    }

    // MARK: - NSSecureCoding Round-Trip Tests

    func testNSSecureCoding_roundTrip_preservesPresentationMode() {
        // Given
        chatState.setFloating()
        chatState.sidebarWidth = 450

        // When
        let data = try! NSKeyedArchiver.archivedData(withRootObject: chatState!, requiringSecureCoding: true)
        let decoded = try! NSKeyedUnarchiver.unarchivedObject(ofClass: AIChatState.self, from: data)!

        // Then
        XCTAssertEqual(decoded.presentationMode, .floating)
        XCTAssertEqual(decoded.sidebarWidth, 450)
    }

    func testNSSecureCoding_legacyFormat_presentedStateMapsToSidebar() throws {
        // Given -- encode using the old key name (no root object)
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        let url = AIChatRemoteSettings().aiChatURL.forAIChatSidebar()
        archiver.encode(url as NSURL, forKey: AIChatState.CodingKeys.initialAIChatURL)
        archiver.encode(true, forKey: AIChatState.CodingKeys.isPresented)
        archiver.finishEncoding()

        // When -- decode using the coder init directly (no root object in archive)
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        unarchiver.requiresSecureCoding = true
        let decoded = AIChatState(coder: unarchiver)!

        // Then
        XCTAssertEqual(decoded.presentationMode, .sidebar)
    }

    func testNSSecureCoding_legacyFormat_hiddenState() throws {
        // Given
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        let url = AIChatRemoteSettings().aiChatURL.forAIChatSidebar()
        archiver.encode(url as NSURL, forKey: AIChatState.CodingKeys.initialAIChatURL)
        archiver.encode(false, forKey: AIChatState.CodingKeys.isPresented)
        archiver.finishEncoding()

        // When
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        unarchiver.requiresSecureCoding = true
        let decoded = AIChatState(coder: unarchiver)!

        // Then
        XCTAssertEqual(decoded.presentationMode, .hidden)
    }

    func testNSSecureCoding_legacyFormat_sidebarState() throws {
        // Given
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        let url = AIChatRemoteSettings().aiChatURL.forAIChatSidebar()
        archiver.encode(url as NSURL, forKey: AIChatState.CodingKeys.initialAIChatURL)
        archiver.encode(true, forKey: AIChatState.CodingKeys.isPresented)
        archiver.finishEncoding()

        // When
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        unarchiver.requiresSecureCoding = true
        let decoded = AIChatState(coder: unarchiver)!

        // Then
        XCTAssertEqual(decoded.presentationMode, .sidebar)
    }

    func testNSSecureCoding_whenPresentationModeIsFloating_hiddenAtIsNormalizedToNil() {
        // Given
        chatState.setHidden(at: Date().addingTimeInterval(-3600))
        chatState.setFloating()
        chatState.updateHiddenAt(Date().addingTimeInterval(-3600))

        // When
        let data = try! NSKeyedArchiver.archivedData(withRootObject: chatState!, requiringSecureCoding: true)
        let decoded = try! NSKeyedUnarchiver.unarchivedObject(ofClass: AIChatState.self, from: data)!

        // Then
        XCTAssertEqual(decoded.presentationMode, .floating)
        XCTAssertNil(decoded.hiddenAt)
    }
}
