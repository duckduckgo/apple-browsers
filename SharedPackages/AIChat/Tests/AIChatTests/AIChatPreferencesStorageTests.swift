//
//  AIChatPreferencesStorageTests.swift
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

#if os(macOS)
import XCTest
@testable import AIChat

final class AIChatPreferencesStorageTests: XCTestCase {

    private var userDefaults: UserDefaults!
    private var storage: DefaultAIChatPreferencesStorage!

    private enum Keys {
        static let showAIChatShortcutInAddressBarWhenTyping = "aichat.showAIChatShortcutInAddressBarWhenTyping"
        static let showSearchAndDuckAIToggle = "aichat.showSearchAndDuckAIToggle"
    }

    override func setUp() {
        super.setUp()
        // Create a unique UserDefaults suite for test isolation
        let suiteName = "com.duckduckgo.aichat.tests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        storage = DefaultAIChatPreferencesStorage(userDefaults: userDefaults)
    }

    override func tearDown() {
        // Clean up all keys
        userDefaults.removePersistentDomain(forName: userDefaults.description)
        userDefaults = nil
        storage = nil
        super.tearDown()
    }

    // MARK: - showSearchAndDuckAIToggle Migration Tests

    /// When showSearchAndDuckAIToggle is not set and showAIChatShortcutInAddressBarWhenTyping is true, the getter returns true
    func testShowSearchAndDuckAIToggle_WhenNotSetAndAddressBarWhenTypingIsTrue_ReturnsTrue() {
        // Given: showSearchAndDuckAIToggle is not set, showAIChatShortcutInAddressBarWhenTyping is true
        userDefaults.removeObject(forKey: Keys.showSearchAndDuckAIToggle)
        userDefaults.set(true, forKey: Keys.showAIChatShortcutInAddressBarWhenTyping)

        // When: accessing showSearchAndDuckAIToggle
        let result = storage.showSearchAndDuckAIToggle

        // Then: it should inherit from showAIChatShortcutInAddressBarWhenTyping
        XCTAssertTrue(result, "showSearchAndDuckAIToggle should inherit true from showAIChatShortcutInAddressBarWhenTyping")
    }

    /// When showSearchAndDuckAIToggle is not set and showAIChatShortcutInAddressBarWhenTyping is false, the getter returns false
    func testShowSearchAndDuckAIToggle_WhenNotSetAndAddressBarWhenTypingIsFalse_ReturnsFalse() {
        // Given: showSearchAndDuckAIToggle is not set, showAIChatShortcutInAddressBarWhenTyping is false
        userDefaults.removeObject(forKey: Keys.showSearchAndDuckAIToggle)
        userDefaults.set(false, forKey: Keys.showAIChatShortcutInAddressBarWhenTyping)

        // When: accessing showSearchAndDuckAIToggle
        let result = storage.showSearchAndDuckAIToggle

        // Then: it should inherit from showAIChatShortcutInAddressBarWhenTyping
        XCTAssertFalse(result, "showSearchAndDuckAIToggle should inherit false from showAIChatShortcutInAddressBarWhenTyping")
    }

    /// Once showSearchAndDuckAIToggle is explicitly set by the user, it persists and no longer inherits from the old setting
    func testShowSearchAndDuckAIToggle_WhenExplicitlySet_PersistsAndDoesNotInherit() {
        // Given: showAIChatShortcutInAddressBarWhenTyping is false
        userDefaults.set(false, forKey: Keys.showAIChatShortcutInAddressBarWhenTyping)

        // When: explicitly setting showSearchAndDuckAIToggle to true
        storage.showSearchAndDuckAIToggle = true

        // Then: it should persist as true and not inherit from showAIChatShortcutInAddressBarWhenTyping
        XCTAssertTrue(storage.showSearchAndDuckAIToggle, "showSearchAndDuckAIToggle should persist as true after being explicitly set")

        // When: changing showAIChatShortcutInAddressBarWhenTyping
        userDefaults.set(true, forKey: Keys.showAIChatShortcutInAddressBarWhenTyping)

        // Then: showSearchAndDuckAIToggle should still be true (not inheriting)
        XCTAssertTrue(storage.showSearchAndDuckAIToggle, "showSearchAndDuckAIToggle should not change when showAIChatShortcutInAddressBarWhenTyping changes after explicit set")
    }

