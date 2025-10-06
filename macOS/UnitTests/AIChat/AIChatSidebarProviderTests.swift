//
//  AIChatSidebarProviderTests.swift
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
import AIChat
@testable import DuckDuckGo_Privacy_Browser

final class AIChatSidebarProviderTests: XCTestCase {

    var provider: AIChatSidebarProvider!

    override func setUp() {
        super.setUp()
        provider = AIChatSidebarProvider(featureFlagger: MockFeatureFlagger())
    }

    override func tearDown() {
        provider = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInit_withDefaultParameters_setsEmptyDictionary() {
        // Given & When
        let provider = AIChatSidebarProvider(featureFlagger: MockFeatureFlagger())

        // Then
        XCTAssertTrue(provider.sidebarsByTab.isEmpty)
        XCTAssertEqual(provider.sidebarWidth, AIChatSidebarProvider.Constants.sidebarWidth)
    }

    func testInit_withProvidedSidebarsByTab_setsDictionary() {
        // Given
        let testSidebar = AIChatSidebar(burnerMode: .regular)
        let sidebarsByTab = ["tab1": testSidebar]

        // When
        let provider = AIChatSidebarProvider(sidebarsByTab: sidebarsByTab, featureFlagger: MockFeatureFlagger())

        // Then
        XCTAssertEqual(provider.sidebarsByTab.count, 1)
        XCTAssertNotNil(provider.sidebarsByTab["tab1"])
    }

    func testInit_withNilParameter_setsEmptyDictionary() {
        // Given & When
        let provider = AIChatSidebarProvider(sidebarsByTab: nil, featureFlagger: MockFeatureFlagger())

        // Then
        XCTAssertTrue(provider.sidebarsByTab.isEmpty)
    }

    // MARK: - Get Sidebar Tests

    func testGetSidebarViewController_withExistingTab_returnsViewController() {
        // Given
        let tabID = "test-tab-id"
        let sidebarViewController = provider.makeSidebarViewController(for: tabID, burnerMode: .regular)

        // When
        let retrievedViewController = provider.getSidebarViewController(for: tabID)

        // Then
        XCTAssertNotNil(retrievedViewController)
        XCTAssertIdentical(retrievedViewController, sidebarViewController)
    }

    func testGetSidebarViewController_withNonExistentTab_returnsNil() {
        // Given
        let tabID = "non-existent-tab"

        // When
        let retrievedViewController = provider.getSidebarViewController(for: tabID)

        // Then
        XCTAssertNil(retrievedViewController)
    }

    // MARK: - Make Sidebar View Controller Tests

    func testMakeSidebarViewController_createsAndStoresViewController() {
        // Given
        let tabID = "new-tab-id"

        // When
        let sidebarViewController = provider.makeSidebarViewController(for: tabID, burnerMode: .regular)

        // Then
        XCTAssertNotNil(sidebarViewController)
        XCTAssertEqual(provider.sidebarsByTab.count, 1)
        XCTAssertNotNil(provider.sidebarsByTab[tabID])
        XCTAssertIdentical(provider.sidebarsByTab[tabID]?.sidebarViewController, sidebarViewController)
    }

    func testMakeSidebarViewController_withBurnerMode_createsCorrectViewController() {
        // Given
        let tabID = "burner-tab-id"
        let burnerMode = BurnerMode.burner(websiteDataStore: .nonPersistent())

        // When
        let sidebarViewController = provider.makeSidebarViewController(for: tabID, burnerMode: burnerMode)

        // Then
        XCTAssertNotNil(sidebarViewController)
        XCTAssertNotNil(provider.sidebarsByTab[tabID])
        XCTAssertIdentical(provider.sidebarsByTab[tabID]?.sidebarViewController, sidebarViewController)
    }

    func testMakeSidebarViewController_withExistingSidebar_returnsExistingViewController() {
        // Given
        let tabID = "existing-tab"
        let firstViewController = provider.makeSidebarViewController(for: tabID, burnerMode: .regular)

        // When
        let secondViewController = provider.makeSidebarViewController(for: tabID, burnerMode: .burner(websiteDataStore: .nonPersistent()))

        // Then
        XCTAssertEqual(provider.sidebarsByTab.count, 1)
        XCTAssertIdentical(firstViewController, secondViewController)
        XCTAssertIdentical(provider.sidebarsByTab[tabID]?.sidebarViewController, firstViewController)
    }

    // MARK: - Is Showing Sidebar Tests

    func testIsShowingSidebar_withRevealedSidebar_returnsTrue() {
        // Given
        let tabID = "test-tab"
        _ = provider.makeSidebarViewController(for: tabID, burnerMode: .regular)
        provider.sidebarsByTab[tabID]?.setRevealed()

        // When
        let isShowing = provider.isShowingSidebar(for: tabID)

        // Then
        XCTAssertTrue(isShowing)
    }

    func testIsShowingSidebar_withUnrevealedSidebar_returnsFalse() {
        // Given
        let tabID = "test-tab"
        _ = provider.makeSidebarViewController(for: tabID, burnerMode: .regular)
        // Note: sidebar starts as not revealed by default

        // When
        let isShowing = provider.isShowingSidebar(for: tabID)

        // Then
        XCTAssertFalse(isShowing)
    }

    func testIsShowingSidebar_withNonExistentSidebar_returnsFalse() {
        // Given
        let tabID = "non-existent-tab"

        // When
        let isShowing = provider.isShowingSidebar(for: tabID)

        // Then
        XCTAssertFalse(isShowing)
    }

    // MARK: - Handle Sidebar Did Close Tests

    func testHandleSidebarDidClose_withExistingTab_removesSidebar() {
        // Given
        let tabID = "closing-tab"
        _ = provider.makeSidebarViewController(for: tabID, burnerMode: .regular)
        XCTAssertEqual(provider.sidebarsByTab.count, 1)

        // When
        provider.handleSidebarDidClose(for: tabID)

        // Then
        XCTAssertEqual(provider.sidebarsByTab.count, 0)
        XCTAssertNil(provider.sidebarsByTab[tabID])
    }

    func testHandleSidebarDidClose_withNonExistentTab_doesNothing() {
        // Given
        let existingTabID = "existing-tab"
        let nonExistentTabID = "non-existent-tab"
        _ = provider.makeSidebarViewController(for: existingTabID, burnerMode: .regular)
        let initialCount = provider.sidebarsByTab.count

        // When
        provider.handleSidebarDidClose(for: nonExistentTabID)

        // Then
        XCTAssertEqual(provider.sidebarsByTab.count, initialCount)
        XCTAssertNotNil(provider.sidebarsByTab[existingTabID])
    }

    func testHandleSidebarDidClose_withKeepSessionEnabled_preservesSidebarData() {
        // Given
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatKeepSession]
        let keepSessionProvider = AIChatSidebarProvider(featureFlagger: mockFeatureFlagger)

        let tabID = "keep-session-tab"
        _ = keepSessionProvider.makeSidebarViewController(for: tabID, burnerMode: .regular)
        keepSessionProvider.sidebarsByTab[tabID]?.setRevealed()
        XCTAssertEqual(keepSessionProvider.sidebarsByTab.count, 1)
        XCTAssertTrue(keepSessionProvider.isShowingSidebar(for: tabID))

        // When
        keepSessionProvider.handleSidebarDidClose(for: tabID)

        // Then - sidebar data is preserved but marked as hidden
        XCTAssertEqual(keepSessionProvider.sidebarsByTab.count, 1)
        XCTAssertNotNil(keepSessionProvider.sidebarsByTab[tabID])
        XCTAssertFalse(keepSessionProvider.isShowingSidebar(for: tabID))
        XCTAssertNil(keepSessionProvider.sidebarsByTab[tabID]?.sidebarViewController)
        XCTAssertNotNil(keepSessionProvider.sidebarsByTab[tabID]?.hiddenAt)
    }

