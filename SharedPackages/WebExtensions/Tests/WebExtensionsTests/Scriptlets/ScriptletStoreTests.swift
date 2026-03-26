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
        let cached = store.loadCached(for: .adBlockingExtension)

        XCTAssertNil(cached)
    }

    func testWhenScriptletsSavedThenCanBeLoaded() throws {
        let scriptlets = [
            Scriptlet(name: "scriptlets/test1.js", content: Data("content1".utf8)),
            Scriptlet(name: "scriptlets/test2.js", content: Data("content2".utf8))
        ]
        let targetPaths = [
            "scriptlets/test1.js": "scriptlets/test1.js",
            "scriptlets/test2.js": "scriptlets/test2.js"
        ]

        try store.save(scriptlets, version: "1.0", for: .adBlockingExtension, withTargetPaths: targetPaths)

        let cached = store.loadCached(for: .adBlockingExtension)

        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.version, "1.0")
        XCTAssertEqual(cached?.scriptlets.count, 2)
        XCTAssertTrue(cached?.scriptlets.contains(where: { $0.name == "scriptlets/test1.js" }) ?? false)
        XCTAssertTrue(cached?.scriptlets.contains(where: { $0.name == "scriptlets/test2.js" }) ?? false)
    }

    func testWhenSavingNewVersionThenOverwritesOldVersion() throws {
        let oldScriptlets = [Scriptlet(name: "scriptlets/old.js", content: Data("old".utf8))]
        let oldTargetPaths = ["scriptlets/old.js": "scriptlets/old.js"]
        try store.save(oldScriptlets, version: "1.0", for: .adBlockingExtension, withTargetPaths: oldTargetPaths)

        let newScriptlets = [Scriptlet(name: "scriptlets/new.js", content: Data("new".utf8))]
        let newTargetPaths = ["scriptlets/new.js": "scriptlets/new.js"]
        try store.save(newScriptlets, version: "2.0", for: .adBlockingExtension, withTargetPaths: newTargetPaths)

        let cached = store.loadCached(for: .adBlockingExtension)

        XCTAssertEqual(cached?.version, "2.0")
        XCTAssertEqual(cached?.scriptlets.count, 1)
        XCTAssertEqual(cached?.scriptlets.first?.name, "scriptlets/new.js")
    }

    func testWhenClearCalledThenRemovesAllData() throws {
        let scriptlets = [Scriptlet(name: "scriptlets/test.js", content: Data("test".utf8))]
        let targetPaths = ["scriptlets/test.js": "scriptlets/test.js"]
        try store.save(scriptlets, version: "1.0", for: .adBlockingExtension, withTargetPaths: targetPaths)

        store.clear(for: .adBlockingExtension)

        let cached = store.loadCached(for: .adBlockingExtension)
        XCTAssertNil(cached)
    }

    func testWhenMultipleExtensionsSavedThenEachCanBeLoadedIndependently() throws {
        let scriptlets1 = [Scriptlet(name: "scriptlets/ext1.js", content: Data("ext1".utf8))]
        let targetPaths1 = ["scriptlets/ext1.js": "scriptlets/ext1.js"]
        try store.save(scriptlets1, version: "1.0", for: .adBlockingExtension, withTargetPaths: targetPaths1)

        let scriptlets2 = [Scriptlet(name: "scriptlets/ext2.js", content: Data("ext2".utf8))]
        let targetPaths2 = ["scriptlets/ext2.js": "scriptlets/ext2.js"]
        try store.save(scriptlets2, version: "2.0", for: .embedded, withTargetPaths: targetPaths2)

        let cached1 = store.loadCached(for: .adBlockingExtension)
        let cached2 = store.loadCached(for: .embedded)

        XCTAssertEqual(cached1?.version, "1.0")
        XCTAssertEqual(cached1?.scriptlets.first?.name, "scriptlets/ext1.js")

        XCTAssertEqual(cached2?.version, "2.0")
        XCTAssertEqual(cached2?.scriptlets.first?.name, "scriptlets/ext2.js")
    }

    func testWhenClearingOneExtensionThenOtherExtensionRemainsIntact() throws {
        let scriptlets1 = [Scriptlet(name: "scriptlets/ext1.js", content: Data("ext1".utf8))]
        let targetPaths1 = ["scriptlets/ext1.js": "scriptlets/ext1.js"]
        try store.save(scriptlets1, version: "1.0", for: .adBlockingExtension, withTargetPaths: targetPaths1)

        let scriptlets2 = [Scriptlet(name: "scriptlets/ext2.js", content: Data("ext2".utf8))]
        let targetPaths2 = ["scriptlets/ext2.js": "scriptlets/ext2.js"]
        try store.save(scriptlets2, version: "2.0", for: .embedded, withTargetPaths: targetPaths2)

        store.clear(for: .adBlockingExtension)

        let cached1 = store.loadCached(for: .adBlockingExtension)
        let cached2 = store.loadCached(for: .embedded)

        XCTAssertNil(cached1)
        XCTAssertNotNil(cached2)
        XCTAssertEqual(cached2?.version, "2.0")
    }

    func testWhenTargetPathsProvidedThenMetadataStoresCorrectPaths() throws {
        let scriptlets = [
            Scriptlet(name: "scriptlets/isolated/ublock-filters.js", content: Data("content".utf8))
        ]
        let targetPaths = [
            "scriptlets/isolated/ublock-filters.js": "scriptlets/isolated/ublock-filters.js"
        ]

        try store.save(scriptlets, version: "1.0", for: .adBlockingExtension, withTargetPaths: targetPaths)

        let cached = store.loadCached(for: .adBlockingExtension)

        XCTAssertEqual(cached?.scriptlets.first?.name, "scriptlets/isolated/ublock-filters.js")
    }
}
