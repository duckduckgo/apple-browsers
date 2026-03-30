//
//  ScriptletManagerTests.swift
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
import Combine
@testable import WebExtensions

@MainActor
final class ScriptletManagerTests: XCTestCase {

    var mockConfigProvider: MockScriptletConfigProvider!
    var mockFetcher: MockScriptletFetcher!
    var mockValidator: MockScriptletValidator!
    var mockStore: MockScriptletStore!
    var manager: ScriptletManager!

    let testExtensionType: DuckDuckGoWebExtensionType = .adBlockingExtension

    override func setUp() {
        super.setUp()
        mockConfigProvider = MockScriptletConfigProvider()
        mockFetcher = MockScriptletFetcher()
        mockValidator = MockScriptletValidator()
        mockStore = MockScriptletStore()

        manager = ScriptletManager(
            configProvider: mockConfigProvider,
            fetcher: mockFetcher,
            validator: mockValidator,
            store: mockStore
        )
    }

    override func tearDown() {
        manager = nil
        mockStore = nil
        mockValidator = nil
        mockFetcher = nil
        mockConfigProvider = nil
        super.tearDown()
    }

    func testWhenStartedWithNoCacheThenAvailabilityIsNotAvailable() async {
        mockStore.cachedScriptlets = nil
        mockConfigProvider.manifests[testExtensionType] = nil

        await manager.start(for: testExtensionType)

        XCTAssertEqual(manager.availability(for: testExtensionType), .notAvailable)
        XCTAssertNil(manager.scriptlets(for: testExtensionType))
        XCTAssertFalse(manager.isReady(for: testExtensionType))
    }

    func testWhenStartedWithValidCacheThenAvailabilityIsAvailable() async {
        let scriptlets = [Scriptlet(path: "test.js", relativeCachedPath: "ext/1.0/test.js")]
        mockStore.cachedScriptlets = CachedScriptlets(version: "1.0", scriptlets: scriptlets)
        mockConfigProvider.manifests[testExtensionType] = ScriptletManifest(version: "1.0", scriptlets: [])

        await manager.start(for: testExtensionType)

        XCTAssertEqual(manager.availability(for: testExtensionType), .available(scriptlets))
        XCTAssertEqual(manager.scriptlets(for: testExtensionType)?.count, 1)
        XCTAssertTrue(manager.isReady(for: testExtensionType))
    }

    func testWhenStartedWithCacheVersionMismatchThenFetchIsTriggered() async {
        mockStore.cachedScriptlets = CachedScriptlets(
            version: "1.0",
            scriptlets: [Scriptlet(path: "old.js", relativeCachedPath: "ext/1.0/old.js")]
        )

        let descriptor = ScriptletDescriptor(
            name: "new.js",
            url: URL(string: "https://example.com/new.js")!,
            signature: "sig"
        )
        mockConfigProvider.manifests[testExtensionType] = ScriptletManifest(version: "2.0", scriptlets: [descriptor])

        let newScriptlet = Scriptlet(path: "new.js", relativeCachedPath: "ext/2.0/new.js")
        mockFetcher.fetchedScriptlets = [FetchedScriptlet(descriptor: descriptor, data: Data("new".utf8))]
        mockStore.scriptletsToReturn = [newScriptlet]

        await manager.start(for: testExtensionType)

        XCTAssertEqual(mockFetcher.fetchCallCount, 1)
        XCTAssertEqual(manager.availability(for: testExtensionType), .available([newScriptlet]))
    }

    func testWhenConfigUpdatesWithNewVersionThenScriptletsAreFetched() async {
        mockConfigProvider.manifests[testExtensionType] = ScriptletManifest(version: "1.0", scriptlets: [])
        await manager.start(for: testExtensionType)

        let descriptor = ScriptletDescriptor(
            name: "test.js",
            url: URL(string: "https://example.com/test.js")!,
            signature: "sig"
        )
        let scriptlet = Scriptlet(path: "test.js", relativeCachedPath: "ext/2.0/test.js")

        mockConfigProvider.manifests[testExtensionType] = ScriptletManifest(version: "2.0", scriptlets: [descriptor])
        mockFetcher.fetchedScriptlets = [FetchedScriptlet(descriptor: descriptor, data: Data("test".utf8))]
        mockStore.scriptletsToReturn = [scriptlet]

        mockConfigProvider.configUpdateSubject.send()

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(mockFetcher.fetchCallCount, 1)
        XCTAssertEqual(manager.availability(for: testExtensionType), .available([scriptlet]))
    }

