//
//  CPMExtensionBaseURLTests.swift
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
import WebKit
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMExtensionBaseURLTests: XCTestCase {
    private let identifier = "A4D1228D-90A2-4B27-B7ED-D7A493B9B54E"

    func testReloadAndNewLoaderKeepInstalledCPMOrigin() async throws {
        let store = registry()
        let policy = CPMExtensionBaseURLPolicy(installationStore: store, isEnabled: { true })
        let storage = WebExtensionStorageProvidingMock()
        storage.resolvedExtensionURL = try extensionDirectory()
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        let loader = WebExtensionLoader(storageProvider: storage, baseURLProvider: policy.baseURL)
        try await loader.loadWebExtension(identifier: identifier, into: controller)
        let initial = try XCTUnwrap(controller.extensionContexts.first)
        XCTAssertEqual(initial.baseURL.absoluteString, "webkit-extension://\(identifier.lowercased())/")
        try loader.unloadExtension(identifier: identifier, from: controller)
        try await loader.reloadWebExtension(initial.webExtension, identifier: identifier, into: controller)
        let reloaded = try XCTUnwrap(controller.extensionContexts.first)
        XCTAssertEqual(reloaded.baseURL, initial.baseURL)
        XCTAssertFalse(reloaded === initial)
        try loader.unloadExtension(identifier: identifier, from: controller)
        let restoredPolicy = CPMExtensionBaseURLPolicy(installationStore: store, isEnabled: { true })
        let nextLoader = WebExtensionLoader(storageProvider: storage, baseURLProvider: restoredPolicy.baseURL)
        try await nextLoader.loadWebExtension(identifier: identifier, into: controller)
        XCTAssertEqual(controller.extensionContexts.first?.baseURL, initial.baseURL)
        try nextLoader.unloadExtension(identifier: identifier, from: controller)
    }

    func testRuntimeDisableAndReenableApplyAtNextContextCreation() async throws {
        var enabled = true
        let policy = CPMExtensionBaseURLPolicy(installationStore: registry(), isEnabled: { enabled })
        let storage = WebExtensionStorageProvidingMock()
        storage.resolvedExtensionURL = try extensionDirectory()
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        let loader = WebExtensionLoader(storageProvider: storage, baseURLProvider: policy.baseURL)
        try await loader.loadWebExtension(identifier: identifier, into: controller)
        let initial = try XCTUnwrap(controller.extensionContexts.first)
        enabled = false
        // A runtime toggle never changes a live context's origin.
        XCTAssertEqual(initial.baseURL.absoluteString, "webkit-extension://\(identifier.lowercased())/")
        try loader.unloadExtension(identifier: identifier, from: controller)
        try await loader.reloadWebExtension(initial.webExtension, identifier: identifier, into: controller)
        let disabled = try XCTUnwrap(controller.extensionContexts.first)
        XCTAssertNotEqual(disabled.baseURL, initial.baseURL)
        try loader.unloadExtension(identifier: identifier, from: controller)
        enabled = true
        try await loader.reloadWebExtension(initial.webExtension, identifier: identifier, into: controller)
        let restored = try XCTUnwrap(controller.extensionContexts.first)
        XCTAssertNotEqual(restored.baseURL, initial.baseURL)
        let origin = try XCTUnwrap(policy.baseURL(for: identifier, webExtension: initial.webExtension))
        XCTAssertEqual(restored.baseURL, origin)
        try loader.unloadExtension(identifier: identifier, from: controller)
    }

    func testDisabledPolicyPreservesRandomOriginsOnReload() async throws {
        let policy = CPMExtensionBaseURLPolicy(installationStore: registry(), isEnabled: { false })
        let storage = WebExtensionStorageProvidingMock()
        storage.resolvedExtensionURL = try extensionDirectory()
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        let loader = WebExtensionLoader(storageProvider: storage, baseURLProvider: policy.baseURL)
        try await loader.loadWebExtension(identifier: identifier, into: controller)
        let initial = try XCTUnwrap(controller.extensionContexts.first)
        try loader.unloadExtension(identifier: identifier, from: controller)
        try await loader.reloadWebExtension(initial.webExtension, identifier: identifier, into: controller)
        XCTAssertNotEqual(controller.extensionContexts.first?.baseURL, initial.baseURL)
        try loader.unloadExtension(identifier: identifier, from: controller)
    }

    func testManifestClaimAloneDoesNotStabilizeUntrustedInstallation() async throws {
        let policy = CPMExtensionBaseURLPolicy(installationStore: registry(type: nil), isEnabled: { true })
        let webExtension = try await webExtension()
        XCTAssertNil(policy.baseURL(for: identifier, webExtension: webExtension))
    }

    func testFirstBundledInstallIsEligibleBeforeRegistryWrite() async throws {
        let store = InstalledWebExtensionStoringMock()
        let policy = CPMExtensionBaseURLPolicy(installationStore: store, isEnabled: { true })
        let webExtension = try await webExtension()
        policy.pendingInstallations[identifier] = .embedded
        XCTAssertNotNil(policy.baseURL(for: identifier, webExtension: webExtension))
        policy.pendingInstallations[identifier] = nil
        XCTAssertNil(policy.baseURL(for: identifier, webExtension: webExtension))
        store.add(installed())
        XCTAssertNotNil(policy.baseURL(for: identifier, webExtension: webExtension))
    }

    func testOtherBundledTypesKeepTheirOriginalPolicy() async throws {
        let webExtension = try await webExtension()
        for type in DuckDuckGoWebExtensionType.allCases where type != .embedded {
            let policy = CPMExtensionBaseURLPolicy(installationStore: registry(type: type), isEnabled: { true })
            XCTAssertNil(policy.baseURL(for: identifier, webExtension: webExtension), type.rawValue)
        }
    }

    func testNonCPMManifestIsRejectedEvenWithTrustedRegistryEntry() async throws {
        let policy = CPMExtensionBaseURLPolicy(installationStore: registry(), isEnabled: { true })
        let webExtension = try await webExtension(type: .darkReader)
        XCTAssertNil(policy.baseURL(for: identifier, webExtension: webExtension))
    }

    func testWebAccessibleResourcesAndMalformedDeclarationsKeepRandomOrigins() async throws {
        let policy = CPMExtensionBaseURLPolicy(installationStore: registry(), isEnabled: { true })
        for resources: Any in [["exposed.js"], [["resources": ["exposed.js"], "matches": ["<all_urls>"]]], "malformed", NSNull()] {
            let webExtension = try await webExtension(resources: resources)
            XCTAssertNil(policy.baseURL(for: identifier, webExtension: webExtension))
        }
    }

    func testEmptyWebAccessibleResourcesRemainEligible() async throws {
        let policy = CPMExtensionBaseURLPolicy(installationStore: registry(), isEnabled: { true })
        let webExtension = try await webExtension(resources: [Any]())
        XCTAssertNotNil(policy.baseURL(for: identifier, webExtension: webExtension))
    }

    func testInvalidIdentifierFallsBackWithoutThrowing() async throws {
        let policy = CPMExtensionBaseURLPolicy(installationStore: InstalledWebExtensionStoringMock(), isEnabled: { true })
        let webExtension = try await webExtension()
        for identifier in ["", "invalid/id", "example.com", "user:pass@host", "..", "../other"] {
            policy.pendingInstallations[identifier] = .embedded
            XCTAssertNil(policy.baseURL(for: identifier, webExtension: webExtension))
        }
    }

    func testDifferentInstallationsNeverShareAnOrigin() async throws {
        let policy = CPMExtensionBaseURLPolicy(installationStore: registry(), isEnabled: { true })
        let otherIdentifier = UUID().uuidString
        policy.pendingInstallations[otherIdentifier] = .embedded
        let webExtension = try await webExtension()
        XCTAssertNotEqual(policy.baseURL(for: identifier, webExtension: webExtension),
                          policy.baseURL(for: otherIdentifier, webExtension: webExtension))
    }

    func testDataClearRotatesOriginAndNewPolicyRestoresIt() async throws {
        let store = registry()
        let policy = CPMExtensionBaseURLPolicy(installationStore: store, isEnabled: { true })
        let webExtension = try await webExtension()
        let initial = try XCTUnwrap(policy.baseURL(for: identifier, webExtension: webExtension))
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = identifier
        policy.prepareForDataClearingReload(of: context)
        let rotated = try XCTUnwrap(policy.baseURL(for: identifier, webExtension: webExtension))
        XCTAssertNotEqual(rotated, initial)
        let decoded = try JSONDecoder().decode(InstalledWebExtension.self, from: JSONEncoder().encode(store.installedExtensions[0]))
        let restoredStore = InstalledWebExtensionStoringMock()
        restoredStore.add(decoded)
        let restored = CPMExtensionBaseURLPolicy(installationStore: restoredStore, isEnabled: { true })
        XCTAssertEqual(restored.baseURL(for: identifier, webExtension: webExtension), rotated)
        XCTAssertEqual(decoded.filename, store.installedExtensions[0].filename)
        XCTAssertEqual(decoded.embeddedType, .embedded)
    }

    func testDataClearWhileFlagDisabledPreparesSafeOriginForReenable() async throws {
        var enabled = false
        let policy = CPMExtensionBaseURLPolicy(installationStore: registry(), isEnabled: { enabled })
        let webExtension = try await webExtension()
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = identifier
        policy.prepareForDataClearingReload(of: context)
        XCTAssertNil(policy.baseURL(for: identifier, webExtension: webExtension))
        enabled = true
        let restored = try XCTUnwrap(policy.baseURL(for: identifier, webExtension: webExtension))
        XCTAssertNotEqual(restored.host, identifier.lowercased())
    }

    func testFailedBackgroundReloadRotatesAndPersistsOrigin() async throws {
        let store = registry()
        let policy = CPMExtensionBaseURLPolicy(installationStore: store, isEnabled: { true })
        let webExtension = try await webExtension()
        let initial = try XCTUnwrap(policy.baseURL(for: identifier, webExtension: webExtension))
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = identifier
        policy.prepareForBackgroundFailureReload(of: context, errors: [NSError(domain: WKWebExtensionContext.errorDomain, code: 6)])
        let replacement = try XCTUnwrap(policy.baseURL(for: identifier, webExtension: webExtension))
        XCTAssertNotEqual(replacement, initial)
        let restored = CPMExtensionBaseURLPolicy(installationStore: store, isEnabled: { true })
        XCTAssertEqual(restored.baseURL(for: identifier, webExtension: webExtension), replacement)
        XCTAssertEqual(store.installedExtensions.first?.uniqueIdentifier, identifier)
    }

    func testHealthyReloadAndUnrelatedErrorsKeepOrigin() async throws {
        let policy = CPMExtensionBaseURLPolicy(installationStore: registry(), isEnabled: { true })
        let webExtension = try await webExtension()
        let initial = try XCTUnwrap(policy.baseURL(for: identifier, webExtension: webExtension))
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = identifier
        for errors: [Error] in [[], [NSError(domain: "other", code: 6)], [NSError(domain: WKWebExtensionContext.errorDomain, code: 1)]] {
            policy.prepareForBackgroundFailureReload(of: context, errors: errors)
            XCTAssertEqual(policy.baseURL(for: identifier, webExtension: webExtension), initial)
        }
    }

    func testBackgroundFailureRotationHonorsRuntimeKillSwitch() async throws {
        var enabled = true
        let store = registry()
        let policy = CPMExtensionBaseURLPolicy(installationStore: store, isEnabled: { enabled })
        let webExtension = try await webExtension()
        let initial = try XCTUnwrap(policy.baseURL(for: identifier, webExtension: webExtension))
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = identifier
        enabled = false
        policy.prepareForBackgroundFailureReload(of: context, errors: [NSError(domain: WKWebExtensionContext.errorDomain, code: 6)])
        XCTAssertNil(store.installedExtensions.first?.cpmOriginIdentifier)
        enabled = true
        XCTAssertEqual(policy.baseURL(for: identifier, webExtension: webExtension), initial)
    }

    func testBackgroundFailureDoesNotRotateUntrustedOrigin() async throws {
        let store = registry(type: nil)
        let policy = CPMExtensionBaseURLPolicy(installationStore: store, isEnabled: { true })
        let context = WKWebExtensionContext(for: try await webExtension())
        context.uniqueIdentifier = identifier
        policy.prepareForBackgroundFailureReload(of: context, errors: [NSError(domain: WKWebExtensionContext.errorDomain, code: 6)])
        XCTAssertNil(store.installedExtensions.first?.cpmOriginIdentifier)
    }

    func testLegacyRegistryRecordStillDecodesWithoutOriginIdentifier() throws {
        let record = installed()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        object.removeValue(forKey: "cpmOriginIdentifier")
        let decoded = try JSONDecoder().decode(InstalledWebExtension.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.cpmOriginIdentifier)
        XCTAssertEqual(decoded.uniqueIdentifier, record.uniqueIdentifier)
        XCTAssertEqual(decoded.embeddedType, .embedded)
    }

    private func installed(type: DuckDuckGoWebExtensionType? = .embedded) -> InstalledWebExtension {
        InstalledWebExtension(uniqueIdentifier: identifier, filename: "test", name: "CPM", version: "1", embeddedType: type)
    }

    private func registry(type: DuckDuckGoWebExtensionType? = .embedded) -> InstalledWebExtensionStoringMock {
        let store = InstalledWebExtensionStoringMock()
        store.add(installed(type: type))
        return store
    }

    private func webExtension(type: DuckDuckGoWebExtensionType = .embedded, resources: Any? = nil) async throws -> WKWebExtension {
        try await WKWebExtension.makeCopyingErrors(at: extensionDirectory(type: type, resources: resources))
    }

    private func extensionDirectory(type: DuckDuckGoWebExtensionType = .embedded, resources: Any? = nil) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var manifest: [String: Any] = ["manifest_version": 3, "name": "CPM", "version": "1.0",
                                      "browser_specific_settings": ["duckduckgo": ["id": type.rawValue]]]
        manifest["web_accessible_resources"] = resources
        try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("manifest.json"))
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}
