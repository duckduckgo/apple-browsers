//
//  NewTabPageOmnibarConfigProviderTests.swift
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

import Combine
import XCTest
import Persistence
import PersistenceTestingUtils
@testable import DuckDuckGo_Privacy_Browser

final class MockNewTabPageAIChatShortcutSettingProvider: NewTabPageAIChatShortcutSettingProviding {
    @Published var isAIChatShortcutEnabled: Bool = true

    var isAIChatShortcutEnabledPublisher: AnyPublisher<Bool, Never> {
        $isAIChatShortcutEnabled.dropFirst().eraseToAnyPublisher()
    }

    @Published var isAIChatSettingVisible: Bool = true

    var isAIChatSettingVisiblePublisher: AnyPublisher<Bool, Never> {
        $isAIChatSettingVisible.dropFirst().eraseToAnyPublisher()
    }
}

final class NewTabPageOmnibarConfigProviderTests: XCTestCase {

    // Key used for persistence in the provider
    private let storageKey = "newTabPageOmnibarMode"

    // Helper to create a mock key-value store
    private func makeStore(
        underlying: [String: Any] = [:],
        throwOnRead: Error? = nil,
        throwOnSet: Error? = nil
    ) throws -> MockKeyValueFileStore {
        let store = try MockKeyValueFileStore(underlyingDict: underlying)
        store.throwOnRead = throwOnRead
        store.throwOnSet = throwOnSet
        return store
    }

    @MainActor
    func testDefaultModeWhenNoValueInStore() throws {
        let store = try makeStore()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider())
        XCTAssertEqual(provider.mode, .search)
    }

    @MainActor
    func testModeReadsStoredValidValue() throws {
        let store = try makeStore(underlying: [storageKey: "ai"])
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider())
        XCTAssertEqual(provider.mode, .ai)
    }

    @MainActor
    func testModeDefaultsToSearchOnInvalidRawValue() throws {
        let store = try makeStore(underlying: [storageKey: "invalid"])
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider())
        XCTAssertEqual(provider.mode, .search)
    }

    @MainActor
    func testModeDefaultsToSearchOnReadError() throws {
        let readError = NSError(domain: "test", code: 1)
        let store = try makeStore(throwOnRead: readError)
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider())
        XCTAssertEqual(provider.mode, .search)
    }

    @MainActor
    func testSettingModeWritesValue() throws {
        let store = try makeStore()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider())
        provider.mode = .ai
        // Underlying dict should contain the rawValue
        XCTAssertEqual(store.underlyingDict[storageKey] as? String, "ai")
        // Reading back returns the same
        XCTAssertEqual(provider.mode, .ai)
    }

    @MainActor
    func testSettingModeHandlesWriteErrorGracefully() throws {
        let writeError = NSError(domain: "test", code: 2)
        let store = try makeStore(throwOnSet: writeError)
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider())
        // Should not throw on write error
        provider.mode = .ai
        // Underlying dict remains unchanged
        XCTAssertNil(store.underlyingDict[storageKey])
    }

    // MARK: - isAIChatShortcutEnabled

    func testThatAIChatShortcutEnabledFlagIsPassedToSettingProvider() throws {
        let store = try makeStore()
        let settingProvider = MockNewTabPageAIChatShortcutSettingProvider()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: settingProvider)

        provider.isAIChatShortcutEnabled = true
        XCTAssertEqual(settingProvider.isAIChatShortcutEnabled, true)

        provider.isAIChatShortcutEnabled = false
        XCTAssertEqual(settingProvider.isAIChatShortcutEnabled, false)
    }

    func testThatAIChatShortcutEnabledFlagPublisherIsConnectedToSettingProvider() throws {
        let store = try makeStore()
        let settingProvider = MockNewTabPageAIChatShortcutSettingProvider()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: settingProvider)

        var events: [Bool] = []

        let cancellable = provider.isAIChatShortcutEnabledPublisher
            .sink { value in
                events.append(value)
            }

        settingProvider.isAIChatShortcutEnabled = true
        settingProvider.isAIChatShortcutEnabled = false
        settingProvider.isAIChatShortcutEnabled = true

        cancellable.cancel()

        XCTAssertEqual(events, [true, false, true])
    }

    // MARK: - isAIChatSettingVisible

    func testThatAIChatSettingsVisibleFlagIsPassedToFromSettingProvider() throws {
        let store = try makeStore()
        let settingProvider = MockNewTabPageAIChatShortcutSettingProvider()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: settingProvider)

        settingProvider.isAIChatSettingVisible = true
        XCTAssertEqual(provider.isAIChatSettingVisible, true)

        settingProvider.isAIChatSettingVisible = false
        XCTAssertEqual(provider.isAIChatSettingVisible, false)
    }

    func testThatAIChatSettingVisibleFlagPublisherIsConnectedToSettingProvider() throws {
        let store = try makeStore()
        let settingProvider = MockNewTabPageAIChatShortcutSettingProvider()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: settingProvider)

        var events: [Bool] = []

        let cancellable = provider.isAIChatSettingVisiblePublisher
            .sink { value in
                events.append(value)
            }

        settingProvider.isAIChatSettingVisible = true
        settingProvider.isAIChatSettingVisible = false
        settingProvider.isAIChatSettingVisible = true

        cancellable.cancel()

        XCTAssertEqual(events, [true, false, true])
    }
}
