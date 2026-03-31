//
//  DefaultTogglePositionTests.swift
//  DuckDuckGoTests
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
import AIChat
import PersistenceTestingUtils
@testable import Core
@testable import DuckDuckGo

// MARK: - DefaultOmnibarMode Resolution

final class DefaultOmnibarModeResolutionTests: XCTestCase {

    func testSearchModeAlwaysResolvesToSearch() {
        let result = DefaultOmnibarMode.search.resolvedTextEntryMode { .aiChat }
        XCTAssertEqual(result, .search)
    }

    func testDuckAIModeAlwaysResolvesToAIChat() {
        let result = DefaultOmnibarMode.duckAI.resolvedTextEntryMode { .search }
        XCTAssertEqual(result, .aiChat)
    }

    func testLastUsedModeResolvesToStoredValue() {
        let resultAI = DefaultOmnibarMode.lastUsed.resolvedTextEntryMode { .aiChat }
        XCTAssertEqual(resultAI, .aiChat)

        let resultSearch = DefaultOmnibarMode.lastUsed.resolvedTextEntryMode { .search }
        XCTAssertEqual(resultSearch, .search)
    }

    func testLastUsedModeDefaultsToSearchWhenNil() {
        let result = DefaultOmnibarMode.lastUsed.resolvedTextEntryMode { nil }
        XCTAssertEqual(result, .search)
    }
}

// MARK: - ToggleModeStorage

final class ToggleModeStorageTests: XCTestCase {

    func testSaveAndRestore() {
        let store = MockKeyValueStore()
        let sut = ToggleModeStorage(store: store)

        sut.save(.aiChat)
        XCTAssertEqual(sut.restore(), .aiChat)

        sut.save(.search)
        XCTAssertEqual(sut.restore(), .search)
    }

    func testRestoreReturnsNilWhenEmpty() {
        let store = MockKeyValueStore()
        let sut = ToggleModeStorage(store: store)

        XCTAssertNil(sut.restore())
    }
}

// MARK: - Tab.preferredTextEntryMode NSCoding

final class TabPreferredTextEntryModeCodingTests: XCTestCase {

    func testRoundTripPreservesMode() throws {
        let tabAI = Tab(link: Link(title: nil, url: URL(string: "https://example.com")!), preferredTextEntryMode: .aiChat)
        let tabSearch = Tab(link: Link(title: nil, url: URL(string: "https://example.com")!), preferredTextEntryMode: .search)

        let dataAI = try NSKeyedArchiver.archivedData(withRootObject: tabAI, requiringSecureCoding: false)
        let decodedAI = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(dataAI) as? Tab
        XCTAssertEqual(decodedAI?.preferredTextEntryMode, .aiChat)

        let dataSearch = try NSKeyedArchiver.archivedData(withRootObject: tabSearch, requiringSecureCoding: false)
        let decodedSearch = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(dataSearch) as? Tab
        XCTAssertEqual(decodedSearch?.preferredTextEntryMode, .search)
    }

    func testLegacyTabWithoutStoredModeInfersFromURL() {
        // Tab with regular URL — should default to .search
        let regularTab = Tab(coder: LegacyCoderStub(properties: [
            "link": Link(title: nil, url: URL(string: "https://example.com")!)
        ]))
        XCTAssertEqual(regularTab?.preferredTextEntryMode, .search)

        // Tab with duck.ai URL — should infer .aiChat
        let aiTab = Tab(coder: LegacyCoderStub(properties: [
            "link": Link(title: nil, url: URL(string: "https://duck.ai/chat")!)
        ]))
        XCTAssertEqual(aiTab?.preferredTextEntryMode, .aiChat)

        // Tab with no URL — should default to .search
        let emptyTab = Tab(coder: LegacyCoderStub(properties: [:]))
        XCTAssertEqual(emptyTab?.preferredTextEntryMode, .search)
    }
}

// MARK: - SwitchBarHandler Default Mode

final class SwitchBarHandlerDefaultModeTests: XCTestCase {

    func testInitializesToggleStateFromSettings() {
        let searchHandler = makeSUT(defaultMode: .search)
        XCTAssertEqual(searchHandler.currentToggleState, .search)

        let aiHandler = makeSUT(defaultMode: .duckAI)
        XCTAssertEqual(aiHandler.currentToggleState, .aiChat)
    }

    func testInitializesFromLastUsedStorage() {
        let store = MockKeyValueStore()
        let storage = ToggleModeStorage(store: store)
        storage.save(.aiChat)

        let handler = makeSUT(defaultMode: .lastUsed, toggleModeStorage: storage)
        XCTAssertEqual(handler.currentToggleState, .aiChat)
    }

