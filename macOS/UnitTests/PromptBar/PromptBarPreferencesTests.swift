//
//  PromptBarPreferencesTests.swift
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

import Carbon.HIToolbox
import Combine
import PersistenceTestingUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

/// Both flags start off, mirroring the opt-in product default.
private final class MockPromptBarPreferencesPersistor: PromptBarPreferencesPersistor {
    var isKeyboardShortcutEnabled: Bool = false
    var keyboardShortcut: PromptBarShortcut = .defaultShortcut
    var isMenuBarIconVisible: Bool = false
}

private extension MockAIChatConfig {
    static var enabled: MockAIChatConfig {
        let configuration = MockAIChatConfig()
        configuration.shouldDisplayAnyAIChatFeature = true
        return configuration
    }
}

final class PromptBarPreferencesTests: XCTestCase {

    private func makePreferences(persistor: PromptBarPreferencesPersistor,
                                 configuration: MockAIChatConfig = .enabled) -> PromptBarPreferences {
        PromptBarPreferences(persistor: persistor, aiChatMenuConfiguration: configuration)
    }

    func testWhenNothingIsPersistedThenBothEntryPointsAreOff() {
        let persistor = PromptBarPreferencesUserDefaultsPersistor(keyValueStore: MockKeyValueFileStore())

        let preferences = makePreferences(persistor: persistor)

        XCTAssertFalse(preferences.isKeyboardShortcutEnabled)
        XCTAssertFalse(preferences.isMenuBarIconVisible)
        XCTAssertFalse(preferences.isKeyboardShortcutEffectivelyEnabled)
        XCTAssertFalse(preferences.isMenuBarIconEffectivelyVisible)
    }

    func testWhenNothingIsPersistedThenNoShortcutIsPublished() {
        let persistor = PromptBarPreferencesUserDefaultsPersistor(keyValueStore: MockKeyValueFileStore())
        let preferences = makePreferences(persistor: persistor)
        var received: [PromptBarShortcut?] = []

        let cancellable = preferences.effectiveKeyboardShortcutPublisher.sink { received.append($0) }

        XCTAssertEqual(received, [nil])
        cancellable.cancel()
    }

    func testWhenInitializedThenValuesAreSeededFromPersistor() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.isKeyboardShortcutEnabled = true
        persistor.isMenuBarIconVisible = true
        persistor.keyboardShortcut = PromptBarShortcut(keyCode: UInt16(kVK_ANSI_D), modifierFlags: [.control, .option])

        let preferences = makePreferences(persistor: persistor)

