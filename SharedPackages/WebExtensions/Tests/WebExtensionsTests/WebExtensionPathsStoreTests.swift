//
//  WebExtensionPathsStoreTests.swift
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

@available(macOS 15.4, *)
final class WebExtensionPathsStoreTests: XCTestCase {

    var inMemoryStore: InMemoryKeyValueStore!
    var storage: (any KeyedStoring<WebExtensionPathsSettings>)!
    var store: WebExtensionPathsStore!

    override func setUp() {
        super.setUp()
        inMemoryStore = InMemoryKeyValueStore()
        storage = inMemoryStore.keyedStoring()
        store = WebExtensionPathsStore(storage: storage)
    }

    override func tearDown() {
        inMemoryStore = nil
        storage = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Add Tests

    func testWhenPathIsAdded_ThenPathsContainsIt() {
        let path = "/path/to/extension"

        store.add(path)

        XCTAssertTrue(store.paths.contains(path))
    }

    func testWhenPathIsAdded_ThenStorageIsUpdated() {
        let path = "/path/to/extension"

        store.add(path)

        XCTAssertEqual(storage.paths, [path])
    }

    func testWhenMultiplePathsAreAdded_ThenAllAreStored() {
        let path1 = "/path/to/extension1"
        let path2 = "/path/to/extension2"

        store.add(path1)
        store.add(path2)

        XCTAssertEqual(store.paths.count, 2)
        XCTAssertTrue(store.paths.contains(path1))
        XCTAssertTrue(store.paths.contains(path2))
    }

    // MARK: - Remove Tests

    func testWhenPathIsRemoved_ThenPathsDoesNotContainIt() {
        let path = "/path/to/extension"
        storage.paths = [path]

        store.remove(path)

        XCTAssertFalse(store.paths.contains(path))
    }

    func testWhenPathIsRemoved_ThenStorageIsUpdated() {
        let path = "/path/to/extension"
        storage.paths = [path]

        store.remove(path)

        XCTAssertEqual(storage.paths, [])
    }

    func testWhenOnePathIsRemoved_ThenOtherPathsRemain() {
        let path1 = "/path/to/extension1"
        let path2 = "/path/to/extension2"
        storage.paths = [path1, path2]

        store.remove(path1)

        XCTAssertEqual(store.paths, [path2])
    }

    // MARK: - Paths Property Tests

    func testThatPathsReturnsEmptyArrayWhenStorageIsEmpty() {
        storage.paths = nil

        XCTAssertEqual(store.paths, [])
    }

    func testThatPathsReturnsStoredPathsFromStorage() {
        let paths = ["/path/to/extension1", "/path/to/extension2"]
        storage.paths = paths

        XCTAssertEqual(store.paths, paths)
    }

    // MARK: - Custom Storage Tests

    func testThatInitWithCustomStorageUsesProvidedStorage() {
        let customInMemoryStore = InMemoryKeyValueStore()
        let customStorage: any KeyedStoring<WebExtensionPathsSettings> = customInMemoryStore.keyedStoring()
        customStorage.paths = ["/custom/path"]

        let customStore = WebExtensionPathsStore(storage: customStorage)

        XCTAssertEqual(customStore.paths, ["/custom/path"])
    }
}
