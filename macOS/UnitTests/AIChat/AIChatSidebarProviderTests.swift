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
@testable import DuckDuckGo_Privacy_Browser

final class AIChatSidebarProviderTests: XCTestCase {

    var provider: AIChatSidebarProvider!

    override func setUp() {
        super.setUp()
        provider = AIChatSidebarProvider()
    }

    override func tearDown() {
        provider = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInit_withDefaultParameters_setsEmptyDictionary() {
        // Given & When
        let provider = AIChatSidebarProvider()

        // Then
        XCTAssertTrue(provider.sidebarsByTab.isEmpty)
        XCTAssertEqual(provider.sidebarWidth, AIChatSidebarProvider.Constants.sidebarWidth)
    }

    func testInit_withProvidedSidebarsByTab_setsDictionary() {
        // Given
        let testSidebar = AIChatSidebar(burnerMode: .regular)
        let sidebarsByTab = ["tab1": testSidebar]

        // When
        let provider = AIChatSidebarProvider(sidebarsByTab: sidebarsByTab)

        // Then
        XCTAssertEqual(provider.sidebarsByTab.count, 1)
        XCTAssertNotNil(provider.sidebarsByTab["tab1"])
    }

    func testInit_withNilParameter_setsEmptyDictionary() {
        // Given & When
        let provider = AIChatSidebarProvider(sidebarsByTab: nil)

        // Then
        XCTAssertTrue(provider.sidebarsByTab.isEmpty)
    }

    // MARK: - Get Sidebar Tests

    func testGetSidebar_withExistingTab_returnsSidebar() {
        // Given
        let tabID = "test-tab-id"
        let sidebar = provider.makeSidebar(for: tabID, burnerMode: .regular)

        // When
        let retrievedSidebar = provider.getSidebar(for: tabID)

        // Then
        XCTAssertNotNil(retrievedSidebar)
        XCTAssertIdentical(retrievedSidebar, sidebar)
    }

    func testGetSidebar_withNonExistentTab_returnsNil() {
        // Given
        let tabID = "non-existent-tab"

        // When
        let retrievedSidebar = provider.getSidebar(for: tabID)

        // Then
        XCTAssertNil(retrievedSidebar)
    }

    // MARK: - Make Sidebar Tests

    func testMakeSidebar_createsAndStoresSidebar() {
        // Given
        let tabID = "new-tab-id"

        // When
        let sidebar = provider.makeSidebar(for: tabID, burnerMode: .regular)

        // Then
        XCTAssertNotNil(sidebar)
        XCTAssertEqual(provider.sidebarsByTab.count, 1)
        XCTAssertIdentical(provider.sidebarsByTab[tabID], sidebar)
    }

    func testMakeSidebar_withBurnerMode_createsCorrectSidebar() {
        // Given
        let tabID = "burner-tab-id"
        let burnerMode = BurnerMode.burner(websiteDataStore: .nonPersistent())

        // When
        let sidebar = provider.makeSidebar(for: tabID, burnerMode: burnerMode)

        // Then
        XCTAssertNotNil(sidebar)
        XCTAssertIdentical(provider.sidebarsByTab[tabID], sidebar)
    }

    func testMakeSidebar_replacesExistingSidebar() {
        // Given
        let tabID = "existing-tab"
        let firstSidebar = provider.makeSidebar(for: tabID, burnerMode: .regular)

        // When
        let secondSidebar = provider.makeSidebar(for: tabID, burnerMode: .burner(websiteDataStore: .nonPersistent()))

        // Then
        XCTAssertEqual(provider.sidebarsByTab.count, 1)
        XCTAssertNotIdentical(firstSidebar, secondSidebar)
        XCTAssertIdentical(provider.sidebarsByTab[tabID], secondSidebar)
    }

    // MARK: - Is Showing Sidebar Tests

    func testIsShowingSidebar_withExistingSidebar_returnsTrue() {
        // Given
        let tabID = "test-tab"
        _ = provider.makeSidebar(for: tabID, burnerMode: .regular)

        // When
        let isShowing = provider.isShowingSidebar(for: tabID)

        // Then
        XCTAssertTrue(isShowing)
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
        _ = provider.makeSidebar(for: tabID, burnerMode: .regular)
        XCTAssertEqual(provider.sidebarsByTab.count, 1)

        // When
        provider.handleSidebarDidClose(for: tabID)

        // Then
        XCTAssertEqual(provider.sidebarsByTab.count, 0)
        XCTAssertNil(provider.getSidebar(for: tabID))
    }

    func testHandleSidebarDidClose_withNonExistentTab_doesNothing() {
        // Given
        let existingTabID = "existing-tab"
        let nonExistentTabID = "non-existent-tab"
        _ = provider.makeSidebar(for: existingTabID, burnerMode: .regular)
        let initialCount = provider.sidebarsByTab.count

        // When
        provider.handleSidebarDidClose(for: nonExistentTabID)

        // Then
        XCTAssertEqual(provider.sidebarsByTab.count, initialCount)
        XCTAssertNotNil(provider.getSidebar(for: existingTabID))
    }

    // MARK: - Clean Up Tests

    func testCleanUp_removesUnneededSidebars() {
        // Given
        _ = provider.makeSidebar(for: "tab1", burnerMode: .regular)
        _ = provider.makeSidebar(for: "tab2", burnerMode: .regular)
        _ = provider.makeSidebar(for: "tab3", burnerMode: .regular)
        XCTAssertEqual(provider.sidebarsByTab.count, 3)

        let currentTabIDs = ["tab1", "tab3"] // tab2 should be removed

        // When
        provider.cleanUp(for: currentTabIDs)

        // Then
        XCTAssertEqual(provider.sidebarsByTab.count, 2)
        XCTAssertNotNil(provider.getSidebar(for: "tab1"))
        XCTAssertNil(provider.getSidebar(for: "tab2"))
        XCTAssertNotNil(provider.getSidebar(for: "tab3"))
    }

    func testCleanUp_withEmptyCurrentTabIDs_removesAllSidebars() {
        // Given
        _ = provider.makeSidebar(for: "tab1", burnerMode: .regular)
        _ = provider.makeSidebar(for: "tab2", burnerMode: .regular)
        XCTAssertEqual(provider.sidebarsByTab.count, 2)

        // When
        provider.cleanUp(for: [])

        // Then
        XCTAssertEqual(provider.sidebarsByTab.count, 0)
        XCTAssertTrue(provider.sidebarsByTab.isEmpty)
    }

    func testCleanUp_withAllCurrentTabs_removesNoSidebars() {
        // Given
        _ = provider.makeSidebar(for: "tab1", burnerMode: .regular)
        _ = provider.makeSidebar(for: "tab2", burnerMode: .regular)
        let allTabIDs = ["tab1", "tab2"]
        XCTAssertEqual(provider.sidebarsByTab.count, 2)

        // When
        provider.cleanUp(for: allTabIDs)

        // Then
        XCTAssertEqual(provider.sidebarsByTab.count, 2)
        XCTAssertNotNil(provider.getSidebar(for: "tab1"))
        XCTAssertNotNil(provider.getSidebar(for: "tab2"))
    }

    func testCleanUp_withExtraCurrentTabIDs_doesNotAddSidebars() {
        // Given
        _ = provider.makeSidebar(for: "tab1", burnerMode: .regular)
        let currentTabIDs = ["tab1", "tab2", "tab3"] // tab2 and tab3 don't exist

        // When
        provider.cleanUp(for: currentTabIDs)

        // Then
        XCTAssertEqual(provider.sidebarsByTab.count, 1)
        XCTAssertNotNil(provider.getSidebar(for: "tab1"))
        XCTAssertNil(provider.getSidebar(for: "tab2"))
        XCTAssertNil(provider.getSidebar(for: "tab3"))
    }

    // MARK: - Restore State Tests

    func testRestoreState_clearsExistingState() {
        // Given
        _ = provider.makeSidebar(for: "existing-tab", burnerMode: .regular)
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
        _ = provider.makeSidebar(for: "old-tab1", burnerMode: .regular)
        _ = provider.makeSidebar(for: "old-tab2", burnerMode: .regular)
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
        XCTAssertNil(provider.getSidebar(for: "old-tab1"))
        XCTAssertNil(provider.getSidebar(for: "old-tab2"))
        XCTAssertIdentical(provider.sidebarsByTab["new-tab1"], newSidebar1)
        XCTAssertIdentical(provider.sidebarsByTab["new-tab2"], newSidebar2)
    }

    // MARK: - Integration Tests

    func testMultipleSidebarOperations() {
        // Given - Create multiple sidebars
        let tab1 = "tab1"
        let tab2 = "tab2"
        let tab3 = "tab3"

        _ = provider.makeSidebar(for: tab1, burnerMode: .regular)
        _ = provider.makeSidebar(for: tab2, burnerMode: .burner(websiteDataStore: .nonPersistent()))
        _ = provider.makeSidebar(for: tab3, burnerMode: .regular)

        // When - Check initial state
        XCTAssertEqual(provider.sidebarsByTab.count, 3)
        XCTAssertTrue(provider.isShowingSidebar(for: tab1))
        XCTAssertTrue(provider.isShowingSidebar(for: tab2))
        XCTAssertTrue(provider.isShowingSidebar(for: tab3))

        // When - Close one sidebar
        provider.handleSidebarDidClose(for: tab2)

        // Then - Verify state after close
        XCTAssertEqual(provider.sidebarsByTab.count, 2)
        XCTAssertTrue(provider.isShowingSidebar(for: tab1))
        XCTAssertFalse(provider.isShowingSidebar(for: tab2))
        XCTAssertTrue(provider.isShowingSidebar(for: tab3))

        // When - Clean up with only tab1 active
        provider.cleanUp(for: [tab1])

        // Then - Verify final state
        XCTAssertEqual(provider.sidebarsByTab.count, 1)
        XCTAssertTrue(provider.isShowingSidebar(for: tab1))
        XCTAssertFalse(provider.isShowingSidebar(for: tab2))
        XCTAssertFalse(provider.isShowingSidebar(for: tab3))
    }

}
