//
//  ChromeWebStoreServiceTests.swift
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

@_spi(Testing) import Persistence
import WebKit
import XCTest
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class ChromeWebStoreServiceTests: XCTestCase {
    private let installationStore = InstalledWebExtensionStoringMock()
    private let keyValueStore = InMemoryThrowingKeyValueStore()
    private let presenter = StorePresenterMock()
    private let prompter = StorePermissionPrompter()
    private let catalog = StoreCatalogMock()
    private var permissionStore: WebExtensionPermissionStore { WebExtensionPermissionStore(keyValueStore: keyValueStore) }

    private func makeManager() throws -> WebExtensionManager {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return WebExtensionManager(configuration: WebExtensionConfigurationProvidingMock(),
                                   windowTabProvider: WebExtensionWindowTabProvidingMock(),
                                   storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory),
                                   installationStore: installationStore,
                                   permissionController: WebExtensionPermissionController(
                                    store: permissionStore, installationStore: installationStore, prompter: prompter))
    }

    private func service(_ manager: WebExtensionManager, fixture: ChromeWebStoreFixture,
                         download: (() async throws -> Data)? = nil) -> ChromeWebStoreService {
        ChromeWebStoreService(manager: manager, catalog: catalog,
                              downloader: StoreDownloaderMock(action: download ?? { fixture.package }), presenter: presenter)
    }

    func testInstallRestoreAndRemove() async throws {
        let fixture = try ChromeWebStoreFixture()
        let manager = try makeManager()
        let service = service(manager, fixture: fixture)
        XCTAssertEqual(service.status(for: fixture.identifier), .installable)
        let installed = await service.install(identifier: fixture.identifier, downloadURL: try ChromeWebStoreURL.downloadURL(for: fixture.identifier))
        XCTAssertTrue(installed, "\(presenter.errors)")
        let record = try XCTUnwrap(installationStore.installedExtensions.first)
        XCTAssertEqual(record.chromeWebStoreID, fixture.identifier)
        XCTAssertNil(record.embeddedType)
        XCTAssertNotEqual(record.uniqueIdentifier, fixture.identifier)
        XCTAssertEqual(service.status(for: fixture.identifier), .installed)
        XCTAssertEqual(prompter.installationRequests, 1)
        XCTAssertEqual(try permissionStore.settings(for: record.uniqueIdentifier)?.hasAccessToPrivateData, true)
        XCTAssertFalse(presenter.progressVisible)

        manager.unloadAllExtensions()
        await manager.reloadInstalledExtensions()
        XCTAssertEqual(manager.context(for: record.uniqueIdentifier)?.hasAccessToPrivateData, true)
        XCTAssertEqual(prompter.installationRequests, 1)
        XCTAssertEqual(self.service(manager, fixture: fixture).status(for: fixture.identifier), .installed)

        let removed = await service.remove(identifier: fixture.identifier)
        XCTAssertTrue(removed)
        XCTAssertEqual(service.status(for: fixture.identifier), .installable)
        XCTAssertTrue(installationStore.installedExtensions.isEmpty)
        XCTAssertNil(try permissionStore.settings(for: record.uniqueIdentifier))
        XCTAssertTrue(manager.loadedExtensions.isEmpty)
        XCTAssertTrue(presenter.errors.isEmpty, "\(presenter.errors)")
    }

    func testDeniedInstallationLeavesNoFilesOrSettings() async throws {
        let fixture = try ChromeWebStoreFixture()
        let manager = try makeManager()
        prompter.response = nil
        let service = service(manager, fixture: fixture)
        let success = await service.install(identifier: fixture.identifier, downloadURL: try ChromeWebStoreURL.downloadURL(for: fixture.identifier))
        XCTAssertFalse(success)
        XCTAssertTrue(installationStore.installedExtensions.isEmpty)
        XCTAssertTrue(manager.loadedExtensions.isEmpty)
        XCTAssertTrue(presenter.errors.isEmpty)
        XCTAssertFalse(presenter.progressVisible)
    }

    func testRepeatedInstallDoesNotPromptOrDuplicateRecords() async throws {
        let fixture = try ChromeWebStoreFixture()
        let manager = try makeManager()
        defer { manager.unloadAllExtensions() }
        let service = service(manager, fixture: fixture)
        for _ in 0..<2 {
            let success = await service.install(identifier: fixture.identifier, downloadURL: try ChromeWebStoreURL.downloadURL(for: fixture.identifier))
            XCTAssertTrue(success)
        }
        XCTAssertEqual(prompter.installationRequests, 1)
        XCTAssertEqual(installationStore.installedExtensions.count, 1)
    }

    func testRemovalRequiresConfirmation() async throws {
        let fixture = try ChromeWebStoreFixture()
        let manager = try makeManager()
        installationStore.add(InstalledWebExtension(uniqueIdentifier: "installed", filename: "test.zip",
                                                    name: "Test", version: "1", chromeWebStoreID: fixture.identifier))
        presenter.allowRemoval = false
        let service = service(manager, fixture: fixture)
        let removed = await service.remove(identifier: fixture.identifier)
        XCTAssertFalse(removed)
        XCTAssertEqual(service.status(for: fixture.identifier), .installed)
        XCTAssertEqual(presenter.removalRequests, ["Test"])
    }

    func testAnotherTabCannotStartAnOperationWhileConsentIsPending() async throws {
        let fixture = try ChromeWebStoreFixture()
        let manager = try makeManager()
        defer { manager.unloadAllExtensions() }
        let service = service(manager, fixture: fixture)
        let url = try ChromeWebStoreURL.downloadURL(for: fixture.identifier)
        prompter.onPrompt = {
            XCTAssertEqual(service.status(for: fixture.identifier), .installable)
            let duplicate = await service.install(identifier: fixture.identifier, downloadURL: url)
            XCTAssertFalse(duplicate)
            let removed = await service.remove(identifier: fixture.identifier)
            XCTAssertFalse(removed)
        }
        let installed = await service.install(identifier: fixture.identifier, downloadURL: url)
        XCTAssertTrue(installed)
        XCTAssertEqual(prompter.installationRequests, 1)
        XCTAssertEqual(installationStore.installedExtensions.count, 1)
    }

    func testInvalidPackageFailsBeforePermissionPrompt() async throws {
        let fixture = try ChromeWebStoreFixture()
        let manager = try makeManager()
        let service = service(manager, fixture: fixture, download: { Data("invalid".utf8) })
        let success = await service.install(identifier: fixture.identifier, downloadURL: try ChromeWebStoreURL.downloadURL(for: fixture.identifier))
        XCTAssertFalse(success)
        XCTAssertEqual(prompter.installationRequests, 0)
        XCTAssertEqual(presenter.errors.count, 1)
        XCTAssertTrue(installationStore.installedExtensions.isEmpty)
    }

    func testUnsupportedRequiredPermissionsFailBeforePrompt() async throws {
        let fixture = try ChromeWebStoreFixture(manifest: ["manifest_version": 3, "name": "Unsupported",
                                                          "description": "Unsupported fixture", "version": "1",
                                                          "permissions": ["nativeMessaging"]])
        let manager = try makeManager()
        let service = service(manager, fixture: fixture)
        let success = await service.install(identifier: fixture.identifier, downloadURL: try ChromeWebStoreURL.downloadURL(for: fixture.identifier))
        XCTAssertFalse(success)
        XCTAssertEqual(prompter.installationRequests, 0)
        XCTAssertEqual(presenter.errors.count, 1)
    }

    func testCatalogRevokedDuringDownloadPreventsInstall() async throws {
        let fixture = try ChromeWebStoreFixture()
        let manager = try makeManager()
        let service = service(manager, fixture: fixture, download: { [catalog] in
            await MainActor.run { catalog.allowed = false }
            return fixture.package
        })
        let success = await service.install(identifier: fixture.identifier, downloadURL: try ChromeWebStoreURL.downloadURL(for: fixture.identifier))
        XCTAssertFalse(success)
        XCTAssertEqual(prompter.installationRequests, 0)
        XCTAssertTrue(installationStore.installedExtensions.isEmpty)
        XCTAssertEqual(service.status(for: fixture.identifier), .unsupported)
    }

    func testCancelDownloadIsNotAnError() async throws {
        let fixture = try ChromeWebStoreFixture()
        let manager = try makeManager()
        presenter.cancelImmediately = true
        let service = service(manager, fixture: fixture, download: {
            try Task.checkCancellation()
            return fixture.package
        })
        let success = await service.install(identifier: fixture.identifier, downloadURL: try ChromeWebStoreURL.downloadURL(for: fixture.identifier))
        XCTAssertFalse(success)
        XCTAssertTrue(presenter.errors.isEmpty)
        XCTAssertEqual(prompter.installationRequests, 0)
    }

    func testUncuratedAndInvalidURLRequestsNeverDownload() async throws {
        let fixture = try ChromeWebStoreFixture()
        let manager = try makeManager()
        let service = service(manager, fixture: fixture, download: {
            XCTFail("Must not download")
            return fixture.package
        })
        let invalid = await service.install(identifier: fixture.identifier, downloadURL: try XCTUnwrap(URL(string: "https://evil.example/file")))
        XCTAssertFalse(invalid)
        catalog.allowed = false
        let uncurated = await service.install(identifier: fixture.identifier, downloadURL: try ChromeWebStoreURL.downloadURL(for: fixture.identifier))
        XCTAssertFalse(uncurated)
        XCTAssertFalse(presenter.progressVisible)
    }

    func testStoreIDCodableRoundTripAndLegacyRecord() throws {
        let record = InstalledWebExtension(uniqueIdentifier: "uuid", filename: "extension.zip", name: "Name", version: "1",
                                           chromeWebStoreID: String(repeating: "a", count: 32))
        let restored = try JSONDecoder().decode(InstalledWebExtension.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(restored.chromeWebStoreID, record.chromeWebStoreID)
        let legacy = Data(#"{"uniqueIdentifier":"uuid","filename":"extension.zip"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(InstalledWebExtension.self, from: legacy).chromeWebStoreID)
    }
}

private struct StoreDownloaderMock: ChromeWebStoreDownloading {
    let action: () async throws -> Data
    func download(extensionID: String) async throws -> Data { try await action() }
}

@MainActor
private final class StoreCatalogMock: ChromeWebStoreCatalogProviding {
    var allowed = true
    func contains(_ identifier: String) -> Bool { allowed }
}

@MainActor
private final class StorePresenterMock: ChromeWebStorePresenting {
    var errors: [Error] = []
    var removalRequests: [String] = []
    var allowRemoval = true
    var progressVisible = false
    var cancelImmediately = false

    func showDownloadProgress(cancel: @escaping () -> Void) {
        progressVisible = true
        if cancelImmediately { cancel() }
    }
    func dismissDownloadProgress() { progressVisible = false }
    func confirmRemoval(name: String) async -> Bool {
        removalRequests.append(name)
        return allowRemoval
    }
    func showError(_ error: Error) async { errors.append(error) }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class StorePermissionPrompter: WebExtensionPermissionPrompting {
    var response: Bool? = true
    var installationRequests = 0
    var onPrompt: (() async -> Void)?
    func confirmInstallation(of webExtension: WKWebExtension, permissions: WebExtensionPermissionRequest) async -> Bool? {
        installationRequests += 1
        await onPrompt?()
        return response
    }
    func confirmPermissions(_ permissions: WebExtensionPermissionRequest, for context: WKWebExtensionContext) async -> Bool { true }
}
