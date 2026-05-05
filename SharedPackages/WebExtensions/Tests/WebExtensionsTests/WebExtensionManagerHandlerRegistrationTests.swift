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
    private func makeManager() -> WebExtensionManager {
        WebExtensionManager(
            configuration: configurationMock,
            windowTabProvider: windowTabProviderMock,
            storageProvider: storageProvidingMock,
            installationStore: installedExtensionStoringMock,
            loader: webExtensionLoadingMock,
            messageRouter: messageRouter,
            handlerProvider: handlerProvider
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
    func testWhenExtensionIsInstalled_ThenHandlersAreRegistered() async throws {
        let manager = makeManager()
        let sourceURL = try createTestWebExtension()

        try await manager.installExtension(from: sourceURL)

        XCTAssertTrue(handlerProvider.makeHandlersCalled)
        XCTAssertTrue(messageRouter.registerHandlerCalled)
        XCTAssertEqual(messageRouter.registeredHandlers.count, 1)
    }

    @MainActor
    func testWhenExtensionIsLoaded_ThenHandlersAreRegisteredBeforeLoad() async throws {
        let manager = makeManager()
        let sourceURL = try createTestWebExtension()

        try await manager.installExtension(from: sourceURL)

        XCTAssertTrue(handlerProvider.makeHandlersCalled)
        XCTAssertTrue(messageRouter.registerHandlerCalled)
        XCTAssertTrue(webExtensionLoadingMock.loadWebExtensionCalled)
    }

    // MARK: - Test Helpers

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

    func makeHandlers(for context: WKWebExtensionContext) -> [WebExtensionMessageHandler] {
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
