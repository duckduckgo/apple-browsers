//
//  WebExtensionCommandShortcutStoreTests.swift
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

#if os(macOS)
import AppKit
@_spi(Testing) import Persistence
import XCTest
@testable import WebExtensions

@available(macOS 15.4, *)
@MainActor
final class WebExtensionCommandShortcutStoreTests: XCTestCase {

    private let keyValueStore = InMemoryThrowingKeyValueStore()
    private var store: WebExtensionCommandShortcutStore { WebExtensionCommandShortcutStore(keyValueStore: keyValueStore) }

    private let lockShortcut = WebExtensionCommandShortcut(activationKey: "t", modifierFlags: [.command, .option, .shift])

    func testWhenAnInstallationIsUpdated_ThenItsShortcutsAreCopiedToTheNewInstallation() throws {
        try seed(["lock_vault": lockShortcut], for: "old")

        store.copyShortcutsForUpdate(from: "old", to: "new")

        XCTAssertEqual(try saved(for: "new"), ["lock_vault": lockShortcut])
    }

    func testWhenAnInstallationWithoutShortcutsIsUpdated_ThenNothingIsSaved() throws {
        store.copyShortcutsForUpdate(from: "old", to: "new")

        XCTAssertNil(try keyValueStore.object(forKey: "web-extension-command-shortcuts.new"))
    }

    func testWhenShortcutsAreRemoved_ThenOnlyThatInstallationLosesThem() throws {
        try seed(["lock_vault": lockShortcut], for: "removed")
        try seed(["lock_vault": lockShortcut], for: "kept")

        store.removeShortcuts(for: "removed")

        XCTAssertNil(try keyValueStore.object(forKey: "web-extension-command-shortcuts.removed"))
        XCTAssertEqual(try saved(for: "kept"), ["lock_vault": lockShortcut])
    }

    // MARK: - Helpers

    private func seed(_ shortcuts: [String: WebExtensionCommandShortcut], for identifier: String) throws {
        try keyValueStore.set(JSONEncoder().encode(shortcuts), forKey: "web-extension-command-shortcuts.\(identifier)")
    }

    private func saved(for identifier: String) throws -> [String: WebExtensionCommandShortcut]? {
        guard let data = try keyValueStore.object(forKey: "web-extension-command-shortcuts.\(identifier)") as? Data else { return nil }
        return try JSONDecoder().decode([String: WebExtensionCommandShortcut].self, from: data)
    }
}
#endif
