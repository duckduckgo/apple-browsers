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

@available(macOS 15.4, iOS 18.4, *)
final class ScriptletStoreTests: XCTestCase {

    var tempDirectory: URL!
    var store: ScriptletStore!
    var defaults: UserDefaults!
    var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        defaultsSuiteName = "test.scriptlets.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!

        store = ScriptletStore(
            baseDirectory: tempDirectory,
            defaults: defaults
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        store = nil
        defaults = nil
        defaultsSuiteName = nil
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
        XCTAssertTrue(cached?.scriptlets.contains(where: { $0.path == "scriptlets/test1.js" }) ?? false)
        XCTAssertTrue(cached?.scriptlets.contains(where: { $0.path == "scriptlets/test2.js" }) ?? false)
    }

    func testWhenScriptletsSavedThenFilesPreserveOriginalPathStructure() throws {
        try store.save(
            [makeFetchedScriptlet(name: "isolated/ublock-filters.js", content: "content")],
            version: "1.0",
            for: .adBlockingExtension)

        let expectedFile = tempDirectory
            .appendingPathComponent(DuckDuckGoWebExtensionType.adBlockingExtension.rawValue)
            .appendingPathComponent("1.0")
            .appendingPathComponent("isolated/ublock-filters.js")

        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFile.path))
    }

    func testWhenScriptletsSavedThenRelativeCachedPathIsCorrect() throws {
        let scriptlets = try store.save(
            [makeFetchedScriptlet(name: "isolated/ublock-filters.js", content: "content")],
            version: "1.0",
            for: .adBlockingExtension)

        let expectedRelativePath = "\(DuckDuckGoWebExtensionType.adBlockingExtension.rawValue)/1.0/isolated/ublock-filters.js"
        XCTAssertEqual(scriptlets.first?.relativeCachedPath, expectedRelativePath)
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
        XCTAssertEqual(cached?.scriptlets.first?.path, "scriptlets/new.js")
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
        XCTAssertEqual(cached1?.scriptlets.first?.path, "scriptlets/ext1.js")

        XCTAssertEqual(cached2?.version, "2.0")
        XCTAssertEqual(cached2?.scriptlets.first?.path, "scriptlets/ext2.js")
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

    func testWhenCacheRootDirectoryAccessedThenReturnsBaseDirectory() {
        XCTAssertEqual(store.cacheRootDirectory, tempDirectory)
    }

    // MARK: - Installed Version Tracking

    func testWhenNoInstalledVersionThenReturnsNil() {
        XCTAssertNil(store.installedVersion(for: .adBlockingExtension))
    }

    func testWhenInstalledVersionSetThenCanBeRetrieved() {
        store.setInstalledVersion("1.0", for: .adBlockingExtension)

        XCTAssertEqual(store.installedVersion(for: .adBlockingExtension), "1.0")
    }

    func testWhenInstalledVersionClearedThenReturnsNil() {
        store.setInstalledVersion("1.0", for: .adBlockingExtension)
        store.clearInstalledVersion(for: .adBlockingExtension)

        XCTAssertNil(store.installedVersion(for: .adBlockingExtension))
    }

    func testWhenClearCalledThenInstalledVersionIsAlsoCleared() throws {
        try store.save(
            [makeFetchedScriptlet(name: "scriptlets/test.js", content: "test")],
            version: "1.0",
            for: .adBlockingExtension)
        store.setInstalledVersion("1.0", for: .adBlockingExtension)

        store.clear(for: .adBlockingExtension)

        XCTAssertNil(store.installedVersion(for: .adBlockingExtension))
    }

    func testWhenClearAllCalledThenAllInstalledVersionsAreCleared() {
        store.setInstalledVersion("1.0", for: .adBlockingExtension)
        store.setInstalledVersion("2.0", for: .embedded)

        store.clearAll()

        XCTAssertNil(store.installedVersion(for: .adBlockingExtension))
        XCTAssertNil(store.installedVersion(for: .embedded))
    }

    func testWhenInstalledVersionSetForMultipleExtensionsThenTrackedIndependently() {
        store.setInstalledVersion("1.0", for: .adBlockingExtension)
        store.setInstalledVersion("2.0", for: .embedded)

        XCTAssertEqual(store.installedVersion(for: .adBlockingExtension), "1.0")
        XCTAssertEqual(store.installedVersion(for: .embedded), "2.0")

        store.clearInstalledVersion(for: .adBlockingExtension)

        XCTAssertNil(store.installedVersion(for: .adBlockingExtension))
        XCTAssertEqual(store.installedVersion(for: .embedded), "2.0")
    }

    func testWhenClearCacheCalledThenCachedDataIsRemovedButInstalledVersionIsPreserved() throws {
        try store.save(
            [makeFetchedScriptlet(name: "scriptlets/test.js", content: "test")],
            version: "1.0",
            for: .adBlockingExtension)
        store.setInstalledVersion("1.0", for: .adBlockingExtension)

        store.clearCache(for: .adBlockingExtension)

        XCTAssertNil(store.loadCached(for: .adBlockingExtension))
        XCTAssertNil(store.cachedVersion(for: .adBlockingExtension))
        XCTAssertEqual(store.installedVersion(for: .adBlockingExtension), "1.0")
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
