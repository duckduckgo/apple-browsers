//
//  WebExtensionLoaderDelegateTests.swift
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
final class WebExtensionLoaderDelegateTests: XCTestCase {

    var loader: WebExtensionLoader!
    var delegateMock: WebExtensionLoadingDelegateMock!
    var storageProvider: WebExtensionStorageProvidingMock!
    var controller: WKWebExtensionController!

    @MainActor
    override func setUp() {
        super.setUp()
        storageProvider = WebExtensionStorageProvidingMock()
        loader = WebExtensionLoader(storageProvider: storageProvider)
        delegateMock = WebExtensionLoadingDelegateMock()
        loader.delegate = delegateMock
        controller = WKWebExtensionController(configuration: .default())
    }

    override func tearDown() {
        loader = nil
        delegateMock = nil
        storageProvider = nil
        controller = nil
        super.tearDown()
    }

    @MainActor
    func testWhenExtensionLoads_ThenDelegateIsCalledBeforeLoad() async throws {
        let identifier = "test-extension-id"
        let extensionURL = try createTestWebExtension()
        storageProvider.resolvedExtensionURL = extensionURL

        try await loader.loadWebExtension(identifier: identifier, into: controller)

        XCTAssertTrue(delegateMock.willLoadCalled)
        XCTAssertEqual(delegateMock.willLoadIdentifier, identifier)
        XCTAssertNotNil(delegateMock.willLoadContext)
        XCTAssertEqual(delegateMock.willLoadContext?.uniqueIdentifier, identifier)
    }

    @MainActor
    func testWhenExtensionLoadingFails_ThenDelegateIsNotCalled() async {
        let identifier = "test-extension-id"
        storageProvider.resolvedExtensionURL = nil

        do {
            try await loader.loadWebExtension(identifier: identifier, into: controller)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertFalse(delegateMock.willLoadCalled)
        }
    }

    @MainActor
    func testWhenNoDelegateSet_ThenLoadingStillSucceeds() async throws {
        let identifier = "test-extension-id"
        let extensionURL = try createTestWebExtension()
        storageProvider.resolvedExtensionURL = extensionURL
        loader.delegate = nil

        let result = try await loader.loadWebExtension(identifier: identifier, into: controller)

        XCTAssertEqual(result.identifier, identifier)
        XCTAssertFalse(result.filename.isEmpty)
        XCTAssertEqual(result.displayName, "Test Extension")
        XCTAssertEqual(result.version, "1.0.0")
    }

    // MARK: - isInspectable Tests

    @MainActor
    func testWhenIsInspectableTrue_ThenContextIsInspectable() async throws {
        let inspectableLoader = WebExtensionLoader(storageProvider: storageProvider, isInspectable: true)
        inspectableLoader.delegate = delegateMock
        let identifier = "test-extension-id"
        let extensionURL = try createTestWebExtension()
        storageProvider.resolvedExtensionURL = extensionURL

        try await inspectableLoader.loadWebExtension(identifier: identifier, into: controller)

        XCTAssertTrue(delegateMock.willLoadCalled)
        XCTAssertNotNil(delegateMock.willLoadContext)
        XCTAssertTrue(delegateMock.willLoadContext?.isInspectable == true)
    }

    @MainActor
    func testWhenIsInspectableFalse_ThenContextIsNotInspectable() async throws {
        let nonInspectableLoader = WebExtensionLoader(storageProvider: storageProvider, isInspectable: false)
        nonInspectableLoader.delegate = delegateMock
        let identifier = "test-extension-id"
        let extensionURL = try createTestWebExtension()
        storageProvider.resolvedExtensionURL = extensionURL

        try await nonInspectableLoader.loadWebExtension(identifier: identifier, into: controller)

        XCTAssertTrue(delegateMock.willLoadCalled)
        XCTAssertNotNil(delegateMock.willLoadContext)
        XCTAssertFalse(delegateMock.willLoadContext?.isInspectable == true)
    }

