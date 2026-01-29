//
//  WebExtensionManagerTests.swift
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
@testable import WebExtensions

@available(macOS 15.4, *)
final class WebExtensionManagerTests: XCTestCase {

    var pathsStoringMock: WebExtensionPathsStoringMock!
    var webExtensionLoadingMock: WebExtensionLoadingMock!
    var windowTabProviderMock: WebExtensionWindowTabProvidingMock!
    var eventsListenerMock: WebExtensionEventsListenerMock!
    var lifecycleDelegateMock: WebExtensionLifecycleDelegateMock!
    var configurationMock: WebExtensionConfigurationProvidingMock!

    override func setUp() {
        super.setUp()

        pathsStoringMock = WebExtensionPathsStoringMock()
        webExtensionLoadingMock = WebExtensionLoadingMock()
        windowTabProviderMock = WebExtensionWindowTabProvidingMock()
        eventsListenerMock = WebExtensionEventsListenerMock()
        lifecycleDelegateMock = WebExtensionLifecycleDelegateMock()
        configurationMock = WebExtensionConfigurationProvidingMock()
    }

    override func tearDown() {
        webExtensionLoadingMock?.cleanupTestExtensions()
        pathsStoringMock = nil
        webExtensionLoadingMock = nil
        windowTabProviderMock = nil
        eventsListenerMock = nil
        lifecycleDelegateMock = nil
        configurationMock = nil

        super.tearDown()
    }

    // MARK: - Helper

    @MainActor
    private func makeManager() -> WebExtensionManager {
        let manager = WebExtensionManager(
            configuration: configurationMock,
            windowTabProvider: windowTabProviderMock,
            installationStore: pathsStoringMock,
            loader: webExtensionLoadingMock,
            eventsListener: eventsListenerMock
        )
        manager.lifecycleDelegate = lifecycleDelegateMock
        return manager
    }

    // MARK: - Install Extension Tests

    @MainActor
    func testWhenExtensionIsInstalled_ThenPathIsStored() async {
        let manager = makeManager()
        let path = "/path/to/extension"

        await manager.installExtension(path: path)

        XCTAssertTrue(pathsStoringMock.addCalled)
        XCTAssertEqual(pathsStoringMock.addedPath, path)
    }

    @MainActor
    func testWhenExtensionIsInstalled_ThenLoaderIsCalled() async {
        let manager = makeManager()
        let path = "/path/to/extension"

        await manager.installExtension(path: path)

        XCTAssertTrue(webExtensionLoadingMock.loadWebExtensionCalled)
        XCTAssertTrue(webExtensionLoadingMock.loadedPaths.contains(path))
    }

    @MainActor
    func testWhenExtensionIsInstalled_ThenLifecycleDelegateDidUpdateIsCalled() async {
        let manager = makeManager()

        await manager.installExtension(path: "/path/to/extension")

        XCTAssertTrue(lifecycleDelegateMock.didUpdateExtensionsCalled)
    }

    // MARK: - Uninstall Extension Tests

    @MainActor
    func testWhenExtensionIsUninstalled_ThenPathIsRemovedFromStore() throws {
        let manager = makeManager()
        let path = "/path/to/extension"
        pathsStoringMock.paths = [path]

        try manager.uninstallExtension(path: path)

        XCTAssertTrue(pathsStoringMock.removeCalled)
        XCTAssertEqual(pathsStoringMock.removedPath, path)
    }

    @MainActor
    func testWhenExtensionIsUninstalled_ThenLoaderUnloadIsCalled() throws {
        let manager = makeManager()
        let path = "/path/to/extension"
        pathsStoringMock.paths = [path]

        try manager.uninstallExtension(path: path)

        XCTAssertTrue(webExtensionLoadingMock.unloadExtensionCalled)
        XCTAssertEqual(webExtensionLoadingMock.unloadedPath, path)
    }

    @MainActor
    func testWhenUninstallFails_ThenErrorIsThrown() {
        let manager = makeManager()
        let path = "/path/to/extension"
        pathsStoringMock.paths = [path]

        let expectedError = NSError(domain: "test", code: 1)
        webExtensionLoadingMock.mockUnloadError = expectedError

        XCTAssertThrowsError(try manager.uninstallExtension(path: path)) { error in
            if case WebExtensionError.failedToUnloadWebExtension = error {
                // Expected error type
            } else {
                XCTFail("Expected WebExtensionError.failedToUnloadWebExtension, got \(error)")
            }
        }
    }

    @MainActor
    func testWhenExtensionIsUninstalled_ThenLifecycleDelegateDidUpdateIsCalled() throws {
        let manager = makeManager()
        let path = "/path/to/extension"
        pathsStoringMock.paths = [path]

        try manager.uninstallExtension(path: path)

        XCTAssertTrue(lifecycleDelegateMock.didUpdateExtensionsCalled)
    }

