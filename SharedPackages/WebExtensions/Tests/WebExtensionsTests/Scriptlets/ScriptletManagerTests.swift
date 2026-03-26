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
        let scriptlets = [Scriptlet(name: "test", targetPath: "test")]
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
            scriptlets: [Scriptlet(name: "old", targetPath: "old")]
        )

        let descriptor = ScriptletDescriptor(
            name: "new",
            url: URL(string: "https://example.com/new.js")!,
            signature: "sig"
        )
        mockConfigProvider.manifests[testExtensionType] = ScriptletManifest(version: "2.0", scriptlets: [descriptor])

        let newScriptlet = Scriptlet(name: "new", targetPath: "new")
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
            name: "test",
            url: URL(string: "https://example.com/test.js")!,
            signature: "sig"
        )
        let scriptlet = Scriptlet(name: "test", targetPath: "test")

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
            name: "test",
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
        let existingScriptlet = Scriptlet(name: "existing", targetPath: "existing")
        mockStore.cachedScriptlets = CachedScriptlets(version: "1.0", scriptlets: [existingScriptlet])
        mockConfigProvider.manifests[testExtensionType] = ScriptletManifest(version: "1.0", scriptlets: [])

        await manager.start(for: testExtensionType)

        XCTAssertEqual(manager.availability(for: testExtensionType), .available([existingScriptlet]))

        let descriptor = ScriptletDescriptor(
            name: "new",
            url: URL(string: "https://example.com/new.js")!,
            signature: "sig"
        )
        mockConfigProvider.manifests[testExtensionType] = ScriptletManifest(version: "2.0", scriptlets: [descriptor])
        mockFetcher.shouldThrowError = true

        mockConfigProvider.configUpdateSubject.send()

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(manager.availability(for: testExtensionType), .available([existingScriptlet]))
    }
}
