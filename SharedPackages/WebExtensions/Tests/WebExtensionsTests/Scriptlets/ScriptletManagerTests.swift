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

@available(macOS 15.4, iOS 18.4, *)
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
        mockStore.cachedScriptlets = CachedScriptlets(version: "1.0", scriptlets: [])
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

        let fetchExpectation = expectation(description: "Fetch triggered by config update")
        mockFetcher.onFetch = { fetchExpectation.fulfill() }

        mockConfigProvider.configUpdateSubject.send()

        await fulfillment(of: [fetchExpectation], timeout: 2.0)

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

        let fetchExpectation = expectation(description: "Fetch attempted")
        mockFetcher.onFetch = { fetchExpectation.fulfill() }

        mockConfigProvider.configUpdateSubject.send()

        await fulfillment(of: [fetchExpectation], timeout: 2.0)

        XCTAssertEqual(manager.availability(for: testExtensionType), .available([existingScriptlet]))
    }

    func testWhenConfigUpdateRemovesScriptletsThenCacheIsClearedAndAvailabilityIsNotAvailable() async {
        let scriptlets = [Scriptlet(path: "test.js", relativeCachedPath: "ext/1.0/test.js")]
        mockStore.cachedScriptlets = CachedScriptlets(version: "1.0", scriptlets: scriptlets)
        mockConfigProvider.manifests[testExtensionType] = ScriptletManifest(version: "1.0", scriptlets: [])

        await manager.start(for: testExtensionType)

        XCTAssertEqual(manager.availability(for: testExtensionType), .available(scriptlets))

        let availabilityExpectation = expectation(description: "Availability becomes notAvailable")
        let cancellable = manager.availabilityPublisher(for: testExtensionType)
            .dropFirst()
            .filter { $0 == .notAvailable }
            .first()
            .sink { _ in availabilityExpectation.fulfill() }

        mockConfigProvider.manifests[testExtensionType] = nil
        mockConfigProvider.configUpdateSubject.send()

        await fulfillment(of: [availabilityExpectation], timeout: 2.0)
        cancellable.cancel()

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

        let availabilityExpectation = expectation(description: "Availability becomes notAvailable")
        let cancellable = manager.availabilityPublisher(for: testExtensionType)
            .dropFirst()
            .filter { $0 == .notAvailable }
            .first()
            .sink { _ in availabilityExpectation.fulfill() }

        mockConfigProvider.manifests[testExtensionType] = nil
        mockConfigProvider.configUpdateSubject.send()

        await fulfillment(of: [availabilityExpectation], timeout: 2.0)
        cancellable.cancel()

        XCTAssertEqual(mockStore.installedVersion(for: testExtensionType), "1.0")
    }

    func testWhenManifestAlreadyAbsentThenNoClearIsPerformed() async {
        mockStore.cachedScriptlets = nil
        mockConfigProvider.manifests[testExtensionType] = nil

        await manager.start(for: testExtensionType)

        XCTAssertEqual(manager.availability(for: testExtensionType), .notAvailable)
        XCTAssertEqual(mockStore.clearCacheCallCount, 0)
    }

    func testWhenStartedThenScriptletVersionDelegatesToStore() async {
        let scriptlets = [Scriptlet(path: "test.js", relativeCachedPath: "ext/1.0/test.js")]
        mockStore.cachedScriptlets = CachedScriptlets(version: "1.0", scriptlets: scriptlets)
        mockConfigProvider.manifests[testExtensionType] = ScriptletManifest(version: "1.0", scriptlets: [])

        await manager.start(for: testExtensionType)

        XCTAssertEqual(manager.scriptletVersion(for: testExtensionType), "1.0")
    }

    func testWhenStoppedThenExtensionTypeIsRemovedFromActive() async {
        mockStore.cachedScriptlets = CachedScriptlets(version: "1.0", scriptlets: [])
        mockConfigProvider.manifests[testExtensionType] = ScriptletManifest(version: "1.0", scriptlets: [])
        await manager.start(for: testExtensionType)

        manager.stop(for: testExtensionType)

        let descriptor = ScriptletDescriptor(
            name: "test.js",
            url: URL(string: "https://example.com/test.js")!,
            signature: "sig"
        )
        mockConfigProvider.manifests[testExtensionType] = ScriptletManifest(version: "2.0", scriptlets: [descriptor])
        mockFetcher.fetchedScriptlets = [FetchedScriptlet(descriptor: descriptor, data: Data("test".utf8))]

        let fetchExpectation = expectation(description: "Fetch should not be called")
        fetchExpectation.isInverted = true
        mockFetcher.onFetch = { fetchExpectation.fulfill() }

        mockConfigProvider.configUpdateSubject.send()

        await fulfillment(of: [fetchExpectation], timeout: 1.0)

        XCTAssertEqual(mockFetcher.fetchCallCount, 0)
    }

    func testWhenClearCachedScriptletsCalledThenStoreIsClearedAndAvailabilitiesReset() async {
        let scriptlets = [Scriptlet(path: "test.js", relativeCachedPath: "ext/1.0/test.js")]
        mockStore.cachedScriptlets = CachedScriptlets(version: "1.0", scriptlets: scriptlets)
        mockConfigProvider.manifests[testExtensionType] = ScriptletManifest(version: "1.0", scriptlets: [])

        await manager.start(for: testExtensionType)

        XCTAssertEqual(manager.availability(for: testExtensionType), .available(scriptlets))

        manager.clearCachedScriptlets()

        XCTAssertEqual(mockStore.clearAllCallCount, 1)
        XCTAssertEqual(manager.availability(for: testExtensionType), .notAvailable)
    }

    func testWhenValidatorFailsThenAvailabilityRemainsNotAvailable() async {
        let descriptor = ScriptletDescriptor(
            name: "test.js",
            url: URL(string: "https://example.com/test.js")!,
            signature: "sig"
        )
        mockConfigProvider.manifests[testExtensionType] = ScriptletManifest(version: "1.0", scriptlets: [descriptor])
        mockFetcher.fetchedScriptlets = [FetchedScriptlet(descriptor: descriptor, data: Data("test".utf8))]
        mockValidator.shouldThrowError = true

        await manager.start(for: testExtensionType)

        XCTAssertEqual(manager.availability(for: testExtensionType), .notAvailable)
        XCTAssertNil(mockStore.savedFetched)
    }

    func testWhenValidatorFailsWithExistingScriptletsThenKeepsExisting() async {
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
        mockFetcher.fetchedScriptlets = [FetchedScriptlet(descriptor: descriptor, data: Data("new".utf8))]
        mockValidator.shouldThrowError = true

        let fetchExpectation = expectation(description: "Fetch attempted")
        mockFetcher.onFetch = { fetchExpectation.fulfill() }

        mockConfigProvider.configUpdateSubject.send()

        await fulfillment(of: [fetchExpectation], timeout: 2.0)

        XCTAssertEqual(manager.availability(for: testExtensionType), .available([existingScriptlet]))
    }

    func testWhenCachedVersionMatchesManifestThenNoFetchIsTriggered() async {
        let scriptlets = [Scriptlet(path: "test.js", relativeCachedPath: "ext/1.0/test.js")]
        mockStore.cachedScriptlets = CachedScriptlets(version: "1.0", scriptlets: scriptlets)
        mockConfigProvider.manifests[testExtensionType] = ScriptletManifest(version: "1.0", scriptlets: [])

        await manager.start(for: testExtensionType)

        XCTAssertEqual(mockFetcher.fetchCallCount, 0)
        XCTAssertEqual(manager.availability(for: testExtensionType), .available(scriptlets))
    }

    func testAvailabilityPublisherEmitsUpdates() async {
        let scriptlets = [Scriptlet(path: "test.js", relativeCachedPath: "ext/1.0/test.js")]

        let availableExpectation = expectation(description: "Publisher emits available")
        var receivedNotAvailable = false

        let cancellable = manager.availabilityPublisher(for: testExtensionType)
            .sink { availability in
                if availability == .notAvailable {
                    receivedNotAvailable = true
                }
                if availability == .available(scriptlets) {
                    availableExpectation.fulfill()
                }
            }

        mockStore.cachedScriptlets = CachedScriptlets(version: "1.0", scriptlets: scriptlets)
        mockConfigProvider.manifests[testExtensionType] = ScriptletManifest(version: "1.0", scriptlets: [])

        await manager.start(for: testExtensionType)

        await fulfillment(of: [availableExpectation], timeout: 2.0)

        XCTAssertTrue(receivedNotAvailable)

        cancellable.cancel()
    }
}
