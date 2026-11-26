//
//  WebExtensionManagerHandlerRegistrationTests.swift
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

@_spi(Testing) import Persistence
import XCTest
import WebKit
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionManagerHandlerRegistrationTests: XCTestCase {

    var installedExtensionStoringMock: InstalledWebExtensionStoringMock!
    var storageProvidingMock: WebExtensionStorageProvidingMock!
    var webExtensionLoadingMock: WebExtensionLoadingMock!
    var windowTabProviderMock: WebExtensionWindowTabProvidingMock!
    var configurationMock: WebExtensionConfigurationProvidingMock!
    var messageRouter: TestMessageRouter!
    var handlerProvider: TestHandlerProvider!

    @MainActor
    override func setUp() {
        super.setUp()

        installedExtensionStoringMock = InstalledWebExtensionStoringMock()
        storageProvidingMock = WebExtensionStorageProvidingMock()
        webExtensionLoadingMock = WebExtensionLoadingMock()
        windowTabProviderMock = WebExtensionWindowTabProvidingMock()
        configurationMock = WebExtensionConfigurationProvidingMock()
        messageRouter = TestMessageRouter()
        handlerProvider = TestHandlerProvider()
    }

    override func tearDown() {
        webExtensionLoadingMock?.cleanupTestExtensions()
        installedExtensionStoringMock = nil
        storageProvidingMock = nil
        webExtensionLoadingMock = nil
        windowTabProviderMock = nil
        configurationMock = nil
        messageRouter = nil
        handlerProvider = nil

        super.tearDown()
    }

    // MARK: - Helper

    @MainActor
    private func makeManager(useRealLoader: Bool = false,
                             bundledURL: URL? = nil,
                             permissionController: WebExtensionPermissionController? = nil,
                             isPermissionEnforcementEnabled: Bool = true) -> WebExtensionManager {
        WebExtensionManager(
            configuration: configurationMock,
            controllerConfiguration: .nonPersistent(),
            windowTabProvider: windowTabProviderMock,
            storageProvider: storageProvidingMock,
            installationStore: installedExtensionStoringMock,
            permissionController: permissionController,
            isPermissionEnforcementEnabled: { isPermissionEnforcementEnabled },
            loader: useRealLoader ? nil : webExtensionLoadingMock,
            messageRouter: messageRouter,
            handlerProvider: handlerProvider,
            bundledExtensionURL: { $0.type == .embedded ? bundledURL : nil }
        )
    }

    // MARK: - Tests

    @MainActor
    func testWhenManagerIsCreated_ThenLoaderDelegateIsSet() {
        let manager = makeManager()

        XCTAssertNotNil(webExtensionLoadingMock.delegate)
        XCTAssertTrue(webExtensionLoadingMock.delegate === manager)
    }

    @MainActor
    func testWhenBundledExtensionIsInstalledAndReloaded_ThenHandlersAreRegistered() async throws {
        let sourceURL = try createTestWebExtension(claimsDDGIdentity: true)
        storageProvidingMock.resolvedExtensionURL = sourceURL
        let manager = makeManager(useRealLoader: true, bundledURL: sourceURL)
        defer { manager.unloadAllExtensions() }

        try await manager.installExtension(from: sourceURL)

        let installed = try XCTUnwrap(installedExtensionStoringMock.installedExtensions.first)
        XCTAssertEqual(installed.embeddedType, .embedded)
        XCTAssertEqual(messageRouter.providedHandlerCount, 1)
        XCTAssertTrue(manager.installingEmbeddedIdentifiers.isEmpty)

        try await manager.reloadExtension(identifier: installed.uniqueIdentifier)

        XCTAssertEqual(messageRouter.providedHandlerCount, 2)
        XCTAssertEqual(handlerProvider.lastIdentifier, installed.uniqueIdentifier)
    }

    @MainActor
    func testWhenBundledExtensionIsInstalled_ThenHandlersAreRegisteredBeforeLoad() async throws {
        let sourceURL = try createTestWebExtension(claimsDDGIdentity: true)
        storageProvidingMock.resolvedExtensionURL = sourceURL
        let manager = makeManager(useRealLoader: true, bundledURL: sourceURL)
        defer { manager.unloadAllExtensions() }
        let installationStore = try XCTUnwrap(installedExtensionStoringMock)
        handlerProvider.onMakeHandlers = { context in
            XCTAssertTrue(installationStore.installedExtensions.isEmpty)
            XCTAssertFalse(context.isLoaded)
        }

        try await manager.installExtension(from: sourceURL)

        XCTAssertTrue(handlerProvider.makeHandlersCalled)
        XCTAssertEqual(messageRouter.providedHandlerCount, 1)
        XCTAssertEqual(messageRouter.subscriptionEventsHandlerCount, 1)
    }

    @MainActor
    func testWhenStoreExtensionClaimsDDGIdentity_ThenInternalHandlersAreUnavailableOnInstallAndReload() async throws {
        let sourceURL = try createTestWebExtension(claimsDDGIdentity: true)
        storageProvidingMock.resolvedExtensionURL = sourceURL
        let manager = makeManager(useRealLoader: true)
        defer { manager.unloadAllExtensions() }

        try await manager.installExtension(from: sourceURL,
                                           storeIdentity: WebExtensionStoreIdentity(store: .chromeWebStore, id: "catalog-extension"))
        let installed = try XCTUnwrap(installedExtensionStoringMock.installedExtensions.first)
        let context = try XCTUnwrap(manager.context(for: installed.uniqueIdentifier))
        XCTAssertEqual(context.duckDuckGoWebExtensionType, .embedded)
        XCTAssertNil(installed.embeddedType)
        XCTAssertFalse(handlerProvider.makeHandlersCalled)
        XCTAssertFalse(messageRouter.registerHandlerCalled)

        try await manager.reloadExtension(identifier: installed.uniqueIdentifier)

        XCTAssertNotNil(manager.context(for: installed.uniqueIdentifier))
        XCTAssertFalse(handlerProvider.makeHandlersCalled)
        XCTAssertFalse(messageRouter.registerHandlerCalled)
    }

    @MainActor
    func testWhenStoreUpdateAddsDDGIdentity_ThenInternalHandlersRemainUnavailable() async throws {
        let sourceURL = try createTestWebExtension()
        storageProvidingMock.resolvedExtensionURL = sourceURL
        let manager = makeManager(useRealLoader: true)
        defer { manager.unloadAllExtensions() }
        let identity = WebExtensionStoreIdentity(store: .chromeWebStore, id: "catalog-extension")
        try await manager.installExtension(from: sourceURL, storeIdentity: identity)
        let original = try XCTUnwrap(installedExtensionStoringMock.installedExtensions.first)

        let replacementURL = try createTestWebExtension(claimsDDGIdentity: true)
        storageProvidingMock.resolvedExtensionURL = replacementURL
        try await manager.installExtension(from: replacementURL, storeIdentity: identity, replacing: original.uniqueIdentifier)

        let replacement = try XCTUnwrap(installedExtensionStoringMock.installedExtensions.first {
            $0.uniqueIdentifier != original.uniqueIdentifier
        })
        let context = try XCTUnwrap(manager.context(for: replacement.uniqueIdentifier))
        XCTAssertEqual(context.duckDuckGoWebExtensionType, .embedded)
        XCTAssertNil(replacement.embeddedType)
        XCTAssertFalse(handlerProvider.makeHandlersCalled)
        XCTAssertFalse(messageRouter.registerHandlerCalled)
    }

    @MainActor
    func testWhenUnbundledExtensionClaimsDDGIdentity_ThenHandlersAreUnavailableRegardlessOfPermissionEnforcement() async throws {
        let modes = [(hasController: false, enforcesPermissions: false),
                     (hasController: true, enforcesPermissions: false),
                     (hasController: true, enforcesPermissions: true)]
        for mode in modes {
            let sourceURL = try createTestWebExtension(claimsDDGIdentity: true)
            storageProvidingMock.resolvedExtensionURL = sourceURL
            let permissionController = mode.hasController ? WebExtensionPermissionController(
                store: WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore()),
                installationStore: installedExtensionStoringMock,
                prompter: HandlerRegistrationPermissionPrompter()) : nil
            let manager = makeManager(useRealLoader: true,
                                      permissionController: permissionController,
                                      isPermissionEnforcementEnabled: mode.enforcesPermissions)
            defer { manager.unloadAllExtensions() }

            try await manager.installExtension(from: sourceURL)

            let context = try XCTUnwrap(manager.loadedExtensions.first)
            let installed = try XCTUnwrap(installedExtensionStoringMock.installedExtension(withUniqueIdentifier: context.uniqueIdentifier))
            XCTAssertEqual(context.duckDuckGoWebExtensionType, .embedded)
            XCTAssertNil(installed.embeddedType)
            XCTAssertFalse(handlerProvider.makeHandlersCalled)
            XCTAssertFalse(messageRouter.registerHandlerCalled)

            try await manager.reloadExtension(identifier: installed.uniqueIdentifier)

            XCTAssertNotNil(manager.context(for: installed.uniqueIdentifier))
            XCTAssertFalse(handlerProvider.makeHandlersCalled)
            XCTAssertFalse(messageRouter.registerHandlerCalled)
        }
    }