    func testHandleSidebarDidClose_withKeepSessionDisabled_removesSidebarData() {
        // Given
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [] // aiChatKeepSession disabled
        let noKeepSessionProvider = AIChatSidebarProvider(featureFlagger: mockFeatureFlagger)

        let tabID = "no-keep-session-tab"
        _ = noKeepSessionProvider.makeSidebarViewController(for: tabID, burnerMode: .regular)
        noKeepSessionProvider.sidebarsByTab[tabID]?.setRevealed()
        XCTAssertEqual(noKeepSessionProvider.sidebarsByTab.count, 1)

        // When
        noKeepSessionProvider.handleSidebarDidClose(for: tabID)

        // Then - sidebar data is completely removed
        XCTAssertEqual(noKeepSessionProvider.sidebarsByTab.count, 0)
        XCTAssertNil(noKeepSessionProvider.sidebarsByTab[tabID])
    }

    // MARK: - Clean Up Tests

    func testCleanUp_removesUnneededSidebars() {
        // Given
        _ = provider.makeSidebarViewController(for: "tab1", burnerMode: .regular)
        _ = provider.makeSidebarViewController(for: "tab2", burnerMode: .regular)
        _ = provider.makeSidebarViewController(for: "tab3", burnerMode: .regular)
        XCTAssertEqual(provider.sidebarsByTab.count, 3)

        let currentTabIDs = ["tab1", "tab3"] // tab2 should be removed

        // When
        provider.cleanUp(for: currentTabIDs)

        // Then
        XCTAssertEqual(provider.sidebarsByTab.count, 2)
        XCTAssertNotNil(provider.sidebarsByTab["tab1"])
        XCTAssertNil(provider.sidebarsByTab["tab2"])
        XCTAssertNotNil(provider.sidebarsByTab["tab3"])
    }

