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
        let fetched = [
            makeFetchedScriptlet(name: "scriptlets/test1.js", content: "content1"),
            makeFetchedScriptlet(name: "scriptlets/test2.js", content: "content2")
        ]

        try store.save(fetched, version: "1.0", for: .adBlockingExtension)

        let cached = store.loadCached(for: .adBlockingExtension)

        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.version, "1.0")
        XCTAssertEqual(cached?.scriptlets.count, 2)
        XCTAssertTrue(cached?.scriptlets.contains(where: { $0.targetPath == "scriptlets/test1.js" }) ?? false)
        XCTAssertTrue(cached?.scriptlets.contains(where: { $0.targetPath == "scriptlets/test2.js" }) ?? false)
    }

    func testWhenSavingNewVersionThenOverwritesOldVersion() throws {
        try store.save(
            [makeFetchedScriptlet(name: "scriptlets/old.js", content: "old")],
            version: "1.0",
            for: .adBlockingExtension)

        try store.save(
            [makeFetchedScriptlet(name: "scriptlets/new.js", content: "new")],
            version: "2.0",
            for: .adBlockingExtension)

        let cached = store.loadCached(for: .adBlockingExtension)

        XCTAssertEqual(cached?.version, "2.0")
        XCTAssertEqual(cached?.scriptlets.count, 1)
        XCTAssertEqual(cached?.scriptlets.first?.targetPath, "scriptlets/new.js")
    }

    func testWhenClearCalledThenRemovesAllData() throws {
        try store.save(
            [makeFetchedScriptlet(name: "scriptlets/test.js", content: "test")],
            version: "1.0",
            for: .adBlockingExtension)

        store.clear(for: .adBlockingExtension)

        let cached = store.loadCached(for: .adBlockingExtension)
        XCTAssertNil(cached)
    }

    func testWhenMultipleExtensionsSavedThenEachCanBeLoadedIndependently() throws {
        try store.save(
            [makeFetchedScriptlet(name: "scriptlets/ext1.js", content: "ext1")],
            version: "1.0",
            for: .adBlockingExtension)

        try store.save(
            [makeFetchedScriptlet(name: "scriptlets/ext2.js", content: "ext2")],
            version: "2.0",
            for: .embedded)

        let cached1 = store.loadCached(for: .adBlockingExtension)
        let cached2 = store.loadCached(for: .embedded)

        XCTAssertEqual(cached1?.version, "1.0")
        XCTAssertEqual(cached1?.scriptlets.first?.targetPath, "scriptlets/ext1.js")

        XCTAssertEqual(cached2?.version, "2.0")
        XCTAssertEqual(cached2?.scriptlets.first?.targetPath, "scriptlets/ext2.js")
    }

    func testWhenClearingOneExtensionThenOtherExtensionRemainsIntact() throws {
        try store.save(
            [makeFetchedScriptlet(name: "scriptlets/ext1.js", content: "ext1")],
            version: "1.0",
            for: .adBlockingExtension)

        try store.save(
            [makeFetchedScriptlet(name: "scriptlets/ext2.js", content: "ext2")],
            version: "2.0",
            for: .embedded)

        store.clear(for: .adBlockingExtension)

        let cached1 = store.loadCached(for: .adBlockingExtension)
        let cached2 = store.loadCached(for: .embedded)

        XCTAssertNil(cached1)
        XCTAssertNotNil(cached2)
        XCTAssertEqual(cached2?.version, "2.0")
    }

    func testWhenTargetPathsProvidedThenMetadataStoresCorrectPaths() throws {
        try store.save(
            [makeFetchedScriptlet(name: "scriptlets/isolated/ublock-filters.js", content: "content")],
            version: "1.0",
            for: .adBlockingExtension)

        let cached = store.loadCached(for: .adBlockingExtension)

        XCTAssertEqual(cached?.scriptlets.first?.targetPath, "scriptlets/isolated/ublock-filters.js")
    }

    // MARK: - Helpers

    private func makeFetchedScriptlet(name: String, content: String) -> FetchedScriptlet {
        let descriptor = ScriptletDescriptor(
            name: name,
            url: URL(string: "https://example.com/\(name)")!,
            signature: "sig")
        return FetchedScriptlet(descriptor: descriptor, data: Data(content.utf8))
    }
}