#if os(macOS)
    @MainActor
    func testWhenEmbeddedExtensionsAreSynced_ThenHandlersAreRegisteredOnFirstLoadAndReload() async throws {
        let bundledURL = try XCTUnwrap(EmbeddedWebExtensionRegistry.descriptor(for: .embedded)?.bundledURL)
        storageProvidingMock.resolvedExtensionURL = bundledURL
        let manager = makeManager(useRealLoader: true, bundledURL: bundledURL)
        defer { manager.unloadAllExtensions() }

        await manager.syncEmbeddedExtensions(enabledTypes: [.embedded])

        let installed = try XCTUnwrap(manager.installedEmbeddedExtension(for: .embedded))
        XCTAssertNotNil(manager.context(for: installed.uniqueIdentifier))
        XCTAssertEqual(messageRouter.providedHandlerCount, 1)
        XCTAssertTrue(manager.installingEmbeddedIdentifiers.isEmpty)

        try await manager.reloadExtension(identifier: installed.uniqueIdentifier)

        XCTAssertEqual(messageRouter.providedHandlerCount, 2)
    }
#endif

    @MainActor
    func testWhenBundledExtensionInstallFails_ThenPendingTrustIsRemoved() async throws {
        let sourceURL = try createTestWebExtension(claimsDDGIdentity: true)
        let manager = makeManager(bundledURL: sourceURL)
        webExtensionLoadingMock.mockError = NSError(domain: "test", code: 1)

        do {
            try await manager.installExtension(from: sourceURL)
            XCTFail("Expected installation to fail")
        } catch {
            XCTAssertTrue(manager.installingEmbeddedIdentifiers.isEmpty)
            XCTAssertTrue(installedExtensionStoringMock.installedExtensions.isEmpty)
        }
    }