    func testCleanUp_withEmptyCurrentTabIDs_removesAllSidebars() {
        // Given
        _ = provider.makeSidebarViewController(for: "tab1", burnerMode: .regular)
        _ = provider.makeSidebarViewController(for: "tab2", burnerMode: .regular)
        XCTAssertEqual(provider.sidebarsByTab.count, 2)

        // When
        provider.cleanUp(for: [])

        // Then
        XCTAssertEqual(provider.sidebarsByTab.count, 0)
        XCTAssertTrue(provider.sidebarsByTab.isEmpty)
    }

    func testCleanUp_withAllCurrentTabs_removesNoSidebars() {
        // Given
        _ = provider.makeSidebarViewController(for: "tab1", burnerMode: .regular)
        _ = provider.makeSidebarViewController(for: "tab2", burnerMode: .regular)
        let allTabIDs = ["tab1", "tab2"]
        XCTAssertEqual(provider.sidebarsByTab.count, 2)

        // When
        provider.cleanUp(for: allTabIDs)

        // Then
        XCTAssertEqual(provider.sidebarsByTab.count, 2)
        XCTAssertNotNil(provider.sidebarsByTab["tab1"])
        XCTAssertNotNil(provider.sidebarsByTab["tab2"])
    }

    func testCleanUp_withExtraCurrentTabIDs_doesNotAddSidebars() {
        // Given
        _ = provider.makeSidebarViewController(for: "tab1", burnerMode: .regular)
        let currentTabIDs = ["tab1", "tab2", "tab3"] // tab2 and tab3 don't exist

        // When
        provider.cleanUp(for: currentTabIDs)

        // Then
        XCTAssertEqual(provider.sidebarsByTab.count, 1)
        XCTAssertNotNil(provider.sidebarsByTab["tab1"])
        XCTAssertNil(provider.sidebarsByTab["tab2"])
        XCTAssertNil(provider.sidebarsByTab["tab3"])
    }

    // MARK: - Restore State Tests

    func testRestoreState_clearsExistingState() {
        // Given
        _ = provider.makeSidebarViewController(for: "existing-tab", burnerMode: .regular)
        XCTAssertEqual(provider.sidebarsByTab.count, 1)

        let newState: AIChatSidebarsByTab = [:]

        // When
        provider.restoreState(newState)

        // Then
        XCTAssertTrue(provider.sidebarsByTab.isEmpty)
    }

