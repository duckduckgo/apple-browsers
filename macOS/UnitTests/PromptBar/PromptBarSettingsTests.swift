//
//  PromptBarSettingsTests.swift
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
import XCTest
@testable import DuckDuckGo_Privacy_Browser

private final class MockPromptBarPreferencesPersistor: PromptBarPreferencesPersistor {
    var isKeyboardShortcutEnabled: Bool = true
    var keyboardShortcut: PromptBarShortcut = .defaultShortcut
    var isMenuBarIconVisible: Bool = true
}

final class PromptBarSettingsTests: XCTestCase {

    func testWhenInitializedThenValuesAreSeededFromPersistor() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.isKeyboardShortcutEnabled = false
        persistor.isMenuBarIconVisible = false
        persistor.keyboardShortcut = PromptBarShortcut(keyCode: UInt16(kVK_ANSI_D), modifierFlags: [.control, .option])

        let settings = PromptBarSettings(persistor: persistor)

        XCTAssertFalse(settings.isKeyboardShortcutEnabled)
        XCTAssertFalse(settings.isMenuBarIconVisible)
        XCTAssertEqual(settings.keyboardShortcut, persistor.keyboardShortcut)
    }

    func testWhenValuesChangeThenTheyAreWrittenToPersistor() {
        let persistor = MockPromptBarPreferencesPersistor()
        let settings = PromptBarSettings(persistor: persistor)
        let customShortcut = PromptBarShortcut(keyCode: UInt16(kVK_ANSI_D), modifierFlags: [.control, .option])

        settings.isKeyboardShortcutEnabled = false
        settings.isMenuBarIconVisible = false
        settings.keyboardShortcut = customShortcut

        XCTAssertFalse(persistor.isKeyboardShortcutEnabled)
        XCTAssertFalse(persistor.isMenuBarIconVisible)
        XCTAssertEqual(persistor.keyboardShortcut, customShortcut)
    }

    func testWhenResetKeyboardShortcutToDefaultThenDefaultShortcutIsAppliedAndPersisted() {
        let persistor = MockPromptBarPreferencesPersistor()
        persistor.keyboardShortcut = PromptBarShortcut(keyCode: UInt16(kVK_ANSI_D), modifierFlags: [.control, .option])
        let settings = PromptBarSettings(persistor: persistor)

        settings.resetKeyboardShortcutToDefault()

        XCTAssertEqual(settings.keyboardShortcut, .defaultShortcut)
        XCTAssertEqual(persistor.keyboardShortcut, .defaultShortcut)
    }
}
