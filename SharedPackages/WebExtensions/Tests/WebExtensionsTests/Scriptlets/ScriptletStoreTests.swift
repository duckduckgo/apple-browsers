//
//  ScriptletStoreTests.swift
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

import XCTest
@testable import WebExtensions

final class ScriptletStoreTests: XCTestCase {

    var tempDirectory: URL!
    var store: ScriptletStore!
    var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        defaults = UserDefaults(suiteName: "test.scriptlets.\(UUID().uuidString)")!

        store = ScriptletStore(
            baseDirectory: tempDirectory,
            defaults: defaults
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        defaults.removePersistentDomain(forName: defaults.suiteName!)
        store = nil
        defaults = nil
        tempDirectory = nil
        super.tearDown()
    }

    func testWhenNoDataSavedThenLoadCachedReturnsNil() {
        let cached = store.loadCached()

        XCTAssertNil(cached)
    }

    func testWhenScriptletsSavedThenCanBeLoaded() throws {
        let scriptlets = [
            Scriptlet(name: "test1", content: Data("content1".utf8)),
            Scriptlet(name: "test2", content: Data("content2".utf8))
        ]

        try store.save(scriptlets, version: "1.0")

        let cached = store.loadCached()

        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.version, "1.0")
        XCTAssertEqual(cached?.scriptlets.count, 2)
        XCTAssertTrue(cached?.scriptlets.contains(where: { $0.name == "test1" }) ?? false)
        XCTAssertTrue(cached?.scriptlets.contains(where: { $0.name == "test2" }) ?? false)
    }

    func testWhenSavingNewVersionThenOverwritesOldVersion() throws {
        let oldScriptlets = [Scriptlet(name: "old", content: Data("old".utf8))]
        try store.save(oldScriptlets, version: "1.0")

        let newScriptlets = [Scriptlet(name: "new", content: Data("new".utf8))]
        try store.save(newScriptlets, version: "2.0")

        let cached = store.loadCached()

        XCTAssertEqual(cached?.version, "2.0")
        XCTAssertEqual(cached?.scriptlets.count, 1)
        XCTAssertEqual(cached?.scriptlets.first?.name, "new")
    }

    func testWhenClearCalledThenRemovesAllData() throws {
        let scriptlets = [Scriptlet(name: "test", content: Data("test".utf8))]
        try store.save(scriptlets, version: "1.0")

        store.clear()

        let cached = store.loadCached()
        XCTAssertNil(cached)
    }
}
