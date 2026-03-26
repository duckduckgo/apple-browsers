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

    override func setUp() {
        super.setUp()
        mockConfigProvider = MockScriptletConfigProvider()
        mockFetcher = MockScriptletFetcher()
        mockValidator = MockScriptletValidator()
        mockStore = MockScriptletStore()

        manager = ScriptletManager(
            extensionType: .adBlockingExtension,
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
        mockConfigProvider.manifest = nil

        await manager.start()

        XCTAssertEqual(manager.availability, .notAvailable)
        XCTAssertNil(manager.scriptlets)
        XCTAssertFalse(manager.isReady)
    }

    func testWhenStartedWithValidCacheThenAvailabilityIsAvailable() async {
        let scriptlets = [Scriptlet(name: "test", content: Data("test".utf8))]
        mockStore.cachedScriptlets = CachedScriptlets(version: "1.0", scriptlets: scriptlets)
        mockConfigProvider.manifest = ScriptletManifest(version: "1.0", scriptlets: [])

        await manager.start()

        XCTAssertEqual(manager.availability, .available(scriptlets))
        XCTAssertEqual(manager.scriptlets?.count, 1)
        XCTAssertTrue(manager.isReady)
    }

    func testWhenStartedWithCacheVersionMismatchThenFetchIsTriggered() async {
        mockStore.cachedScriptlets = CachedScriptlets(
            version: "1.0",
            scriptlets: [Scriptlet(name: "old", content: Data("old".utf8))]
        )

        let descriptor = ScriptletDescriptor(
            name: "new",
            url: URL(string: "https://example.com/new.js")!,
            signature: "sig"
        )
        mockConfigProvider.manifest = ScriptletManifest(version: "2.0", scriptlets: [descriptor])

        let newScriptlet = Scriptlet(name: "new", content: Data("new".utf8))
        mockFetcher.fetchedScriptlets = [FetchedScriptlet(descriptor: descriptor, data: Data("new".utf8))]
        mockValidator.validatedScriptlets = [newScriptlet]

        await manager.start()

        XCTAssertEqual(mockFetcher.fetchCallCount, 1)
        XCTAssertEqual(manager.availability, .available([newScriptlet]))
    }

    func testWhenConfigUpdatesWithNewVersionThenScriptletsAreFetched() async {
        mockConfigProvider.manifest = ScriptletManifest(version: "1.0", scriptlets: [])
        await manager.start()

        let descriptor = ScriptletDescriptor(
            name: "test",
            url: URL(string: "https://example.com/test.js")!,
            signature: "sig"
        )
        let scriptlet = Scriptlet(name: "test", content: Data("test".utf8))

        mockConfigProvider.manifest = ScriptletManifest(version: "2.0", scriptlets: [descriptor])
        mockFetcher.fetchedScriptlets = [FetchedScriptlet(descriptor: descriptor, data: Data("test".utf8))]
        mockValidator.validatedScriptlets = [scriptlet]

        mockConfigProvider.configUpdateSubject.send()

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(mockFetcher.fetchCallCount, 1)
        XCTAssertEqual(manager.availability, .available([scriptlet]))
    }

    func testWhenFetchFailsThenAvailabilityRemainsNotAvailable() async {
        let descriptor = ScriptletDescriptor(
            name: "test",
            url: URL(string: "https://example.com/test.js")!,
            signature: "sig"
        )
        mockConfigProvider.manifest = ScriptletManifest(version: "1.0", scriptlets: [descriptor])
        mockFetcher.shouldThrowError = true

        await manager.start()

        XCTAssertEqual(manager.availability, .notAvailable)
        XCTAssertNil(manager.scriptlets)
    }

    func testWhenFetchFailsWithExistingScriptletsThenKeepsExisting() async {
        let existingScriptlet = Scriptlet(name: "existing", content: Data("existing".utf8))
        mockStore.cachedScriptlets = CachedScriptlets(version: "1.0", scriptlets: [existingScriptlet])
        mockConfigProvider.manifest = ScriptletManifest(version: "1.0", scriptlets: [])

        await manager.start()

        XCTAssertEqual(manager.availability, .available([existingScriptlet]))

        let descriptor = ScriptletDescriptor(
            name: "new",
            url: URL(string: "https://example.com/new.js")!,
            signature: "sig"
        )
        mockConfigProvider.manifest = ScriptletManifest(version: "2.0", scriptlets: [descriptor])
        mockFetcher.shouldThrowError = true

        mockConfigProvider.configUpdateSubject.send()

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(manager.availability, .available([existingScriptlet]))
    }
}
