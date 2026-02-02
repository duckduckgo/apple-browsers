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

@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionManagerTests: XCTestCase {

    var pathsStoringMock: WebExtensionPathsStoringMock!
    var storageProvidingMock: WebExtensionStorageProvidingMock!
    var webExtensionLoadingMock: WebExtensionLoadingMock!
    var windowTabProviderMock: WebExtensionWindowTabProvidingMock!
    var eventsListenerMock: WebExtensionEventsListenerMock!
    var lifecycleDelegateMock: WebExtensionLifecycleDelegateMock!
    var configurationMock: WebExtensionConfigurationProvidingMock!

    override func setUp() {
        super.setUp()

        pathsStoringMock = WebExtensionPathsStoringMock()
        storageProvidingMock = WebExtensionStorageProvidingMock()
        webExtensionLoadingMock = WebExtensionLoadingMock()
        windowTabProviderMock = WebExtensionWindowTabProvidingMock()
        eventsListenerMock = WebExtensionEventsListenerMock()
        lifecycleDelegateMock = WebExtensionLifecycleDelegateMock()
        configurationMock = WebExtensionConfigurationProvidingMock()
    }

    override func tearDown() {
        webExtensionLoadingMock?.cleanupTestExtensions()
        pathsStoringMock = nil
        storageProvidingMock = nil
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
        WebExtensionManager(
            configuration: configurationMock,
            windowTabProvider: windowTabProviderMock,
            storageProvider: storageProvidingMock,
            installationStore: pathsStoringMock,
            loader: webExtensionLoadingMock,
            eventsListener: eventsListenerMock,
            lifecycleDelegate: lifecycleDelegateMock
        )
    }

    // MARK: - Install Extension Tests

    @MainActor
    func testWhenExtensionIsInstalled_ThenStorageProviderIsCalled() async throws {
        let manager = makeManager()
        let sourceURL = URL(fileURLWithPath: "/source/extension.zip")

        try await manager.installExtension(from: sourceURL)

        XCTAssertTrue(storageProvidingMock.installExtensionCalled)
        XCTAssertEqual(storageProvidingMock.installExtensionSourceURL, sourceURL)
    }

    @MainActor
    func testWhenExtensionIsInstalled_ThenIdentifierIsStored() async throws {
        let manager = makeManager()
        let sourceURL = URL(fileURLWithPath: "/source/extension.zip")

        try await manager.installExtension(from: sourceURL)

        XCTAssertTrue(pathsStoringMock.addCalled)
        XCTAssertEqual(pathsStoringMock.addedPath, "extension.zip")
    }

    @MainActor
    func testWhenExtensionIsInstalled_ThenLoaderIsCalled() async throws {
        let manager = makeManager()
        let sourceURL = URL(fileURLWithPath: "/source/extension.zip")

        try await manager.installExtension(from: sourceURL)

        XCTAssertTrue(webExtensionLoadingMock.loadWebExtensionCalled)
    }

    @MainActor
    func testWhenExtensionIsInstalled_ThenLifecycleDelegateDidUpdateIsCalled() async throws {
        let manager = makeManager()
        let sourceURL = URL(fileURLWithPath: "/source/extension.zip")

        try await manager.installExtension(from: sourceURL)

        XCTAssertTrue(lifecycleDelegateMock.didUpdateExtensionsCalled)
    }

    @MainActor
    func testWhenInstallFails_ThenIdentifierIsRemovedFromStore() async {
        let manager = makeManager()
        let sourceURL = URL(fileURLWithPath: "/source/extension.zip")
        webExtensionLoadingMock.mockError = NSError(domain: "test", code: 1)

        do {
            try await manager.installExtension(from: sourceURL)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(pathsStoringMock.removeCalled)
            XCTAssertTrue(storageProvidingMock.removeExtensionCalled)
        }
    }

    // MARK: - Uninstall Extension Tests

    @MainActor
    func testWhenExtensionIsUninstalled_ThenIdentifierIsRemovedFromStore() throws {
        let manager = makeManager()
        let identifier = "extension.zip"
        pathsStoringMock.paths = [identifier]

        try manager.uninstallExtension(identifier: identifier)

        XCTAssertTrue(pathsStoringMock.removeCalled)
        XCTAssertEqual(pathsStoringMock.removedPath, identifier)
    }

    @MainActor
    func testWhenExtensionIsUninstalled_ThenLoaderUnloadIsCalled() throws {
        let manager = makeManager()
        let identifier = "extension.zip"
        pathsStoringMock.paths = [identifier]

        try manager.uninstallExtension(identifier: identifier)

        XCTAssertTrue(webExtensionLoadingMock.unloadExtensionCalled)
    }

    @MainActor
    func testWhenExtensionIsUninstalled_ThenStorageProviderRemovesExtension() throws {
        let manager = makeManager()
        let identifier = "extension.zip"
        pathsStoringMock.paths = [identifier]

        try manager.uninstallExtension(identifier: identifier)

        XCTAssertTrue(storageProvidingMock.removeExtensionCalled)
        XCTAssertEqual(storageProvidingMock.removeExtensionIdentifier, identifier)
    }

    @MainActor
    func testWhenUninstallFails_ThenErrorIsThrown() {
        let manager = makeManager()
        let identifier = "extension.zip"
        pathsStoringMock.paths = [identifier]

        let expectedError = NSError(domain: "test", code: 1)
        webExtensionLoadingMock.mockUnloadError = expectedError

        XCTAssertThrowsError(try manager.uninstallExtension(identifier: identifier)) { error in
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
        let identifier = "extension.zip"
        pathsStoringMock.paths = [identifier]

        try manager.uninstallExtension(identifier: identifier)

        XCTAssertTrue(lifecycleDelegateMock.didUpdateExtensionsCalled)
    }

    // MARK: - Uninstall All Extensions Tests

    @MainActor
    func testWhenUninstallAllExtensions_ThenAllIdentifiersAreUninstalled() {
        let manager = makeManager()
        let identifiers = ["extension1.zip", "extension2.zip"]
        pathsStoringMock.paths = identifiers

        let results = manager.uninstallAllExtensions()

        XCTAssertEqual(results.count, 2)
    }

    @MainActor
    func testWhenUninstallAllExtensions_ThenResultsContainSuccessAndFailures() {
        let manager = makeManager()
        let identifiers = ["extension1.zip", "extension2.zip"]
        pathsStoringMock.paths = identifiers

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
    func testWhenLoadInstalledExtensions_ThenIdentifiersAreResolvedToPaths() async {
        let identifiers = ["extension1.zip", "extension2.zip"]
        pathsStoringMock.paths = identifiers
        let manager = makeManager()

        await manager.loadInstalledExtensions()

        XCTAssertTrue(webExtensionLoadingMock.loadWebExtensionsCalled)
        XCTAssertEqual(webExtensionLoadingMock.loadedPaths.count, 2)
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
    func testThatWebExtensionIdentifiers_ReturnsIdentifiersFromStore() {
        let manager = makeManager()
        let identifiers = ["extension1.zip", "extension2.zip"]
        pathsStoringMock.paths = identifiers

        let resultIdentifiers = manager.webExtensionIdentifiers

        XCTAssertEqual(resultIdentifiers, identifiers)
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
