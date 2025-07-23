//
//  NewTabPageAIChatShortcutSettingProviderTests.swift
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

import AIChat
import Combine
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class NewTabPageAIChatShortcutSettingProviderTests: XCTestCase {
    private var provider: NewTabPageAIChatShortcutSettingProvider!
    private var suiteName: String!
    private var userDefaults: UserDefaults!
    private var configuration: AIChatMenuConfiguration!
    private var storage: DefaultAIChatPreferencesStorage!

    override func setUp() async throws {
        suiteName = UUID().uuidString
        userDefaults = UserDefaults(suiteName: suiteName)
        storage = DefaultAIChatPreferencesStorage(userDefaults: userDefaults)
        configuration = AIChatMenuConfiguration(storage: storage, remoteSettings: MockRemoteAISettings())

        provider = NewTabPageAIChatShortcutSettingProvider(
            aiChatMenuConfiguration: configuration,
            aiChatPreferencesStorage: storage
        )
    }

    override func tearDown() async throws {
        userDefaults.removePersistentDomain(forName: suiteName)
        provider = nil
        configuration = nil
        userDefaults = nil
    }

    func testWhenFlagIsTrueThenGetterReturnsTrue() {
        storage.showShortcutOnNewTabPage = true
        XCTAssertEqual(provider.isAIChatShortcutEnabled, true)
    }

    func testWhenFlagIsFalseThenGetterReturnsFalse() {
        storage.showShortcutOnNewTabPage = false
        XCTAssertEqual(provider.isAIChatShortcutEnabled, false)
    }

    func testWhenFlagIsTrueButGlobalToggleIsFalseThenGetterReturnsFalse() {
        storage.showShortcutOnNewTabPage = true
        storage.isAIFeaturesEnabled = false
        XCTAssertEqual(provider.isAIChatShortcutEnabled, false)
    }

    func testThatSetterUpdatesStorage() {
        provider.isAIChatShortcutEnabled = true
        XCTAssertEqual(storage.showShortcutOnNewTabPage, true)
        provider.isAIChatShortcutEnabled = false
        XCTAssertEqual(storage.showShortcutOnNewTabPage, false)
    }

    func testThatPublisherEmitsValuesWhenGlobalToggleOrLocalFlagChange() {
        var events: [Bool] = []

        let cancellable = provider.isAIChatShortcutEnabledPublisher
            .sink { value in
                events.append(value)
            }

        storage.showShortcutOnNewTabPage = true
        XCTAssertEqual(events, [])

        storage.showShortcutOnNewTabPage = false
        XCTAssertEqual(events, [false])

        storage.showShortcutOnNewTabPage = true
        XCTAssertEqual(events, [false, true])

        storage.isAIFeaturesEnabled = false // overrides flag to false
        XCTAssertEqual(events, [false, true, false])

        storage.showShortcutOnNewTabPage = false
        XCTAssertEqual(events, [false, true, false])

        storage.isAIFeaturesEnabled = true // overrides flag to false
        XCTAssertEqual(events, [false, true, false])

        storage.showShortcutOnNewTabPage = true
        XCTAssertEqual(events, [false, true, false, true])

        cancellable.cancel()
    }
}