        XCTAssertTrue(preferences.isKeyboardShortcutEnabled)
        XCTAssertTrue(preferences.isMenuBarIconVisible)
        XCTAssertEqual(preferences.keyboardShortcut, persistor.keyboardShortcut)
    }

    func testWhenValuesChangeThenTheyAreWrittenToPersistor() {
        let persistor = MockPromptBarPreferencesPersistor()
        let preferences = makePreferences(persistor: persistor)
        let customShortcut = PromptBarShortcut(keyCode: UInt16(kVK_ANSI_D), modifierFlags: [.control, .option])

        preferences.isKeyboardShortcutEnabled = true
        preferences.isMenuBarIconVisible = true
        preferences.keyboardShortcut = customShortcut

        XCTAssertTrue(persistor.isKeyboardShortcutEnabled)
        XCTAssertTrue(persistor.isMenuBarIconVisible)
        XCTAssertEqual(persistor.keyboardShortcut, customShortcut)
    }

    func testWhenResetKeyboardShortcutToDefaultThenDefaultShortcutIsAppliedAndPersisted() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.keyboardShortcut = PromptBarShortcut(keyCode: UInt16(kVK_ANSI_D), modifierFlags: [.control, .option])
        let preferences = makePreferences(persistor: persistor)

        preferences.resetKeyboardShortcutToDefault()

        XCTAssertEqual(preferences.keyboardShortcut, .defaultShortcut)
        XCTAssertEqual(persistor.keyboardShortcut, .defaultShortcut)
    }

    func testWhenKeyboardShortcutIsDisabledThenMenuBarIconIsStillEffectivelyVisible() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.isMenuBarIconVisible = true
        persistor.isKeyboardShortcutEnabled = false

        let preferences = makePreferences(persistor: persistor)

        XCTAssertTrue(preferences.isMenuBarIconEffectivelyVisible)
    }

    func testWhenMenuBarIconIsEnabledThenIconIsEffectivelyVisible() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.isMenuBarIconVisible = true
        persistor.isKeyboardShortcutEnabled = true

        let preferences = makePreferences(persistor: persistor)

        XCTAssertTrue(preferences.isMenuBarIconEffectivelyVisible)
    }

    func testWhenKeyboardShortcutIsTurnedOffThenMenuBarIconVisibilityIsUnaffected() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.isMenuBarIconVisible = true
        persistor.isKeyboardShortcutEnabled = true
        let preferences = makePreferences(persistor: persistor)

        preferences.isKeyboardShortcutEnabled = false

        XCTAssertTrue(preferences.isMenuBarIconVisible)
        XCTAssertTrue(persistor.isMenuBarIconVisible)
        XCTAssertTrue(preferences.isMenuBarIconEffectivelyVisible)
    }

    func testWhenKeyboardShortcutIsTurnedOffThenEffectiveVisibilityPublisherDoesNotEmitAgain() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.isMenuBarIconVisible = true
        persistor.isKeyboardShortcutEnabled = true
        let preferences = makePreferences(persistor: persistor)
        var received: [Bool] = []
        let cancellable = preferences.isMenuBarIconEffectivelyVisiblePublisher.sink { received.append($0) }

        preferences.isKeyboardShortcutEnabled = false

        XCTAssertEqual(received, [true])
        cancellable.cancel()
    }

    func testWhenMenuBarIconIsTurnedOffThenEffectiveVisibilityPublisherEmitsFalse() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.isMenuBarIconVisible = true
        let preferences = makePreferences(persistor: persistor)
        var received: [Bool] = []
        let cancellable = preferences.isMenuBarIconEffectivelyVisiblePublisher.sink { received.append($0) }

        preferences.isMenuBarIconVisible = false

        XCTAssertEqual(received, [true, false])
        cancellable.cancel()
    }

    func testWhenSubscribedThenEffectiveVisibilityPublisherEmitsCurrentValueSynchronously() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.isMenuBarIconVisible = false
        persistor.isKeyboardShortcutEnabled = true
        let preferences = makePreferences(persistor: persistor)
        var received: [Bool] = []

        let cancellable = preferences.isMenuBarIconEffectivelyVisiblePublisher.sink { received.append($0) }

        XCTAssertEqual(received, [false])
        cancellable.cancel()
    }

    func testWhenAIFeaturesAreDisabledThenMenuBarIconIsNotEffectivelyVisible() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.isMenuBarIconVisible = true
        persistor.isKeyboardShortcutEnabled = true
        let configuration = MockAIChatConfig()
        configuration.shouldDisplayAnyAIChatFeature = false

        let preferences = makePreferences(persistor: persistor, configuration: configuration)

        XCTAssertFalse(preferences.isMenuBarIconEffectivelyVisible)
    }

    func testWhenAIFeaturesAreTurnedOffThenEffectiveVisibilityPublisherEmitsFalse() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.isMenuBarIconVisible = true
        persistor.isKeyboardShortcutEnabled = true
        let configuration = MockAIChatConfig.enabled
        let preferences = makePreferences(persistor: persistor, configuration: configuration)
        var received: [Bool] = []
        let cancellable = preferences.isMenuBarIconEffectivelyVisiblePublisher.sink { received.append($0) }

        configuration.shouldDisplayAnyAIChatFeature = false
        configuration.valuesChangedPublisher.send()

        XCTAssertEqual(received, [true, false])
        cancellable.cancel()
    }

    func testWhenAIFeaturesAreDisabledThenStoredMenuBarIconPreferenceIsUnchanged() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.isMenuBarIconVisible = true
        persistor.isKeyboardShortcutEnabled = true
        let configuration = MockAIChatConfig()
        configuration.shouldDisplayAnyAIChatFeature = false

        let preferences = makePreferences(persistor: persistor, configuration: configuration)

        XCTAssertTrue(preferences.isMenuBarIconVisible)
        XCTAssertTrue(persistor.isMenuBarIconVisible)
        XCTAssertFalse(preferences.isMenuBarIconEffectivelyVisible)
    }
}
