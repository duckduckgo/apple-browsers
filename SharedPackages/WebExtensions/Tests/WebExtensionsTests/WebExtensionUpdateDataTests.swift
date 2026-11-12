//
//  WebExtensionUpdateDataTests.swift
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

#if os(macOS)
@_spi(Testing) import Persistence
import WebKit
import XCTest
@testable import WebExtensions

/// Exercises WebKit's actual persistent stores through the production loader and worker patcher.
@available(macOS 15.4, *)
@MainActor
final class WebExtensionUpdateDataTests: XCTestCase {
    private let installationID = UUID().uuidString
    private let configurationID = UUID()
    private let websiteDataID = UUID()
    private let keyValueStore = InMemoryThrowingKeyValueStore()
    private let installationStore = InstalledWebExtensionStoringMock()
    private let navigation = NavigationObserver()
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        let controller = makeController()
        let types = WKWebExtensionController.allExtensionDataTypes
        let records = await controller.dataRecords(ofTypes: types)
        await controller.removeData(ofTypes: types, from: records)
        await WKWebsiteDataStore(forIdentifier: websiteDataID).removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        try FileManager.default.removeItem(at: directory)
    }

    func testSameIdentityPreservesDataAcrossReplacementAndControllerRecreation() async throws {
        let store = WebExtensionPermissionStore(keyValueStore: keyValueStore)
        var approved = WebExtensionPermissionSettings()
        approved.grantedPermissions = ["storage": .distantFuture]
        approved.hasAccessToPrivateData = true
        try store.save(approved, for: installationID)
        try writeFixture(version: "1.0")
        var controller = makeController()
        var loader = makeLoader(store: store)
        let before = try await readGeneration(controller: controller, loader: loader, version: "1.0", seed: true)

        try loader.unloadExtension(identifier: installationID, from: controller)
        try writeFixture(version: "2.0")
        let after = try await readGeneration(controller: controller, loader: loader, version: "2.0")
        assertPreserved(before, after)

        try loader.unloadExtension(identifier: installationID, from: controller)
        weak var previousController = controller
        controller = makeController()
        loader = makeLoader(store: store)
        XCTAssertNil(previousController, "The relaunch probe must release its old controller and views")
        assertPreserved(before, try await readGeneration(controller: controller, loader: loader, version: "2.0"))
        XCTAssertEqual(try store.settings(for: installationID), approved)
        try loader.unloadExtension(identifier: installationID, from: controller)
    }

    func testSameIdentityPreservesDataFromFlatToVersionedPackagesAndControllerRecreation() async throws {
        let store = WebExtensionPermissionStore(keyValueStore: keyValueStore)
        var approved = WebExtensionPermissionSettings()
        approved.grantedPermissions = ["storage": .distantFuture]
        approved.hasAccessToPrivateData = true
        try store.save(approved, for: installationID)
        let installed = InstalledWebExtension(uniqueIdentifier: installationID, filename: installationID, name: "Update data fixture", version: "1.0",
                                              storeIdentity: .init(store: .chromeWebStore, id: ChromeWebStoreID.bitwarden.rawValue))
        installationStore.add(installed)
        try writeFixture(version: "1.0")
        var controller = makeController()
        var loader = makeLoader(store: store)
        let before = try await readGeneration(controller: controller, loader: loader, version: "1.0", seed: true)

        for version in ["2.0", "3.0"] {
            try loader.unloadExtension(identifier: installationID, from: controller)
            let replacement = InstalledWebExtension(uniqueIdentifier: installationID, filename: installationID, name: installed.name, version: version,
                                                    storeIdentity: installed.storeIdentity, packageIdentifier: UUID())
            try writeFixture(version: version, resourceIdentifier: replacement.resourceIdentifier)
            installationStore.update(replacement)
            loader = makeLoader(store: store)
            assertPreserved(before, try await readGeneration(controller: controller, loader: loader, version: version))
        }

        try loader.unloadExtension(identifier: installationID, from: controller)
        let selected = try XCTUnwrap(installationStore.installedExtensions.first?.packageIdentifier)
        let packages = WebExtensionUpdatePackageStore(extensionsDirectory: directory)
        await packages.cleanup(activatedPackages: [installationID: selected])
        let installation = directory.appendingPathComponent(installationID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installation.appendingPathComponent("manifest.json").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: installation.appendingPathComponent("versions").path), [selected.uuidString])
        weak var previousController = controller
        controller = makeController()
        loader = makeLoader(store: store)
        XCTAssertNil(previousController, "The relaunch probe must release its old controller and views")
        assertPreserved(before, try await readGeneration(controller: controller, loader: loader, version: "3.0"))
        XCTAssertEqual(try store.settings(for: installationID), approved)
        try loader.unloadExtension(identifier: installationID, from: controller)
    }

    private func makeController() -> WKWebExtensionController {
        let configuration = WKWebExtensionController.Configuration(identifier: configurationID)
        configuration.defaultWebsiteDataStore = WKWebsiteDataStore(forIdentifier: websiteDataID)
        return WKWebExtensionController(configuration: configuration)
    }

    private func makeLoader(store: WebExtensionPermissionStore) -> WebExtensionLoader {
        let permissions = WebExtensionPermissionController(store: store, installationStore: installationStore, prompter: UnexpectedPrompt())
        return WebExtensionLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions, installationStore: installationStore)
    }

    private func writeFixture(version: String, resourceIdentifier: String? = nil) throws {
        let folder = directory.appendingPathComponent(resourceIdentifier ?? installationID)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Update data fixture", "version": version,
                                      "permissions": ["storage"], "background": ["service_worker": "worker.js"]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
        try "<!doctype html><title>Update data fixture</title>".write(to: folder.appendingPathComponent("probe.html"), atomically: true, encoding: .utf8)
        try "// Intentionally empty background worker.".write(to: folder.appendingPathComponent("worker.js"), atomically: true, encoding: .utf8)
    }

    private func loadPage(controller: WKWebExtensionController, loader: WebExtensionLoader) async throws -> WKWebView {
        try await loader.loadWebExtension(identifier: installationID, into: controller)
        let context = try XCTUnwrap(controller.extensionContexts.first)
        try await context.loadBackgroundContent()
        let configuration = try XCTUnwrap(context.webViewConfiguration)
        let page = WKWebView(frame: .zero, configuration: configuration)
        page.navigationDelegate = navigation
        let loaded = expectation(description: "extension page loads")
        navigation.onFinish = { loaded.fulfill() }
        page.load(URLRequest(url: context.baseURL.appendingPathComponent("probe.html")))
        await fulfillment(of: [loaded], timeout: 10)
        return page
    }

    private func readGeneration(controller: WKWebExtensionController, loader: WebExtensionLoader, version: String, seed: Bool = false) async throws -> [String: String] {
        let page = try await loadPage(controller: controller, loader: loader)
        let context = try XCTUnwrap(controller.extensionContexts.first)
        XCTAssertEqual(context.grantedPermissions[.storage], .distantFuture)
        XCTAssertTrue(context.hasAccessToPrivateData)
        let result = try await snapshot(page, seed: seed)
        XCTAssertEqual(result["version"], version)
        XCTAssertEqual(result["origin"], context.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        return result
    }

    private func snapshot(_ page: WKWebView, seed: Bool = false) async throws -> [String: String] {
        let result = try await page.callAsyncJavaScript("""
            const request = indexedDB.open('update-probe', 1);
            const db = await new Promise((resolve, reject) => {
                request.onupgradeneeded = () => request.result.createObjectStore('values');
                request.onsuccess = () => resolve(request.result);
                request.onerror = () => reject(request.error);
            });
            if (seed) {
                await chrome.storage.local.set({ token: 'storage-token' });
                localStorage.setItem('token', 'local-token');
                await new Promise((resolve, reject) => {
                    const tx = db.transaction('values', 'readwrite');
                    tx.objectStore('values').put('indexed-token', 'token');
                    tx.oncomplete = resolve; tx.onerror = () => reject(tx.error);
                });
            }
            const indexed = await new Promise((resolve, reject) => {
                const query = db.transaction('values').objectStore('values').get('token');
                query.onsuccess = () => resolve(query.result); query.onerror = () => reject(query.error);
            });
            db.close();
            const stored = await chrome.storage.local.get('token');
            return { id: chrome.runtime.id, origin: location.origin, version: chrome.runtime.getManifest().version,
                     storage: stored.token || '', local: localStorage.getItem('token') || '', indexed: indexed || '' };
            """, arguments: ["seed": seed], contentWorld: .page)
        return try XCTUnwrap(result as? [String: String])
    }

    private func assertPreserved(_ before: [String: String], _ after: [String: String], file: StaticString = #filePath, line: UInt = #line) {
        for key in ["id", "storage", "local", "indexed"] {
            XCTAssertEqual(after[key], before[key], key, file: file, line: line)
        }
        XCTAssertEqual(after["storage"], "storage-token", file: file, line: line)
        XCTAssertEqual(after["local"], "local-token", file: file, line: line)
        XCTAssertEqual(after["indexed"], "indexed-token", file: file, line: line)
        print("Update data probe: \(before) -> \(after)")
    }
}

@available(macOS 15.4, *)
@MainActor
private final class NavigationObserver: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish?() }
}

@available(macOS 15.4, *)
@MainActor
private struct UnexpectedPrompt: WebExtensionPermissionPrompting {
    func confirmInstallation(of webExtension: WKWebExtension, permissions: WebExtensionPermissionRequest) async -> WebExtensionPermissionInstallationPromptResult {
        XCTFail("An update must restore consent without prompting")
        return .denied
    }
    func confirmPermissions(_ permissions: WebExtensionPermissionRequest, for context: WKWebExtensionContext) async -> WebExtensionPermissionPromptResult {
        XCTFail("An update must not request permissions")
        return .denied
    }
}
#endif
