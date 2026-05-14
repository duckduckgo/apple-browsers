//
//  AIChatSessionStoreTests.swift
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

import AIChat
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class AIChatSessionStoreTests: XCTestCase {

    var provider: AIChatSessionStore!

    override func setUp() {
        super.setUp()
        provider = AIChatSessionStore(featureFlagger: MockFeatureFlagger())
    }

    override func tearDown() {
        provider = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInit_withDefaultParameters_setsEmptyDictionary() {
        // Given & When
        let provider = AIChatSessionStore(featureFlagger: MockFeatureFlagger())

        // Then
        XCTAssertTrue(provider.statesByTab.isEmpty)
    }

    // MARK: - Get Or Create Session Tests

    func testGetOrCreateSession_createsNewSession() {
        // Given
        let tabID = "new-tab-id"

        // When
        let session = provider.getOrCreateSession(for: tabID, burnerMode: .regular)

        // Then
        XCTAssertNotNil(session)
        XCTAssertEqual(provider.sessions.count, 1)
        XCTAssertNotNil(provider.sessions[tabID])
    }

    func testGetOrCreateSession_returnsExistingSession() {
        // Given
        let tabID = "existing-tab"
        let first = provider.getOrCreateSession(for: tabID, burnerMode: .regular)

        // When
        let second = provider.getOrCreateSession(for: tabID, burnerMode: .burner(websiteDataStore: .nonPersistent()))

        // Then
        XCTAssertEqual(provider.sessions.count, 1)
        XCTAssertIdentical(first, second)
    }

    // MARK: - Chat View Controller Tests

    func testMakeChatViewController_createsAndStoresViewController() {
        // Given
        let tabID = "new-tab-id"
        let session = provider.getOrCreateSession(for: tabID, burnerMode: .regular)

        // When
        let chatViewController = session.makeChatViewController(tabID: tabID)

        // Then
        XCTAssertNotNil(chatViewController)
        XCTAssertIdentical(provider.sessions[tabID]?.chatViewController, chatViewController)
    }

    func testMakeChatViewController_withBurnerMode_createsCorrectViewController() {
        // Given
        let tabID = "burner-tab-id"
        let session = provider.getOrCreateSession(for: tabID, burnerMode: .burner(websiteDataStore: .nonPersistent()))

        // When
        let chatViewController = session.makeChatViewController(tabID: tabID)

        // Then
        XCTAssertNotNil(chatViewController)
        XCTAssertIdentical(provider.sessions[tabID]?.chatViewController, chatViewController)
    }

    func testMakeChatViewController_withExistingVC_returnsExistingViewController() {
        // Given
        let tabID = "existing-tab"
        let session = provider.getOrCreateSession(for: tabID, burnerMode: .regular)
        let firstViewController = session.makeChatViewController(tabID: tabID)

        // When
        let secondViewController = session.makeChatViewController(tabID: tabID)

        // Then
        XCTAssertIdentical(firstViewController, secondViewController)
    }

    func testGetChatViewController_withNonExistentTab_returnsNil() {
        // Given
        let tabID = "non-existent-tab"

        // When
        let retrievedViewController = provider.sessions[tabID]?.chatViewController

        // Then
        XCTAssertNil(retrievedViewController)
    }

    // MARK: - Is Showing Sidebar Tests

    func testIsShowingSidebar_withRevealedSidebar_returnsTrue() {
        // Given
        let tabID = "test-tab"
        let session = provider.getOrCreateSession(for: tabID, burnerMode: .regular)
        session.state.setSidebar()

        // Then
        XCTAssertEqual(session.state.presentationMode, .sidebar)
    }

    func testIsShowingSidebar_withUnrevealedSidebar_returnsFalse() {
        // Given
        let tabID = "test-tab"
        let session = provider.getOrCreateSession(for: tabID, burnerMode: .regular)

        // Then
        XCTAssertEqual(session.state.presentationMode, .hidden)
    }

    func testIsShowingSidebar_withNonExistentSession_returnsFalse() {
        // Given
        let tabID = "non-existent-tab"

        // Then
        XCTAssertEqual(provider.sessions[tabID]?.state.presentationMode ?? .hidden, .hidden)
    }

    // MARK: - End Session Tests

    func testEndSession_withExistingTab_removesSession() {
        // Given
        let tabID = "closing-tab"
        _ = provider.getOrCreateSession(for: tabID, burnerMode: .regular)
        XCTAssertEqual(provider.sessions.count, 1)

        // When
        provider.endSession(for: tabID)

        // Then
        XCTAssertEqual(provider.sessions.count, 0)
        XCTAssertNil(provider.sessions[tabID])
    }

    func testEndSession_withNonExistentTab_doesNothing() {
        // Given
        let existingTabID = "existing-tab"
        let nonExistentTabID = "non-existent-tab"
        _ = provider.getOrCreateSession(for: existingTabID, burnerMode: .regular)
        let initialCount = provider.sessions.count

        // When
        provider.endSession(for: nonExistentTabID)

        // Then
        XCTAssertEqual(provider.sessions.count, initialCount)
        XCTAssertNotNil(provider.sessions[existingTabID])
    }

    func testEndSession_withKeepSessionEnabled_preservesSessionData() {
        // Given
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatKeepSession]
        let keepSessionProvider = AIChatSessionStore(featureFlagger: mockFeatureFlagger)

        let tabID = "keep-session-tab"
        let session = keepSessionProvider.getOrCreateSession(for: tabID, burnerMode: .regular)
        _ = session.makeChatViewController(tabID: tabID)
        session.state.setSidebar()
        XCTAssertEqual(session.state.presentationMode, .sidebar)

        // When
        keepSessionProvider.endSession(for: tabID)

        // Then - session is preserved but marked as hidden with VC torn down
        XCTAssertEqual(keepSessionProvider.sessions.count, 1)
        XCTAssertNotNil(keepSessionProvider.sessions[tabID])
        XCTAssertEqual(keepSessionProvider.sessions[tabID]!.state.presentationMode, .hidden)
        XCTAssertNil(keepSessionProvider.sessions[tabID]?.chatViewController)
        XCTAssertNotNil(keepSessionProvider.sessions[tabID]?.state.hiddenAt)
    }

    func testEndSession_withKeepSessionDisabled_removesSessionData() {
        // Given
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = []
        let noKeepSessionProvider = AIChatSessionStore(featureFlagger: mockFeatureFlagger)

        let tabID = "no-keep-session-tab"
        let session = noKeepSessionProvider.getOrCreateSession(for: tabID, burnerMode: .regular)
        _ = session.makeChatViewController(tabID: tabID)
        session.state.setSidebar()

        // When
        noKeepSessionProvider.endSession(for: tabID)

        // Then - session is completely removed
        XCTAssertEqual(noKeepSessionProvider.sessions.count, 0)
        XCTAssertNil(noKeepSessionProvider.sessions[tabID])
    }

    // MARK: - Remove Orphaned Sessions Tests

    func testRemoveOrphanedSessions_removesUnneededSessions() {
        // Given
        _ = provider.getOrCreateSession(for: "tab1", burnerMode: .regular)
        _ = provider.getOrCreateSession(for: "tab2", burnerMode: .regular)
        _ = provider.getOrCreateSession(for: "tab3", burnerMode: .regular)
        XCTAssertEqual(provider.sessions.count, 3)

        let currentTabIDs = ["tab1", "tab3"]

        // When
        provider.removeOrphanedSessions(currentTabIDs: currentTabIDs)

        // Then
        XCTAssertEqual(provider.sessions.count, 2)
        XCTAssertNotNil(provider.sessions["tab1"])
        XCTAssertNil(provider.sessions["tab2"])
        XCTAssertNotNil(provider.sessions["tab3"])
    }

    func testRemoveOrphanedSessions_withEmptyCurrentTabIDs_removesAllSessions() {
        // Given
        _ = provider.getOrCreateSession(for: "tab1", burnerMode: .regular)
        _ = provider.getOrCreateSession(for: "tab2", burnerMode: .regular)
        XCTAssertEqual(provider.sessions.count, 2)

        // When
        provider.removeOrphanedSessions(currentTabIDs: [])

        // Then
        XCTAssertEqual(provider.sessions.count, 0)
    }

    func testRemoveOrphanedSessions_withAllCurrentTabs_removesNoSessions() {
        // Given
        _ = provider.getOrCreateSession(for: "tab1", burnerMode: .regular)
        _ = provider.getOrCreateSession(for: "tab2", burnerMode: .regular)
        let allTabIDs = ["tab1", "tab2"]

        // When
        provider.removeOrphanedSessions(currentTabIDs: allTabIDs)

        // Then
        XCTAssertEqual(provider.sessions.count, 2)
        XCTAssertNotNil(provider.sessions["tab1"])
        XCTAssertNotNil(provider.sessions["tab2"])
    }

    func testRemoveOrphanedSessions_withExtraCurrentTabIDs_doesNotAddSessions() {
        // Given
        _ = provider.getOrCreateSession(for: "tab1", burnerMode: .regular)
        let currentTabIDs = ["tab1", "tab2", "tab3"]

        // When
        provider.removeOrphanedSessions(currentTabIDs: currentTabIDs)

        // Then
        XCTAssertEqual(provider.sessions.count, 1)
        XCTAssertNotNil(provider.sessions["tab1"])
    }

    // MARK: - Restore State Tests

    func testRestoreState_clearsExistingState() {
        // Given
        _ = provider.getOrCreateSession(for: "existing-tab", burnerMode: .regular)
        XCTAssertEqual(provider.sessions.count, 1)

        // When
        provider.restoreState([:])

        // Then
        XCTAssertTrue(provider.sessions.isEmpty)
    }

    func testRestoreState_setsNewState() {
        // Given
        let newState = AIChatState()
        let newStates: AIChatStatesByTab = ["new-tab": newState]

        // When
        provider.restoreState(newStates)

        // Then
        XCTAssertEqual(provider.sessions.count, 1)
        XCTAssertIdentical(provider.sessions["new-tab"]?.state, newState)
    }

    func testRestoreState_replacesCompleteState() {
        // Given
        _ = provider.getOrCreateSession(for: "old-tab1", burnerMode: .regular)
        _ = provider.getOrCreateSession(for: "old-tab2", burnerMode: .regular)
        XCTAssertEqual(provider.sessions.count, 2)

        let newState1 = AIChatState()
        let newState2 = AIChatState()
        let newStates: AIChatStatesByTab = ["new-tab1": newState1, "new-tab2": newState2]

        // When
        provider.restoreState(newStates)

        // Then
        XCTAssertEqual(provider.sessions.count, 2)
        XCTAssertNil(provider.sessions["old-tab1"])
        XCTAssertNil(provider.sessions["old-tab2"])
        XCTAssertIdentical(provider.sessions["new-tab1"]?.state, newState1)
        XCTAssertIdentical(provider.sessions["new-tab2"]?.state, newState2)
    }

    // MARK: - Integration Tests

    func testMultipleSessionOperations() {
        // Given
        let tab1 = "tab1"
        let tab2 = "tab2"
        let tab3 = "tab3"

        let session1 = provider.getOrCreateSession(for: tab1, burnerMode: .regular)
        let session2 = provider.getOrCreateSession(for: tab2, burnerMode: .burner(websiteDataStore: .nonPersistent()))
        let session3 = provider.getOrCreateSession(for: tab3, burnerMode: .regular)
        _ = session1.makeChatViewController(tabID: tab1)
        _ = session2.makeChatViewController(tabID: tab2)
        _ = session3.makeChatViewController(tabID: tab3)

        XCTAssertEqual(provider.sessions.count, 3)
        XCTAssertNotNil(provider.sessions[tab1]?.chatViewController)
        XCTAssertNotNil(provider.sessions[tab2]?.chatViewController)
        XCTAssertNotNil(provider.sessions[tab3]?.chatViewController)

        // When - End one session
        provider.endSession(for: tab2)

        // Then
        XCTAssertEqual(provider.sessions.count, 2)
        XCTAssertNotNil(provider.sessions[tab1]?.chatViewController)
        XCTAssertNil(provider.sessions[tab2])
        XCTAssertNotNil(provider.sessions[tab3]?.chatViewController)

        // When - Clean up with only tab1 active
        provider.removeOrphanedSessions(currentTabIDs: [tab1])

        // Then
        XCTAssertEqual(provider.sessions.count, 1)
        XCTAssertNotNil(provider.sessions[tab1]?.chatViewController)
        XCTAssertNil(provider.sessions[tab2])
        XCTAssertNil(provider.sessions[tab3])
    }

    // MARK: - Session Timeout Tests

    func testGetOrCreateSession_withExpiredSession_createsNewSession() {
        // Given
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatKeepSession]
        let keepSessionProvider = AIChatSessionStore(featureFlagger: mockFeatureFlagger)

        let tabID = "session-timeout-tab"
        let session = keepSessionProvider.getOrCreateSession(for: tabID, burnerMode: .regular)
        _ = session.makeChatViewController(tabID: tabID)
        session.state.setSidebar()

        keepSessionProvider.endSession(for: tabID)
        XCTAssertNotNil(keepSessionProvider.sessions[tabID])
        XCTAssertNotNil(keepSessionProvider.sessions[tabID]?.state.hiddenAt)

        let oldDate = Date().addingTimeInterval(-4000)
        keepSessionProvider.sessions[tabID]?.state.updateHiddenAt(oldDate)

        // When
        let newSession = keepSessionProvider.getOrCreateSession(for: tabID, burnerMode: .regular)

        // Then - fresh session since the old one expired
        XCTAssertNotNil(newSession)
        XCTAssertNil(newSession.state.hiddenAt)
    }

    func testGetOrCreateSession_withValidSession_returnsExistingSession() {
        // Given
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatKeepSession]
        let keepSessionProvider = AIChatSessionStore(featureFlagger: mockFeatureFlagger)

        let tabID = "valid-session-tab"
        let session = keepSessionProvider.getOrCreateSession(for: tabID, burnerMode: .regular)
        _ = session.makeChatViewController(tabID: tabID)
        session.state.setSidebar()

        keepSessionProvider.endSession(for: tabID)
        XCTAssertNotNil(keepSessionProvider.sessions[tabID])

        let recentDate = Date().addingTimeInterval(-1800)
        keepSessionProvider.sessions[tabID]?.state.setHidden(at: recentDate)

        // When
        let existingSession = keepSessionProvider.getOrCreateSession(for: tabID, burnerMode: .regular)

        // Then - reuses existing session since it hasn't expired
        XCTAssertNotNil(existingSession)
        XCTAssertNotNil(existingSession.state.hiddenAt)
    }

    // MARK: - State Management Tests

    func testSetSidebar_updatesState() {
        // Given
        let tabID = "revealed-tab"
        let session = provider.getOrCreateSession(for: tabID, burnerMode: .regular)
        XCTAssertEqual(session.state.presentationMode, .hidden)

        // When
        session.state.setSidebar()

        // Then
        XCTAssertEqual(session.state.presentationMode, .sidebar)
        XCTAssertNil(session.state.hiddenAt)
    }

    func testSetHidden_updatesState() {
        // Given
        let tabID = "hidden-tab"
        let session = provider.getOrCreateSession(for: tabID, burnerMode: .regular)
        session.state.setSidebar()
        XCTAssertEqual(session.state.presentationMode, .sidebar)

        // When
        session.state.setHidden()

        // Then
        XCTAssertEqual(session.state.presentationMode, .hidden)
        XCTAssertNotNil(session.state.hiddenAt)
    }

    // MARK: - Remove Session Tests

    func testRemoveSession_removesSessionFromDictionary() {
        // Given
        let tabID = "reset-test-tab"
        let session = provider.getOrCreateSession(for: tabID, burnerMode: .regular)
        session.state.restorationData = "test-data"
        XCTAssertNotNil(provider.sessions[tabID])

        // When
        provider.removeSession(for: tabID)

        // Then
        XCTAssertNil(provider.sessions[tabID])
        XCTAssertEqual(provider.sessions.count, 0)
    }

    func testRemoveSession_forNonExistentTab_doesNothing() {
        // Given
        let existingTabID = "existing-tab"
        let nonExistentTabID = "non-existent-tab"
        let session = provider.getOrCreateSession(for: existingTabID, burnerMode: .regular)
        session.state.restorationData = "test-data"
        let initialCount = provider.sessions.count

        // When
        provider.removeSession(for: nonExistentTabID)

        // Then
        XCTAssertEqual(provider.sessions.count, initialCount)
        XCTAssertNotNil(provider.sessions[existingTabID]?.state.restorationData)
    }

    func testRemoveSession_doesNotAffectOtherTabs() {
        // Given
        let tabID1 = "tab1"
        let tabID2 = "tab2"
        let session1 = provider.getOrCreateSession(for: tabID1, burnerMode: .regular)
        let session2 = provider.getOrCreateSession(for: tabID2, burnerMode: .regular)
        session1.state.restorationData = "data1"
        session2.state.restorationData = "data2"

        // When
        provider.removeSession(for: tabID1)

        // Then
        XCTAssertNil(provider.sessions[tabID1])
        XCTAssertNotNil(provider.sessions[tabID2])
        XCTAssertEqual(provider.sessions[tabID2]?.state.restorationData, "data2")
    }

    func testRemoveSession_beforeNewHandoff_createsFreshSession() {
        // Given
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatKeepSession]
        let keepSessionProvider = AIChatSessionStore(featureFlagger: mockFeatureFlagger)

        let tabID = "fresh-url-tab"
        let session = keepSessionProvider.getOrCreateSession(for: tabID, burnerMode: .regular)
        _ = session.makeChatViewController(tabID: tabID)
        session.state.setSidebar()
        session.state.restorationData = "old-chat-data"

        keepSessionProvider.endSession(for: tabID)
        XCTAssertNotNil(keepSessionProvider.sessions[tabID])

        // When - Remove then recreate (simulating new handoff)
        keepSessionProvider.removeSession(for: tabID)
        XCTAssertNil(keepSessionProvider.sessions[tabID])

        let newSession = keepSessionProvider.getOrCreateSession(for: tabID, burnerMode: .regular)

        // Then - fresh session without restoration data
        XCTAssertNotNil(newSession)
        XCTAssertNil(newSession.state.restorationData)
    }

    // MARK: - Expire Session If Needed Tests

    func testExpireSessionIfNeeded_withExpiredSession_removesAndReturnsTrue() {
        // Given
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatKeepSession]
        let keepSessionProvider = AIChatSessionStore(featureFlagger: mockFeatureFlagger)

        let tabID = "expired-session-tab"
        let session = keepSessionProvider.getOrCreateSession(for: tabID, burnerMode: .regular)
        _ = session.makeChatViewController(tabID: tabID)
        session.state.setSidebar()

        keepSessionProvider.endSession(for: tabID)
        let oldDate = Date().addingTimeInterval(-4200)
        keepSessionProvider.sessions[tabID]?.state.updateHiddenAt(oldDate)
        XCTAssertNotNil(keepSessionProvider.sessions[tabID])

        // When
        let wasCleared = keepSessionProvider.expireSessionIfNeeded(for: tabID)

        // Then
        XCTAssertTrue(wasCleared)
        XCTAssertNil(keepSessionProvider.sessions[tabID])
    }

    func testExpireSessionIfNeeded_withValidSession_doesNotRemoveAndReturnsFalse() {
        // Given
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatKeepSession]
        let keepSessionProvider = AIChatSessionStore(featureFlagger: mockFeatureFlagger)

        let tabID = "valid-session-tab"
        let session = keepSessionProvider.getOrCreateSession(for: tabID, burnerMode: .regular)
        _ = session.makeChatViewController(tabID: tabID)
        session.state.setSidebar()

        keepSessionProvider.endSession(for: tabID)
        let recentDate = Date().addingTimeInterval(-1800)
        keepSessionProvider.sessions[tabID]?.state.updateHiddenAt(recentDate)

        // When
        let wasCleared = keepSessionProvider.expireSessionIfNeeded(for: tabID)

        // Then
        XCTAssertFalse(wasCleared)
        XCTAssertNotNil(keepSessionProvider.sessions[tabID])
    }

    func testExpireSessionIfNeeded_withNoSession_returnsFalse() {
        // Given
        let tabID = "non-existent-tab"

        // When
        let wasCleared = provider.expireSessionIfNeeded(for: tabID)

        // Then
        XCTAssertFalse(wasCleared)
    }

    func testExpireSessionIfNeeded_withNilHiddenAt_returnsFalse() {
        // Given
        let tabID = "never-hidden-tab"
        let session = provider.getOrCreateSession(for: tabID, burnerMode: .regular)
        session.state.setSidebar()
        XCTAssertNil(session.state.hiddenAt)

        // When
        let wasCleared = provider.expireSessionIfNeeded(for: tabID)

        // Then
        XCTAssertFalse(wasCleared)
        XCTAssertNotNil(provider.sessions[tabID])
    }
}
