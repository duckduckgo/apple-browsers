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
import WebKit
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
    private var createdTestExtensionDirs: [URL] = []

    @MainActor
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
        for dir in createdTestExtensionDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        createdTestExtensionDirs.removeAll()
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
                                           filename: String = "extension.zip",
                                           name: String? = nil,
                                           version: String? = nil) -> InstalledWebExtension {
        InstalledWebExtension(
            uniqueIdentifier: uniqueIdentifier,
            filename: filename,
            name: name,
            version: version
        )
    }

    /// Loads a real (backgroundless) extension context into the controller so that
    /// `unloadAllExtensions()` has something to capture for the lightweight reload tests.
    @MainActor
    @discardableResult
    private func loadRealContext(identifier: String, into controller: WKWebExtensionController) async throws -> WKWebExtensionContext {
        let dir = try makeTestExtensionDirectory()
        let webExtension = try await WKWebExtension(resourceBaseURL: dir)
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = identifier
        try controller.load(context)
        return context
    }

    private func makeTestExtensionDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ReloadTestExtension-\(UUID().uuidString)")
        let manifest = """
        {
            "manifest_version": 3,
            "name": "Reload Test Extension",
            "version": "1.0.0",
            "description": "Minimal backgroundless test extension for reload unit tests"
        }
        """
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try manifest.write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        createdTestExtensionDirs.append(dir)
        return dir
    }

    // MARK: - Install Extension Tests

    @MainActor
    func testWhenExtensionIsInstalled_ThenStorageProviderIsCalled() async throws {
        let manager = makeManager()
        let sourceURL = try createTestWebExtension()

        try await manager.installExtension(from: sourceURL)

        XCTAssertTrue(storageProvidingMock.copyExtensionCalled)
        XCTAssertEqual(storageProvidingMock.copyExtensionSourceURL, sourceURL)
    }

    @MainActor
    func testWhenExtensionIsInstalled_ThenExtensionIsStored() async throws {
        let manager = makeManager()
        let sourceURL = try createTestWebExtension()

        try await manager.installExtension(from: sourceURL)

        XCTAssertTrue(installedExtensionStoringMock.addCalled)
        XCTAssertNotNil(installedExtensionStoringMock.addedExtension?.uniqueIdentifier)
        XCTAssertEqual(storageProvidingMock.copyExtensionIdentifier, installedExtensionStoringMock.addedExtension?.uniqueIdentifier)
    }

    @MainActor
    func testWhenExtensionIsInstalled_ThenLoaderIsCalled() async throws {
        let manager = makeManager()
        let sourceURL = try createTestWebExtension()

        try await manager.installExtension(from: sourceURL)

        XCTAssertTrue(webExtensionLoadingMock.loadWebExtensionCalled)
    }

    @MainActor
    func testWhenExtensionIsInstalled_ThenLifecycleDelegateDidUpdateIsCalled() async throws {
        let manager = makeManager()
        let sourceURL = try createTestWebExtension()

        try await manager.installExtension(from: sourceURL)

        XCTAssertTrue(lifecycleDelegateMock.didUpdateExtensionsCalled)
    }

    @MainActor
    func testWhenInstallFails_ThenStorageIsCleanedUp() async throws {
        let manager = makeManager()
        let sourceURL = try createTestWebExtension()
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
    func testWhenExtensionIsUninstalled_ThenIdentifierIsRemovedFromStore() throws {
        let manager = makeManager()
        let identifier = "extension.zip"
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: identifier)]

        try manager.uninstallExtension(identifier: identifier)

        XCTAssertTrue(installedExtensionStoringMock.removeCalled)
        XCTAssertEqual(installedExtensionStoringMock.removedIdentifier, identifier)
    }

    @MainActor
    func testWhenExtensionIsUninstalled_ThenLoaderUnloadIsCalled() throws {
        let manager = makeManager()
        let identifier = "extension.zip"
        installedExtensionStoringMock.installedExtensions = [makeInstalledWebExtension(uniqueIdentifier: identifier)]

        try manager.uninstallExtension(identifier: identifier)

        XCTAssertTrue(webExtensionLoadingMock.unloadExtensionCalled)
        XCTAssertEqual(webExtensionLoadingMock.unloadedIdentifier, identifier)
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
    func testWhenLoadInstalledExtensions_ThenLoaderIsCalledWithIdentifiers() async {
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1"),
            makeInstalledWebExtension(uniqueIdentifier: "extension2")
        ]
        let manager = makeManager()

        await manager.loadInstalledExtensions()

        XCTAssertTrue(webExtensionLoadingMock.loadWebExtensionsCalled)
        XCTAssertEqual(webExtensionLoadingMock.loadedIdentifiers, ["extension1", "extension2"])
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

    @MainActor
    func testWhenLoadInstalledExtensions_ThenOrphanedExtensionsAreCleaned() async {
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1"),
            makeInstalledWebExtension(uniqueIdentifier: "extension2")
        ]
        let manager = makeManager()

        await manager.loadInstalledExtensions()

        XCTAssertTrue(storageProvidingMock.cleanupOrphanedExtensionsCalled)
        XCTAssertEqual(storageProvidingMock.cleanupOrphanedExtensionsKnownIdentifiers, Set(["extension1", "extension2"]))
    }

    // MARK: - Reload Installed Extensions Tests

    @MainActor
    func testWhenReloadInstalledExtensionsCalledWithEmptyCache_ThenFallsBackToFullLoad() async {
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1")
        ]
        webExtensionLoadingMock.mockLoadResults = [
            .success(WebExtensionLoadResult(identifier: "extension1", filename: "extension.zip", displayName: "Extension 1", version: "1.0"))
        ]
        let manager = makeManager()

        await manager.reloadInstalledExtensions()

        // With nothing captured by a prior unload, reload must fall back to the full load path.
        XCTAssertTrue(webExtensionLoadingMock.loadWebExtensionsCalled)
        XCTAssertFalse(webExtensionLoadingMock.reloadWebExtensionCalled)
    }

    @MainActor
    func testWhenReloadInstalledExtensionsCalledAfterUnload_ThenUsesLightweightReloadAndSkipsFullLoad() async throws {
        let manager = makeManager()
        try await loadRealContext(identifier: "extension1", into: manager.controller)

        manager.unloadAllExtensions()
        await manager.reloadInstalledExtensions()

        // The cached extension is re-created via the lightweight path, not re-parsed from disk.
        XCTAssertTrue(webExtensionLoadingMock.reloadWebExtensionCalled)
        XCTAssertTrue(webExtensionLoadingMock.loadedIdentifiers.contains("extension1"))
        XCTAssertFalse(webExtensionLoadingMock.loadWebExtensionsCalled)
        // The heavy install-store reconciliation / orphan cleanup is skipped on the lightweight path.
        XCTAssertFalse(storageProvidingMock.cleanupOrphanedExtensionsCalled)
    }

    @MainActor
    func testWhenLightweightReloadFails_ThenFallsBackToFullLoad() async throws {
        let manager = makeManager()
        try await loadRealContext(identifier: "extension1", into: manager.controller)
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "extension1")
        ]
        webExtensionLoadingMock.mockLoadResults = [
            .success(WebExtensionLoadResult(identifier: "extension1", filename: "extension.zip", displayName: "Extension 1", version: "1.0"))
        ]

        manager.unloadAllExtensions()
        webExtensionLoadingMock.mockError = NSError(domain: "test", code: 1)

        await manager.reloadInstalledExtensions()

        // The lightweight reload was attempted, failed, and recovery used the full load path.
        XCTAssertTrue(webExtensionLoadingMock.reloadWebExtensionCalled)
        XCTAssertTrue(webExtensionLoadingMock.loadWebExtensionsCalled)
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

    // MARK: - Extension Version Lookup Tests

    @MainActor
    func testWhenExtensionVersionRequested_ThenReturnsVersionFromStore() {
        let manager = makeManager()
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "ext-1", version: "1.2.3")
        ]

        let version = manager.extensionVersion(for: "ext-1")

        XCTAssertEqual(version, "1.2.3")
    }

    @MainActor
    func testWhenExtensionVersionRequestedForUnknownIdentifier_ThenReturnsNil() {
        let manager = makeManager()
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "ext-1", version: "1.0.0")
        ]

        let version = manager.extensionVersion(for: "unknown-ext")

        XCTAssertNil(version)
    }

    @MainActor
    func testWhenExtensionHasNoVersion_ThenReturnsNil() {
        let manager = makeManager()
        installedExtensionStoringMock.installedExtensions = [
            makeInstalledWebExtension(uniqueIdentifier: "ext-1", version: nil)
        ]

        let version = manager.extensionVersion(for: "ext-1")

        XCTAssertNil(version)
    }

    // MARK: - Configuration Tests

    @MainActor
    func testWhenManagerCreatedWithoutLoader_ThenLoaderReceivesIsInspectableFromConfiguration() async throws {
        configurationMock.isInspectable = true

        let extensionURL = try createTestWebExtension()
        storageProvidingMock.resolvedExtensionURL = extensionURL
        storageProvidingMock.mockCopyResult = extensionURL

        let manager = makeManagerWithRealLoader()

        try await manager.installExtension(from: extensionURL)

        let context = manager.contexts.first
        XCTAssertNotNil(context)
        XCTAssertTrue(context?.isInspectable == true)
    }

    @MainActor
    func testWhenManagerCreatedWithIsInspectableFalse_ThenContextIsNotInspectable() async throws {
        configurationMock.isInspectable = false

        let extensionURL = try createTestWebExtension()
        storageProvidingMock.resolvedExtensionURL = extensionURL
        storageProvidingMock.mockCopyResult = extensionURL

        let manager = makeManagerWithRealLoader()

        try await manager.installExtension(from: extensionURL)

        let context = manager.contexts.first
        XCTAssertNotNil(context)
        XCTAssertFalse(context?.isInspectable == true)
    }

    // MARK: - Additional Helpers

    @MainActor
    private func makeManagerWithRealLoader() -> WebExtensionManager {
        WebExtensionManager(
            configuration: configurationMock,
            windowTabProvider: windowTabProviderMock,
            storageProvider: storageProvidingMock,
            installationStore: installedExtensionStoringMock,
            loader: nil,
            eventsListener: eventsListenerMock,
            lifecycleDelegate: lifecycleDelegateMock
        )
    }

    private func createTestWebExtension() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let extensionDir = tempDir.appendingPathComponent("TestExtension-\(UUID().uuidString)")

        let manifest = """
        {
            "manifest_version": 3,
            "name": "Test Extension",
            "version": "1.0.0",
            "description": "Minimal test extension for unit tests"
        }
        """

        try FileManager.default.createDirectory(at: extensionDir, withIntermediateDirectories: true)
        try manifest.write(to: extensionDir.appendingPathComponent("manifest.json"),
                          atomically: true, encoding: .utf8)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: extensionDir)
        }

        return extensionDir
    }

}