#if os(macOS)
    @MainActor
    func testWhenEmbeddedSyncFails_ThenPendingTrustIsRemoved() async throws {
        let bundledURL = try XCTUnwrap(EmbeddedWebExtensionRegistry.descriptor(for: .embedded)?.bundledURL)
        let manager = makeManager(bundledURL: bundledURL)
        webExtensionLoadingMock.mockError = NSError(domain: "test", code: 1)

        await manager.syncEmbeddedExtensions(enabledTypes: [.embedded])

        XCTAssertTrue(manager.installingEmbeddedIdentifiers.isEmpty)
        XCTAssertTrue(installedExtensionStoringMock.installedExtensions.isEmpty)
    }
#endif

    // MARK: - Test Helpers

    private func createTestWebExtension(claimsDDGIdentity: Bool = false) throws -> URL {
        let extensionDir = FileManager.default.temporaryDirectory.appendingPathComponent("TestExtension-\(UUID().uuidString)")
        var manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Test Extension",
            "version": "1.0.0",
            "description": "Minimal test extension for unit tests"
        ]
        if claimsDDGIdentity {
            manifest["browser_specific_settings"] = [
                "duckduckgo": ["id": DuckDuckGoWebExtensionType.embedded.rawValue]
            ]
        }

        try FileManager.default.createDirectory(at: extensionDir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: manifest).write(to: extensionDir.appendingPathComponent("manifest.json"))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: extensionDir)
        }
        return extensionDir
    }

    @MainActor
    func testWhenExtensionIsUninstalled_ThenHandlersAreUnregistered() throws {
        let manager = makeManager()
        let identifier = "test-extension-id"
        installedExtensionStoringMock.installedExtensions = [
            InstalledWebExtension(uniqueIdentifier: identifier, filename: "test.zip", name: nil, version: nil)
        ]

        try manager.uninstallExtension(identifier: identifier)

        XCTAssertTrue(messageRouter.unregisterHandlersCalled)
        XCTAssertEqual(messageRouter.unregisteredIdentifier, identifier)
    }

    @MainActor
    func testWhenReloadUnloadFails_ThenLiveHandlersAreNotUnregistered() async {
        let manager = makeManager()
        webExtensionLoadingMock.mockUnloadError = NSError(domain: "test", code: 1)

        do {
            try await manager.reloadExtension(identifier: "test-extension-id")
            XCTFail("Expected reload to fail")
        } catch {
            XCTAssertFalse(messageRouter.unregisterHandlersCalled)
            XCTAssertFalse(webExtensionLoadingMock.loadWebExtensionCalled)
        }
    }

    @MainActor
    func testWhenReloadLoadFails_ThenHandlersForUnloadedContextAreRemoved() async {
        let manager = makeManager()
        webExtensionLoadingMock.mockError = NSError(domain: "test", code: 2)

        do {
            try await manager.reloadExtension(identifier: "test-extension-id")
            XCTFail("Expected reload to fail")
        } catch {
            XCTAssertTrue(messageRouter.unregisterHandlersCalled)
            XCTAssertTrue(webExtensionLoadingMock.loadWebExtensionCalled)
        }
    }
}