    // MARK: - Uninstall All Extensions Tests

    @MainActor
    func testWhenUninstallAllExtensions_ThenAllPathsAreUninstalled() {
        let manager = makeManager()
        let paths = ["/path/to/extension1", "/path/to/extension2"]
        pathsStoringMock.paths = paths

        let results = manager.uninstallAllExtensions()

        XCTAssertEqual(results.count, 2)
    }

    @MainActor
    func testWhenUninstallAllExtensions_ThenResultsContainSuccessAndFailures() {
        let manager = makeManager()
        let paths = ["/path/to/extension1", "/path/to/extension2"]
        pathsStoringMock.paths = paths

        let results = manager.uninstallAllExtensions()

        for result in results {
            switch result {
            case .success:
                continue
            case .failure:
                XCTFail("Expected all uninstalls to succeed with mock")
            }
        }
    }

    // MARK: - Load Installed Extensions Tests

    @MainActor
    func testWhenLoadInstalledExtensions_ThenPathsAreFetchedFromStore() async {
        let paths = ["/path/to/extension1", "/path/to/extension2"]
        pathsStoringMock.paths = paths
        let manager = makeManager()

        await manager.loadInstalledExtensions()

        XCTAssertTrue(webExtensionLoadingMock.loadWebExtensionsCalled)
        XCTAssertEqual(webExtensionLoadingMock.loadedPaths, paths)
    }

    @MainActor
    func testWhenLoadInstalledExtensions_ThenLifecycleDelegateWillLoadIsCalled() async {
        let manager = makeManager()

        await manager.loadInstalledExtensions()

        XCTAssertTrue(lifecycleDelegateMock.willLoadExtensionsCalled)
    }

    @MainActor
    func testWhenLoadInstalledExtensions_ThenLifecycleDelegateDidUpdateIsCalled() async {
        let manager = makeManager()

        await manager.loadInstalledExtensions()

        XCTAssertTrue(lifecycleDelegateMock.didUpdateExtensionsCalled)
    }

    @MainActor
    func testWhenLoadInstalledExtensions_ThenEventsListenerControllerIsSet() async {
        let manager = makeManager()

        await manager.loadInstalledExtensions()

        XCTAssertNotNil(eventsListenerMock.controller)
        XCTAssertTrue(eventsListenerMock.controller === manager.controller)
    }

    // MARK: - Computed Properties Tests

    @MainActor
    func testThatWebExtensionPaths_ReturnsPathsFromStore() {
        let manager = makeManager()
        let paths = ["/path/to/extension1", "/path/to/extension2"]
        pathsStoringMock.paths = paths

        let resultPaths = manager.webExtensionPaths

        XCTAssertEqual(resultPaths, paths)
    }

    @MainActor
    func testThatHasInstalledExtensions_ReturnsTrueWhenPathsExist() {
        let manager = makeManager()
        pathsStoringMock.paths = ["/path/to/extension"]

        XCTAssertTrue(manager.hasInstalledExtensions)
    }

    @MainActor
    func testThatHasInstalledExtensions_ReturnsFalseWhenNoPathsExist() {
        let manager = makeManager()
        pathsStoringMock.paths = []

        XCTAssertFalse(manager.hasInstalledExtensions)
    }

    // MARK: - Identifier Hash Tests

    @MainActor
    func testThatIdentifierHash_ReturnsConsistentHashForSamePath() {
        let manager = makeManager()
        let path = "/path/to/extension"

        let hash1 = manager.identifierHash(forPath: path)
        let hash2 = manager.identifierHash(forPath: path)

        XCTAssertEqual(hash1, hash2)
    }

    @MainActor
    func testThatIdentifierHash_ReturnsDifferentHashForDifferentPaths() {
        let manager = makeManager()

        let hash1 = manager.identifierHash(forPath: "/path/to/extension1")
        let hash2 = manager.identifierHash(forPath: "/path/to/extension2")

        XCTAssertNotEqual(hash1, hash2)
    }

    @MainActor
    func testThatIdentifierHash_ReturnsHexString() {
        let manager = makeManager()

        let hash = manager.identifierHash(forPath: "/path/to/extension")

        let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(hash.unicodeScalars.allSatisfy { hexCharacterSet.contains($0) })
    }

    // MARK: - Extension Name Tests

    @MainActor
    func testThatExtensionName_ReturnsLastPathComponent() {
        let manager = makeManager()

        let name = manager.extensionName(from: "file:///path/to/MyExtension.appex")

        XCTAssertEqual(name, "MyExtension.appex")
    }

    @MainActor
    func testThatExtensionName_ReturnsNilForInvalidURL() {
        let manager = makeManager()

        let name = manager.extensionName(from: "")

        XCTAssertNil(name)
    }
}