    func testRestoreState_setsNewState() {
        // Given
        let newSidebar = AIChatSidebar(burnerMode: .regular)
        let newState: AIChatSidebarsByTab = ["new-tab": newSidebar]

        // When
        provider.restoreState(newState)

        // Then
        XCTAssertEqual(provider.sidebarsByTab.count, 1)
        XCTAssertIdentical(provider.sidebarsByTab["new-tab"], newSidebar)
    }

    func testRestoreState_replacesCompleteState() {
        // Given
        _ = provider.makeSidebarViewController(for: "old-tab1", burnerMode: .regular)
        _ = provider.makeSidebarViewController(for: "old-tab2", burnerMode: .regular)
        XCTAssertEqual(provider.sidebarsByTab.count, 2)

        let newSidebar1 = AIChatSidebar(burnerMode: .regular)
        let newSidebar2 = AIChatSidebar(burnerMode: .burner(websiteDataStore: .nonPersistent()))
        let newState: AIChatSidebarsByTab = [
            "new-tab1": newSidebar1,
            "new-tab2": newSidebar2
        ]

        // When
        provider.restoreState(newState)

        // Then
        XCTAssertEqual(provider.sidebarsByTab.count, 2)
        XCTAssertNil(provider.sidebarsByTab["old-tab1"])
        XCTAssertNil(provider.sidebarsByTab["old-tab2"])
        XCTAssertIdentical(provider.sidebarsByTab["new-tab1"], newSidebar1)
        XCTAssertIdentical(provider.sidebarsByTab["new-tab2"], newSidebar2)
    }

    // MARK: - Integration Tests

    func testMultipleSidebarOperations() {
        // Given - Create multiple sidebars
        let tab1 = "tab1"
        let tab2 = "tab2"
        let tab3 = "tab3"

        _ = provider.makeSidebarViewController(for: tab1, burnerMode: .regular)
        _ = provider.makeSidebarViewController(for: tab2, burnerMode: .burner(websiteDataStore: .nonPersistent()))
        _ = provider.makeSidebarViewController(for: tab3, burnerMode: .regular)

        // When - Check initial state
        XCTAssertEqual(provider.sidebarsByTab.count, 3)
        XCTAssertNotNil(provider.getSidebarViewController(for: tab1))
        XCTAssertNotNil(provider.getSidebarViewController(for: tab2))
        XCTAssertNotNil(provider.getSidebarViewController(for: tab3))

        // When - Close one sidebar
        provider.handleSidebarDidClose(for: tab2)

        // Then - Verify state after close
        XCTAssertEqual(provider.sidebarsByTab.count, 2)
        XCTAssertNotNil(provider.getSidebarViewController(for: tab1))
        XCTAssertNil(provider.getSidebarViewController(for: tab2))
        XCTAssertNotNil(provider.getSidebarViewController(for: tab3))

        // When - Clean up with only tab1 active
        provider.cleanUp(for: [tab1])

        // Then - Verify final state
        XCTAssertEqual(provider.sidebarsByTab.count, 1)
        XCTAssertNotNil(provider.getSidebarViewController(for: tab1))
        XCTAssertNil(provider.getSidebarViewController(for: tab2))
        XCTAssertNil(provider.getSidebarViewController(for: tab3))
    }

    // MARK: - Session Timeout Tests

    func testMakeSidebarViewController_withExpiredSession_createsNewSidebar() {
        // Given - Create provider with keep session enabled
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatKeepSession]
        let keepSessionProvider = AIChatSidebarProvider(featureFlagger: mockFeatureFlagger)

        let tabID = "session-timeout-tab"
        _ = keepSessionProvider.makeSidebarViewController(for: tabID, burnerMode: .regular)
        keepSessionProvider.sidebarsByTab[tabID]?.setRevealed()

