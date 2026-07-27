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
import XCTest
@testable import DuckDuckGo_Privacy_Browser

private final class MockPromptBarPreferencesPersistor: PromptBarPreferencesPersistor {
    var isKeyboardShortcutEnabled: Bool = true
    var keyboardShortcut: PromptBarShortcut = .defaultShortcut
    var isMenuBarIconVisible: Bool = true
}

final class PromptBarPreferencesTests: XCTestCase {

    func testWhenInitializedThenValuesAreSeededFromPersistor() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.isKeyboardShortcutEnabled = false
        persistor.isMenuBarIconVisible = false
        persistor.keyboardShortcut = PromptBarShortcut(keyCode: UInt16(kVK_ANSI_D), modifierFlags: [.control, .option])

        let preferences = PromptBarPreferences(persistor: persistor)

        XCTAssertFalse(preferences.isKeyboardShortcutEnabled)
        XCTAssertFalse(preferences.isMenuBarIconVisible)
        XCTAssertEqual(preferences.keyboardShortcut, persistor.keyboardShortcut)
    }

    func testWhenValuesChangeThenTheyAreWrittenToPersistor() {
        let persistor = MockPromptBarPreferencesPersistor()
        let preferences = PromptBarPreferences(persistor: persistor)
        let customShortcut = PromptBarShortcut(keyCode: UInt16(kVK_ANSI_D), modifierFlags: [.control, .option])

        preferences.isKeyboardShortcutEnabled = false
        preferences.isMenuBarIconVisible = false
        preferences.keyboardShortcut = customShortcut

        XCTAssertFalse(persistor.isKeyboardShortcutEnabled)
        XCTAssertFalse(persistor.isMenuBarIconVisible)
        XCTAssertEqual(persistor.keyboardShortcut, customShortcut)
    }

    func testWhenResetKeyboardShortcutToDefaultThenDefaultShortcutIsAppliedAndPersisted() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.keyboardShortcut = PromptBarShortcut(keyCode: UInt16(kVK_ANSI_D), modifierFlags: [.control, .option])
        let preferences = PromptBarPreferences(persistor: persistor)

        preferences.resetKeyboardShortcutToDefault()

        XCTAssertEqual(preferences.keyboardShortcut, .defaultShortcut)
        XCTAssertEqual(persistor.keyboardShortcut, .defaultShortcut)
    }

    func testWhenKeyboardShortcutIsDisabledThenMenuBarIconIsNotEffectivelyVisible() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.isMenuBarIconVisible = true
        persistor.isKeyboardShortcutEnabled = false

        let preferences = PromptBarPreferences(persistor: persistor)

        XCTAssertFalse(preferences.isMenuBarIconEffectivelyVisible)
    }

    func testWhenKeyboardShortcutAndMenuBarIconAreEnabledThenIconIsEffectivelyVisible() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.isMenuBarIconVisible = true
        persistor.isKeyboardShortcutEnabled = true

        let preferences = PromptBarPreferences(persistor: persistor)

        XCTAssertTrue(preferences.isMenuBarIconEffectivelyVisible)
    }

    func testWhenKeyboardShortcutIsDisabledThenStoredMenuBarIconPreferenceIsUnchanged() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.isMenuBarIconVisible = true
        let preferences = PromptBarPreferences(persistor: persistor)

        preferences.isKeyboardShortcutEnabled = false

        XCTAssertTrue(preferences.isMenuBarIconVisible)
        XCTAssertTrue(persistor.isMenuBarIconVisible)
        XCTAssertFalse(preferences.isMenuBarIconEffectivelyVisible)
    }

    func testWhenKeyboardShortcutIsDisabledThenEffectiveVisibilityPublisherEmitsFalse() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.isMenuBarIconVisible = true
        persistor.isKeyboardShortcutEnabled = true
        let preferences = PromptBarPreferences(persistor: persistor)
        var received: [Bool] = []
        let cancellable = preferences.isMenuBarIconEffectivelyVisiblePublisher.sink { received.append($0) }

        preferences.isKeyboardShortcutEnabled = false

        XCTAssertEqual(received, [true, false])
        cancellable.cancel()
    }

    func testWhenSubscribedThenEffectiveVisibilityPublisherEmitsCurrentValueSynchronously() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.isMenuBarIconVisible = true
        persistor.isKeyboardShortcutEnabled = false
        let preferences = PromptBarPreferences(persistor: persistor)
        var received: [Bool] = []

        let cancellable = preferences.isMenuBarIconEffectivelyVisiblePublisher.sink { received.append($0) }

        XCTAssertEqual(received, [false])
        cancellable.cancel()
    }
}
