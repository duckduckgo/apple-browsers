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
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
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

    func test_state_forUnknownUID_returnsSeededFromLastUsedAtConstruction() {
        // lastUsed is captured at init time from preferences/storage.
        toggleStorage.stored = .aiChat
        preferences.selectedModelId = "gpt-5"
        let sutWithSeed = UnifiedInputStateStore(preferences: preferences, toggleModeStorage: toggleStorage)
        let state = sutWithSeed.state(for: "tab-1")
        XCTAssertEqual(state.toggleMode, .aiChat)
        XCTAssertEqual(state.selectedModelID, "gpt-5")
        XCTAssertEqual(state.text, "")
        XCTAssertTrue(state.attachments.isEmpty)
    }

    func test_state_whenToggleStorageEmpty_defaultsToSearch() {
        // sut was constructed in setUp with toggleStorage.stored == nil.
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

    // MARK: - update vs recordUserChoice

    func test_update_doesNotWriteThroughToGlobals() {
        var state = TabInputState()
        state.toggleMode = .aiChat
        state.selectedModelID = "claude-opus"
        state.selectedReasoningMode = .reasoning
        sut.update(state, for: "tab-1")
        XCTAssertNil(toggleStorage.stored)
        XCTAssertNil(preferences.selectedModelId)
        XCTAssertNil(preferences.selectedReasoningMode)
    }

    func test_update_doesNotMutateLastUsed() {
        // lastUsed reflects construction-time defaults until a user choice is recorded.
        let initialLastUsed = sut.lastUsed
        var state = TabInputState()
        state.toggleMode = .aiChat
        state.selectedModelID = "claude-opus"
        sut.update(state, for: "tab-1")
        XCTAssertEqual(sut.lastUsed, initialLastUsed)
    }

    func test_recordUserChoice_writesThroughToggleModeToStorage() {
        var state = TabInputState()
        state.toggleMode = .aiChat
        sut.recordUserChoice(state, for: "tab-1")
        XCTAssertEqual(toggleStorage.stored, .aiChat)
    }

    func test_recordUserChoice_writesThroughSelectedModelIDToPreferences() {
        var state = TabInputState()
        state.selectedModelID = "claude-opus"
        sut.recordUserChoice(state, for: "tab-1")
        XCTAssertEqual(preferences.selectedModelId, "claude-opus")
    }

    func test_recordUserChoice_writesThroughReasoningModeToPreferences() {
        var state = TabInputState()
        state.selectedReasoningMode = .reasoning
        sut.recordUserChoice(state, for: "tab-1")
        XCTAssertEqual(preferences.selectedReasoningMode, .reasoning)
    }

    func test_recordUserChoice_updatesLastUsed() {
        var state = TabInputState()
        state.toggleMode = .aiChat
        state.selectedModelID = "claude-opus"
        state.selectedTool = .webSearch
        sut.recordUserChoice(state, for: "tab-1")
        XCTAssertEqual(sut.lastUsed.toggleMode, .aiChat)
        XCTAssertEqual(sut.lastUsed.selectedModelID, "claude-opus")
        XCTAssertEqual(sut.lastUsed.selectedTool, .webSearch)
    }

    // Regression for the new-tab inheritance bug: tab-flush after a user choice in another
    // tab must not overwrite lastUsed with the flushed (active-tab) values.
    func test_update_afterRecordUserChoiceElsewhere_preservesLastUsed() {
        var deliberateA = TabInputState()
        deliberateA.selectedModelID = "user-picked-A"
        sut.recordUserChoice(deliberateA, for: "tab-A")

        // Simulate a tab-switch flush of an unrelated, never-deliberately-chosen tab.
        var driftB = TabInputState()
        driftB.selectedModelID = "drift-B"
        sut.update(driftB, for: "tab-B")

        XCTAssertEqual(sut.lastUsed.selectedModelID, "user-picked-A")
    }

    // MARK: - TabsModel observation

    func test_observingTabsModel_seedsToggleModeFromAppWideLastUsed() {
        toggleStorage.stored = .aiChat
        let store = UnifiedInputStateStore(preferences: preferences, toggleModeStorage: toggleStorage)
        let tabsModel = TabsModel(desktop: false)
        let tab = Tab(uid: "tab-eager", fireTab: false)
        store.observeTabsModel(tabsModel)
        tabsModel.insert(tab: tab, placement: .atEnd, selectNewTab: true)
        XCTAssertEqual(store.state(for: "tab-eager").toggleMode, .aiChat)
    }

    func test_observingTabsModel_seedsRemainingFieldsFromLastUsed() {
        preferences.selectedModelId = "gpt-5"
        let store = UnifiedInputStateStore(preferences: preferences, toggleModeStorage: toggleStorage)
        let tabsModel = TabsModel(desktop: false)
        let tab = Tab(uid: "tab-eager", fireTab: false)
        store.observeTabsModel(tabsModel)
        tabsModel.insert(tab: tab, placement: .atEnd, selectNewTab: true)
        XCTAssertEqual(store.state(for: "tab-eager").selectedModelID, "gpt-5")
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

    // MARK: - Per-tab persistence (NSCoding round-trip)

    func test_observingTabsModel_seedsModelFromTabPersistedSelection() {
        preferences.selectedModelId = "global-default"
        let store = UnifiedInputStateStore(preferences: preferences, toggleModeStorage: toggleStorage)
        let tabsModel = TabsModel(desktop: false)
        let tab = Tab(
            uid: "persisted",
            fireTab: false,
            unifiedInputState: UnifiedInputTabState(
                selectedModelID: "tab-specific-model",
                selectedReasoningMode: .extendedReasoning
            )
        )
        store.observeTabsModel(tabsModel)
        tabsModel.insert(tab: tab, placement: .atEnd, selectNewTab: true)

        XCTAssertEqual(store.state(for: "persisted").selectedModelID, "tab-specific-model")
        XCTAssertEqual(store.state(for: "persisted").selectedReasoningMode, .extendedReasoning)
    }

    func test_observingTabsModel_fallsBackToLastUsed_whenTabHasNoStoredModel() {
        preferences.selectedModelId = "global-default"
        let store = UnifiedInputStateStore(preferences: preferences, toggleModeStorage: toggleStorage)
        let tabsModel = TabsModel(desktop: false)
        let tab = Tab(uid: "fresh", fireTab: false)
        store.observeTabsModel(tabsModel)
        tabsModel.insert(tab: tab, placement: .atEnd, selectNewTab: true)

        XCTAssertEqual(store.state(for: "fresh").selectedModelID, "global-default")
    }

    func test_recordUserChoice_writesSelectedModelBackToTab() {
        let tabsModel = TabsModel(desktop: false)
        let tab = Tab(uid: "writeback", fireTab: false)
        sut.observeTabsModel(tabsModel)
        tabsModel.insert(tab: tab, placement: .atEnd, selectNewTab: true)

        sut.recordUserChoice(
            TabInputState(toggleMode: .aiChat, selectedModelID: "claude-opus", selectedReasoningMode: .reasoning),
            for: "writeback"
        )

        XCTAssertEqual(tab.unifiedInputState.selectedModelID, "claude-opus")
        XCTAssertEqual(tab.unifiedInputState.selectedReasoningMode, .reasoning)
    }

    func test_recordUserChoice_clearingModelOnTab_isAlsoMirrored() {
        let tabsModel = TabsModel(desktop: false)
        let tab = Tab(
            uid: "clear-mirror",
            fireTab: false,
            unifiedInputState: UnifiedInputTabState(
                selectedModelID: "old-model",
                selectedReasoningMode: .reasoning
            )
        )
        sut.observeTabsModel(tabsModel)
        tabsModel.insert(tab: tab, placement: .atEnd, selectNewTab: true)

        sut.recordUserChoice(
            TabInputState(toggleMode: .aiChat, selectedModelID: nil, selectedReasoningMode: nil),
            for: "clear-mirror"
        )

        XCTAssertNil(tab.unifiedInputState.selectedModelID)
        XCTAssertNil(tab.unifiedInputState.selectedReasoningMode)
    }

    // Regression for the fire-mode bug: tabs in a second observed model must also be
    // seeded and evicted.
    func test_observingMultipleTabsModels_seedsAndEvictsBothSources() {
        let normalModel = TabsModel(desktop: false)
        let fireModel = TabsModel(desktop: false, mode: .fire)
        sut.observeTabsModel(normalModel)
        sut.observeTabsModel(fireModel)

        let normalTab = Tab(uid: "normal-1", fireTab: false)
        let fireTab = Tab(uid: "fire-1", fireTab: true)
        normalModel.insert(tab: normalTab, placement: .atEnd, selectNewTab: true)
        fireModel.insert(tab: fireTab, placement: .atEnd, selectNewTab: true)

        sut.update(TabInputState(text: "normal kept"), for: "normal-1")
        sut.update(TabInputState(text: "fire kept"), for: "fire-1")
        XCTAssertEqual(sut.state(for: "normal-1").text, "normal kept")
        XCTAssertEqual(sut.state(for: "fire-1").text, "fire kept")

        fireModel.remove(tab: fireTab)
        XCTAssertEqual(sut.state(for: "fire-1").text, "")
        // Normal-tab entry must still be present.
        XCTAssertEqual(sut.state(for: "normal-1").text, "normal kept")
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
    var selectedTool: AIChatRAGTool?
}

final class StoreStubToggleModeStorage: ToggleModeStoring {
    var stored: TextEntryMode?
    func save(_ mode: TextEntryMode) { stored = mode }
    func restore() -> TextEntryMode? { stored }
}
