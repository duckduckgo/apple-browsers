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
@_spi(Testing) import Persistence
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

    @MainActor
    func testRequiredProtocolActivationGateRunsAfterDelegateAndBeforeNativeLoad() async throws {
        let native = NativeActivationCountingController(configuration: .nonPersistent())
        storageProvider.resolvedExtensionURL = try createTestWebExtension()
        var allowed = true
        delegateMock.onWillLoad = { _ in allowed = false }
        let loading: any WebExtensionLoading = loader

        do {
            _ = try await loading.loadWebExtension(identifier: UUID().uuidString, into: native, beforeActivation: { _ in
                guard allowed else { throw ActivationGateError.revoked }
            })
            XCTFail("The delegate revoked activation before native loading")
        } catch ActivationGateError.revoked { }

        XCTAssertTrue(delegateMock.willLoadCalled)
        XCTAssertEqual(native.activationCount, 0)
        XCTAssertTrue(native.extensionContexts.isEmpty)
    }

    @MainActor
    func testFirstActivationGateRejectsBeforePermissionPreparationCanPrompt() async throws {
        let native = NativeActivationCountingController(configuration: .nonPersistent())
        let store = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        let permissions = WebExtensionPermissionController(store: store, installationStore: InstalledWebExtensionStoringMock(), prompter: ActivationNoPrompt())
        let guardedLoader = WebExtensionLoader(storageProvider: storageProvider, permissionController: permissions)
        guardedLoader.delegate = delegateMock
        storageProvider.resolvedExtensionURL = try createTestWebExtension()

        do {
            _ = try await guardedLoader.loadWebExtension(identifier: UUID().uuidString, into: native, beforeActivation: { _ in throw ActivationGateError.revoked })
            XCTFail("Rejected parsing result must not prepare or prompt")
        } catch ActivationGateError.revoked { }

        XCTAssertFalse(delegateMock.willLoadCalled)
        XCTAssertEqual(native.activationCount, 0)
        XCTAssertTrue(native.extensionContexts.isEmpty)
    }

    @MainActor
    func testRejectedIdempotentLoadKeepsTheExistingContextAndDoesNotBypassItsGate() async throws {
        let native = NativeActivationCountingController(configuration: .nonPersistent())
        let identifier = UUID().uuidString
        storageProvider.resolvedExtensionURL = try createTestWebExtension()
        _ = try await loader.loadWebExtension(identifier: identifier, into: native)
        let original = try XCTUnwrap(native.extensionContexts.first)

        do {
            _ = try await loader.loadWebExtension(identifier: identifier, into: native, beforeActivation: { _ in throw ActivationGateError.revoked })
            XCTFail("An existing context must not bypass eligibility validation")
        } catch ActivationGateError.revoked { }

        XCTAssertEqual(native.activationCount, 1)
        XCTAssertTrue(native.extensionContexts.first === original)
        try loader.unloadExtension(identifier: identifier, from: native)
    }

    @MainActor
    func testRejectedPreparationNeverRecreatesConsentRemovedByDelegate() async throws {
        let native = NativeActivationCountingController(configuration: .nonPersistent())
        let identifier = UUID().uuidString
        let store = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        var approved = WebExtensionPermissionSettings()
        approved.grantedPermissions["storage"] = .distantFuture
        try store.save(approved, for: identifier)
        let permissions = WebExtensionPermissionController(store: store, installationStore: InstalledWebExtensionStoringMock(), prompter: ActivationNoPrompt())
        permissions.beginUpdate(for: identifier)
        defer { permissions.endUpdate(for: identifier) }
        let guardedLoader = WebExtensionLoader(storageProvider: storageProvider, permissionController: permissions)
        guardedLoader.delegate = delegateMock
        storageProvider.resolvedExtensionURL = try createTestWebExtensionWithPermissions(permissions: ["storage"])
        delegateMock.onWillLoad = { context in
            do { try store.removeSettings(for: identifier) } catch { XCTFail("\(error)") }
            // Unload-style persistence would recreate the removed record because this differs from the saved snapshot.
            context.hasAccessToPrivateData = true
        }

        do {
            _ = try await guardedLoader.loadWebExtension(identifier: identifier, into: native, beforeActivation: { parsed in
                guard permissions.canActivateUpdate(parsed, for: identifier) else { throw ActivationGateError.revoked }
            })
            XCTFail("Removed consent must reject activation")
        } catch ActivationGateError.revoked { }

        XCTAssertEqual(native.activationCount, 0)
        XCTAssertTrue(native.extensionContexts.isEmpty)
        XCTAssertNil(try store.settings(for: identifier))
        if let aborted = delegateMock.willLoadContext {
            NotificationCenter.default.post(name: WKWebExtensionContext.permissionsWereGrantedNotification, object: aborted)
        }
        XCTAssertNil(try store.settings(for: identifier), "Late notifications from the aborted context must not restore removed consent")
    }

    @MainActor
    func testNormalUnloadStillPersistsChangedConsentAfterSuccessfulActivation() async throws {
        let native = NativeActivationCountingController(configuration: .nonPersistent())
        let identifier = UUID().uuidString
        let store = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try store.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: store, installationStore: InstalledWebExtensionStoringMock(), prompter: ActivationNoPrompt())
        let guardedLoader = WebExtensionLoader(storageProvider: storageProvider, permissionController: permissions)
        storageProvider.resolvedExtensionURL = try createTestWebExtension()
        _ = try await guardedLoader.loadWebExtension(identifier: identifier, into: native)
        let context = try XCTUnwrap(native.extensionContexts.first)
        context.hasAccessToPrivateData = true

        try guardedLoader.unloadExtension(identifier: identifier, from: native)

        XCTAssertEqual(try store.settings(for: identifier)?.hasAccessToPrivateData, true)
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
    var onWillLoad: (@MainActor (WKWebExtensionContext) -> Void)?

    func webExtensionLoader(_ loader: WebExtensionLoading,
                            willLoad context: WKWebExtensionContext,
                            identifier: String) {
        willLoadCalled = true
        willLoadContext = context
        willLoadIdentifier = identifier
        MainActor.assumeIsolated { onWillLoad?(context) }
    }
}

private enum ActivationGateError: Error { case revoked }

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class NativeActivationCountingController: WKWebExtensionController {
    private(set) var activationCount = 0
    override func load(_ extensionContext: WKWebExtensionContext) throws {
        activationCount += 1
        try super.load(extensionContext)
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private struct ActivationNoPrompt: WebExtensionPermissionPrompting {
    func confirmInstallation(of webExtension: WKWebExtension, permissions: WebExtensionPermissionRequest) async -> WebExtensionPermissionInstallationPromptResult {
        XCTFail("Rejected or restore-only activation must never prompt")
        return .denied
    }
    func confirmPermissions(_ permissions: WebExtensionPermissionRequest, for context: WKWebExtensionContext) async -> WebExtensionPermissionPromptResult {
        XCTFail("Activation must not request new access")
        return .denied
    }
}
