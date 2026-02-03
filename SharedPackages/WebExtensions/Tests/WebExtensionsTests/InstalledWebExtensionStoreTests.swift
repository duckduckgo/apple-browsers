//
//  InstalledWebExtensionStoreTests.swift
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

import XCTest
import Persistence
import PersistenceTestingUtils
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
final class InstalledWebExtensionStoreTests: XCTestCase {

    var inMemoryStore: InMemoryKeyValueStore!
    var storage: (any KeyedStoring<InstalledWebExtensionSettings>)!
    var store: InstalledWebExtensionStore!

    override func setUp() {
        super.setUp()
        inMemoryStore = InMemoryKeyValueStore()
        storage = inMemoryStore.keyedStoring()
        store = InstalledWebExtensionStore(storage: storage)
    }

    override func tearDown() {
        inMemoryStore = nil
        storage = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Test Helpers

    private func makeExtension(uniqueIdentifier: String = "test-extension",
                               filename: String = "extension.zip",
                               name: String? = "Test Extension",
                               version: String? = "1.0.0") -> InstalledWebExtension {
        InstalledWebExtension(uniqueIdentifier: uniqueIdentifier,
                           filename: filename,
                           name: name,
                           version: version)
    }

    // MARK: - Add Tests

    func testWhenExtensionIsAdded_ThenInstalledWebExtensionsContainsIt() {
        let ext = makeExtension()

        store.add(ext)

        XCTAssertTrue(store.installedExtensions.contains(ext))
    }

    func testWhenExtensionIsAdded_ThenStorageIsUpdated() {
        let ext = makeExtension()

        store.add(ext)

        XCTAssertEqual(storage.extensions, [ext])
    }

    func testWhenMultipleExtensionsAreAdded_ThenAllAreStored() {
        let ext1 = makeExtension(uniqueIdentifier: "ext1")
        let ext2 = makeExtension(uniqueIdentifier: "ext2")

        store.add(ext1)
        store.add(ext2)

        XCTAssertEqual(store.installedExtensions.count, 2)
        XCTAssertTrue(store.installedExtensions.contains(ext1))
        XCTAssertTrue(store.installedExtensions.contains(ext2))
    }

    // MARK: - Remove Tests

    func testWhenExtensionIsRemoved_ThenInstalledWebExtensionsDoesNotContainIt() {
        let ext = makeExtension()
        storage.extensions = [ext]

        store.remove(uniqueIdentifier: ext.uniqueIdentifier)

        XCTAssertFalse(store.installedExtensions.contains(ext))
    }

    func testWhenExtensionIsRemoved_ThenStorageIsUpdated() {
        let ext = makeExtension()
        storage.extensions = [ext]

        store.remove(uniqueIdentifier: ext.uniqueIdentifier)

        XCTAssertEqual(storage.extensions, [])
    }

    func testWhenOneExtensionIsRemoved_ThenOtherExtensionsRemain() {
        let ext1 = makeExtension(uniqueIdentifier: "ext1")
        let ext2 = makeExtension(uniqueIdentifier: "ext2")
        storage.extensions = [ext1, ext2]

        store.remove(uniqueIdentifier: ext1.uniqueIdentifier)

        XCTAssertEqual(store.installedExtensions, [ext2])
    }

    // MARK: - InstalledWebExtensions Property Tests

    func testThatInstalledWebExtensionsReturnsEmptyArrayWhenStorageIsEmpty() {
        storage.extensions = nil

        XCTAssertEqual(store.installedExtensions, [])
    }

    func testThatInstalledWebExtensionsReturnsStoredExtensionsFromStorage() {
        let extensions = [makeExtension(uniqueIdentifier: "ext1"), makeExtension(uniqueIdentifier: "ext2")]
        storage.extensions = extensions

        XCTAssertEqual(store.installedExtensions, extensions)
    }

    // MARK: - Lookup Tests

    func testThatInstalledWebExtensionWithUniqueIdentifierReturnsMatchingExtension() {
        let ext1 = makeExtension(uniqueIdentifier: "ext1")
        let ext2 = makeExtension(uniqueIdentifier: "ext2")
        storage.extensions = [ext1, ext2]

        let result = store.installedExtension(withUniqueIdentifier: "ext2")

        XCTAssertEqual(result, ext2)
    }

    func testThatInstalledWebExtensionWithUniqueIdentifierReturnsNilWhenNotFound() {
        let ext = makeExtension(uniqueIdentifier: "ext1")
        storage.extensions = [ext]

        let result = store.installedExtension(withUniqueIdentifier: "non-existent")

        XCTAssertNil(result)
    }

    // MARK: - Custom Storage Tests

    func testThatInitWithCustomStorageUsesProvidedStorage() {
        let customInMemoryStore = InMemoryKeyValueStore()
        let customStorage: any KeyedStoring<InstalledWebExtensionSettings> = customInMemoryStore.keyedStoring()
        let ext = makeExtension()
        customStorage.extensions = [ext]

        let customStore = InstalledWebExtensionStore(storage: customStorage)

        XCTAssertEqual(customStore.installedExtensions, [ext])
    }
}
