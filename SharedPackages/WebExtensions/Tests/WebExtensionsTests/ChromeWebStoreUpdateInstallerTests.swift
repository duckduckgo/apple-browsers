//
//  ChromeWebStoreUpdateInstallerTests.swift
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
import ZIPFoundation
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class ChromeWebStoreUpdateInstallerTests: XCTestCase {
    private let installationID = UUID().uuidString
    private let storeID = ChromeWebStoreID.bitwarden.rawValue
    private let installationStore = InstalledWebExtensionStoringMock()
    private let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
    private var directory: URL!
    private var extensionsDirectory: URL!
    private var pending: ChromeWebStorePendingUpdateStore!
    private var manager: WebExtensionManager!
    private var installer: ChromeWebStoreUpdateInstaller?

    private var original: InstalledWebExtension {
        .init(uniqueIdentifier: installationID, filename: installationID, name: "Startup fixture", version: "1.0",
              storeIdentity: .init(store: .chromeWebStore, id: storeID))
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        extensionsDirectory = directory.appendingPathComponent("Extensions")
        try writePackage(version: "1.0", at: extensionsDirectory.appendingPathComponent(installationID))
        installationStore.add(original)
        try permissionStore.save(WebExtensionPermissionSettings(), for: installationID)
        pending = ChromeWebStorePendingUpdateStore(persistentDirectory: extensionsDirectory.appendingPathComponent(".pending-updates"))
        manager = makeManager()
    }

    override func tearDown() async throws {
        await installer?.cancelAndWait()
        manager.unloadAllExtensions()
        installer = nil
        manager = nil
        pending = nil
        try FileManager.default.removeItem(at: directory)
    }

    func testStartupAppliesVerifiedPendingBeforeTheOrdinaryInstalledExtensionLoad() async throws {
        _ = try await pending.store(makeUpdate(version: "2.0"))
        let owner = makeInstaller()

        await manager.loadInstalledExtensions()

        XCTAssertTrue(owner.isSnapshotReady)
        XCTAssertEqual(installationStore.installedExtensions.first?.version, "2.0")
        XCTAssertEqual(manager.context(for: installationID)?.webExtension.version, "2.0")
        let remaining = await pending.pendingUpdate(for: storeID)
        XCTAssertNil(remaining)
    }

    func testPackagesAcceptedAfterTheFixedSnapshotWaitForAnotherLaunch() async throws {
        let owner = makeInstaller()
        await waitForSnapshot(owner)
        _ = try await pending.store(makeUpdate(version: "2.0"))

        await manager.loadInstalledExtensions()
        _ = await owner.runOnce()

        XCTAssertEqual(installationStore.installedExtensions.first?.version, "1.0")
        XCTAssertEqual(manager.context(for: installationID)?.webExtension.version, "1.0")
        let remaining = await pending.pendingUpdate(for: storeID)
        XCTAssertEqual(remaining?.version, "2.0")
    }

    func testStartupUsesTheOverrideForAVerifiedSameVersionReinstall() async throws {
        _ = try await pending.store(makeUpdate(version: "1.0"))
        let owner = makeInstaller()
        let overrideIdentifier = UUID()
        owner.versionOverride = { _ in ("0.0.0.1", overrideIdentifier) }
        var committed = false
        manager.didCommitStoreUpdate = { _, identifier in
            XCTAssertEqual(identifier, overrideIdentifier)
            committed = true
            return true
        }

        await manager.loadInstalledExtensions()

        XCTAssertTrue(committed)
        XCTAssertEqual(manager.context(for: installationID)?.webExtension.version, "1.0")
        let remaining = await pending.pendingUpdate(for: storeID)
        XCTAssertNil(remaining)
    }

    func testStartupWithoutOverrideRejectsSameVersionAndOverrideCannotPermitRealDowngrade() async throws {
        _ = try await pending.store(makeUpdate(version: "1.0"))
        let owner = makeInstaller()
        var committed = false
        manager.didCommitStoreUpdate = { _, _ in committed = true; return true }

        _ = await owner.runOnce()

        XCTAssertFalse(committed)
        XCTAssertEqual(installationStore.installedExtensions, [original])
        XCTAssertFalse(WebExtensionManager.isVersionEligibleForUpdate("0.9", installedVersion: "1.0", reportedInstalledVersion: "0.0.0.1"))
    }

    func testReinstalledStoreIdentityCannotConsumeThePreviousInstallationPackage() async throws {
        _ = try await pending.store(makeUpdate(version: "2.0", binding: UUID().uuidString))
        let owner = makeInstaller()

        _ = await owner.runOnce()

        XCTAssertEqual(installationStore.installedExtensions, [original])
        XCTAssertNil(manager.context(for: installationID))
        let remaining = await pending.pendingUpdate(for: storeID)
        XCTAssertNil(remaining)
    }

    func testFeatureDisabledDuringCopyDefersAndDoesNotDiscardThePackage() async throws {
        _ = try await pending.store(makeUpdate(version: "2.0"))
        let proxy = StartupPendingStoreProxy(base: pending)
        var enabled = true
        proxy.onCopy = { enabled = false }
        let owner = makeInstaller(store: proxy, isEnabled: { enabled })

        _ = await owner.runOnce()
        enabled = true
        _ = await owner.runOnce()

        XCTAssertEqual(installationStore.installedExtensions, [original])
        let remaining = await pending.pendingUpdate(for: storeID)
        XCTAssertEqual(remaining?.version, "2.0", "Flag re-enabling does not activate in-session")
    }

    func testFeatureDisabledAfterStagingIsAnEligibilityDeferralRatherThanAnInstallFailure() async throws {
        let pixels = WebExtensionUpdatePixelFiringMock()
        manager = makeManager(pixels: pixels)
        _ = try await pending.store(makeUpdate(version: "2.0"))
        var enabled = true
        let transactionRoot = extensionsDirectory.appendingPathComponent(".update-transactions")
        let owner = makeInstaller(isEnabled: {
            if FileManager.default.fileExists(atPath: transactionRoot.path) { enabled = false }
            return enabled
        })

        _ = await owner.runOnce()

        XCTAssertFalse(enabled)
        XCTAssertEqual(installationStore.installedExtensions, [original])
        XCTAssertNil(manager.context(for: installationID))
        let remaining = await pending.pendingUpdate(for: storeID)
        XCTAssertEqual(remaining?.version, "2.0")
        XCTAssertTrue(pixels.events.isEmpty)
    }

    func testNewerDownloadCannotDeleteTheArchiveBeingAppliedAndWaitsForNextLaunch() async throws {
        let pixels = WebExtensionUpdatePixelFiringMock()
        manager = makeManager(pixels: pixels)
        _ = try await pending.store(makeUpdate(version: "2.0"))
        let proxy = StartupPendingStoreProxy(base: pending)
        proxy.onCopy = { _ = try await self.pending.store(self.makeUpdate(version: "3.0")) }
        let owner = makeInstaller(store: proxy)

        _ = await owner.runOnce()

        XCTAssertEqual(installationStore.installedExtensions.first?.version, "2.0")
        XCTAssertEqual(manager.context(for: installationID)?.webExtension.version, "2.0")
        let remaining = await pending.pendingUpdate(for: storeID)
        XCTAssertEqual(remaining?.version, "3.0")
        XCTAssertEqual(pixels.events, [.applied(.other)], "The later session download is not applied or reported yet")
    }

    func testNewestPackageReplacesDisabledCandidateWhileKeepingTheWorkingPredecessor() async throws {
        let pixels = WebExtensionUpdatePixelFiringMock()
        manager = makeManager(pixels: pixels)
        _ = try await manager.applyVerifiedUpdate(makeUpdate(version: "2.0", permissions: ["storage"]), replacing: original, isEligible: { true })
        pixels.reset()
        _ = try await pending.store(makeUpdate(version: "3.0", permissions: ["storage"]))
        let owner = makeInstaller()

        _ = await owner.runOnce()

        let installed = try XCTUnwrap(installationStore.installedExtensions.first)
        XCTAssertEqual(installed.version, "3.0")
        XCTAssertTrue(installed.isDisabled)
        XCTAssertNil(manager.context(for: installationID))
        let transactions = WebExtensionUpdateTransactionStore(extensionsDirectory: extensionsDirectory)
        let journals = try await transactions.journals()
        let predecessor = try JSONDecoder().decode(InstalledWebExtension.self, from: XCTUnwrap(journals.first).previousMetadata)
        XCTAssertEqual(predecessor.version, "1.0")
        XCTAssertEqual(pixels.events, [.applied(.other)], "Preparing a newer disabled package is not a failed-update rollback")
    }

    func testOfferOlderThanDisabledCandidateCannotTriggerPredecessorRestoration() async throws {
        _ = try await manager.applyVerifiedUpdate(makeUpdate(version: "2.0", permissions: ["storage"]), replacing: original, isEligible: { true })
        _ = try await pending.store(makeUpdate(version: "1.5"))
        let owner = makeInstaller()

        _ = await owner.runOnce()

        XCTAssertEqual(installationStore.installedExtensions.first?.version, "2.0")
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, true)
        let transactions = WebExtensionUpdateTransactionStore(extensionsDirectory: extensionsDirectory)
        let journals = try await transactions.journals()
        XCTAssertEqual(journals.first?.phase, .committed)
        XCTAssertEqual(journals.first?.version, "2.0")
    }

    func testPackageAcceptedAfterUninstallIsPrunedWithoutStartingAnInstallation() async throws {
        let proxy = StartupPendingStoreProxy(base: pending)
        let removed = expectation(description: "stale accepted package removed")
        removed.assertForOverFulfill = false
        proxy.onRemove = { _ in removed.fulfill() }
        let owner = makeInstaller(store: proxy)
        await waitForSnapshot(owner)
        try manager.uninstallExtension(identifier: installationID)

        _ = try await pending.store(makeUpdate(version: "2.0"))
        await fulfillment(of: [removed], timeout: 1)

        XCTAssertTrue(installationStore.installedExtensions.isEmpty)
        let remaining = await pending.pendingUpdate(for: storeID)
        XCTAssertNil(remaining)
    }

    func testKnownRecoveryFailurePreservesConsentAndBackupWhileUnrelatedExtensionLoads() async throws {
        let transactions = WebExtensionUpdateTransactionStore(extensionsDirectory: extensionsDirectory)
        let update = try makeUpdate(version: "2.0")
        let staged = try await transactions.stage(update, installationID: installationID, previousVersion: original.version,
                                                  previousMetadata: JSONEncoder().encode(original))
        try await transactions.replace(staged)
        let fileManager = FailingStartupRecoveryFileManager()
        let pixels = WebExtensionUpdatePixelFiringMock()
        manager = makeManager(fileManager: fileManager, pixels: pixels)
        let unrelatedID = UUID().uuidString
        try writePackage(version: "1.0", at: extensionsDirectory.appendingPathComponent(unrelatedID))
        installationStore.add(.init(uniqueIdentifier: unrelatedID, filename: unrelatedID, name: "Unrelated", version: "1.0"))
        try permissionStore.save(WebExtensionPermissionSettings(), for: unrelatedID)
        _ = makeInstaller()

        await manager.loadInstalledExtensions()

        XCTAssertNotNil(installationStore.installedExtension(withUniqueIdentifier: installationID))
        XCTAssertNotNil(try permissionStore.settings(for: installationID))
        XCTAssertNil(manager.context(for: installationID))
        XCTAssertNotNil(manager.context(for: unrelatedID))
        let backup = extensionsDirectory.appendingPathComponent(".update-transactions").appendingPathComponent(staged.transactionID.uuidString).appendingPathComponent("previous")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertEqual(pixels.events, [.failed(.other, .rollbackFailure)])
    }

    func testCleanupOnlyFailureDuringSupersessionDefersTheValidPackageWithoutBlockingThePredecessor() async throws {
        let pixels = WebExtensionUpdatePixelFiringMock()
        manager = makeManager(fileManager: FailingStartupCleanupFileManager(), pixels: pixels)
        _ = try await manager.applyVerifiedUpdate(makeUpdate(version: "2.0", permissions: ["storage"]), replacing: original, isEligible: { true })
        _ = try await pending.store(makeUpdate(version: "3.0", permissions: ["storage"]))
        pixels.reset()
        let owner = makeInstaller()

        _ = await owner.runOnce()

        let remaining = await pending.pendingUpdate(for: storeID)
        XCTAssertEqual(remaining?.version, "3.0")
        XCTAssertEqual(installationStore.installedExtensions.first?.version, "1.0")
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, true)
        try await manager.enableExtension(identifier: installationID)
        XCTAssertEqual(manager.context(for: installationID)?.webExtension.version, "1.0")
        XCTAssertNotNil(try permissionStore.settings(for: installationID))
        XCTAssertTrue(pixels.events.isEmpty, "Residual cleanup ownership is a deferral, not an installation or rollback failure")
    }

    private func makeManager(fileManager: FileManager = .default, pixels: WebExtensionPixelFiring = NoOpWebExtensionPixelFiring()) -> WebExtensionManager {
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: StartupNoPrompt())
        return WebExtensionManager(configuration: WebExtensionConfigurationProvidingMock(), controllerConfiguration: .nonPersistent(),
                                   windowTabProvider: WebExtensionWindowTabProvidingMock(),
                                   storageProvider: WebExtensionStorageProvider(extensionsDirectory: extensionsDirectory, fileManager: fileManager),
                                   installationStore: installationStore, permissionController: permissions, pixelFiring: pixels)
    }

    @discardableResult
    private func makeInstaller(store: (any ChromeWebStorePendingUpdateStoring)? = nil, isEnabled: @escaping () -> Bool = { true }) -> ChromeWebStoreUpdateInstaller {
        let owner = ChromeWebStoreUpdateInstaller(manager: manager, pendingUpdates: store ?? pending,
                                                  isEnabled: isEnabled, isCatalogExtension: { _ in true })
        installer = owner
        manager.startupUpdateInstaller = owner
        return owner
    }

    private func waitForSnapshot(_ owner: ChromeWebStoreUpdateInstaller) async {
        guard !owner.isSnapshotReady else { return }
        let ready = expectation(description: "fixed pre-discovery startup snapshot")
        owner.onSnapshotReady = { ready.fulfill() }
        await fulfillment(of: [ready], timeout: 1)
    }

    private func makeUpdate(version: String, permissions: [String] = [], binding: String? = nil) throws -> ChromeWebStoreVerifiedUpdate {
        let source = directory.appendingPathComponent(UUID().uuidString)
        try writePackage(version: version, at: source, permissions: permissions)
        let archive = source.appendingPathExtension("zip")
        try FileManager.default.zipItem(at: source, to: archive, shouldKeepParent: false)
        return .init(extensionID: storeID, version: version, fileURL: archive, installationIdentifier: binding ?? installationID)
    }

    private func writePackage(version: String, at url: URL, permissions: [String] = []) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Startup fixture", "version": version, "permissions": permissions]
        try JSONSerialization.data(withJSONObject: manifest).write(to: url.appendingPathComponent("manifest.json"))
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class StartupPendingStoreProxy: ChromeWebStorePendingUpdateStoring {
    let base: ChromeWebStorePendingUpdateStore
    var onCopy: (() async throws -> Void)?
    var onRemove: ((ChromeWebStoreVerifiedUpdate) -> Void)?
    init(base: ChromeWebStorePendingUpdateStore) { self.base = base }
    func pendingUpdate(for extensionID: String) async -> ChromeWebStoreVerifiedUpdate? { await base.pendingUpdate(for: extensionID) }
    func store(_ update: ChromeWebStoreVerifiedUpdate) async throws -> Bool { try await base.store(update) }
    func allPendingUpdates() async throws -> [ChromeWebStoreVerifiedUpdate] { try await base.allPendingUpdates() }
    func copyForInstallation(_ update: ChromeWebStoreVerifiedUpdate) async throws -> ChromeWebStoreVerifiedUpdate? {
        let copy = try await base.copyForInstallation(update)
        try await onCopy?()
        return copy
    }
    func remove(_ update: ChromeWebStoreVerifiedUpdate) async throws { try await base.remove(update); onRemove?(update) }
    func removeInstallationCopy(_ update: ChromeWebStoreVerifiedUpdate) async throws { try await base.removeInstallationCopy(update) }
    func cleanupAbandonedInstallationCopies() async throws { try await base.cleanupAbandonedInstallationCopies() }
    func setUpdateStoredHandler(_ handler: (@Sendable (ChromeWebStoreVerifiedUpdate) -> Void)?) async { await base.setUpdateStoredHandler(handler) }
}

private final class FailingStartupRecoveryFileManager: FileManager, @unchecked Sendable {
    override func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        if sourceURL.lastPathComponent == "previous" { throw CocoaError(.fileWriteNoPermission) }
        try super.moveItem(at: sourceURL, to: destinationURL)
    }
}

private final class FailingStartupCleanupFileManager: FileManager, @unchecked Sendable {
    override func removeItem(at url: URL) throws {
        if url.deletingLastPathComponent().lastPathComponent == ".update-transactions" { throw CocoaError(.fileWriteNoPermission) }
        try super.removeItem(at: url)
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private struct StartupNoPrompt: WebExtensionPermissionPrompting {
    func confirmInstallation(of webExtension: WKWebExtension, permissions: WebExtensionPermissionRequest) async -> WebExtensionPermissionInstallationPromptResult {
        XCTFail("Startup updates must never prompt for installation consent")
        return .denied
    }
    func confirmPermissions(_ permissions: WebExtensionPermissionRequest, for context: WKWebExtensionContext) async -> WebExtensionPermissionPromptResult {
        XCTFail("Startup updates must never grant new access")
        return .denied
    }
}