// MARK: - Test Helper Classes

@available(macOS 15.4, iOS 18.4, *)
final class TestMessageRouter: WebExtensionMessageRouting {

    var registerHandlerCalled = false
    var unregisterHandlersCalled = false
    var registeredHandlers: [(handler: WebExtensionMessageHandler, identifier: String)] = []
    var unregisteredIdentifier: String?

    func registerHandler(_ handler: WebExtensionMessageHandler, for extensionIdentifier: String) {
        registerHandlerCalled = true
        registeredHandlers.append((handler, extensionIdentifier))
    }

    /// Handlers made by `TestHandlerProvider`, leaving out the ones the manager registers itself.
    var providedHandlerCount: Int {
        registeredHandlers.filter { $0.handler is TestMessageHandler }.count
    }

    var subscriptionEventsHandlerCount: Int {
        registeredHandlers.filter { $0.handler is SubscriptionEventsWebExtensionMessageHandler }.count
    }

    func unregisterHandlers(for extensionIdentifier: String) {
        unregisterHandlersCalled = true
        unregisteredIdentifier = extensionIdentifier
    }

    func routeMessage(_ message: WebExtensionMessage) async -> WebExtensionMessageResult {
        .success(nil)
    }
}

@available(macOS 15.4, iOS 18.4, *)
final class TestHandlerProvider: WebExtensionHandlerProviding {

    var makeHandlersCalled = false
    var lastIdentifier: String?
    var lastContext: WKWebExtensionContext?
    var onMakeHandlers: ((WKWebExtensionContext) -> Void)?

    func makeHandlers(for context: WKWebExtensionContext) -> [WebExtensionMessageHandler] {
        onMakeHandlers?(context)
        makeHandlersCalled = true
        lastIdentifier = context.uniqueIdentifier
        lastContext = context
        return [TestMessageHandler()]
    }
}

@available(macOS 15.4, iOS 18.4, *)
final class TestMessageHandler: WebExtensionMessageHandler {

    var handledFeatureName: String {
        "testFeature"
    }

    func handleMessage(_ message: WebExtensionMessage) async -> WebExtensionMessageResult {
        .success(nil)
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class HandlerRegistrationPermissionPrompter: WebExtensionPermissionPrompting {
    func confirmInstallation(of webExtension: WKWebExtension,
                             permissions: WebExtensionPermissionRequest) async -> WebExtensionPermissionInstallationPromptResult {
        .granted(privateDataAccess: false)
    }

    func confirmPermissions(_ permissions: WebExtensionPermissionRequest,
                            for context: WKWebExtensionContext) async -> WebExtensionPermissionPromptResult {
        .granted
    }
}
