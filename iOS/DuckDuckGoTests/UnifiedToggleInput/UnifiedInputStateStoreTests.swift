//
//  UnifiedInputStateStoreTests.swift
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

import AIChat
import Combine
import XCTest
@testable import DuckDuckGo

@MainActor
final class UnifiedInputStateStoreTests: XCTestCase {

    private var preferences: StoreStubPreferences!
    private var toggleStorage: StoreStubToggleModeStorage!
    private var sut: UnifiedInputStateStore!

    override func setUp() {
        super.setUp()
        preferences = StoreStubPreferences()
        toggleStorage = StoreStubToggleModeStorage()
        sut = UnifiedInputStateStore(
            preferences: preferences,
            toggleModeStorage: toggleStorage
        )
    }

    override func tearDown() {
        sut = nil
        toggleStorage = nil
        preferences = nil
        super.tearDown()
    }

    // MARK: - get/set/remove

    func test_state_forUnknownUID_returnsSeededFromLastUsed() {
        toggleStorage.stored = .aiChat
        preferences.selectedModelId = "gpt-5"
        let state = sut.state(for: "tab-1")
        XCTAssertEqual(state.toggleMode, .aiChat)
        XCTAssertEqual(state.selectedModelID, "gpt-5")
        XCTAssertEqual(state.text, "")
        XCTAssertTrue(state.attachments.isEmpty)
    }

    func test_state_whenToggleStorageEmpty_defaultsToSearch() {
        toggleStorage.stored = nil
        let state = sut.state(for: "tab-1")
        XCTAssertEqual(state.toggleMode, .search)
    }

    func test_update_thenState_returnsSameValue() {
        var state = TabInputState()
        state.text = "hello"
        state.toggleMode = .aiChat
        sut.update(state, for: "tab-1")
        XCTAssertEqual(sut.state(for: "tab-1"), state)
    }

    func test_remove_clearsEntry() {
        var state = TabInputState()
        state.text = "hello"
        sut.update(state, for: "tab-1")
        sut.remove(for: "tab-1")
        XCTAssertEqual(sut.state(for: "tab-1").text, "")
    }

    // MARK: - lastUsed write-through on update

    func test_update_writesThroughToggleModeToStorage() {
        var state = TabInputState()
        state.toggleMode = .aiChat
        sut.update(state, for: "tab-1")
        XCTAssertEqual(toggleStorage.stored, .aiChat)
    }

    func test_update_writesThroughSelectedModelIDToPreferences() {
        var state = TabInputState()
        state.selectedModelID = "claude-opus"
        sut.update(state, for: "tab-1")
        XCTAssertEqual(preferences.selectedModelId, "claude-opus")
    }

    func test_update_writesThroughReasoningModeToPreferences() {
        var state = TabInputState()
        state.selectedReasoningMode = .reasoning
        sut.update(state, for: "tab-1")
        XCTAssertEqual(preferences.selectedReasoningMode, .reasoning)
    }

    func test_update_setsLastUsedTool() {
        var state = TabInputState()
        state.selectedTool = .webSearch
        sut.update(state, for: "tab-1")
        XCTAssertEqual(sut.lastUsed.selectedTool, .webSearch)
    }

    // MARK: - TabsModel observation

    func test_observingTabsModel_seedsNewTabs() {
        let tabsModel = TabsModel(desktop: false)
        let tab = Tab(uid: "tab-eager", fireTab: false, preferredTextEntryMode: .aiChat)
        sut.observeTabsModel(tabsModel)
        tabsModel.insert(tab: tab, placement: .atEnd, selectNewTab: true)
        XCTAssertEqual(sut.state(for: "tab-eager").toggleMode, .aiChat)
    }

    func test_observingTabsModel_seedsRemainingFieldsFromLastUsed() {
        let tabsModel = TabsModel(desktop: false)
        preferences.selectedModelId = "gpt-5"
        let tab = Tab(uid: "tab-eager", fireTab: false, preferredTextEntryMode: .search)
        sut.observeTabsModel(tabsModel)
        tabsModel.insert(tab: tab, placement: .atEnd, selectNewTab: true)
        XCTAssertEqual(sut.state(for: "tab-eager").selectedModelID, "gpt-5")
    }

    func test_observingTabsModel_evictsRemovedTabs() {
        let tabsModel = TabsModel(desktop: false)
        let tab = Tab(uid: "tab-evict", fireTab: false)
        tabsModel.insert(tab: tab, placement: .atEnd, selectNewTab: true)
        sut.observeTabsModel(tabsModel)
        sut.update(TabInputState(text: "kept"), for: "tab-evict")

        tabsModel.remove(tab: tab)
        XCTAssertEqual(sut.state(for: "tab-evict").text, "")
    }
}

// MARK: - Test Stubs

final class StoreStubPreferences: AIChatPreferencesPersisting {
    var selectedModelId: String?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedModelShortName: String?
    var selectedReasoningEffort: String?
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningMode: AIChatReasoningMode?
}

final class StoreStubToggleModeStorage: ToggleModeStoring {
    var stored: TextEntryMode?
    func save(_ mode: TextEntryMode) { stored = mode }
    func restore() -> TextEntryMode? { stored }
}