    /// Once showSearchAndDuckAIToggle is explicitly set to false, it persists
    func testShowSearchAndDuckAIToggle_WhenExplicitlySetToFalse_Persists() {
        // Given: showAIChatShortcutInAddressBarWhenTyping is true (default)
        userDefaults.set(true, forKey: Keys.showAIChatShortcutInAddressBarWhenTyping)

        // When: explicitly setting showSearchAndDuckAIToggle to false
        storage.showSearchAndDuckAIToggle = false

        // Then: it should persist as false
        XCTAssertFalse(storage.showSearchAndDuckAIToggle, "showSearchAndDuckAIToggle should persist as false after being explicitly set")
    }

    /// The default value is correctly applied when both settings are unset (inherits from showAIChatShortcutInAddressBarWhenTyping default)
    func testShowSearchAndDuckAIToggle_WhenBothSettingsUnset_ReturnsDefaultValue() {
        // Given: both settings are not set (fresh state)
        userDefaults.removeObject(forKey: Keys.showSearchAndDuckAIToggle)
        userDefaults.removeObject(forKey: Keys.showAIChatShortcutInAddressBarWhenTyping)

        // When: accessing showSearchAndDuckAIToggle
        let result = storage.showSearchAndDuckAIToggle

        // Then: it should return true (the default value of showAIChatShortcutInAddressBarWhenTyping)
        XCTAssertTrue(result, "showSearchAndDuckAIToggle should return true (default) when both settings are unset")
    }

    /// Verifies that showAIChatShortcutInAddressBarWhenTyping has correct default value
    func testShowAIChatShortcutInAddressBarWhenTyping_DefaultValue_IsTrue() {
        // Given: setting is not set
        userDefaults.removeObject(forKey: Keys.showAIChatShortcutInAddressBarWhenTyping)

        // When: accessing the setting
        let result = storage.showShortcutInAddressBarWhenTyping

        // Then: it should return true (default)
        XCTAssertTrue(result, "showShortcutInAddressBarWhenTyping should default to true")
    }

    /// Migration scenario: user had showAIChatShortcutInAddressBarWhenTyping set to false before update
    func testMigrationScenario_UserHadAddressBarWhenTypingDisabled_NewToggleInheritsDisabled() {
        // Given: simulating a user who disabled the old setting before the update
        userDefaults.set(false, forKey: Keys.showAIChatShortcutInAddressBarWhenTyping)
        // showSearchAndDuckAIToggle is not set (new feature)

        // When: accessing the new toggle
        let result = storage.showSearchAndDuckAIToggle

        // Then: it should inherit the disabled state
        XCTAssertFalse(result, "New toggle should inherit disabled state from old setting")
    }

    /// Migration scenario: user had showAIChatShortcutInAddressBarWhenTyping enabled (or default)
    func testMigrationScenario_UserHadAddressBarWhenTypingEnabled_NewToggleInheritsEnabled() {
        // Given: simulating a user with the old setting enabled
        userDefaults.set(true, forKey: Keys.showAIChatShortcutInAddressBarWhenTyping)
        // showSearchAndDuckAIToggle is not set (new feature)

        // When: accessing the new toggle
        let result = storage.showSearchAndDuckAIToggle

        // Then: it should inherit the enabled state
        XCTAssertTrue(result, "New toggle should inherit enabled state from old setting")
    }

    /// After user explicitly changes new toggle, changing old setting has no effect
    func testAfterExplicitSet_ChangingOldSetting_HasNoEffect() {
        // Given: user explicitly sets the new toggle
        storage.showSearchAndDuckAIToggle = true

        // When: old setting is changed
        userDefaults.set(false, forKey: Keys.showAIChatShortcutInAddressBarWhenTyping)

        // Then: new toggle should still be true
        XCTAssertTrue(storage.showSearchAndDuckAIToggle, "New toggle should not be affected by old setting changes after explicit set")

        // And when: setting new toggle to false explicitly
        storage.showSearchAndDuckAIToggle = false

        // Then: it should be false
        XCTAssertFalse(storage.showSearchAndDuckAIToggle, "New toggle should persist its explicitly set value")

        // And when: old setting is changed again
        userDefaults.set(true, forKey: Keys.showAIChatShortcutInAddressBarWhenTyping)

        // Then: new toggle should still be false
        XCTAssertFalse(storage.showSearchAndDuckAIToggle, "New toggle should not be affected by old setting changes")
    }
}
#endif