        // Simulate the sidebar being hidden and closed
        keepSessionProvider.handleSidebarDidClose(for: tabID)
        XCTAssertNotNil(keepSessionProvider.sidebarsByTab[tabID])
        XCTAssertNotNil(keepSessionProvider.sidebarsByTab[tabID]?.hiddenAt)

        // Manually set the hiddenAt to simulate a very old session (more than 60 minutes ago)
        let oldDate = Date().addingTimeInterval(-4000) // ~67 minutes ago, exceeds default 60 minute timeout
        keepSessionProvider.sidebarsByTab[tabID]?.updateHiddenAt(oldDate)

        // When - Create a new view controller (which calls getCurrentSidebar internally)
        let newViewController = keepSessionProvider.makeSidebarViewController(for: tabID, burnerMode: .regular)

        // Then - Should have created a fresh sidebar since the session expired
        XCTAssertNotNil(newViewController)
        XCTAssertNotNil(keepSessionProvider.sidebarsByTab[tabID])
        // The hiddenAt should be nil for a fresh sidebar
        XCTAssertNil(keepSessionProvider.sidebarsByTab[tabID]?.hiddenAt)
    }

    func testMakeSidebarViewController_withValidSession_returnsExistingSidebar() {
        // Given - Create provider with keep session enabled
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatKeepSession]
        let keepSessionProvider = AIChatSidebarProvider(featureFlagger: mockFeatureFlagger)

        let tabID = "valid-session-tab"
        _ = keepSessionProvider.makeSidebarViewController(for: tabID, burnerMode: .regular)
        keepSessionProvider.sidebarsByTab[tabID]?.setRevealed()

        // Simulate the sidebar being hidden and closed recently
        keepSessionProvider.handleSidebarDidClose(for: tabID)
        XCTAssertNotNil(keepSessionProvider.sidebarsByTab[tabID])
        XCTAssertNotNil(keepSessionProvider.sidebarsByTab[tabID]?.hiddenAt)

        // Manually set the hiddenAt to simulate a recent session (within timeout)
        let recentDate = Date().addingTimeInterval(-1800) // 30 minutes ago, within default 60 minute timeout
        keepSessionProvider.sidebarsByTab[tabID]?.setHidden(at: recentDate)

        // When - Create a new view controller (which calls getCurrentSidebar internally)
        let newViewController = keepSessionProvider.makeSidebarViewController(for: tabID, burnerMode: .regular)

        // Then - Should reuse the existing sidebar since session is still valid
        XCTAssertNotNil(newViewController)
        XCTAssertNotNil(keepSessionProvider.sidebarsByTab[tabID])
        // The hiddenAt should still be the recent date (session not expired)
        XCTAssertNotNil(keepSessionProvider.sidebarsByTab[tabID]?.hiddenAt)
    }

    // MARK: - State Management Tests

    func testSetRevealed_updatesIsRevealedState() {
        // Given
        let tabID = "revealed-tab"
        _ = provider.makeSidebarViewController(for: tabID, burnerMode: .regular)
        XCTAssertFalse(provider.isShowingSidebar(for: tabID)) // starts as not revealed

        // When
        provider.sidebarsByTab[tabID]?.setRevealed()

        // Then
        XCTAssertTrue(provider.isShowingSidebar(for: tabID))
        XCTAssertNil(provider.sidebarsByTab[tabID]?.hiddenAt) // hiddenAt should be cleared
    }

    func testSetHidden_updatesIsRevealedState() {
        // Given
        let tabID = "hidden-tab"
        _ = provider.makeSidebarViewController(for: tabID, burnerMode: .regular)
        provider.sidebarsByTab[tabID]?.setRevealed()
        XCTAssertTrue(provider.isShowingSidebar(for: tabID))

        // When
        provider.sidebarsByTab[tabID]?.setHidden()

        // Then
        XCTAssertFalse(provider.isShowingSidebar(for: tabID))
        XCTAssertNotNil(provider.sidebarsByTab[tabID]?.hiddenAt) // hiddenAt should be set
    }

}
