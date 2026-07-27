//
//  PromptBarPreferencesPersistorTests.swift
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
import PersistenceTestingUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class PromptBarPreferencesPersistorTests: XCTestCase {

    private var keyValueStore: MockKeyValueFileStore!
    private var persistor: PromptBarPreferencesUserDefaultsPersistor!

    override func setUp() {
        super.setUp()
        keyValueStore = MockKeyValueFileStore()
        persistor = PromptBarPreferencesUserDefaultsPersistor(keyValueStore: keyValueStore)
    }

    override func tearDown() {
        persistor = nil
        keyValueStore = nil
        super.tearDown()
    }

    func testWhenNothingIsPersistedThenDefaultsAreReturned() {
        XCTAssertTrue(persistor.isKeyboardShortcutEnabled)
        XCTAssertTrue(persistor.isMenuBarIconVisible)
        XCTAssertEqual(persistor.keyboardShortcut, .defaultShortcut)
    }

    func testWhenValuesAreSetThenTheyArePersistedToTheStore() {
        let customShortcut = PromptBarShortcut(keyCode: UInt16(kVK_ANSI_D), modifierFlags: [.control, .option])

        persistor.isKeyboardShortcutEnabled = false
        persistor.isMenuBarIconVisible = false
        persistor.keyboardShortcut = customShortcut

        let rereadPersistor = PromptBarPreferencesUserDefaultsPersistor(keyValueStore: keyValueStore)
        XCTAssertFalse(rereadPersistor.isKeyboardShortcutEnabled)
        XCTAssertFalse(rereadPersistor.isMenuBarIconVisible)
        XCTAssertEqual(rereadPersistor.keyboardShortcut, customShortcut)
    }

    func testWhenPersistedShortcutDataIsCorruptedThenDefaultShortcutIsReturned() {
        let key = PromptBarPreferencesUserDefaultsPersistor.Key.keyboardShortcut.rawValue
        keyValueStore.underlyingDict[key] = Data("not a shortcut".utf8)

        XCTAssertEqual(persistor.keyboardShortcut, .defaultShortcut)
    }

    func testWhenStoreThrowsOnReadThenDefaultsAreReturned() {
        keyValueStore.shouldThrowOnGet = true

        XCTAssertTrue(persistor.isKeyboardShortcutEnabled)
        XCTAssertTrue(persistor.isMenuBarIconVisible)
        XCTAssertEqual(persistor.keyboardShortcut, .defaultShortcut)
    }
}
