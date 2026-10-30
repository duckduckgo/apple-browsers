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
import PrivacyConfig
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
                              downloader: StoreDownloaderMock(action: download ?? { fixture.package }), presenter: presenter,
                              verifier: ChromeWebStorePackageVerifier(publisherKeyHash: ChromeWebStoreFixture.publisherKeyHash))
    }

    private func scheduledService(_ manager: WebExtensionManager,
                                  check: @escaping (String, String) async -> ChromeWebStoreUpdateChecker.CheckResult) -> ChromeWebStoreService {
        ChromeWebStoreService(manager: manager, catalog: catalog,
                              downloader: StoreDownloaderMock(action: { Data() }), presenter: presenter,
                              verifier: ChromeWebStorePackageVerifier(), updateCheck: check, updateCheckInterval: 0.01)
    }

    private func installed(_ identifier: String, version: String?, storeID: String? = nil) -> InstalledWebExtension {
        InstalledWebExtension(uniqueIdentifier: identifier, filename: "test.zip", name: "Test", version: version,
                              storeIdentity: storeID.map { .init(store: .chromeWebStore, id: $0) })
    }

    func testVersionOverrideReportsOlderVersionWithoutChangingInstalledRecord() async throws {
        let manager = try makeManager()
        let record = installed("installed", version: "8.12.42.36", storeID: ChromeWebStoreID.onePassword.rawValue)
        installationStore.installedExtensions = [record]
        let checked = expectation(description: "Override used")
        var count = 0
        let service = scheduledService(manager) { _, version in
            XCTAssertEqual(version, "0.0.0.1")
            count += 1
            if count == 1 { checked.fulfill() }
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        }
        service.setUpdateCheckVersionOverride("0.0.0.1", forInstallationIdentifier: record.uniqueIdentifier)
        defer { withExtendedLifetime((manager, service)) {} }
        await fulfillment(of: [checked], timeout: 1)
        XCTAssertEqual(installationStore.installedExtensions, [record])
    }

    func testVersionOverrideClearsAfterReplacementEvenWithSameVersion() async throws {
        let manager = try makeManager()
        let storeID = ChromeWebStoreID.onePassword.rawValue
        installationStore.installedExtensions = [installed("old", version: "8.12.42.36", storeID: storeID)]
        let replacement = installed("replacement", version: "8.12.42.36", storeID: storeID)
        let checked = expectation(description: "Override cleared after replacement")
        var count = 0
        let service = scheduledService(manager) { [installationStore] _, version in
            count += 1
            if count == 1 {
                XCTAssertEqual(version, "0.0.0.1")
                // Successful replacement can temporarily coexist with the old installation.
                installationStore.installedExtensions.append(replacement)
            } else if count == 2 {
                XCTAssertEqual(version, "8.12.42.36")
                installationStore.installedExtensions = [replacement]
            } else if count == 3 {
                XCTAssertEqual(version, "8.12.42.36")
                checked.fulfill()
            }
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        }
        service.setUpdateCheckVersionOverride("0.0.0.1", forInstallationIdentifier: "old")
        defer { withExtendedLifetime((manager, service)) {} }
        await fulfillment(of: [checked], timeout: 1)
    }

    func testVersionOverrideClearsWhenInstalledVersionChangesInPlace() async throws {
        let manager = try makeManager()
        let storeID = ChromeWebStoreID.onePassword.rawValue
        installationStore.installedExtensions = [installed("installed", version: "8.12.42.36", storeID: storeID)]
        let updated = installed("installed", version: "8.13.0", storeID: storeID)
        let checked = expectation(description: "Override cleared after version change")
        var count = 0
        let service = scheduledService(manager) { [installationStore] _, version in
            count += 1
            if count == 1 {
                XCTAssertEqual(version, "0.0.0.1")
                installationStore.installedExtensions = [updated]
            } else if count == 2 {
                XCTAssertEqual(version, "8.13.0")
                checked.fulfill()
            }
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        }
        service.setUpdateCheckVersionOverride("0.0.0.1", forInstallationIdentifier: "installed")
        defer { withExtendedLifetime((manager, service)) {} }
        await fulfillment(of: [checked], timeout: 1)
    }

    func testOnlySelectedExtensionReportsOverriddenVersion() async throws {
        let manager = try makeManager()
        let firstID = String(repeating: "a", count: 32)
        let secondID = String(repeating: "b", count: 32)
        let records = [installed("first", version: "2.0", storeID: firstID), installed("second", version: "3.0", storeID: secondID)]
        installationStore.installedExtensions = records
        let checked = expectation(description: "Both extensions checked independently")
        checked.expectedFulfillmentCount = 2
        var count = 0
        let service = scheduledService(manager) { identifier, version in
            XCTAssertEqual(version, identifier == firstID ? "0.0.0.1" : "3.0")
            count += 1
            if count <= 2 { checked.fulfill() }
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        }
        service.setUpdateCheckVersionOverride("0.0.0.1", forInstallationIdentifier: "first")
        defer { withExtendedLifetime((manager, service)) {} }
        await fulfillment(of: [checked], timeout: 1)
        XCTAssertEqual(service.updateCheckVersionOverride(forInstallationIdentifier: "first"), "0.0.0.1")
        XCTAssertNil(service.updateCheckVersionOverride(forInstallationIdentifier: "second"))
        XCTAssertEqual(installationStore.installedExtensions, records)
    }

    func testResetAndReplacementAffectOnlySelectedExtension() throws {
        let manager = try makeManager()
        catalog.allowed = true
        defer { withExtendedLifetime(manager) {} }
        let firstID = String(repeating: "a", count: 32)
        let secondID = String(repeating: "b", count: 32)
        installationStore.installedExtensions = [installed("first", version: "2.0", storeID: firstID),
                                                installed("second", version: "3.0", storeID: secondID)]
        let service = scheduledService(manager) { _, _ in .init(outcome: .noUpdate, retryNotBefore: nil) }
        service.setUpdateCheckVersionOverride("0.0.0.1", forInstallationIdentifier: "first")
        service.setUpdateCheckVersionOverride("1.0", forInstallationIdentifier: "second")
        catalog.allowed = false
        service.setUpdateCheckVersionOverride(nil, forInstallationIdentifier: "first")
        catalog.allowed = true
        XCTAssertNil(service.updateCheckVersionOverride(forInstallationIdentifier: "first"))
        XCTAssertEqual(service.updateCheckVersionOverride(forInstallationIdentifier: "second"), "1.0")

        service.setUpdateCheckVersionOverride("0.0.0.1", forInstallationIdentifier: "first")
        installationStore.installedExtensions.append(installed("replacement", version: "2.0", storeID: firstID))
        XCTAssertNil(service.updateCheckVersionOverride(forInstallationIdentifier: "replacement"))
        XCTAssertEqual(service.updateCheckVersionOverride(forInstallationIdentifier: "second"), "1.0")
    }

    func testOverrideGetterUsesCanonicalVersionAcrossCoexistingInstallations() throws {
        let manager = try makeManager()
        defer { withExtendedLifetime(manager) {} }
        let storeID = ChromeWebStoreID.onePassword.rawValue
        installationStore.installedExtensions = [installed("old", version: "2.0", storeID: storeID),
                                                installed("new", version: "3.0", storeID: storeID)]
        let service = scheduledService(manager) { _, _ in .init(outcome: .noUpdate, retryNotBefore: nil) }
        service.setUpdateCheckVersionOverride("0.0.0.1", forInstallationIdentifier: "new")
        XCTAssertEqual(service.updateCheckVersionOverride(forInstallationIdentifier: "old"), "0.0.0.1")
        XCTAssertEqual(service.updateCheckVersionOverride(forInstallationIdentifier: "new"), "0.0.0.1")
    }

    func testOverridesIgnoreMissingAndManualInstallationsAndStartOffInFreshService() throws {
        let manager = try makeManager()
        defer { withExtendedLifetime(manager) {} }
        installationStore.installedExtensions = [installed("manual", version: "2.0"),
                                                installed("store", version: "3.0", storeID: ChromeWebStoreID.onePassword.rawValue)]
        let service = scheduledService(manager) { _, _ in .init(outcome: .noUpdate, retryNotBefore: nil) }
        service.setUpdateCheckVersionOverride("0.0.0.1", forInstallationIdentifier: "manual")
        service.setUpdateCheckVersionOverride("0.0.0.1", forInstallationIdentifier: "missing")
        XCTAssertNil(service.updateCheckVersionOverride(forInstallationIdentifier: "manual"))
        XCTAssertNil(service.updateCheckVersionOverride(forInstallationIdentifier: "missing"))
        XCTAssertNil(service.updateCheckVersionOverride(forInstallationIdentifier: "store"))
        service.setUpdateCheckVersionOverride("0.0.0.1", forInstallationIdentifier: "store")
        let freshService = scheduledService(manager) { _, _ in .init(outcome: .noUpdate, retryNotBefore: nil) }
        XCTAssertNil(freshService.updateCheckVersionOverride(forInstallationIdentifier: "store"))
        XCTAssertEqual(service.updateCheckVersionOverride(forInstallationIdentifier: "store"), "0.0.0.1")
    }

    func testUpdateChecksStartImmediatelyAndRepeatWithoutOverlapping() async throws {
        let manager = try makeManager()
        installationStore.installedExtensions = [installed("installed", version: "1.0", storeID: ChromeWebStoreID.bitwarden.rawValue)]
        let checked = expectation(description: "Two completed checks")
        checked.expectedFulfillmentCount = 2
        var count = 0
        var active = false
        let service = scheduledService(manager) { identifier, version in
            XCTAssertFalse(active)
            XCTAssertEqual(identifier, ChromeWebStoreID.bitwarden.rawValue)
            XCTAssertEqual(version, "1.0")
            active = true
            try? await Task.sleep(for: .milliseconds(20))
            active = false
            count += 1
            if count <= 2 { checked.fulfill() }
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        }
        defer { withExtendedLifetime((manager, service)) {} }
        await fulfillment(of: [checked], timeout: 1)
    }

    func testUpdateChecksReadFreshInstallationsEachCycle() async throws {
        let manager = try makeManager()
        let firstID = ChromeWebStoreID.bitwarden.rawValue
        let secondID = ChromeWebStoreID.onePassword.rawValue
        installationStore.installedExtensions = [installed("first", version: "1.0", storeID: firstID)]
        let refreshed = expectation(description: "New installation checked")
        let second = installed("second", version: "2.0", storeID: secondID)
        var count = 0
        let service = scheduledService(manager) { [installationStore] identifier, version in
            count += 1
            if count == 1 {
                XCTAssertEqual(identifier, firstID)
                installationStore.installedExtensions = [second]
            } else if count == 2 {
                XCTAssertEqual(identifier, secondID)
                XCTAssertEqual(version, "2.0")
                refreshed.fulfill()
            }
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        }
        defer { withExtendedLifetime((manager, service)) {} }
        await fulfillment(of: [refreshed], timeout: 1)
    }

    func testUpdateChecksSkipManualAndMissingVersionsAndUseNewestDuplicate() async throws {
        let manager = try makeManager()
        let identifier = ChromeWebStoreID.bitwarden.rawValue
        installationStore.installedExtensions = [
            installed("manual", version: "1.0"),
            installed("unknown-version", version: nil, storeID: ChromeWebStoreID.onePassword.rawValue),
            installed("old", version: "4.9.3", storeID: identifier),
            installed("new", version: "4.10.0", storeID: identifier)
        ]
        let checked = expectation(description: "Newest store installation checked")
        var count = 0
        let service = scheduledService(manager) { storeID, version in
            XCTAssertEqual(storeID, identifier)
            XCTAssertEqual(version, "4.10.0")
            count += 1
            if count == 1 { checked.fulfill() }
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        }
        defer { withExtendedLifetime((manager, service)) {} }
        await fulfillment(of: [checked], timeout: 1)
    }

    func testRemovalAndReplacementDuringCheckRefreshRemainingCandidates() async throws {
        let manager = try makeManager()
        let identifiers = ["a", "b", "c"].map { String(repeating: $0, count: 32) }
        installationStore.installedExtensions = identifiers.map { installed($0, version: "1.0", storeID: $0) }
        let replacement = installed("replacement", version: "2.0", storeID: identifiers[2])
        let checked = expectation(description: "Updated remaining installation checked")
        var count = 0
        let service = scheduledService(manager) { [installationStore] identifier, version in
            count += 1
            if count == 1 {
                XCTAssertEqual(identifier, identifiers[0])
                installationStore.installedExtensions.removeAll { $0.storeIdentity?.id != identifiers[0] }
                installationStore.installedExtensions.append(replacement)
            } else if count == 2 {
                XCTAssertEqual(identifier, identifiers[2], "The removed extension must not be queried")
                XCTAssertEqual(version, "2.0", "The replaced extension must use its current version")
                checked.fulfill()
            }
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        }
        defer { withExtendedLifetime((manager, service)) {} }
        await fulfillment(of: [checked], timeout: 1)
    }

    func testServerRetryAfterFailurePausesWholeBatchUntilDeadline() async throws {
        let manager = try makeManager()
        let firstID = String(repeating: "a", count: 32)
        installationStore.installedExtensions = [
            installed("first", version: "1.0", storeID: firstID),
            installed("second", version: "1.0", storeID: String(repeating: "b", count: 32))
        ]
        let resumed = expectation(description: "Checks resume after server deadline")
        var deadline = Date.distantFuture
        var count = 0
        let service = scheduledService(manager) { identifier, _ in
            count += 1
            if count == 1 {
                deadline = Date().addingTimeInterval(0.1)
                return .init(outcome: .failure(.httpStatus(503)), retryNotBefore: deadline)
            }
            XCTAssertGreaterThanOrEqual(Date(), deadline)
            if count == 2 {
                XCTAssertEqual(identifier, String(repeating: "b", count: 32), "Resume the remaining extension after the server throttle")
                resumed.fulfill()
            }
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        }
        defer { withExtendedLifetime((manager, service)) {} }
        await fulfillment(of: [resumed], timeout: 1)
    }

    func testRepeatedRetryDeadlinesDoNotStarveLaterExtensions() async throws {
        let manager = try makeManager()
        let identifiers = ["a", "b", "c"].map { String(repeating: $0, count: 32) }
        installationStore.installedExtensions = identifiers.map { installed($0, version: "1.0", storeID: $0) }
        let checked = expectation(description: "All extensions checked despite repeated throttling")
        checked.expectedFulfillmentCount = identifiers.count
        var previousDeadline = Date.distantPast
        var observed: [String] = []
        let service = scheduledService(manager) { identifier, _ in
            XCTAssertGreaterThanOrEqual(Date(), previousDeadline)
            observed.append(identifier)
            if observed.count <= identifiers.count { checked.fulfill() }
            previousDeadline = Date().addingTimeInterval(0.02)
            return .init(outcome: .noUpdate, retryNotBefore: previousDeadline)
        }
        defer { withExtendedLifetime((manager, service)) {} }
        await fulfillment(of: [checked], timeout: 1)
        XCTAssertEqual(Array(observed.prefix(3)), identifiers)
    }

    func testCatalogRevocationStopsChecksAndReenableResumes() async throws {
        let manager = try makeManager()
        installationStore.installedExtensions = [installed("installed", version: "1.0", storeID: ChromeWebStoreID.bitwarden.rawValue)]
        let first = expectation(description: "Initial check")
        let resumed = expectation(description: "Check after catalog reenable")
        var count = 0
        let service = scheduledService(manager) { [catalog] _, _ in
            count += 1
            if count == 1 {
                catalog.allowed = false
                first.fulfill()
            } else if count == 2 {
                resumed.fulfill()
            }
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        }
        defer { withExtendedLifetime((manager, service)) {} }
        await fulfillment(of: [first], timeout: 1)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(count, 1)
        catalog.allowed = true
        await fulfillment(of: [resumed], timeout: 1)
    }

    func testReleasingServiceCancelsActiveCheck() async throws {
        let manager = try makeManager()
        defer { withExtendedLifetime(manager) {} }
        installationStore.installedExtensions = [installed("installed", version: "1.0", storeID: ChromeWebStoreID.bitwarden.rawValue)]
        let started = expectation(description: "Check started")
        let cancelled = expectation(description: "Active check cancelled")
        var service: ChromeWebStoreService? = scheduledService(manager) { _, _ in
            started.fulfill()
            do {
                try await Task.sleep(for: .seconds(5))
                XCTFail("The active check should have been cancelled")
            } catch {
                cancelled.fulfill()
            }
            return .init(outcome: .failure(.cancelled), retryNotBefore: nil)
        }
        weak var weakService = service
        await fulfillment(of: [started], timeout: 1)
        service = nil
        XCTAssertNil(weakService)
        await fulfillment(of: [cancelled], timeout: 1)
    }

    func testInstallRestoreAndRemove() async throws {
        let fixture = try ChromeWebStoreFixture()
        let manager = try makeManager()
        let service = service(manager, fixture: fixture)
        XCTAssertEqual(service.status(for: fixture.identifier), .installable)
        let installed = await service.install(identifier: fixture.identifier, downloadURL: try ChromeWebStoreURL.downloadURL(for: fixture.identifier))
        XCTAssertTrue(installed, "\(presenter.errors)")
        let record = try XCTUnwrap(installationStore.installedExtensions.first)
        XCTAssertEqual(record.filename, "\(fixture.identifier)-1.0.zip")
        XCTAssertEqual(record.storeIdentity, .init(store: .chromeWebStore, id: fixture.identifier))
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
        prompter.response = .denied
        let service = service(manager, fixture: fixture)
        let success = await service.install(identifier: fixture.identifier, downloadURL: try ChromeWebStoreURL.downloadURL(for: fixture.identifier))
        XCTAssertFalse(success)
        XCTAssertEqual(prompter.installationRequests, 1)
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
                                                    name: "Test", version: "1", storeIdentity: .init(store: .chromeWebStore, id: fixture.identifier)))
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
                                           storeIdentity: .init(store: .chromeWebStore, id: String(repeating: "a", count: 32)))
        let restored = try JSONDecoder().decode(InstalledWebExtension.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(restored.storeIdentity, record.storeIdentity)
        let legacy = Data(#"{"uniqueIdentifier":"uuid","filename":"extension.zip"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(InstalledWebExtension.self, from: legacy).storeIdentity)
    }
}

private struct StoreDownloaderMock: ChromeWebStoreDownloading {
    let action: () async throws -> Data
    func download(extensionID: String) async throws -> Data { try await action() }
}

@MainActor
private final class StoreCatalogMock: ChromeWebStoreCatalogProviding {
    var allowed = true
    var extensionIDs: [String] = []
    var learnMoreURL: URL?
    func contains(_ identifier: String) -> Bool { allowed }
    func listing(of subfeature: ExtensionsCatalogSubfeature) -> ChromeWebStoreListing? { nil }
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
    var response: WebExtensionPermissionInstallationPromptResult = .granted(privateDataAccess: true)
    var installationRequests = 0
    var onPrompt: (() async -> Void)?
    func confirmInstallation(of webExtension: WKWebExtension, permissions: WebExtensionPermissionRequest) async -> WebExtensionPermissionInstallationPromptResult {
        installationRequests += 1
        await onPrompt?()
        return response
    }
    func confirmPermissions(_ permissions: WebExtensionPermissionRequest, for context: WKWebExtensionContext) async -> WebExtensionPermissionPromptResult {
        return .granted
    }
}
