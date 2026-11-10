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

import Combine
import CryptoKit
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

    private func scheduledService(_ manager: WebExtensionManager, interval: TimeInterval = ChromeWebStoreUpdateCoordinator.defaultCheckInterval,
                                  isUpdateDiscoveryEnabled: @escaping @MainActor @Sendable () -> Bool = { true },
                                  featureFlagUpdates: AnyPublisher<Void, Never>? = nil,
                                  scheduler: ChromeWebStorePeriodicSchedulerMock = ChromeWebStorePeriodicSchedulerMock(),
                                  pixelFiring: WebExtensionPixelFiring = NoOpWebExtensionPixelFiring(),
                                  keyValueStore: (any ThrowingKeyValueStoring)? = nil,
                                  check: @escaping @MainActor @Sendable (String, String) async -> ChromeWebStoreUpdateChecker.CheckResult) -> ChromeWebStoreService {
        ChromeWebStoreService(manager: manager, catalog: catalog,
                              downloader: StoreDownloaderMock(action: { Data() }), presenter: presenter,
                              verifier: ChromeWebStorePackageVerifier(), isUpdateDiscoveryEnabled: isUpdateDiscoveryEnabled,
                              updateDiscoveryFeatureFlagUpdates: featureFlagUpdates,
                              keyValueStore: keyValueStore, pixelFiring: pixelFiring, updateCheck: { identifier, version in
                                  await check(identifier, version)
                              }, updateCheckInterval: interval, updateSchedulerFactory: { _ in scheduler })
    }

    func testDisabledDiscoveryDoesNotScheduleCheckOrEmitPixels() async throws {
        let manager = try makeManager()
        installationStore.installedExtensions = [installed("installed", version: "2.0", storeID: ChromeWebStoreID.onePassword.rawValue)]
        let scheduler = ChromeWebStorePeriodicSchedulerMock()
        let pixels = StoreUpdatePixelFiringMock()
        let service = scheduledService(manager, isUpdateDiscoveryEnabled: { false }, scheduler: scheduler, pixelFiring: pixels) { _, _ in
            XCTFail("Disabled discovery must not reach Google")
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        }
        defer { withExtendedLifetime((manager, service)) {} }
        await service.checkForUpdatesNow()
        XCTAssertEqual(scheduler.scheduleCount, 0)
        XCTAssertFalse(service.canCheckForUpdates)
        XCTAssertTrue(pixels.outcomes.isEmpty)
    }

    func testManualChecksUseLiveFlagBeforePublisherDelivery() async throws {
        let manager = try makeManager()
        installationStore.installedExtensions = [installed("installed", version: "2.0", storeID: ChromeWebStoreID.onePassword.rawValue)]
        var enabled = false
        var checkCount = 0
        let updates = PassthroughSubject<Void, Never>()
        let service = scheduledService(manager, isUpdateDiscoveryEnabled: { enabled }, featureFlagUpdates: updates.eraseToAnyPublisher()) { _, _ in
            checkCount += 1
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        }
        XCTAssertFalse(service.canCheckForUpdates)
        await service.checkForUpdatesNow()
        XCTAssertEqual(checkCount, 0)
        enabled = true
        XCTAssertTrue(service.canCheckForUpdates)
        await service.checkForUpdatesNow()
        XCTAssertGreaterThan(checkCount, 0)
        let enabledCount = checkCount
        enabled = false
        XCTAssertFalse(service.canCheckForUpdates)
        await service.checkForUpdatesNow()
        XCTAssertEqual(checkCount, enabledCount, "A pending publisher delivery must not allow another request")
        withExtendedLifetime((manager, service)) {}
    }

    func testFlagPublisherEnablesAndCancelsDiscoveryWithoutManualAction() async throws {
        let manager = try makeManager()
        installationStore.installedExtensions = [installed("installed", version: "2.0", storeID: ChromeWebStoreID.onePassword.rawValue)]
        let entered = expectation(description: "Remote enable starts discovery")
        let cancelled = expectation(description: "Remote disable cancels discovery")
        let updates = PassthroughSubject<Void, Never>()
        var enabled = false
        let service = scheduledService(manager, isUpdateDiscoveryEnabled: { enabled }, featureFlagUpdates: updates.eraseToAnyPublisher()) { _, _ in
            entered.fulfill()
            do { try await Task.sleep(for: .seconds(5)) } catch { cancelled.fulfill() }
            return .init(outcome: .failure(.cancelled), retryNotBefore: nil)
        }
        enabled = true
        updates.send()
        await fulfillment(of: [entered], timeout: 1)
        enabled = false
        updates.send()
        await fulfillment(of: [cancelled], timeout: 1)
        XCTAssertFalse(service.canCheckForUpdates)
        withExtendedLifetime((manager, service)) {}
    }

    func testLiveFlagOffBlocksScheduledRequestsBeforePublisherDelivery() async throws {
        let manager = try makeManager()
        installationStore.installedExtensions = [installed("installed", version: "2.0", storeID: ChromeWebStoreID.onePassword.rawValue)]
        let scheduled = expectation(description: "Activity registered after startup")
        let scheduler = ChromeWebStorePeriodicSchedulerMock()
        var enabled = true
        var checkCount = 0
        let service = ChromeWebStoreService(manager: manager, catalog: catalog, downloader: StoreDownloaderMock(action: { Data() }), presenter: presenter,
                                           verifier: ChromeWebStorePackageVerifier(), isUpdateDiscoveryEnabled: { enabled }, updateCheck: { _, _ in
            await MainActor.run { checkCount += 1 }
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        }, updateSchedulerFactory: { _ in
            scheduled.fulfill()
            return scheduler
        })
        await fulfillment(of: [scheduled], timeout: 1)
        XCTAssertEqual(checkCount, 1)
        enabled = false
        await scheduler.fire()
        XCTAssertEqual(checkCount, 1, "The live provider must reject requests before a flag notification is handled")
        await service.checkForUpdatesNow()
        XCTAssertEqual(scheduler.invalidationCount, 1)
        withExtendedLifetime((manager, service)) {}
    }

    func testServiceRestoresServerBackoffBeforeLaunchOrImmediateManualCheck() async throws {
        let manager = try makeManager()
        installationStore.installedExtensions = [installed("installed", version: "2.0", storeID: ChromeWebStoreID.onePassword.rawValue)]
        let now = Date(timeIntervalSince1970: 100000)
        ChromeWebStoreUpdateStateStore(keyValueStore: keyValueStore).save(.init(lastCompletedBatch: nil,
                                                                            retryNotBefore: now.addingTimeInterval(3600)))
        let scheduled = expectation(description: "Periodic activity registered after deferred launch")
        let service = ChromeWebStoreService(manager: manager, catalog: catalog, downloader: StoreDownloaderMock(action: { Data() }), presenter: presenter,
                                           verifier: ChromeWebStorePackageVerifier(), keyValueStore: keyValueStore, now: { now }, updateCheck: { _, _ in
            XCTFail("Restored server backoff must apply before any request can start")
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        }, updateSchedulerFactory: { _ in
            scheduled.fulfill()
            return ChromeWebStorePeriodicSchedulerMock()
        })
        defer { withExtendedLifetime((manager, service)) {} }
        await service.checkForUpdatesNow()
        await fulfillment(of: [scheduled], timeout: 1)
    }

    func testServiceRestoresRecentCompletionButManualCheckStillRuns() async throws {
        let manager = try makeManager()
        installationStore.installedExtensions = [installed("installed", version: "2.0", storeID: ChromeWebStoreID.onePassword.rawValue)]
        let now = Date(timeIntervalSince1970: 100000)
        let store = ChromeWebStoreUpdateStateStore(keyValueStore: keyValueStore)
        store.save(.init(lastCompletedBatch: now.addingTimeInterval(-3600), retryNotBefore: nil))
        let scheduled = expectation(description: "Periodic activity registered after skipped launch")
        var checkCount = 0
        let service = ChromeWebStoreService(manager: manager, catalog: catalog, downloader: StoreDownloaderMock(action: { Data() }), presenter: presenter,
                                           verifier: ChromeWebStorePackageVerifier(), keyValueStore: keyValueStore, now: { now }, updateCheck: { _, _ in
            await MainActor.run { checkCount += 1 }
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        }, updateSchedulerFactory: { _ in
            scheduled.fulfill()
            return ChromeWebStorePeriodicSchedulerMock()
        })
        defer { withExtendedLifetime((manager, service)) {} }
        await fulfillment(of: [scheduled], timeout: 1)
        XCTAssertEqual(checkCount, 0)
        await service.checkForUpdatesNow()
        XCTAssertEqual(checkCount, 1)
        XCTAssertEqual(store.load().lastCompletedBatch, now)
    }

    func testCheckOutcomesEmitOnlyExpectedDiscoveryPixels() async throws {
        let manager = try makeManager()
        let identifier = ChromeWebStoreID.onePassword.rawValue
        catalog.catalogEntries[identifier] = .onePassword
        installationStore.installedExtensions = [installed("installed", version: "2.0", storeID: identifier)]
        let update = ChromeWebStoreUpdateChecker.Update(extensionID: identifier, version: "3.0",
                                                        downloadURL: try XCTUnwrap(URL(string: "https://clients2.googleusercontent.com/extension.crx")),
                                                        size: 100, sha256: String(repeating: "a", count: 64))
        let cases: [(ChromeWebStoreUpdateChecker.Outcome, WebExtensionUpdateCheckOutcome?)] = [
            (.noUpdate, nil), (.failure(.cancelled), nil), (.skipped, .googleFlagged),
            (.failure(.networkFailure), .networkFailure), (.update(update), .updateFound)
        ]
        for (outcome, expected) in cases {
            let pixels = StoreUpdatePixelFiringMock()
            let scheduled = expectation(description: "Initial check completed")
            let service = ChromeWebStoreService(manager: manager, catalog: catalog, downloader: StoreDownloaderMock(action: { Data() }), presenter: presenter,
                                               verifier: ChromeWebStorePackageVerifier(), pixelFiring: pixels,
                                               updateDownload: { _ in throw WebExtensionUpdateDownloadFailure.networkFailure }, updateCheck: { _, _ in
                .init(outcome: outcome, retryNotBefore: nil)
            }, updateSchedulerFactory: { _ in
                scheduled.fulfill()
                return ChromeWebStorePeriodicSchedulerMock()
            })
            await fulfillment(of: [scheduled], timeout: 1)
            XCTAssertEqual(pixels.outcomes, expected.map { [$0] } ?? [])
            XCTAssertEqual(pixels.extensions, expected == nil ? [] : [.catalog(.onePassword)])
            withExtendedLifetime(service) {}
        }
        withExtendedLifetime(manager) {}
    }

    func testDiscoveryPixelsUseOtherWhenTheCatalogHasNoEntry() async throws {
        let manager = try makeManager()
        installationStore.installedExtensions = [installed("installed", version: "2.0", storeID: ChromeWebStoreID.onePassword.rawValue)]
        let pixels = StoreUpdatePixelFiringMock()
        let service = scheduledService(manager, pixelFiring: pixels) { _, _ in
            .init(outcome: .skipped, retryNotBefore: nil)
        }
        await service.checkForUpdatesNow()
        XCTAssertFalse(pixels.extensions.isEmpty)
        XCTAssertTrue(pixels.extensions.allSatisfy { $0 == .other })
        withExtendedLifetime((manager, service)) {}
    }

    func testDiscoveryPreparesPendingPackageWithoutCallingPresenterOrInstaller() async throws {
        let fixture = try ChromeWebStoreFixture()
        let manager = try makeManager()
        catalog.catalogEntries[fixture.identifier] = .bitwarden
        installationStore.installedExtensions = [installed("installed", version: "0.9", storeID: fixture.identifier)]
        let update = try updateOffer(fixture)
        let pixels = StoreUpdatePixelFiringMock()
        let service = ChromeWebStoreService(manager: manager, catalog: catalog, downloader: StoreDownloaderMock(action: {
            XCTFail("Background updates must not enter the UI download flow")
            return Data()
        }), presenter: presenter, verifier: ChromeWebStorePackageVerifier(publisherKeyHash: ChromeWebStoreFixture.publisherKeyHash),
                                           pixelFiring: pixels, updateDownload: { _ in fixture.package }, updateCheck: { _, _ in
            .init(outcome: .update(update), retryNotBefore: nil)
        }, updateSchedulerFactory: { _ in ChromeWebStorePeriodicSchedulerMock() })
        await service.checkForUpdatesNow()
        let pending = await service.pendingUpdates.pendingUpdate(for: fixture.identifier)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(pending).fileURL), fixture.archive)
        guard case .updateVerified(let pixelExtension) = pixels.preparationEvents.first else { return XCTFail("Expected verified update") }
        XCTAssertEqual(pixelExtension, .catalog(.bitwarden))
        XCTAssertEqual(presenter.progressRequests, 0)
        XCTAssertTrue(presenter.errors.isEmpty)
        XCTAssertTrue(presenter.removalRequests.isEmpty)
        XCTAssertEqual(prompter.installationRequests, 0)
        XCTAssertEqual(installationStore.installedExtensions.first?.version, "0.9")
        withExtendedLifetime((manager, service)) {}
    }

    func testUpdateVerificationUsesDebugVersionOverrideOnlyWhenSet() async throws {
        let fixture = try ChromeWebStoreFixture()
        for versionOverride in [String?.none, "0.0.0.1"] {
            let manager = try makeManager()
            installationStore.installedExtensions = [installed("installed", version: "1.0", storeID: fixture.identifier)]
            let update = try updateOffer(fixture)
            let pixels = StoreUpdatePixelFiringMock()
            let service = ChromeWebStoreService(manager: manager, catalog: catalog, downloader: StoreDownloaderMock(action: { Data() }),
                                               presenter: presenter, verifier: ChromeWebStorePackageVerifier(publisherKeyHash: ChromeWebStoreFixture.publisherKeyHash),
                                               pixelFiring: pixels, updateDownload: { _ in fixture.package }, updateCheck: { _, reported in
                XCTAssertEqual(reported, versionOverride ?? "1.0")
                return .init(outcome: .update(update), retryNotBefore: nil)
            }, updateSchedulerFactory: { _ in ChromeWebStorePeriodicSchedulerMock() })
            service.setUpdateCheckVersionOverride(versionOverride, forInstallationIdentifier: "installed")
            await service.checkForUpdatesNow()
            let pending = await service.pendingUpdates.pendingUpdate(for: fixture.identifier)
            if versionOverride != nil {
                XCTAssertEqual(try Data(contentsOf: XCTUnwrap(pending).fileURL), fixture.archive)
                guard case .updateVerified(let pixelExtension) = pixels.preparationEvents.first else { return XCTFail("Expected verified update") }
                XCTAssertEqual(pixelExtension, .other)
            } else {
                XCTAssertNil(pending)
                guard case .updateVerificationFailed(let pixelExtension, let reason) = pixels.preparationEvents.first else {
                    return XCTFail("Expected version rejection")
                }
                XCTAssertEqual(pixelExtension, .other)
                XCTAssertEqual(reason, .notNewer)
            }
            XCTAssertEqual(installationStore.installedExtensions.first?.version, "1.0")
            XCTAssertEqual(presenter.progressRequests, 0)
            XCTAssertTrue(presenter.errors.isEmpty)
            withExtendedLifetime((manager, service)) {}
        }
    }

    func testUpdateDownloadFailurePixelsUseCatalogEntryAndOther() async throws {
        let fixture = try ChromeWebStoreFixture()
        for pixelExtension in WebExtensionPixelExtension.allCases {
            let manager = try makeManager()
            if case .catalog(let entry) = pixelExtension {
                catalog.catalogEntries[fixture.identifier] = entry
            } else {
                catalog.catalogEntries.removeValue(forKey: fixture.identifier)
            }
            installationStore.installedExtensions = [installed("installed", version: "0.9", storeID: fixture.identifier)]
            let update = try updateOffer(fixture)
            let pixels = StoreUpdatePixelFiringMock()
            let service = ChromeWebStoreService(manager: manager, catalog: catalog, downloader: StoreDownloaderMock(action: { Data() }),
                                               presenter: presenter, verifier: ChromeWebStorePackageVerifier(), pixelFiring: pixels,
                                               updateDownload: { _ in throw WebExtensionUpdateDownloadFailure.networkFailure }, updateCheck: { _, _ in
                .init(outcome: .update(update), retryNotBefore: nil)
            }, updateSchedulerFactory: { _ in ChromeWebStorePeriodicSchedulerMock() })
            await service.checkForUpdatesNow()
            guard case .updateDownloadFailed(let reportedExtension, let reason) = pixels.preparationEvents.first else {
                return XCTFail("Expected download failure")
            }
            XCTAssertEqual(reportedExtension, pixelExtension)
            XCTAssertEqual(reason, .networkFailure)
            withExtendedLifetime((manager, service)) {}
        }
    }

    private func updateOffer(_ fixture: ChromeWebStoreFixture) throws -> ChromeWebStoreUpdateChecker.Update {
        .init(extensionID: fixture.identifier, version: "1.0",
              downloadURL: try XCTUnwrap(URL(string: "https://clients2.googleusercontent.com/update.crx")),
              size: fixture.package.count, sha256: SHA256.hash(data: fixture.package).map { String(format: "%02x", $0) }.joined())
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
        for _ in 0..<3 { await service.checkForUpdatesNow() }
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
        await service.checkForUpdatesNow()
        await service.checkForUpdatesNow()
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

    func testPersistedOverridesSurviveRecreationAndDisableAndResetOnlyTheirExtension() throws {
        let manager = try makeManager()
        installationStore.installedExtensions = [installed("first", version: "2.0", storeID: ChromeWebStoreID.onePassword.rawValue),
                                                 installed("second", version: "3.0", storeID: ChromeWebStoreID.bitwarden.rawValue)]
        let service = scheduledService(manager, keyValueStore: keyValueStore) { _, _ in .init(outcome: .noUpdate, retryNotBefore: nil) }
        service.setUpdateCheckVersionOverride("0.0.0.1", forInstallationIdentifier: "first")
        service.setUpdateCheckVersionOverride("1.0", forInstallationIdentifier: "second")
        installationStore.installedExtensions[0].isDisabled = true
        let relaunched = scheduledService(manager, keyValueStore: keyValueStore) { _, _ in .init(outcome: .noUpdate, retryNotBefore: nil) }

        XCTAssertEqual(relaunched.updateCheckVersionOverride(forInstallationIdentifier: "first"), "0.0.0.1")
        relaunched.setUpdateCheckVersionOverride(nil, forInstallationIdentifier: "first")
        let afterReset = scheduledService(manager, keyValueStore: keyValueStore) { _, _ in .init(outcome: .noUpdate, retryNotBefore: nil) }
        XCTAssertNil(afterReset.updateCheckVersionOverride(forInstallationIdentifier: "first"))
        XCTAssertEqual(afterReset.updateCheckVersionOverride(forInstallationIdentifier: "second"), "1.0")
    }

    func testPersistedOverrideCannotTransferToReinstalledIdentity() throws {
        let manager = try makeManager()
        let storeID = ChromeWebStoreID.onePassword.rawValue
        installationStore.installedExtensions = [installed("original", version: "2.0", storeID: storeID)]
        let service = scheduledService(manager, keyValueStore: keyValueStore) { _, _ in .init(outcome: .noUpdate, retryNotBefore: nil) }
        service.setUpdateCheckVersionOverride("0.0.0.1", forInstallationIdentifier: "original")
        installationStore.installedExtensions = [installed("replacement", version: "2.0", storeID: storeID)]
        let relaunched = scheduledService(manager, keyValueStore: keyValueStore) { _, _ in .init(outcome: .noUpdate, retryNotBefore: nil) }
        XCTAssertNil(relaunched.updateCheckVersionOverride(forInstallationIdentifier: "replacement"))
        let afterPrune = scheduledService(manager, keyValueStore: keyValueStore) { _, _ in .init(outcome: .noUpdate, retryNotBefore: nil) }
        XCTAssertNil(afterPrune.updateCheckVersionOverride(forInstallationIdentifier: "replacement"))
    }

    func testSuccessfulSameVersionCommitClearsOnlyItsPersistedOverrideAndRetriesFailedWrites() throws {
        let manager = try makeManager()
        let first = installed("first", version: "2.0", storeID: ChromeWebStoreID.onePassword.rawValue)
        installationStore.installedExtensions = [first, installed("second", version: "3.0", storeID: ChromeWebStoreID.bitwarden.rawValue)]
        let service = scheduledService(manager, keyValueStore: keyValueStore) { _, _ in .init(outcome: .noUpdate, retryNotBefore: nil) }
        service.setUpdateCheckVersionOverride("0.0.0.1", forInstallationIdentifier: "first")
        service.setUpdateCheckVersionOverride("1.0", forInstallationIdentifier: "second")
        let overrideIdentifier = try persistedOverrideIdentifier(for: ChromeWebStoreID.onePassword.rawValue)
        keyValueStore.throwOnSet = CocoaError(.fileWriteNoPermission)
        XCTAssertFalse(manager.didCommitStoreUpdate(first, overrideIdentifier))
        XCTAssertEqual(service.updateCheckVersionOverride(forInstallationIdentifier: "first"), "0.0.0.1")
        keyValueStore.throwOnSet = nil
        XCTAssertTrue(manager.didCommitStoreUpdate(first, overrideIdentifier))
        let relaunched = scheduledService(manager, keyValueStore: keyValueStore) { _, _ in .init(outcome: .noUpdate, retryNotBefore: nil) }
        XCTAssertNil(relaunched.updateCheckVersionOverride(forInstallationIdentifier: "first"))
        XCTAssertEqual(relaunched.updateCheckVersionOverride(forInstallationIdentifier: "second"), "1.0")
    }

    func testFailedOverrideSetResetAndPruneKeepDurableStateRetryable() throws {
        let manager = try makeManager()
        let storeID = ChromeWebStoreID.onePassword.rawValue
        let record = installed("original", version: "2.0", storeID: storeID)
        installationStore.installedExtensions = [record]
        let service = scheduledService(manager, keyValueStore: keyValueStore) { _, _ in .init(outcome: .noUpdate, retryNotBefore: nil) }
        keyValueStore.throwOnSet = CocoaError(.fileWriteNoPermission)
        service.setUpdateCheckVersionOverride("0.0.0.1", forInstallationIdentifier: "original")
        XCTAssertNil(service.updateCheckVersionOverride(forInstallationIdentifier: "original"))
        keyValueStore.throwOnSet = nil
        service.setUpdateCheckVersionOverride("0.0.0.1", forInstallationIdentifier: "original")
        let overrideIdentifier = try persistedOverrideIdentifier(for: storeID)
        keyValueStore.throwOnSet = CocoaError(.fileWriteNoPermission)
        service.setUpdateCheckVersionOverride(nil, forInstallationIdentifier: "original")
        XCTAssertEqual(service.updateCheckVersionOverride(forInstallationIdentifier: "original"), "0.0.0.1")
        installationStore.installedExtensions = [installed("replacement", version: "2.0", storeID: storeID)]
        XCTAssertNil(service.updateCheckVersionOverride(forInstallationIdentifier: "replacement"))
        XCTAssertFalse(manager.didCommitStoreUpdate(try XCTUnwrap(installationStore.installedExtensions.first), overrideIdentifier))
        keyValueStore.throwOnSet = nil
        XCTAssertTrue(manager.didCommitStoreUpdate(try XCTUnwrap(installationStore.installedExtensions.first), overrideIdentifier))
        let relaunched = scheduledService(manager, keyValueStore: keyValueStore) { _, _ in .init(outcome: .noUpdate, retryNotBefore: nil) }
        XCTAssertNil(relaunched.updateCheckVersionOverride(forInstallationIdentifier: "replacement"))
    }

    func testOverrideSetAfterADisabledSameVersionCommitSurvivesRetainedJournalRecovery() async throws {
        let manager = try makeManager()
        let fixture = try ChromeWebStoreFixture(manifest: ["manifest_version": 3, "name": "Reinstall fixture", "version": "1.0", "permissions": ["storage"]])
        let identifier = UUID().uuidString
        let record = installed(identifier, version: "1.0", storeID: fixture.identifier)
        installationStore.installedExtensions = [record]
        let root = manager.storageProvider.extensionsDirectory
        let current = root.appendingPathComponent(identifier)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["manifest_version": 3, "name": "Original", "version": "1.0"])
            .write(to: current.appendingPathComponent("manifest.json"))
        let archive = root.appendingPathComponent("verified.zip")
        try fixture.archive.write(to: archive)
        let service = scheduledService(manager, keyValueStore: keyValueStore) { _, _ in .init(outcome: .noUpdate, retryNotBefore: nil) }
        service.setUpdateCheckVersionOverride("0.0.0.1", forInstallationIdentifier: identifier)
        let consumed = try persistedOverrideIdentifier(for: fixture.identifier)
        let update = ChromeWebStoreVerifiedUpdate(extensionID: fixture.identifier, version: "1.0", fileURL: archive)
        _ = try await manager.applyVerifiedUpdate(update, replacing: record, reportedInstalledVersion: "0.0.0.1",
                                                  versionOverrideIdentifier: consumed, isEligible: { true })
        XCTAssertTrue(try XCTUnwrap(installationStore.installedExtensions.first).isDisabled)
        XCTAssertNil(service.updateCheckVersionOverride(forInstallationIdentifier: identifier))
        service.setUpdateCheckVersionOverride("0.0.0.1", forInstallationIdentifier: identifier)
        let rearmed = try persistedOverrideIdentifier(for: fixture.identifier)
        XCTAssertNotEqual(rearmed, consumed)

        let failures = try await manager.recoverExtensionUpdates(isAllowed: { _ in true })

        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(service.updateCheckVersionOverride(forInstallationIdentifier: identifier), "0.0.0.1")
        XCTAssertEqual(try persistedOverrideIdentifier(for: fixture.identifier), rearmed)
        XCTAssertTrue(manager.didCommitStoreUpdate(try XCTUnwrap(installationStore.installedExtensions.first), nil))
        XCTAssertEqual(service.updateCheckVersionOverride(forInstallationIdentifier: identifier), "0.0.0.1")
    }

    func testRearmingAnOverrideAfterClearFailureCannotBeClearedByTheOldCompletion() throws {
        let manager = try makeManager()
        let record = installed("installed", version: "1.0", storeID: ChromeWebStoreID.bitwarden.rawValue)
        installationStore.installedExtensions = [record]
        let service = scheduledService(manager, keyValueStore: keyValueStore) { _, _ in .init(outcome: .noUpdate, retryNotBefore: nil) }
        service.setUpdateCheckVersionOverride("0.0.0.1", forInstallationIdentifier: "installed")
        let consumed = try persistedOverrideIdentifier(for: ChromeWebStoreID.bitwarden.rawValue)
        keyValueStore.throwOnSet = CocoaError(.fileWriteNoPermission)
        XCTAssertFalse(manager.didCommitStoreUpdate(record, consumed))
        keyValueStore.throwOnSet = nil
        service.setUpdateCheckVersionOverride("0.0.0.1", forInstallationIdentifier: "installed")
        let rearmed = try persistedOverrideIdentifier(for: ChromeWebStoreID.bitwarden.rawValue)

        XCTAssertTrue(manager.didCommitStoreUpdate(record, consumed))
        XCTAssertEqual(try persistedOverrideIdentifier(for: ChromeWebStoreID.bitwarden.rawValue), rearmed)
        XCTAssertEqual(service.updateCheckVersionOverride(forInstallationIdentifier: "installed"), "0.0.0.1")
    }

    private func persistedOverrideIdentifier(for storeID: String) throws -> UUID {
        let data = try XCTUnwrap(keyValueStore.object(forKey: "web-extension-update-version-overrides") as? Data)
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        let rawIdentifier = try XCTUnwrap(values[storeID]?["identifier"] as? String)
        return try XCTUnwrap(UUID(uuidString: rawIdentifier))
    }

    func testLaunchAndManualChecksDoNotOverlap() async throws {
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
        await service.checkForUpdatesNow()
        await service.checkForUpdatesNow()
        await fulfillment(of: [checked], timeout: 1)
    }

    func testManualCheckRunsDuringTwoHourIntervalAndUsesCurrentOverride() async throws {
        let manager = try makeManager()
        installationStore.installedExtensions = [installed("installed", version: "2.0", storeID: ChromeWebStoreID.onePassword.rawValue)]
        var reportedVersions: [String] = []
        let service = scheduledService(manager, interval: 2 * 60 * 60) { _, version in
            reportedVersions.append(version)
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        }
        defer { withExtendedLifetime((manager, service)) {} }
        let store: any ChromeWebStoreManaging = service
        await store.checkForUpdatesNow()
        let previousCount = reportedVersions.count
        XCTAssertGreaterThan(previousCount, 0)
        service.setUpdateCheckVersionOverride("0.0.0.1", forInstallationIdentifier: "installed")
        await store.checkForUpdatesNow()
        XCTAssertEqual(reportedVersions.count, previousCount + 1)
        XCTAssertEqual(reportedVersions.last, "0.0.0.1")
    }

    func testManualChecksCoalesceAndCancellingOneWaiterKeepsBatchAlive() async throws {
        let manager = try makeManager()
        installationStore.installedExtensions = [installed("installed", version: "2.0", storeID: ChromeWebStoreID.onePassword.rawValue)]
        let started = expectation(description: "Shared check started")
        let requested = expectation(description: "Both manual checks requested")
        requested.expectedFulfillmentCount = 2
        var resumeCheck: CheckedContinuation<Void, Never>?
        var count = 0
        let service = scheduledService(manager, interval: 2 * 60 * 60) { _, _ in
            count += 1
            if count == 1 {
                await withCheckedContinuation { continuation in
                    resumeCheck = continuation
                    started.fulfill()
                }
                XCTAssertFalse(Task.isCancelled)
            } else {
                XCTFail("Manual checks must join the same active batch")
            }
            return .init(outcome: .noUpdate, retryNotBefore: nil)
        }
        defer { withExtendedLifetime((manager, service)) {} }
        let first = Task {
            requested.fulfill()
            await service.checkForUpdatesNow()
        }
        let second = Task {
            requested.fulfill()
            await service.checkForUpdatesNow()
        }
        await fulfillment(of: [started, requested], timeout: 1)
        first.cancel()
        resumeCheck?.resume()
        await first.value
        await second.value
        XCTAssertEqual(count, 1)
    }

    func testManualCheckHonorsServerRetryDeadline() async throws {
        let manager = try makeManager()
        installationStore.installedExtensions = [installed("installed", version: "2.0", storeID: ChromeWebStoreID.onePassword.rawValue)]
        var count = 0
        let service = scheduledService(manager, interval: 2 * 60 * 60) { _, _ in
            count += 1
            return .init(outcome: .failure(.httpStatus(503)), retryNotBefore: Date().addingTimeInterval(0.1))
        }
        defer { withExtendedLifetime((manager, service)) {} }
        await service.checkForUpdatesNow()
        XCTAssertEqual(count, 1)
        await service.checkForUpdatesNow()
        XCTAssertEqual(count, 1)
        try await Task.sleep(for: .milliseconds(150))
        await service.checkForUpdatesNow()
        XCTAssertEqual(count, 2)
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
        await service.checkForUpdatesNow()
        await service.checkForUpdatesNow()
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
        await service.checkForUpdatesNow()
        await service.checkForUpdatesNow()
        XCTAssertEqual(count, 1)
        try await Task.sleep(for: .milliseconds(150))
        await service.checkForUpdatesNow()
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
        for _ in identifiers {
            await service.checkForUpdatesNow()
            try await Task.sleep(for: .milliseconds(30))
        }
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
        await service.checkForUpdatesNow()
        await fulfillment(of: [first], timeout: 1)
        await service.checkForUpdatesNow()
        XCTAssertEqual(count, 1)
        catalog.allowed = true
        await service.checkForUpdatesNow()
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
    var catalogEntries: [String: ExtensionsCatalogSubfeature] = [:]
    var learnMoreURL: URL?
    func contains(_ identifier: String) -> Bool { allowed }
    func catalogEntry(of identifier: String) -> ExtensionsCatalogSubfeature? { catalogEntries[identifier] }
    func listing(of subfeature: ExtensionsCatalogSubfeature) -> ChromeWebStoreListing? { nil }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class StorePresenterMock: ChromeWebStorePresenting {
    var errors: [Error] = []
    var removalRequests: [String] = []
    var allowRemoval = true
    var progressVisible = false
    var progressRequests = 0
    var cancelImmediately = false

    func showDownloadProgress(cancel: @escaping () -> Void) {
        progressRequests += 1
        progressVisible = true
        if cancelImmediately { cancel() }
    }
    func dismissDownloadProgress() { progressVisible = false }
    func confirmRemoval(name: String, webExtension: WKWebExtension?) async -> Bool {
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

@available(macOS 15.4, iOS 18.4, *)
private final class StoreUpdatePixelFiringMock: WebExtensionPixelFiring {
    private(set) var extensions: [WebExtensionPixelExtension] = []
    private(set) var outcomes: [WebExtensionUpdateCheckOutcome] = []
    private(set) var preparationEvents: [WebExtensionPixelEvent] = []

    func fire(_ event: WebExtensionPixelEvent) {
        guard case .updateCheck(let pixelExtension, let outcome) = event else {
            preparationEvents.append(event)
            return
        }
        extensions.append(pixelExtension)
        outcomes.append(outcome)
    }
}