    @MainActor
    func testDefaultIsInspectableIsFalse() async throws {
        let identifier = "test-extension-id"
        let extensionURL = try createTestWebExtension()
        storageProvider.resolvedExtensionURL = extensionURL

        try await loader.loadWebExtension(identifier: identifier, into: controller)

        XCTAssertTrue(delegateMock.willLoadCalled)
        XCTAssertNotNil(delegateMock.willLoadContext)
        XCTAssertFalse(delegateMock.willLoadContext?.isInspectable == true)
    }

    // MARK: - Permission Granting Tests

    @MainActor
    func testWhenExtensionLoads_ThenRequestedPermissionsAreGranted() async throws {
        let identifier = "test-extension-id"
        let extensionURL = try createTestWebExtensionWithPermissions(
            permissions: ["storage", "tabs"]
        )
        storageProvider.resolvedExtensionURL = extensionURL

        try await loader.loadWebExtension(identifier: identifier, into: controller)

        XCTAssertNotNil(delegateMock.willLoadContext)
        let context = delegateMock.willLoadContext!

        let storagePermission = WKWebExtension.Permission("storage")
        let tabsPermission = WKWebExtension.Permission("tabs")

        XCTAssertEqual(context.permissionStatus(for: storagePermission), .grantedExplicitly)
        XCTAssertEqual(context.permissionStatus(for: tabsPermission), .grantedExplicitly)
    }

    @MainActor
    func testWhenExtensionLoads_ThenMatchPatternsAreGranted() async throws {
        let identifier = "test-extension-id"
        let extensionURL = try createTestWebExtensionWithPermissions(
            hostPermissions: ["https://example.com/*", "https://duckduckgo.com/*"]
        )
        storageProvider.resolvedExtensionURL = extensionURL

        try await loader.loadWebExtension(identifier: identifier, into: controller)

        XCTAssertNotNil(delegateMock.willLoadContext)
        let context = delegateMock.willLoadContext!

        let examplePattern = try WKWebExtension.MatchPattern(string: "https://example.com/*")
        let ddgPattern = try WKWebExtension.MatchPattern(string: "https://duckduckgo.com/*")

        XCTAssertEqual(context.permissionStatus(for: examplePattern), .grantedExplicitly)
        XCTAssertEqual(context.permissionStatus(for: ddgPattern), .grantedExplicitly)
    }

    @MainActor
    func testWhenExtensionHasNoPermissions_ThenNoPermissionsAreGranted() async throws {
        let identifier = "test-extension-id"
        let extensionURL = try createTestWebExtension()
        storageProvider.resolvedExtensionURL = extensionURL

        try await loader.loadWebExtension(identifier: identifier, into: controller)

        XCTAssertNotNil(delegateMock.willLoadContext)
        let context = delegateMock.willLoadContext!

        let storagePermission = WKWebExtension.Permission("storage")
        XCTAssertNotEqual(context.permissionStatus(for: storagePermission), .grantedExplicitly)
    }

    // MARK: - Test Helpers

    private func createTestWebExtension() throws -> URL {
        return try createTestWebExtensionWithPermissions()
    }

    private func createTestWebExtensionWithPermissions(
        permissions: [String] = [],
        hostPermissions: [String] = []
    ) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let extensionDir = tempDir.appendingPathComponent("TestExtension-\(UUID().uuidString)")

        let permissionsJSON = permissions.isEmpty ? "" : """
            "permissions": [\(permissions.map { "\"\($0)\"" }.joined(separator: ", "))],
        """

        let hostPermissionsJSON = hostPermissions.isEmpty ? "" : """
            "host_permissions": [\(hostPermissions.map { "\"\($0)\"" }.joined(separator: ", "))],
        """

        let manifest = """
        {
            "manifest_version": 3,
            "name": "Test Extension",
            "version": "1.0.0",
            \(permissionsJSON)
            \(hostPermissionsJSON)
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

// MARK: - Mock Delegate

@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionLoadingDelegateMock: WebExtensionLoadingDelegate {

    var willLoadCalled = false
    var willLoadContext: WKWebExtensionContext?
    var willLoadIdentifier: String?

    func webExtensionLoader(_ loader: WebExtensionLoading,
                            willLoad context: WKWebExtensionContext,
                            identifier: String) {
        willLoadCalled = true
        willLoadContext = context
        willLoadIdentifier = identifier
    }
}
