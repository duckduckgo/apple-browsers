//
//  WebExtensionUpdateInstallationTests.swift
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

import WebKit
import XCTest
import ZIPFoundation
import PrivacyConfigTestsUtils
@_spi(Testing) import Persistence
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class WebExtensionUpdateInstallationTests: XCTestCase {
    private let identifier = UUID().uuidString
    private let storeID = ChromeWebStoreID.bitwarden.rawValue
    private let installationStore = InstalledWebExtensionStoringMock()
    private let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try writePackage(version: "1.0", at: directory.appendingPathComponent(identifier))
        installationStore.add(original)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private var original: InstalledWebExtension {
        .init(uniqueIdentifier: identifier, filename: identifier, name: "Fixture", version: "1.0", storeIdentity: .init(store: .chromeWebStore, id: storeID))
    }

    func testPreparationLeavesTheInstalledRecordAndOriginalFilesUntouched() async throws {
        let packages = WebExtensionUpdatePackageStore(extensionsDirectory: directory)
        let prepared = try await packages.prepare(makeUpdate(), installationID: identifier)
        XCTAssertEqual(installationStore.installedExtensions, [original])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(identifier).appendingPathComponent("manifest.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.bundleURL.appendingPathComponent("manifest.json").path))
    }

    func testPreparationAndCleanupDoNotFollowAnExistingPackageDirectorySymlink() async throws {
        let outside = directory.appendingPathComponent(UUID().uuidString)
        let kept = outside.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
        let link = directory.appendingPathComponent(identifier).appendingPathComponent(InstalledWebExtension.packagesDirectoryName)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let packages = WebExtensionUpdatePackageStore(extensionsDirectory: directory)
        do {
            _ = try await packages.prepare(makeUpdate(), installationID: identifier)
            XCTFail("A package-controlled symlink must not redirect update writes")
        } catch WebExtensionUpdatePackageStore.PackageError.invalidPackageLocation { }
        await packages.cleanup(installationIDs: [identifier], selectedPackages: [:])
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))
    }

    func testPublicationAndFreshManagerLoadUseTheCommittedGeneration() async throws {
        let manager = makeManager()
        _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })
        let committed = try XCTUnwrap(installationStore.installedExtensions.first)
        XCTAssertNotNil(committed.packageIdentifier)
        XCTAssertTrue(committed.needsInitialUpdateActivationValidation)
        XCTAssertNil(manager.context(for: identifier))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(identifier).appendingPathComponent("manifest.json").path))
        try recreateInventory()
        let reopened = makeManager()
        await reopened.loadInstalledExtensions()
        XCTAssertEqual(reopened.context(for: identifier)?.webExtension.version, "2.0")
        XCTAssertEqual(installationStore.installedExtensions.first?.needsInitialUpdateActivationValidation, false)
        reopened.unloadAllExtensions()
    }

    func testLegacyImplicitConsentAppliesNewAPIAndHostPermissions() async throws {
        let manager = makeManager()
        let pattern = try WKWebExtension.MatchPattern(string: "https://example.com/*")
        _ = try await manager.applyVerifiedUpdate(makeUpdate(permissions: ["storage"], hosts: [pattern.string]), replacing: original, isEligible: { true })
        await manager.loadInstalledExtensions()
        let context = try XCTUnwrap(manager.context(for: identifier))
        XCTAssertTrue(context.hasPermission(.storage))
        XCTAssertEqual(context.permissionStatus(for: pattern), .grantedExplicitly)
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, false)
        manager.unloadAllExtensions()
    }

    func testMissingConsentWithEnforcementInstallsDisabledWithoutLoading() async throws {
        let manager = makeManager(enforcePermissions: true)
        _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })
        await manager.loadInstalledExtensions()
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, true)
        XCTAssertEqual(installationStore.installedExtensions.first?.needsInitialUpdateActivationValidation, true)
        XCTAssertNil(manager.context(for: identifier))
        XCTAssertNil(try permissionStore.settings(for: identifier))
    }

    func testPermissionIncreaseInstallsDisabledAndKeepsExistingGrants() async throws {
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let manager = makeManager(enforcePermissions: true)
        _ = try await manager.applyVerifiedUpdate(makeUpdate(permissions: ["storage"]), replacing: original, isEligible: { true })
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, true)
        XCTAssertEqual(try permissionStore.settings(for: identifier)?.grantedPermissions, [:])
        XCTAssertNil(manager.context(for: identifier))
    }

    func testPreviouslyDisabledExtensionStaysDisabledInLegacyMode() async throws {
        var disabled = original
        disabled.isDisabled = true
        installationStore.update(disabled)
        let manager = makeManager()
        _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: disabled, isEligible: { true })
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, true)
        XCTAssertNil(manager.context(for: identifier))
    }

    func testManualEnableUsesOldGrantsAndClearsInitialValidationTogether() async throws {
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let manager = makeManager(enforcePermissions: true)
        _ = try await manager.applyVerifiedUpdate(makeUpdate(permissions: ["storage"]), replacing: original, isEligible: { true })
        try await manager.enableExtension(identifier: identifier)
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, false)
        XCTAssertEqual(installationStore.installedExtensions.first?.needsInitialUpdateActivationValidation, false)
        XCTAssertFalse(try XCTUnwrap(manager.context(for: identifier)).hasPermission(.storage))
        manager.unloadAllExtensions()
        let reopened = makeManager(enforcePermissions: true)
        await reopened.loadInstalledExtensions()
        XCTAssertNotNil(reopened.context(for: identifier))
        XCTAssertFalse(try XCTUnwrap(reopened.context(for: identifier)).hasPermission(.storage))
        reopened.unloadAllExtensions()
    }

    func testLegacyManualEnableWorksWithTheStartupInstallerPresent() async throws {
        var disabled = original
        disabled.isDisabled = true
        installationStore.update(disabled)
        let manager = makeManager()
        let installer = ChromeWebStoreUpdateInstaller(manager: manager, pendingUpdates: ChromeWebStorePendingUpdateStore(),
                                                     isEnabled: { true }, isCatalogExtension: { _ in true })
        manager.startupUpdateInstaller = installer
        defer { installer.cancelStartup() }
        await installer.runOnce()
        try await manager.enableExtension(identifier: identifier)
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, false)
        XCTAssertNotNil(manager.context(for: identifier))
        manager.unloadAllExtensions()
    }

    func testConsentRemovedAfterPublicationDisablesTheSelectedPackageOnFreshLoad() async throws {
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let manager = makeManager(enforcePermissions: true)
        _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })
        let committed = try XCTUnwrap(installationStore.installedExtensions.first)
        try permissionStore.removeSettings(for: identifier)
        let reopened = makeManager(enforcePermissions: true)
        await reopened.loadInstalledExtensions()
        let kept = try XCTUnwrap(installationStore.installedExtensions.first)
        XCTAssertEqual(kept.packageIdentifier, committed.packageIdentifier)
        XCTAssertTrue(kept.isDisabled)
        XCTAssertTrue(kept.needsInitialUpdateActivationValidation)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(kept.resourceIdentifier).path))
        XCTAssertNil(reopened.context(for: identifier))
    }

    func testConsentRemovedDuringParsingCannotPromptOrUninstallTheSelectedPackage() async throws {
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let (manager, loader) = makeInterceptedManager(enforcePermissions: true)
        _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })
        loader.beforeLoad = { try self.permissionStore.removeSettings(for: self.identifier) }
        await manager.loadInstalledExtensions()
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, true)
        XCTAssertEqual(installationStore.installedExtensions.first?.needsInitialUpdateActivationValidation, true)
        XCTAssertNil(manager.context(for: identifier))
        XCTAssertNil(try permissionStore.settings(for: identifier))
    }

    func testUninstallDuringFirstLoadCannotActivateOrResurrectThePackage() async throws {
        let (manager, loader) = makeInterceptedManager()
        _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })
        loader.beforeLoad = { try manager.uninstallExtension(identifier: self.identifier) }
        await manager.loadInstalledExtensions()
        XCTAssertTrue(installationStore.installedExtensions.isEmpty)
        XCTAssertNil(manager.context(for: identifier))
    }

    func testDisableDuringFirstLoadPreservesUserStateAndPendingValidation() async throws {
        let (manager, loader) = makeInterceptedManager()
        _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })
        loader.beforeLoadAsync = { _ in try await manager.disableExtension(identifier: self.identifier) }
        await manager.loadInstalledExtensions()
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, true)
        XCTAssertEqual(installationStore.installedExtensions.first?.needsInitialUpdateActivationValidation, true)
        XCTAssertNil(manager.context(for: identifier))
    }

    func testRemoteBlockDuringFirstLoadCannotActivateThePackage() async throws {
        let (manager, loader) = makeInterceptedManager()
        var blocked = false
        manager.remoteDisableEnforcer = WebExtensionRemoteDisableEnforcer(manager: manager, configurationManager: MockPrivacyConfigurationManager(),
                                                                        disabledExtensionIDs: { blocked ? [self.storeID] : [] })
        _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })
        loader.beforeLoad = { blocked = true }
        await manager.loadInstalledExtensions()
        XCTAssertNotNil(installationStore.installedExtensions.first)
        XCTAssertEqual(installationStore.installedExtensions.first?.needsInitialUpdateActivationValidation, true)
        XCTAssertNil(manager.context(for: identifier))
    }

    func testCancellationDuringFirstLoadKeepsTheSelectedPackageAndValidationMarker() async throws {
        let (manager, loader) = makeInterceptedManager()
        _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })
        loader.beforeLoad = { withUnsafeCurrentTask { $0?.cancel() } }
        let operation = Task { await manager.loadInstalledExtensions() }
        await operation.value
        XCTAssertTrue(operation.isCancelled)
        XCTAssertEqual(installationStore.installedExtensions.first?.version, "2.0")
        XCTAssertEqual(installationStore.installedExtensions.first?.needsInitialUpdateActivationValidation, true)
        XCTAssertNil(manager.context(for: identifier))
    }

    func testStaleFirstLoadCannotClearANewerSameVersionPackageMarker() async throws {
        let (manager, loader) = makeInterceptedManager()
        _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })
        let packages = WebExtensionUpdatePackageStore(extensionsDirectory: directory)
        let prepared = try await packages.prepare(makeUpdate(), installationID: identifier)
        let newer = InstalledWebExtension(uniqueIdentifier: identifier, filename: prepared.bundleURL.lastPathComponent, name: "Fixture", version: "2.0",
                                         storeIdentity: original.storeIdentity, packageIdentifier: prepared.identifier, needsInitialUpdateActivationValidation: true)
        loader.beforeLoad = { self.installationStore.update(newer) }
        await manager.loadInstalledExtensions()
        XCTAssertEqual(installationStore.installedExtensions, [newer])
        XCTAssertNil(manager.context(for: identifier))
    }

    func testMissingSelectedPackageDoesNotFallBackToLegacyFiles() async throws {
        let manager = makeManager()
        _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })
        let selected = try XCTUnwrap(installationStore.installedExtensions.first)
        try FileManager.default.removeItem(at: directory.appendingPathComponent(selected.resourceIdentifier))
        let loader = WebExtensionLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), installationStore: installationStore)
        do {
            _ = try await loader.loadWebExtension(identifier: identifier, into: manager.controller)
            XCTFail("A missing selected package must not load the old files")
        } catch { }
        XCTAssertNil(manager.context(for: identifier))
    }

    func testWorkerCopiesBelongToTheirGenerationEvenWithEqualManifestTimestamps() async throws {
        let manager = makeManager()
        _ = try await manager.applyVerifiedUpdate(makeUpdate(backgroundWorker: true), replacing: original, isEligible: { true })
        await manager.loadInstalledExtensions()
        XCTAssertEqual(manager.context(for: identifier)?.webExtension.version, "2.0")
        manager.unloadAllExtensions()
        let first = try XCTUnwrap(installationStore.installedExtensions.first)
        _ = try await manager.applyVerifiedUpdate(makeUpdate(version: "3.0", backgroundWorker: true), replacing: first, isEligible: { true })
        await manager.loadInstalledExtensions()
        XCTAssertEqual(manager.context(for: identifier)?.webExtension.version, "3.0")
        manager.unloadAllExtensions()
    }

    func testEligibilityChangeAfterPreparationDoesNotPublish() async throws {
        let manager = makeManager()
        let packages = directory.appendingPathComponent(identifier).appendingPathComponent(InstalledWebExtension.packagesDirectoryName)
        do {
            _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: {
                !FileManager.default.fileExists(atPath: packages.path)
            })
            XCTFail("The final eligibility check must prevent publication")
        } catch WebExtensionManager.UpdateInstallationError.installationChanged { }
        XCTAssertEqual(installationStore.installedExtensions, [original])
    }

    func testVersionMismatchLeavesOldSelectionIntact() async throws {
        let manager = makeManager()
        let update = try makeUpdate()
        do {
            _ = try await manager.applyVerifiedUpdate(.init(extensionID: storeID, version: "3.0", fileURL: update.fileURL), replacing: original, isEligible: { true })
            XCTFail("Advertised and package versions must match")
        } catch WebExtensionManager.UpdateInstallationError.invalidPackage { }
        XCTAssertEqual(installationStore.installedExtensions, [original])
    }

    func testSameVersionRequiresOverrideAndCannotPermitRealDowngrade() async throws {
        let manager = makeManager()
        let update = try makeUpdate(version: "1.0")
        do {
            _ = try await manager.applyVerifiedUpdate(update, replacing: original, isEligible: { true })
            XCTFail("Same version requires a debug override")
        } catch WebExtensionManager.UpdateInstallationError.invalidPackage { }
        let consumed = UUID()
        _ = try await manager.applyVerifiedUpdate(update, replacing: original, reportedInstalledVersion: "0.0.0.1",
                                                 versionOverrideIdentifier: consumed, isEligible: { true })
        let committed = try XCTUnwrap(installationStore.installedExtensions.first)
        XCTAssertEqual(committed.consumedVersionOverrideIdentifier, consumed)
        do {
            _ = try await manager.applyVerifiedUpdate(makeUpdate(version: "0.9"), replacing: committed,
                                                     reportedInstalledVersion: "0.0.0.1", isEligible: { true })
            XCTFail("Debug overrides cannot permit a real downgrade")
        } catch WebExtensionManager.UpdateInstallationError.invalidPackage { }
    }

    func testCleanupRetainsTheFreshlySelectedGenerationAndRemovesTheOtherOne() async throws {
        let manager = makeManager()
        _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })
        let first = try XCTUnwrap(installationStore.installedExtensions.first)
        _ = try await manager.applyVerifiedUpdate(makeUpdate(version: "3.0"), replacing: first, isEligible: { true })
        let second = try XCTUnwrap(installationStore.installedExtensions.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(first.resourceIdentifier).path))
        try recreateInventory()
        await makeManager().cleanupUnselectedUpdatePackages()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(first.resourceIdentifier).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(second.resourceIdentifier).path))
    }

    func testLostPublicationKeepsTheOldCompleteSelectionUsable() async throws {
        let manager = makeManager()
        _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })
        let first = try XCTUnwrap(installationStore.installedExtensions.first)
        _ = try await manager.applyVerifiedUpdate(makeUpdate(version: "3.0"), replacing: first, isEligible: { true })
        installationStore.installedExtensions = [first]
        try recreateInventory()
        let reopened = makeManager()
        await reopened.cleanupUnselectedUpdatePackages()
        await reopened.loadInstalledExtensions()
        XCTAssertEqual(reopened.context(for: identifier)?.webExtension.version, "2.0")
        reopened.unloadAllExtensions()
    }

    func testLostFirstActivationAcknowledgementRevalidatesWithoutChangingPackage() async throws {
        let manager = makeManager()
        _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })
        let committed = try XCTUnwrap(installationStore.installedExtensions.first)
        await manager.loadInstalledExtensions()
        manager.unloadAllExtensions()
        installationStore.installedExtensions = [committed]
        let reopened = makeManager()
        await reopened.loadInstalledExtensions()
        XCTAssertEqual(installationStore.installedExtensions.first?.packageIdentifier, committed.packageIdentifier)
        XCTAssertEqual(installationStore.installedExtensions.first?.needsInitialUpdateActivationValidation, false)
        reopened.unloadAllExtensions()
    }

    func testNativeLoadFailureDoesNotRestoreThePreviousVersion() async throws {
        let (manager, loader) = makeInterceptedManager()
        _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })
        loader.rejectLoad = true
        await manager.loadInstalledExtensions()
        XCTAssertTrue(installationStore.installedExtensions.isEmpty, "Normal broken-extension handling applies; do not restore the predecessor")
        XCTAssertNil(manager.context(for: identifier))
    }

    func testStaleBatchEntryPreservesHandlersOfTheManuallyEnabledContext() async throws {
        let (manager, loader) = makeInterceptedManager()
        _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })
        let second = try XCTUnwrap(installationStore.installedExtensions.first)
        let firstID = UUID().uuidString
        try writePackage(version: "1.0", at: directory.appendingPathComponent(firstID))
        let first = InstalledWebExtension(uniqueIdentifier: firstID, filename: firstID, name: "First fixture", version: "1.0",
                                         storeIdentity: .init(store: .chromeWebStore, id: ChromeWebStoreID.onePassword.rawValue),
                                         needsInitialUpdateActivationValidation: true)
        installationStore.installedExtensions = [first, second]
        let handler = MockMessageHandler(featureName: "update-probe")
        var enabledContext: WKWebExtensionContext?
        loader.beforeLoadAsync = { loadedID in
            guard loadedID == firstID else { return }
            try await manager.disableExtension(identifier: self.identifier)
            try await manager.enableExtension(identifier: self.identifier)
            enabledContext = manager.context(for: self.identifier)
            manager.registerMessageHandler(handler, for: self.identifier)
            XCTAssertTrue(manager.messageRouter.hasHandler(for: self.identifier, featureName: handler.handledFeatureName))
        }

        await manager.loadInstalledExtensions()

        XCTAssertNotNil(enabledContext)
        XCTAssertTrue(manager.context(for: identifier) === enabledContext)
        XCTAssertTrue(manager.messageRouter.hasHandler(for: identifier, featureName: handler.handledFeatureName))
        let message = WebExtensionMessage(featureName: handler.handledFeatureName, method: "probe", id: nil, context: identifier, extensionIdentifier: identifier)
        _ = await manager.messageRouter.routeMessage(message)
        XCTAssertEqual(handler.receivedMessages.count, 1)
        manager.unloadAllExtensions()
    }

    func testCancelledFirstLoadPreservesLiveHandlersWhenUnloadingFails() async throws {
        let (manager, loader) = makeInterceptedManager()
        _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })
        let handler = MockMessageHandler(featureName: "update-probe")
        loader.rejectUnload = true
        loader.afterLoad = {
            XCTAssertNotNil(manager.context(for: self.identifier), "The failure must happen after actual native activation")
            manager.registerMessageHandler(handler, for: self.identifier)
            withUnsafeCurrentTask { $0?.cancel() }
        }
        let operation = Task { await manager.loadInstalledExtensions() }

        await operation.value

        XCTAssertTrue(operation.isCancelled)
        XCTAssertEqual(loader.unloadAttempts, 1)
        XCTAssertNotNil(manager.context(for: identifier))
        XCTAssertTrue(manager.messageRouter.hasHandler(for: identifier, featureName: handler.handledFeatureName))
        XCTAssertEqual(installationStore.installedExtensions.first?.needsInitialUpdateActivationValidation, true)
        let message = WebExtensionMessage(featureName: handler.handledFeatureName, method: "probe", id: nil, context: identifier, extensionIdentifier: identifier)
        _ = await manager.messageRouter.routeMessage(message)
        XCTAssertEqual(handler.receivedMessages.count, 1)
        loader.rejectUnload = false
        manager.unloadAllExtensions()
    }

    func testLegacyRecordDecodingDefaultsToTheOriginalLayoutWithoutActivationGate() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        for key in ["packageIdentifier", "consumedVersionOverrideIdentifier", "needsInitialUpdateActivationValidation"] { object.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(InstalledWebExtension.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.packageIdentifier)
        XCTAssertFalse(decoded.needsInitialUpdateActivationValidation)
        XCTAssertEqual(decoded.resourceIdentifier, identifier)
    }

    func testUnreadableOldDebugJournalDoesNotBlockLoadingOrDeleteItsBackup() async throws {
        let backup = directory.appendingPathComponent(".update-transactions/old-debug-transaction/previous")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try Data("unreadable journal".utf8).write(to: backup.deletingLastPathComponent().appendingPathComponent("journal.json"))
        let manager = makeManager()
        await manager.loadInstalledExtensions()
        XCTAssertEqual(manager.context(for: identifier)?.webExtension.version, "1.0")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        manager.unloadAllExtensions()
    }

    private func recreateInventory() throws {
        installationStore.installedExtensions = try JSONDecoder().decode([InstalledWebExtension].self, from: JSONEncoder().encode(installationStore.installedExtensions))
    }

    private func makeManager(enforcePermissions: Bool = false) -> WebExtensionManager {
        let permissions = enforcePermissions ? WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt()) : nil
        return WebExtensionManager(configuration: WebExtensionConfigurationProvidingMock(), controllerConfiguration: .nonPersistent(),
                                   windowTabProvider: WebExtensionWindowTabProvidingMock(), storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory),
                                   installationStore: installationStore, permissionController: permissions)
    }

    private func makeInterceptedManager(enforcePermissions: Bool = false) -> (WebExtensionManager, UpdateTestLoader) {
        let permissions = enforcePermissions ? WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt()) : nil
        let storage = WebExtensionStorageProvider(extensionsDirectory: directory)
        let loader = UpdateTestLoader(storage: storage, installations: installationStore, permissions: permissions)
        let manager = WebExtensionManager(configuration: WebExtensionConfigurationProvidingMock(), controllerConfiguration: .nonPersistent(),
                                          windowTabProvider: WebExtensionWindowTabProvidingMock(), storageProvider: storage,
                                          installationStore: installationStore, permissionController: permissions, loader: loader)
        return (manager, loader)
    }

    private func makeUpdate(version: String = "2.0", permissions: [String] = [], hosts: [String] = [], backgroundWorker: Bool = false) throws -> ChromeWebStoreVerifiedUpdate {
        let folder = directory.appendingPathComponent(UUID().uuidString)
        try writePackage(version: version, at: folder, permissions: permissions, hosts: hosts)
        if backgroundWorker {
            var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("manifest.json"))) as? [String: Any])
            manifest["background"] = ["service_worker": "worker.js"]
            try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
            try "// Empty fixture worker".write(to: folder.appendingPathComponent("worker.js"), atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceReferenceDate: 0)], ofItemAtPath: folder.appendingPathComponent("manifest.json").path)
        }
        let archive = folder.appendingPathExtension("zip")
        try FileManager.default.zipItem(at: folder, to: archive, shouldKeepParent: false)
        try FileManager.default.removeItem(at: folder)
        return .init(extensionID: storeID, version: version, fileURL: archive)
    }

    private func writePackage(version: String, at folder: URL, permissions: [String] = [], hosts: [String] = []) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Fixture", "version": version, "permissions": permissions, "host_permissions": hosts]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class UpdateTestLoader: WebExtensionLoading {
    enum LoadError: Error { case injected, injectedUnload }
    private let base: WebExtensionLoader
    var beforeLoad: (() throws -> Void)?
    var beforeLoadAsync: ((String) async throws -> Void)?
    var afterLoad: (() -> Void)?
    var rejectLoad = false
    var rejectUnload = false
    private(set) var unloadAttempts = 0
    var delegate: WebExtensionLoadingDelegate? { get { base.delegate } set { base.delegate = newValue } }

    init(storage: WebExtensionStorageProviding, installations: InstalledWebExtensionStoring, permissions: WebExtensionPermissionController?) {
        base = WebExtensionLoader(storageProvider: storage, permissionController: permissions, installationStore: installations)
    }

    func loadWebExtension(identifier: String, into controller: WKWebExtensionController) async throws -> WebExtensionLoadResult {
        try await loadWebExtension(identifier: identifier, into: controller, beforeActivation: { _ in })
    }

    func loadWebExtension(identifier: String, into controller: WKWebExtensionController,
                          beforeActivation: @MainActor (WKWebExtension) throws -> Void) async throws -> WebExtensionLoadResult {
        try beforeLoad?()
        try await beforeLoadAsync?(identifier)
        if rejectLoad { throw LoadError.injected }
        let result = try await base.loadWebExtension(identifier: identifier, into: controller, beforeActivation: beforeActivation)
        afterLoad?()
        return result
    }

    func loadWebExtensions(identifiers: [String], into controller: WKWebExtensionController) async -> [Result<WebExtensionLoadResult, Error>] {
        await base.loadWebExtensions(identifiers: identifiers, into: controller)
    }

    func unloadExtension(identifier: String, from controller: WKWebExtensionController) throws {
        unloadAttempts += 1
        if rejectUnload { throw LoadError.injectedUnload }
        try base.unloadExtension(identifier: identifier, from: controller)
    }

    func reloadWebExtension(_ webExtension: WKWebExtension, identifier: String, into controller: WKWebExtensionController) async throws {
        try await base.reloadWebExtension(webExtension, identifier: identifier, into: controller)
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private struct NoUpdatePrompt: WebExtensionPermissionPrompting {
    func confirmInstallation(of webExtension: WKWebExtension, permissions: WebExtensionPermissionRequest) async -> WebExtensionPermissionInstallationPromptResult {
        XCTFail("Automatic updates must not show an installation prompt")
        return .denied
    }
    func confirmPermissions(_ permissions: WebExtensionPermissionRequest, for context: WKWebExtensionContext) async -> WebExtensionPermissionPromptResult {
        XCTFail("Automatic updates must not request new access")
        return .denied
    }
}