    func testWhenFetchFailsThenAvailabilityRemainsNotAvailable() async {
        let descriptor = ScriptletDescriptor(
            name: "test.js",
            url: URL(string: "https://example.com/test.js")!,
            signature: "sig"
        )
        mockConfigProvider.manifests[testExtensionType] = ScriptletManifest(version: "1.0", scriptlets: [descriptor])
        mockFetcher.shouldThrowError = true

        await manager.start(for: testExtensionType)

        XCTAssertEqual(manager.availability(for: testExtensionType), .notAvailable)
        XCTAssertNil(manager.scriptlets(for: testExtensionType))
    }

    func testWhenFetchFailsWithExistingScriptletsThenKeepsExisting() async {
        let existingScriptlet = Scriptlet(path: "existing.js", relativeCachedPath: "ext/1.0/existing.js")
        mockStore.cachedScriptlets = CachedScriptlets(version: "1.0", scriptlets: [existingScriptlet])
        mockConfigProvider.manifests[testExtensionType] = ScriptletManifest(version: "1.0", scriptlets: [])

        await manager.start(for: testExtensionType)

        XCTAssertEqual(manager.availability(for: testExtensionType), .available([existingScriptlet]))

        let descriptor = ScriptletDescriptor(
            name: "new.js",
            url: URL(string: "https://example.com/new.js")!,
            signature: "sig"
        )
        mockConfigProvider.manifests[testExtensionType] = ScriptletManifest(version: "2.0", scriptlets: [descriptor])
        mockFetcher.shouldThrowError = true

        mockConfigProvider.configUpdateSubject.send()

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(manager.availability(for: testExtensionType), .available([existingScriptlet]))
    }

    func testWhenConfigUpdateRemovesScriptletsThenCacheIsClearedAndAvailabilityIsNotAvailable() async {
        let scriptlets = [Scriptlet(path: "test.js", relativeCachedPath: "ext/1.0/test.js")]
        mockStore.cachedScriptlets = CachedScriptlets(version: "1.0", scriptlets: scriptlets)
        mockConfigProvider.manifests[testExtensionType] = ScriptletManifest(version: "1.0", scriptlets: [])

        await manager.start(for: testExtensionType)

        XCTAssertEqual(manager.availability(for: testExtensionType), .available(scriptlets))

        mockConfigProvider.manifests[testExtensionType] = nil
        mockConfigProvider.configUpdateSubject.send()

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(manager.availability(for: testExtensionType), .notAvailable)
        XCTAssertNil(manager.scriptlets(for: testExtensionType))
        XCTAssertEqual(mockStore.clearCacheCallCount, 1)
        XCTAssertEqual(mockStore.clearCacheExtensionType, testExtensionType)
    }

    func testWhenConfigUpdateRemovesScriptletsThenInstalledVersionIsPreserved() async {
        let scriptlets = [Scriptlet(path: "test.js", relativeCachedPath: "ext/1.0/test.js")]
        mockStore.cachedScriptlets = CachedScriptlets(version: "1.0", scriptlets: scriptlets)
        mockStore.setInstalledVersion("1.0", for: testExtensionType)
        mockConfigProvider.manifests[testExtensionType] = ScriptletManifest(version: "1.0", scriptlets: [])

        await manager.start(for: testExtensionType)

        XCTAssertEqual(manager.availability(for: testExtensionType), .available(scriptlets))

        mockConfigProvider.manifests[testExtensionType] = nil
        mockConfigProvider.configUpdateSubject.send()

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(manager.availability(for: testExtensionType), .notAvailable)
        XCTAssertEqual(mockStore.installedVersion(for: testExtensionType), "1.0")
    }

    func testWhenManifestAlreadyAbsentThenNoClearIsPerformed() async {
        mockStore.cachedScriptlets = nil
        mockConfigProvider.manifests[testExtensionType] = nil

        await manager.start(for: testExtensionType)

        XCTAssertEqual(manager.availability(for: testExtensionType), .notAvailable)
        XCTAssertEqual(mockStore.clearCacheCallCount, 0)
    }
}