    func testSetToggleStateDoesNotAutoSave() {
        let store = MockKeyValueStore()
        let storage = ToggleModeStorage(store: store)
        let handler = makeSUT(defaultMode: .search, toggleModeStorage: storage)

        handler.setToggleState(.aiChat)
        XCTAssertNil(storage.restore(), "setToggleState should not auto-save")

        handler.saveToggleState()
        XCTAssertEqual(storage.restore(), .aiChat)
    }

    private func makeSUT(
        defaultMode: DefaultOmnibarMode,
        toggleModeStorage: ToggleModeStoring = ToggleModeStorage(store: MockKeyValueStore())
    ) -> SwitchBarHandler {
        let settings = MockAIChatSettingsProvider(defaultOmnibarMode: defaultMode)
        return SwitchBarHandler(
            voiceSearchHelper: MockVoiceSearchHelper(),
            aiChatSettings: settings,
            toggleModeStorage: toggleModeStorage,
            sessionStateMetrics: SessionStateMetrics(storage: MockKeyValueStore()),
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []),
            isFireTab: false
        )
    }
}

// MARK: - Tab Creation Mode Inheritance

final class TabCreationModeInheritanceTests: XCTestCase {

    func testTabsInheritModeFromCurrentSettingAndRetainItAfterChange() {
        let settings = MockAIChatSettingsProvider(defaultOmnibarMode: .search)
        let store = MockKeyValueStore()
        let storage = ToggleModeStorage(store: store)

        let resolve: () -> TextEntryMode = {
            settings.defaultOmnibarMode.resolvedTextEntryMode { storage.restore() }
        }

        // Create tabs with search setting
        let tab1 = Tab(link: nil, preferredTextEntryMode: resolve())
        let tab2 = Tab(link: nil, preferredTextEntryMode: resolve())
        let tab3 = Tab(link: nil, preferredTextEntryMode: resolve())

        // Change setting to duck.ai
        settings.defaultOmnibarMode = .duckAI

        // Create tabs with duck.ai setting
        let tab4 = Tab(link: nil, preferredTextEntryMode: resolve())
        let tab5 = Tab(link: nil, preferredTextEntryMode: resolve())

        // Original tabs retain their mode
        XCTAssertEqual(tab1.preferredTextEntryMode, .search)
        XCTAssertEqual(tab2.preferredTextEntryMode, .search)
        XCTAssertEqual(tab3.preferredTextEntryMode, .search)

        // New tabs have the updated mode
        XCTAssertEqual(tab4.preferredTextEntryMode, .aiChat)
        XCTAssertEqual(tab5.preferredTextEntryMode, .aiChat)
    }

    func testLastUsedSettingPicksUpCommittedMode() {
        let settings = MockAIChatSettingsProvider(defaultOmnibarMode: .lastUsed)
        let store = MockKeyValueStore()
        let storage = ToggleModeStorage(store: store)

        let resolve: () -> TextEntryMode = {
            settings.defaultOmnibarMode.resolvedTextEntryMode { storage.restore() }
        }

        // No stored value — defaults to search
        let tab1 = Tab(link: nil, preferredTextEntryMode: resolve())
        XCTAssertEqual(tab1.preferredTextEntryMode, .search)

        // Simulate commit: user submitted in aiChat mode
        storage.save(.aiChat)

        // New tab inherits last committed mode
        let tab2 = Tab(link: nil, preferredTextEntryMode: resolve())
        XCTAssertEqual(tab2.preferredTextEntryMode, .aiChat)

        // Simulate commit: user submitted in search mode
        storage.save(.search)

        let tab3 = Tab(link: nil, preferredTextEntryMode: resolve())
        XCTAssertEqual(tab3.preferredTextEntryMode, .search)
    }
}

// MARK: - Helpers

/// Simulates a legacy NSCoder that does NOT contain the preferredTextEntryMode key,
/// mimicking tabs created before the feature was introduced.
private class LegacyCoderStub: NSCoder {

    private let properties: [String: Any]

    init(properties: [String: Any]) {
        self.properties = properties
    }

    override func containsValue(forKey key: String) -> Bool {
        return properties.keys.contains(key)
    }

    override func decodeObject(forKey key: String) -> Any? {
        return properties[key]
    }

    override func decodeBool(forKey key: String) -> Bool {
        return (properties[key] as? Bool) ?? false
    }

    override func decodeInteger(forKey key: String) -> Int {
        return (properties[key] as? Int) ?? 0
    }

    override var allowsKeyedCoding: Bool { true }
}
