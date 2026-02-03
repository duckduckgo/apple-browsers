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

    var installedExtensionStoringMock: InstalledWebExtensionStoringMock!
    var storageProvidingMock: WebExtensionStorageProvidingMock!
    var webExtensionLoadingMock: WebExtensionLoadingMock!
    var windowTabProviderMock: WebExtensionWindowTabProvidingMock!
    var eventsListenerMock: WebExtensionEventsListenerMock!
    var lifecycleDelegateMock: WebExtensionLifecycleDelegateMock!
    var configurationMock: WebExtensionConfigurationProvidingMock!

    override func setUp() {
        super.setUp()

        installedExtensionStoringMock = InstalledWebExtensionStoringMock()
        storageProvidingMock = WebExtensionStorageProvidingMock()
        webExtensionLoadingMock = WebExtensionLoadingMock()
        windowTabProviderMock = WebExtensionWindowTabProvidingMock()
        eventsListenerMock = WebExtensionEventsListenerMock()
        lifecycleDelegateMock = WebExtensionLifecycleDelegateMock()
        configurationMock = WebExtensionConfigurationProvidingMock()
    }

    override func tearDown() {
        webExtensionLoadingMock?.cleanupTestExtensions()
        installedExtensionStoringMock = nil
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
            installationStore: installedExtensionStoringMock,
            loader: webExtensionLoadingMock,
            eventsListener: eventsListenerMock,
            lifecycleDelegate: lifecycleDelegateMock
        )
    }

    private func makeInstalledWebExtension(uniqueIdentifier: String,
                                        name: String? = nil,
                                        storagePath: String? = nil,
                                        version: String? = nil) -> InstalledWebExtension {
        InstalledWebExtension(
            uniqueIdentifier: uniqueIdentifier,
            name: name,
            storagePath: storagePath ?? "/path/to/\(uniqueIdentifier)",
            version: version
        )
    }

    // MARK: - Install Extension Tests

    @MainActor
    func testWhenExtensionIsInstalled_ThenStorageProviderIsCalled() async throws {
        let manager = makeManager()
        let sourceURL = URL(fileURLWithPath: "/source/extension.zip")

        try await manager.installExtension(from: sourceURL)

        XCTAssertTrue(storageProvidingMock.copyExtensionCalled)
        XCTAssertEqual(storageProvidingMock.copyExtensionSourceURL, sourceURL)
    }

    @MainActor
    func testWhenExtensionIsInstalled_ThenExtensionIsStored() async throws {
        let manager = makeManager()
        let sourceURL = URL(fileURLWithPath: "/source/extension.zip")

        try await manager.installExtension(from: sourceURL)

        XCTAssertTrue(installedExtensionStoringMock.addCalled)
        XCTAssertEqual(installedExtensionStoringMock.addedExtension?.uniqueIdentifier, "extension.zip")
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
    func testWhenInstallFails_ThenStorageIsCleanedUp() async {
        let manager = makeManager()
        let sourceURL = URL(fileURLWithPath: "/source/extension.zip")
        webExtensionLoadingMock.mockError = NSError(domain: "test", code: 1)

        do {
            try await manager.installExtension(from: sourceURL)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertFalse(installedExtensionStoringMock.addCalled)
            XCTAssertTrue(storageProvidingMock.removeExtensionCalled)
        }
    }

    // MARK: - Uninstall Extension Tests

    @MainActor
    func testWhenExtensionIsUninstalled_ThenStorageProviderResolvesPath() throws {
        let manager = makeManager()
        let identifier = "extension.zip"
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: identifier)]

        try manager.uninstallExtension(identifier: identifier)

        XCTAssertTrue(storageProvidingMock.resolveInstalledWebExtensionCalled)
        XCTAssertEqual(storageProvidingMock.resolveInstalledWebExtensionIdentifier, identifier)
    }

    @MainActor
    func testWhenExtensionIsUninstalled_ThenIdentifierIsRemovedFromStore() throws {
        let manager = makeManager()
        let identifier = "extension.zip"
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: identifier)]

        try manager.uninstallExtension(identifier: identifier)

        XCTAssertTrue(installedExtensionStoringMock.removeCalled)
        XCTAssertEqual(installedExtensionStoringMock.removedIdentifier, identifier)
    }

    @MainActor
    func testWhenUninstallExtensionNotFound_ThenErrorIsThrown() {
        let manager = makeManager()
        let identifier = "extension.zip"
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: identifier)]
        storageProvidingMock.shouldReturnNilForResolve = true

        XCTAssertThrowsError(try manager.uninstallExtension(identifier: identifier)) { error in
            if case WebExtensionError.extensionNotFound(let notFoundIdentifier) = error {
                XCTAssertEqual(notFoundIdentifier, identifier)
            } else {
                XCTFail("Expected WebExtensionError.extensionNotFound, got \(error)")
            }
        }
    }

    @MainActor
    func testWhenExtensionIsUninstalled_ThenLoaderUnloadIsCalled() throws {
        let manager = makeManager()
        let identifier = "extension.zip"
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: identifier)]

        try manager.uninstallExtension(identifier: identifier)

        XCTAssertTrue(webExtensionLoadingMock.unloadExtensionCalled)
    }

    @MainActor
    func testWhenExtensionIsUninstalled_ThenStorageProviderRemovesExtension() throws {
        let manager = makeManager()
        let identifier = "extension.zip"
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: identifier)]

        try manager.uninstallExtension(identifier: identifier)

        XCTAssertTrue(storageProvidingMock.removeExtensionCalled)
        XCTAssertEqual(storageProvidingMock.removeExtensionIdentifier, identifier)
    }

    @MainActor
    func testWhenUninstallFails_ThenErrorIsThrown() {
        let manager = makeManager()
        let identifier = "extension.zip"
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: identifier)]

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
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: identifier)]

        try manager.uninstallExtension(identifier: identifier)

        XCTAssertTrue(lifecycleDelegateMock.didUpdateExtensionsCalled)
    }

    // MARK: - Uninstall All Extensions Tests

    @MainActor
    func testWhenUninstallAllExtensions_ThenAllIdentifiersAreUninstalled() {
        let manager = makeManager()
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1.zip"),
            makeInstalledWebExtension(uniqueIdentifier: "extension2.zip")
        ]

        let results = manager.uninstallAllExtensions()

        XCTAssertEqual(results.count, 2)
    }

    @MainActor
    func testWhenUninstallAllExtensions_ThenResultsContainSuccessAndFailures() {
        let manager = makeManager()
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1.zip"),
            makeInstalledWebExtension(uniqueIdentifier: "extension2.zip")
        ]

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
    func testWhenLoadInstalledWebExtensions_ThenIdentifiersAreResolvedToPaths() async {
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1.zip"),
            makeInstalledWebExtension(uniqueIdentifier: "extension2.zip")
        ]
        let manager = makeManager()

        await manager.loadInstalledWebExtensions()

        XCTAssertTrue(storageProvidingMock.resolveInstalledWebExtensionCalled)
        XCTAssertTrue(webExtensionLoadingMock.loadWebExtensionsCalled)
        XCTAssertEqual(webExtensionLoadingMock.loadedPaths.count, 2)
    }

    @MainActor
    func testWhenLoadInstalledWebExtensions_ThenMissingExtensionsAreRemovedFromStore() async {
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1.zip"),
            makeInstalledWebExtension(uniqueIdentifier: "extension2.zip")
        ]
        storageProvidingMock.shouldReturnNilForResolve = true
        let manager = makeManager()

        await manager.loadInstalledWebExtensions()

        XCTAssertTrue(installedExtensionStoringMock.removeCalled)
        XCTAssertFalse(webExtensionLoadingMock.loadWebExtensionsCalled)
    }

    @MainActor
    func testWhenLoadInstalledWebExtensions_ThenLifecycleDelegateWillLoadIsCalled() async {
        let manager = makeManager()

        await manager.loadInstalledWebExtensions()

        XCTAssertTrue(lifecycleDelegateMock.willLoadExtensionsCalled)
    }

    @MainActor
    func testWhenLoadInstalledWebExtensions_ThenLifecycleDelegateDidUpdateIsCalled() async {
        let manager = makeManager()

        await manager.loadInstalledWebExtensions()

        XCTAssertTrue(lifecycleDelegateMock.didUpdateExtensionsCalled)
    }

    @MainActor
    func testWhenLoadInstalledWebExtensions_ThenEventsListenerControllerIsSet() async {
        let manager = makeManager()

        await manager.loadInstalledWebExtensions()

        XCTAssertNotNil(eventsListenerMock.controller)
        XCTAssertTrue(eventsListenerMock.controller === manager.controller)
    }

    // MARK: - Computed Properties Tests

    @MainActor
    func testThatWebExtensionIdentifiers_ReturnsIdentifiersFromStore() {
        let manager = makeManager()
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1.zip"),
            makeInstalledWebExtension(uniqueIdentifier: "extension2.zip")
        ]

        let resultIdentifiers = manager.webExtensionIdentifiers

        XCTAssertEqual(resultIdentifiers, ["extension1.zip", "extension2.zip"])
    }

    @MainActor
    func testThatHasInstalledWebExtensions_ReturnsTrueWhenExtensionsExist() {
        let manager = makeManager()
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: "extension.zip")]

        XCTAssertTrue(manager.hasInstalledWebExtensions)
    }

    @MainActor
    func testThatHasInstalledWebExtensions_ReturnsFalseWhenNoExtensionsExist() {
        let manager = makeManager()
        installedExtensionStoringMock.installedExtensions = []

        XCTAssertFalse(manager.hasInstalledWebExtensions)
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
