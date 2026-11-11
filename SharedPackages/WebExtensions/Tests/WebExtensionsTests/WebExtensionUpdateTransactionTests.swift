//
//  WebExtensionUpdateTransactionTests.swift
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
final class WebExtensionUpdateTransactionTests: XCTestCase {
    private let identifier = UUID().uuidString
    private let storeID = ChromeWebStoreID.bitwarden.rawValue
    private var directory: URL!
    private var transactions: WebExtensionUpdateTransactionStore!
    private let installationStore = InstalledWebExtensionStoringMock()

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        transactions = WebExtensionUpdateTransactionStore(extensionsDirectory: directory)
        try writePackage(version: "1.0", at: currentDirectory)
    }

    override func tearDownWithError() throws {
        transactions = nil
        try FileManager.default.removeItem(at: directory)
    }

    private var currentDirectory: URL { directory.appendingPathComponent(identifier, isDirectory: true) }
    private var original: InstalledWebExtension {
        .init(uniqueIdentifier: identifier, filename: identifier, name: "Update fixture", version: "1.0",
              storeIdentity: .init(store: .chromeWebStore, id: storeID))
    }

    func testRollbackRestoresTheEntirePredecessorDirectory() async throws {
        try Data("old derived files".utf8).write(to: currentDirectory.appendingPathComponent("derived.txt"))
        let staged = try await stage()
        XCTAssertEqual(try installedVersion(), "1.0", "Staging must not touch the live installation")
        try await transactions.replace(staged)
        XCTAssertEqual(try installedVersion(), "2.0")

        try await transactions.rollback(staged.transactionID, restoreInstallation: true)

        XCTAssertEqual(try installedVersion(), "1.0")
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentDirectory.appendingPathComponent("derived.txt").path))
        try await assertRollbackIntent()
        try await transactions.finish(staged.transactionID)
        let remaining = try await transactions.journals()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testInterruptedReplacementRecoversAfterStoreRecreation() async throws {
        let previousMetadata = try JSONEncoder().encode(original)
        let staged = try await stage(previousMetadata: previousMetadata)
        try await transactions.replace(staged)
        transactions = WebExtensionUpdateTransactionStore(extensionsDirectory: directory)
        let journal = try await onlyJournal()

        let metadata = try await transactions.recover(journal, installationStillMatches: true)

        XCTAssertEqual(metadata, previousMetadata)
        XCTAssertEqual(try installedVersion(), "1.0")
    }

    func testCrashBetweenTheTwoRenamesRestoresTheBackup() async throws {
        let staged = try await stage()
        try await transactions.replace(staged)
        // This is the filesystem state after current-to-backup but before staged-to-current.
        try FileManager.default.removeItem(at: currentDirectory)

        _ = try await transactions.recover(try await onlyJournal(), installationStillMatches: true)

        XCTAssertEqual(try installedVersion(), "1.0")
    }

    func testCommittedRecoveryRetainsJournalUntilRegistryWriteFinishes() async throws {
        let staged = try await stage()
        let metadata = Data("committed registry value".utf8)
        try await transactions.replace(staged)
        try await transactions.commit(staged, updatedMetadata: metadata, retainPrevious: false)

        let recovered = try await transactions.recover(try await onlyJournal(), installationStillMatches: true)

        XCTAssertEqual(recovered, metadata)
        XCTAssertEqual(try installedVersion(), "2.0")
        let remaining = try await transactions.journals()
        XCTAssertEqual(remaining.count, 1, "Recovery must not delete the journal before the caller updates its registry")
        try await transactions.finish(staged.transactionID)
    }

    func testSameVersionReinstallRequiresOverrideAndStillChecksActualVersionAndPermissions() async throws {
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let manager = makeManager(loader: loader, permissions: permissions)
        installationStore.add(original)
        let update = try makeUpdate(version: "1.0", permissions: ["storage"])
        do {
            _ = try await manager.applyVerifiedUpdate(update, replacing: original, isEligible: { true })
            XCTFail("Equal real versions require an explicit override")
        } catch WebExtensionManager.UpdateInstallationError.invalidPackage { }
        do {
            _ = try await manager.applyVerifiedUpdate(makeUpdate(version: "0.9"), replacing: original,
                                                      reportedInstalledVersion: "0.0.0.1", isEligible: { true })
            XCTFail("An override cannot authorize a real downgrade")
        } catch WebExtensionManager.UpdateInstallationError.invalidPackage { }

        let result = try await manager.applyVerifiedUpdate(update, replacing: original,
                                                           reportedInstalledVersion: "0.0.0.1", isEligible: { true })

        guard case .installedDisabled = result else { return XCTFail("Reinstallation cannot grant new permissions") }
        XCTAssertNil(manager.context(for: identifier))
        XCTAssertEqual(installationStore.installedExtensions.first?.permissions, ["storage"])
        XCTAssertTrue(try XCTUnwrap(installationStore.installedExtensions.first).isDisabled)
        XCTAssertEqual(try permissionStore.settings(for: identifier)?.grantedPermissions, [:])
        let journal = try await onlyJournal()
        XCTAssertEqual(journal.registryCommitted, true)
    }

    func testSameVersionCrashBeforeRegistryCommitReconcilesCandidateMetadataAndRetainsItsDisabledBackup() async throws {
        let staged = try await transactions.stage(makeUpdate(version: "1.0", permissions: ["storage"]), installationID: identifier,
                                                  previousVersion: "1.0", previousMetadata: JSONEncoder().encode(original))
        let candidate = InstalledWebExtension(uniqueIdentifier: identifier, filename: identifier, name: original.name, version: "1.0",
                                               storeIdentity: original.storeIdentity, permissions: ["storage"], isDisabled: true)
        try await transactions.replace(staged)
        try await transactions.commit(staged, updatedMetadata: JSONEncoder().encode(candidate), retainPrevious: true)
        installationStore.add(original)
        let manager = makeManager(loader: WebExtensionLoadingMock())
        var clearCount = 0
        manager.didCommitStoreUpdate = { _, _ in clearCount += 1; return true }

        let failures = try await manager.recoverExtensionUpdates(isAllowed: { _ in true })

        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(installationStore.installedExtensions, [candidate])
        XCTAssertEqual(clearCount, 1)
        let journal = try await onlyJournal()
        XCTAssertEqual(journal.registryCommitted, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: transactionDirectory(staged.transactionID).appendingPathComponent("previous").path))
    }

    func testAcknowledgedSameVersionRecoveryPreservesLaterExplicitEnable() async throws {
        let staged = try await transactions.stage(makeUpdate(version: "1.0"), installationID: identifier,
                                                  previousVersion: "1.0", previousMetadata: JSONEncoder().encode(original))
        var candidate = original
        candidate.isDisabled = true
        try await transactions.replace(staged)
        try await transactions.commit(staged, updatedMetadata: JSONEncoder().encode(candidate), retainPrevious: true)
        let acknowledged = await transactions.acknowledgeRegistry(staged.transactionID)
        XCTAssertTrue(acknowledged)
        candidate.isDisabled = false
        installationStore.add(candidate)
        let manager = makeManager(loader: WebExtensionLoadingMock())

        let failures = try await manager.recoverExtensionUpdates(isAllowed: { _ in true })

        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(installationStore.installedExtensions, [candidate])
        let remaining = try await transactions.journals()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testAcknowledgedSameVersionRecoveryPreservesLaterDisable() async throws {
        let staged = try await transactions.stage(makeUpdate(version: "1.0"), installationID: identifier,
                                                  previousVersion: "1.0", previousMetadata: JSONEncoder().encode(original))
        try await transactions.replace(staged)
        try await transactions.commit(staged, updatedMetadata: JSONEncoder().encode(original), retainPrevious: true)
        let acknowledged = await transactions.acknowledgeRegistry(staged.transactionID)
        XCTAssertTrue(acknowledged)
        var disabled = original
        disabled.isDisabled = true
        installationStore.add(disabled)
        let manager = makeManager(loader: WebExtensionLoadingMock())

        let failures = try await manager.recoverExtensionUpdates(isAllowed: { _ in true })

        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(installationStore.installedExtensions, [disabled])
    }

    func testCommittedRecoveryRetriesFailedOverrideClearEvenWhenRegistryWasAlreadyReconciled() async throws {
        let overrideIdentifier = UUID()
        let staged = try await transactions.stage(makeUpdate(version: "1.0"), installationID: identifier,
                                                  previousVersion: "1.0", previousMetadata: JSONEncoder().encode(original),
                                                  versionOverrideIdentifier: overrideIdentifier)
        try await transactions.replace(staged)
        try await transactions.commit(staged, updatedMetadata: JSONEncoder().encode(original), retainPrevious: false)
        installationStore.add(original)
        let manager = makeManager(loader: WebExtensionLoadingMock())
        var canClear = false
        var attempts = 0
        manager.didCommitStoreUpdate = { _, identifier in
            XCTAssertEqual(identifier, overrideIdentifier)
            attempts += 1
            return canClear
        }

        let initialFailures = try await manager.recoverExtensionUpdates(isAllowed: { _ in true })
        XCTAssertTrue(initialFailures.isEmpty)
        let retained = try await onlyJournal()
        XCTAssertEqual(retained.registryCommitted, true)
        canClear = true
        let retryFailures = try await manager.recoverExtensionUpdates(isAllowed: { _ in true })

        XCTAssertTrue(retryFailures.isEmpty)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(installationStore.installedExtensions, [original])
        let remaining = try await transactions.journals()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testSameVersionRollbackResetsAcknowledgementBeforeRestoringRegistryMetadata() async throws {
        let staged = try await transactions.stage(makeUpdate(version: "1.0", permissions: ["storage"]), installationID: identifier,
                                                  previousVersion: "1.0", previousMetadata: JSONEncoder().encode(original))
        let candidate = InstalledWebExtension(uniqueIdentifier: identifier, filename: identifier, name: original.name, version: "1.0",
                                               storeIdentity: original.storeIdentity, permissions: ["storage"])
        try await transactions.replace(staged)
        try await transactions.commit(staged, updatedMetadata: JSONEncoder().encode(candidate), retainPrevious: true)
        _ = await transactions.acknowledgeRegistry(staged.transactionID)
        installationStore.add(candidate)
        _ = try await transactions.rollback(staged.transactionID, restoreInstallation: true)
        let rollingBack = try await onlyJournal()
        XCTAssertEqual(rollingBack.registryCommitted, false)
        let manager = makeManager(loader: WebExtensionLoadingMock())

        let failures = try await manager.recoverExtensionUpdates(isAllowed: { _ in true })

        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(installationStore.installedExtensions, [original])
    }

    func testPersistentAcknowledgementFailurePreventsEnableUntilItsRegistryStateIsDurable() async throws {
        let staged = try await transactions.stage(makeUpdate(version: "1.0"), installationID: identifier,
                                                   previousVersion: "1.0", previousMetadata: JSONEncoder().encode(original))
        var candidate = original
        candidate.isDisabled = true
        try await transactions.replace(staged)
        try await transactions.commit(staged, updatedMetadata: JSONEncoder().encode(candidate), retainPrevious: true)
        installationStore.add(candidate)
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let manager = makeManager(loader: loader, permissions: permissions)
        let transaction = transactionDirectory(staged.transactionID)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: transaction.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: transaction.path) }
        let recovered = try await manager.recoverExtensionUpdates(isAllowed: { _ in true })
        XCTAssertTrue(recovered.isEmpty, "A failed acknowledgement must not quarantine a coherent package")

        do {
            try await manager.enableExtension(identifier: identifier)
            XCTFail("Enable cannot be reported successful while recovery would undo it")
        } catch WebExtensionManager.UpdateInstallationError.recoveryFailed { }

        XCTAssertNil(manager.context(for: identifier))
        XCTAssertTrue(loader.loadedVersions.isEmpty)
        XCTAssertEqual(installationStore.installedExtensions, [candidate])
        let journal = try await onlyJournal()
        XCTAssertEqual(journal.registryCommitted, false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: transaction.path)
        try await manager.enableExtension(identifier: identifier)
        XCTAssertFalse(try XCTUnwrap(installationStore.installedExtensions.first).isDisabled)
        try loader.unloadExtension(identifier: identifier, from: manager.controller)
    }

    func testFallbackEnableCannotBypassAcknowledgementFailureAfterRollback() async throws {
        let staged = try await transactions.stage(makeUpdate(version: "1.0"), installationID: identifier,
                                                   previousVersion: "1.0", previousMetadata: JSONEncoder().encode(original))
        var candidate = original
        candidate.isDisabled = true
        try await transactions.replace(staged)
        try await transactions.commit(staged, updatedMetadata: JSONEncoder().encode(candidate), retainPrevious: true)
        _ = await transactions.acknowledgeRegistry(staged.transactionID)
        installationStore.add(candidate)
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let fileManager = ReadOnlyTransactionAfterRollbackFileManager()
        let manager = makeManager(loader: loader, permissions: permissions, fileManager: fileManager)
        _ = try await manager.recoverExtensionUpdates(isAllowed: { _ in true })
        loader.rejectedVersion = "1.0"
        let transaction = transactionDirectory(staged.transactionID)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: transaction.path) }

        do {
            try await manager.enableExtension(identifier: identifier)
            XCTFail("Fallback cannot report enable success before predecessor metadata is acknowledged")
        } catch WebExtensionManager.UpdateInstallationError.recoveryFailed { }

        XCTAssertNil(manager.context(for: identifier))
        XCTAssertTrue(try XCTUnwrap(installationStore.installedExtensions.first).isDisabled)
        XCTAssertEqual(loader.loadedVersions, ["1.0"], "The rejected candidate is the only attempted activation")
        let journal = try await onlyJournal()
        XCTAssertEqual(journal.phase, .rollingBack)
        XCTAssertEqual(journal.registryCommitted, false)
    }

    func testRollbackInterruptedAfterCurrentRemovalRestoresBackupAndRetainsIntent() async throws {
        let previousMetadata = try JSONEncoder().encode(original)
        let staged = try await stage(previousMetadata: previousMetadata)
        try await transactions.replace(staged)
        try await transactions.commit(staged, updatedMetadata: Data(), retainPrevious: true)
        let journal = try await persistRollbackIntent()
        try FileManager.default.removeItem(at: currentDirectory)
        transactions = WebExtensionUpdateTransactionStore(extensionsDirectory: directory)

        let metadata = try await transactions.recover(journal, installationStillMatches: true)

        XCTAssertEqual(metadata, previousMetadata)
        XCTAssertEqual(try installedVersion(), "1.0")
        try await assertRollbackIntent()
    }

    func testRollbackInterruptedAfterBackupRestorationDoesNotReturnCandidateMetadata() async throws {
        let previousMetadata = try JSONEncoder().encode(original)
        let staged = try await stage(previousMetadata: previousMetadata)
        try await transactions.replace(staged)
        try await transactions.commit(staged, updatedMetadata: Data("candidate metadata".utf8), retainPrevious: true)
        let journal = try await persistRollbackIntent()
        try FileManager.default.removeItem(at: currentDirectory)
        let previous = transactionDirectory(staged.transactionID).appendingPathComponent("previous")
        try FileManager.default.moveItem(at: previous, to: currentDirectory)
        transactions = WebExtensionUpdateTransactionStore(extensionsDirectory: directory)

        let metadata = try await transactions.recover(journal, installationStillMatches: true)

        XCTAssertEqual(metadata, previousMetadata)
        XCTAssertEqual(try installedVersion(), "1.0")
        try await assertRollbackIntent()
    }

    func testCrashAfterRollbackRecoveryBeforeRegistryWriteReconcilesOnNextLaunch() async throws {
        let staged = try await stage()
        let candidate = InstalledWebExtension(uniqueIdentifier: identifier, filename: identifier, name: original.name, version: "2.0",
                                             storeIdentity: original.storeIdentity, isDisabled: true)
        installationStore.add(candidate)
        try await transactions.replace(staged)
        try await transactions.commit(staged, updatedMetadata: JSONEncoder().encode(candidate), retainPrevious: true)

        _ = try await transactions.recover(try await onlyJournal(), installationStillMatches: true, rejectCandidate: true)
        XCTAssertEqual(installationStore.installedExtensions.first?.version, "2.0", "Simulate crashing before registry reconciliation")
        XCTAssertEqual(try installedVersion(), "1.0")
        try await assertRollbackIntent()

        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory))
        let pixels = WebExtensionUpdatePixelFiringMock()
        let manager = makeManager(loader: loader, pixels: pixels)
        try await manager.recoverExtensionUpdates(isAllowed: { _ in true })

        XCTAssertEqual(installationStore.installedExtensions.first?.version, "1.0")
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, true)
        XCTAssertEqual(loader.loadedVersions, [])
        XCTAssertEqual(pixels.events, [.failed(.other, .storageFailure, .success)])
        let remaining = try await transactions.journals()
        XCTAssertTrue(remaining.isEmpty, "Only registry reconciliation may acknowledge and remove the rollback journal")
    }

    func testDisabledCommitKeepsWorkingPredecessorAndRejectsAnotherTransaction() async throws {
        let staged = try await stage()
        try await transactions.replace(staged)
        try await transactions.commit(staged, updatedMetadata: Data(), retainPrevious: true)
        do {
            _ = try await stage()
            XCTFail("A retained predecessor must be resolved before replacing the disabled incumbent")
        } catch WebExtensionUpdateTransactionStore.TransactionError.transactionAlreadyExists { }

        try await transactions.rollback(staged.transactionID, restoreInstallation: true)

        XCTAssertEqual(try installedVersion(), "1.0")
    }

    func testUninstalledGenerationIsNotResurrectedDuringRecovery() async throws {
        let staged = try await stage()
        try await transactions.replace(staged)
        try FileManager.default.removeItem(at: currentDirectory)

        let metadata = try await transactions.recover(try await onlyJournal(), installationStillMatches: false)

        XCTAssertNil(metadata)
        XCTAssertFalse(FileManager.default.fileExists(atPath: currentDirectory.path))
    }

    func testBlockedCandidateRestoresPredecessorInsteadOfDeletingTheOnlyBackup() async throws {
        let previousMetadata = try JSONEncoder().encode(original)
        let staged = try await stage(previousMetadata: previousMetadata)
        try await transactions.replace(staged)

        let metadata = try await transactions.recover(try await onlyJournal(), installationStillMatches: true, rejectCandidate: true)

        XCTAssertEqual(metadata, previousMetadata)
        XCTAssertEqual(try installedVersion(), "1.0")
    }

    func testUnreadableJournalRetainsTheBackup() async throws {
        let staged = try await stage()
        try await transactions.replace(staged)
        let transactionDirectory = directory.appendingPathComponent(".update-transactions").appendingPathComponent(staged.transactionID.uuidString)
        try Data("invalid".utf8).write(to: transactionDirectory.appendingPathComponent("journal.json"))
        do {
            _ = try await transactions.journals()
            XCTFail("Unreadable journals must stop recovery")
        } catch { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: transactionDirectory.appendingPathComponent("previous").path))
    }

    func testDefaultManagerPathInstallsDisabledWithoutExecutingNewCode() async throws {
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory))
        let pixels = WebExtensionUpdatePixelFiringMock()
        let manager = makeManager(loader: loader, pixels: pixels)
        installationStore.add(original)
        let update = try makeUpdate()

        let outcome = try await manager.applyVerifiedUpdate(update, replacing: original, isEligible: { true })

        guard case .installedDisabled = outcome else { return XCTFail("Default automated replacement must fail closed") }
        XCTAssertEqual(loader.loadedVersions, [])
        XCTAssertEqual(installationStore.installedExtensions.first?.uniqueIdentifier, identifier)
        XCTAssertEqual(installationStore.installedExtensions.first?.version, "2.0")
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, true)
        let journals = try await transactions.journals()
        XCTAssertEqual(journals.count, 1)
        XCTAssertTrue(try XCTUnwrap(journals.first).retainsPrevious)
        XCTAssertEqual(pixels.events, [.applied(.other)], "A safe disabled commit is an applied package, not a failure")
    }

    func testFailedCandidateLoadLeavesOldRuntimeRegistryAndConsentWorking() async throws {
        try writePackage(version: "1.0", at: currentDirectory, permissions: ["storage"])
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        var approved = WebExtensionPermissionSettings()
        approved.grantedPermissions["storage"] = .distantFuture
        approved.hasAccessToPrivateData = true
        try permissionStore.save(approved, for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let pixels = WebExtensionUpdatePixelFiringMock()
        let manager = makeManager(loader: loader, permissions: permissions, pixels: pixels)
        installationStore.add(original)
        _ = try await loader.loadWebExtension(identifier: identifier, into: manager.controller)
        loader.rejectedVersion = "2.0"
        do {
            _ = try await manager.applyVerifiedUpdate(try makeUpdate(permissions: ["storage"]), replacing: original, isEligible: { true })
            XCTFail("Injected load failure must fail the update")
        } catch RejectingUpdateLoader.LoadError.injected { }

        XCTAssertEqual(loader.loadedVersions, ["1.0", "2.0", "1.0"])
        XCTAssertEqual(manager.controller.extensionContexts.first?.webExtension.version, "1.0")
        XCTAssertEqual(try installedVersion(), "1.0")
        XCTAssertEqual(installationStore.installedExtensions, [original])
        XCTAssertEqual(try permissionStore.settings(for: identifier), approved)
        XCTAssertEqual(pixels.events.count, 1)
        XCTAssertTrue(pixels.events.contains(.failed(.other, .loadFailure, .success)))
        try loader.unloadExtension(identifier: identifier, from: manager.controller)
    }

    func testFailedRollbackReportsTheOriginalLoadFailureOnce() async throws {
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let pixels = WebExtensionUpdatePixelFiringMock()
        let manager = makeManager(loader: loader, permissions: permissions, fileManager: FailingTransactionRollbackFileManager(), pixels: pixels)
        installationStore.add(original)
        _ = try await loader.loadWebExtension(identifier: identifier, into: manager.controller)
        loader.rejectedVersion = "2.0"

        do {
            _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })
            XCTFail("The failed restoration must propagate")
        } catch WebExtensionManager.UpdateInstallationError.rollbackFailed { }

        XCTAssertEqual(pixels.events, [.failed(.other, .loadFailure, .failure)])
    }

    func testFailedCandidateUnloadLeavesItsFilesAndBackupUntouchedForLaunchRecovery() async throws {
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let pixels = WebExtensionUpdatePixelFiringMock()
        let manager = makeManager(loader: loader, permissions: permissions, pixels: pixels)
        installationStore.add(original)
        _ = try await loader.loadWebExtension(identifier: identifier, into: manager.controller)
        loader.rejectedUnloadVersion = "2.0"
        do {
            _ = try await manager.applyVerifiedUpdate(try makeUpdate(), replacing: original, isEligible: {
                manager.controller.extensionContexts.first?.webExtension.version != "2.0"
            })
            XCTFail("Rollback must report the injected unload failure")
        } catch WebExtensionManager.UpdateInstallationError.rollbackFailed { }

        XCTAssertEqual(try installedVersion(), "2.0", "Do not replace files underneath a candidate that remains loaded")
        XCTAssertEqual(manager.controller.extensionContexts.first?.webExtension.version, "2.0")
        XCTAssertEqual(installationStore.installedExtensions, [original])
        let journal = try await onlyJournal()
        XCTAssertEqual(journal.phase, .replacing)
        XCTAssertEqual(pixels.events, [.failed(.other, .rollbackFailure, .failure)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: transactionDirectory(journal.transactionID).appendingPathComponent("previous").path))
        loader.rejectedUnloadVersion = nil
        try loader.unloadExtension(identifier: identifier, from: manager.controller)
    }

    func testRequiredPermissionIncreaseInstallsDisabledWithoutLoadingCandidate() async throws {
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let manager = makeManager(loader: loader, permissions: permissions)
        installationStore.add(original)
        _ = try await loader.loadWebExtension(identifier: identifier, into: manager.controller)

        let matchPatterns = ["https://example.com/*"]
        let update = try makeUpdate(permissions: ["storage"], hostPermissions: matchPatterns)
        let result = try await manager.applyVerifiedUpdate(update, replacing: original, isEligible: { true })

        guard case .installedDisabled = result else { return XCTFail("Increased access must disable the candidate") }
        XCTAssertEqual(loader.loadedVersions, ["1.0"])
        XCTAssertTrue(manager.controller.extensionContexts.isEmpty)
        XCTAssertEqual(installationStore.installedExtensions.first?.permissions, ["storage"])
        XCTAssertEqual(installationStore.installedExtensions.first?.matchPatterns, matchPatterns)
        XCTAssertEqual(manager.extensionMatchPatterns(for: identifier), matchPatterns)
        XCTAssertEqual(try permissionStore.settings(for: identifier)?.grantedPermissions, [:])
    }

    func testPreviouslyDisabledExtensionStaysDisabledWithNoPermissionIncrease() async throws {
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let manager = makeManager(loader: loader, permissions: permissions)
        var disabled = original
        disabled.isDisabled = true
        installationStore.add(disabled)

        _ = try await manager.applyVerifiedUpdate(try makeUpdate(), replacing: disabled, isEligible: { true })

        XCTAssertEqual(installationStore.installedExtensions.first?.version, "2.0")
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, true)
        XCTAssertTrue(loader.loadedVersions.isEmpty)
        XCTAssertTrue(manager.controller.extensionContexts.isEmpty)
    }

    func testRevocationDuringUnloadWaitIsPreservedAndPreventsCandidateExecution() async throws {
        let required = ["storage", "declarativeNetRequest"]
        try writePackage(version: "1.0", at: currentDirectory, permissions: required)
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        var approved = WebExtensionPermissionSettings()
        approved.grantedPermissions = Dictionary(uniqueKeysWithValues: required.map { ($0, .distantFuture) })
        approved.hasAccessToPrivateData = true
        try permissionStore.save(approved, for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let manager = makeManager(loader: loader, permissions: permissions)
        installationStore.add(original)
        _ = try await loader.loadWebExtension(identifier: identifier, into: manager.controller)
        let incumbent = try XCTUnwrap(manager.controller.extensionContexts.first)
        var revokedDuringWait = false
        manager.unloadGuard = WebExtensionUnloadGuard(now: { .distantPast }, sleeper: { _ in
            await Task.yield()
            incumbent.grantedPermissions.removeValue(forKey: .storage)
            do { try permissions.setHasAccessToPrivateData(false, for: self.identifier) } catch { XCTFail("\(error)") }
            revokedDuringWait = true
        })
        manager.unloadGuard.recordLoad(of: identifier)

        let result = try await manager.applyVerifiedUpdate(try makeUpdate(permissions: required), replacing: original, isEligible: { true })

        guard case .installedDisabled = result else { return XCTFail("Revoked required access must prevent activation") }
        XCTAssertTrue(revokedDuringWait)
        XCTAssertEqual(loader.loadedVersions, ["1.0"])
        XCTAssertNil(try permissionStore.settings(for: identifier)?.grantedPermissions["storage"])
        XCTAssertEqual(try permissionStore.settings(for: identifier)?.hasAccessToPrivateData, false)
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, true)
    }

    func testConsentDisappearingDuringLoaderParsingInstallsDisabledWithoutPrompting() async throws {
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let manager = makeManager(loader: loader, permissions: permissions)
        installationStore.add(original)
        loader.beforeLoad = { version in
            guard version == "2.0" else { return }
            do { try permissionStore.removeSettings(for: self.identifier) } catch { XCTFail("\(error)") }
        }

        let result = try await manager.applyVerifiedUpdate(try makeUpdate(), replacing: original, isEligible: { true })

        guard case .installedDisabled = result else { return XCTFail("Missing consent must install disabled") }
        XCTAssertTrue(manager.controller.extensionContexts.isEmpty)
        XCTAssertEqual(installationStore.installedExtensions.first?.version, "2.0")
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, true)
        XCTAssertNil(try permissionStore.settings(for: identifier))
    }

    func testFailedExplicitEnableRestoresAndEnablesTheWorkingPredecessor() async throws {
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let pixels = WebExtensionUpdatePixelFiringMock()
        let manager = makeManager(loader: loader, permissions: permissions, pixels: pixels)
        installationStore.add(original)
        _ = try await manager.applyVerifiedUpdate(makeUpdate(permissions: ["storage"]), replacing: original, isEligible: { true })
        loader.rejectedVersion = "2.0"
        pixels.reset()

        try await manager.enableExtension(identifier: identifier)

        XCTAssertEqual(installationStore.installedExtensions.first?.version, "1.0")
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, false)
        XCTAssertEqual(manager.context(for: identifier)?.webExtension.version, "1.0")
        XCTAssertEqual(try permissionStore.settings(for: identifier)?.grantedPermissions, [:])
        let remaining = try await transactions.journals()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertEqual(pixels.events.count, 1)
        XCTAssertTrue(pixels.events.contains(.failed(.other, .loadFailure, .success)))
        try loader.unloadExtension(identifier: identifier, from: manager.controller)
    }

    func testSuccessfulExplicitEnableCleansTheBackupWithoutGrantingNewPermissions() async throws {
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let manager = makeManager(loader: loader, permissions: permissions)
        installationStore.add(original)
        _ = try await manager.applyVerifiedUpdate(makeUpdate(permissions: ["storage"]), replacing: original, isEligible: { true })

        try await manager.enableExtension(identifier: identifier)

        XCTAssertEqual(installationStore.installedExtensions.first?.version, "2.0")
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, false)
        XCTAssertNil(try permissionStore.settings(for: identifier)?.grantedPermissions["storage"])
        let remaining = try await transactions.journals()
        XCTAssertTrue(remaining.isEmpty)
        try loader.unloadExtension(identifier: identifier, from: manager.controller)
    }

    func testDisableWhileRetainedCandidateIsEnablingPreventsStaleActivation() async throws {
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let manager = makeManager(loader: loader, permissions: permissions)
        installationStore.add(original)
        _ = try await manager.applyVerifiedUpdate(makeUpdate(permissions: ["storage"]), replacing: original, isEligible: { true })
        loader.beforeLoadAsync = { version in
            if version == "2.0" { try await manager.disableExtension(identifier: self.identifier) }
        }
        do {
            try await manager.enableExtension(identifier: identifier)
            XCTFail("The later disable must invalidate the suspended enable")
        } catch WebExtensionManager.UpdateInstallationError.installationChanged { }

        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, true)
        XCTAssertNil(manager.context(for: identifier))
        XCTAssertEqual(try permissionStore.settings(for: identifier)?.grantedPermissions, [:])
    }

    func testCommittedCandidateRegistryStateSurvivesInterruptedEnableCleanupAndLaterDisable() async throws {
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let manager = makeManager(loader: loader, permissions: permissions)
        installationStore.add(original)
        _ = try await manager.applyVerifiedUpdate(makeUpdate(permissions: ["storage"]), replacing: original, isEligible: { true })
        var afterExplicitEnable = try XCTUnwrap(installationStore.installedExtensions.first)
        afterExplicitEnable.isDisabled = false
        installationStore.update(afterExplicitEnable)

        // The enable's registry write is durable, but its retained journal/backup cleanup has not run.
        let reopened = makeManager(loader: loader, permissions: permissions)
        _ = try await reopened.recoverExtensionUpdates(isAllowed: { _ in true })
        XCTAssertEqual(installationStore.installedExtensions.first, afterExplicitEnable)

        var afterManualDisable = afterExplicitEnable
        afterManualDisable.isDisabled = true
        installationStore.update(afterManualDisable)
        _ = try await reopened.recoverExtensionUpdates(isAllowed: { _ in true })
        XCTAssertEqual(installationStore.installedExtensions.first, afterManualDisable)
    }

    func testDisableDuringRetainedFallbackLoadDoesNotReactivateThePredecessor() async throws {
        let (manager, loader, permissionStore) = try await retainedCandidateForFallback()
        loader.beforeLoadAsync = { version in
            guard version == "1.0" else { return }
            await Task.yield()
            try await manager.disableExtension(identifier: self.identifier)
        }

        await manager.loadInstalledExtensions()

        XCTAssertEqual(installationStore.installedExtensions.first?.version, "1.0")
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, true)
        XCTAssertNil(manager.context(for: identifier))
        XCTAssertNotNil(try permissionStore.settings(for: identifier))
    }

    func testUninstallDuringRetainedFallbackLoadDoesNotResurrectThePredecessor() async throws {
        let (manager, loader, permissionStore) = try await retainedCandidateForFallback()
        loader.beforeLoadAsync = { version in
            guard version == "1.0" else { return }
            await Task.yield()
            try manager.uninstallExtension(identifier: self.identifier)
        }

        await manager.loadInstalledExtensions()

        XCTAssertTrue(installationStore.installedExtensions.isEmpty)
        XCTAssertNil(manager.context(for: identifier))
        XCTAssertNil(try permissionStore.settings(for: identifier))
    }

    func testConsentRemovedDuringRetainedFallbackParsingDoesNotPromptOrForgetTheInstallation() async throws {
        let (manager, loader, permissionStore) = try await retainedCandidateForFallback()
        loader.beforeLoadAsync = { version in
            guard version == "1.0" else { return }
            await Task.yield()
            try permissionStore.removeSettings(for: self.identifier)
        }

        await manager.loadInstalledExtensions()

        XCTAssertEqual(installationStore.installedExtensions.first?.version, "1.0")
        XCTAssertNil(manager.context(for: identifier))
        XCTAssertNil(try permissionStore.settings(for: identifier))
    }

    func testRollbackCleanupFailureStillRestoresTheWorkingRuntimeAndConsent() async throws {
        let fileManager = FailingTransactionCleanupFileManager()
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        let approved = WebExtensionPermissionSettings()
        try permissionStore.save(approved, for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory, fileManager: fileManager), permissionController: permissions)
        let pixels = WebExtensionUpdatePixelFiringMock()
        let manager = makeManager(loader: loader, permissions: permissions, fileManager: fileManager, pixels: pixels)
        installationStore.add(original)
        _ = try await loader.loadWebExtension(identifier: identifier, into: manager.controller)
        loader.rejectedVersion = "2.0"

        do {
            _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })
            XCTFail("Injected candidate failure must propagate")
        } catch RejectingUpdateLoader.LoadError.injected { }

        XCTAssertEqual(manager.context(for: identifier)?.webExtension.version, "1.0")
        XCTAssertEqual(installationStore.installedExtensions, [original])
        XCTAssertEqual(try permissionStore.settings(for: identifier), approved)
        try await assertRollbackIntent()
        XCTAssertEqual(pixels.events.count, 1, "Cleanup-only errors must not add a failure pixel")
        XCTAssertTrue(pixels.events.contains(.failed(.other, .loadFailure, .success)))
        try loader.unloadExtension(identifier: identifier, from: manager.controller)
    }

    func testCommittedRecoveryCleanupFailureDoesNotQuarantineTheCoherentNewPackage() async throws {
        let staged = try await stage()
        try await transactions.replace(staged)
        let candidate = InstalledWebExtension(uniqueIdentifier: identifier, filename: identifier, name: original.name, version: "2.0", storeIdentity: original.storeIdentity)
        try await transactions.commit(staged, updatedMetadata: JSONEncoder().encode(candidate), retainPrevious: false)
        installationStore.add(original)
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let pixels = WebExtensionUpdatePixelFiringMock()
        let manager = makeManager(loader: loader, permissions: permissions, fileManager: FailingTransactionCleanupFileManager(), pixels: pixels)

        let failed = try await manager.recoverExtensionUpdates(isAllowed: { _ in true })
        await manager.loadInstalledExtensions()

        XCTAssertTrue(failed.isEmpty)
        XCTAssertEqual(installationStore.installedExtensions.first, candidate)
        XCTAssertEqual(manager.context(for: identifier)?.webExtension.version, "2.0")
        XCTAssertNotNil(try permissionStore.settings(for: identifier))
        let remaining = try await transactions.journals()
        XCTAssertEqual(remaining.first?.phase, .committed)
        _ = try await manager.recoverExtensionUpdates(isAllowed: { _ in true })
        XCTAssertEqual(pixels.events, [.applied(.other)], "A cleanup retry must not repeat the applied event or add a failure")
        try loader.unloadExtension(identifier: identifier, from: manager.controller)
    }

    func testPreparedCleanupFailureLeavesTheUntouchedIncumbentLoadable() async throws {
        _ = try await stage()
        installationStore.add(original)
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let pixels = WebExtensionUpdatePixelFiringMock()
        let manager = makeManager(loader: loader, permissions: permissions, fileManager: FailingTransactionCleanupFileManager(), pixels: pixels)

        let failed = try await manager.recoverExtensionUpdates(isAllowed: { _ in true })
        await manager.loadInstalledExtensions()

        XCTAssertTrue(failed.isEmpty)
        XCTAssertEqual(installationStore.installedExtensions, [original])
        XCTAssertEqual(manager.context(for: identifier)?.webExtension.version, "1.0")
        XCTAssertNotNil(try permissionStore.settings(for: identifier))
        let remaining = try await transactions.journals()
        XCTAssertEqual(remaining.first?.phase, .prepared)
        XCTAssertTrue(pixels.events.isEmpty)
        try loader.unloadExtension(identifier: identifier, from: manager.controller)
    }

    func testRollbackJournalCleanupRetryPreservesLaterEnableAndDisableState() async throws {
        var disabledOriginal = original
        disabledOriginal.isDisabled = true
        let update = try makeUpdate()
        let staged = try await transactions.stage(update, installationID: identifier, previousVersion: original.version,
                                                  previousMetadata: JSONEncoder().encode(disabledOriginal))
        try await transactions.replace(staged)
        _ = try await transactions.rollback(staged.transactionID, restoreInstallation: true)
        installationStore.add(original) // The restored predecessor has since been explicitly enabled.
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let manager = makeManager(loader: loader, permissions: permissions, fileManager: FailingTransactionCleanupFileManager())

        let failed = try await manager.recoverExtensionUpdates(isAllowed: { _ in true })
        await manager.loadInstalledExtensions()

        XCTAssertTrue(failed.isEmpty)
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, false)
        XCTAssertEqual(manager.context(for: identifier)?.webExtension.version, "1.0")
        try await manager.disableExtension(identifier: identifier)
        _ = try await manager.recoverExtensionUpdates(isAllowed: { _ in true })
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, true)
        XCTAssertNotNil(try permissionStore.settings(for: identifier))
    }

    func testMismatchedPackageVersionReportsOnlyABoundedInvalidPackageFailure() async throws {
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory))
        let pixels = WebExtensionUpdatePixelFiringMock()
        let manager = makeManager(loader: loader, pixels: pixels)
        installationStore.add(original)
        let package = try makeUpdate()
        let mismatched = ChromeWebStoreVerifiedUpdate(extensionID: storeID, version: "3.0", fileURL: package.fileURL)

        do {
            _ = try await manager.applyVerifiedUpdate(mismatched, replacing: original, isEligible: { true })
            XCTFail("Candidate manifest version must match the verified offer")
        } catch WebExtensionManager.UpdateInstallationError.invalidPackage { }

        XCTAssertEqual(pixels.events, [.failed(.other, .invalidPackage, .notNeeded)])
        XCTAssertEqual(installationStore.installedExtensions, [original])
    }

    func testStagingFailureReportsOnlyStorageFailureWithoutRollbackOrAppliedEvents() async throws {
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory))
        let pixels = WebExtensionUpdatePixelFiringMock()
        let manager = makeManager(loader: loader, pixels: pixels)
        installationStore.add(original)
        let offered = try makeUpdate()
        try FileManager.default.removeItem(at: offered.fileURL)

        do {
            _ = try await manager.applyVerifiedUpdate(offered, replacing: original, isEligible: { true })
            XCTFail("Missing package must fail staging")
        } catch { }

        XCTAssertEqual(pixels.events, [.failed(.other, .storageFailure, .notNeeded)])
        XCTAssertEqual(installationStore.installedExtensions, [original])
    }

    func testIncumbentUnloadFailureReportsOnlyItsBoundedFailureAndLeavesItRunning() async throws {
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let pixels = WebExtensionUpdatePixelFiringMock()
        let manager = makeManager(loader: loader, permissions: permissions, pixels: pixels)
        installationStore.add(original)
        _ = try await loader.loadWebExtension(identifier: identifier, into: manager.controller)
        loader.rejectedUnloadVersion = "1.0"

        do {
            _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })
            XCTFail("Injected unload failure must prevent replacement")
        } catch RejectingUpdateLoader.LoadError.injectedUnload { }

        XCTAssertEqual(pixels.events, [.failed(.other, .unloadFailure, .notNeeded)])
        XCTAssertEqual(manager.context(for: identifier)?.webExtension.version, "1.0")
        XCTAssertEqual(installationStore.installedExtensions, [original])
        loader.rejectedUnloadVersion = nil
        try loader.unloadExtension(identifier: identifier, from: manager.controller)
    }

    func testCancellationDoesNotHideAGenuineRollbackFailure() async throws {
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let pixels = WebExtensionUpdatePixelFiringMock()
        let manager = makeManager(loader: loader, permissions: permissions, pixels: pixels)
        installationStore.add(original)
        _ = try await loader.loadWebExtension(identifier: identifier, into: manager.controller)
        loader.rejectedUnloadVersion = "2.0"
        let update = try makeUpdate()
        let operation = Task { @MainActor in
            _ = try await manager.applyVerifiedUpdate(update, replacing: self.original, isEligible: {
                guard manager.context(for: self.identifier)?.webExtension.version == "2.0" else { return true }
                withUnsafeCurrentTask { $0?.cancel() }
                return false
            })
        }

        do {
            _ = try await operation.value
            XCTFail("The candidate remains loaded when its rollback unload fails")
        } catch WebExtensionManager.UpdateInstallationError.rollbackFailed { }

        XCTAssertTrue(operation.isCancelled)
        XCTAssertEqual(pixels.events, [.failed(.other, .rollbackFailure, .failure)])
        loader.rejectedUnloadVersion = nil
        try loader.unloadExtension(identifier: identifier, from: manager.controller)
    }

    func testBlockingACommittedCandidateRestoresItsPredecessorWithoutReportingFailure() async throws {
        let staged = try await stage()
        try await transactions.replace(staged)
        let candidate = InstalledWebExtension(uniqueIdentifier: identifier, filename: identifier, name: original.name, version: "2.0",
                                             storeIdentity: original.storeIdentity, isDisabled: true)
        try await transactions.commit(staged, updatedMetadata: JSONEncoder().encode(candidate), retainPrevious: true)
        installationStore.add(candidate)
        let pixels = WebExtensionUpdatePixelFiringMock()
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory))
        let manager = makeManager(loader: loader, pixels: pixels)

        let failures = try await manager.recoverExtensionUpdates(isAllowed: { _ in false })

        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(try installedVersion(), "1.0")
        XCTAssertTrue(pixels.events.isEmpty, "Blocklist rejection is not an installation failure")
    }

    func testBlockedCommittedCandidateReportsRollbackFailureWhenRestoringItsBackupFails() async throws {
        let staged = try await stage()
        try await transactions.replace(staged)
        let candidate = InstalledWebExtension(uniqueIdentifier: identifier, filename: identifier, name: original.name, version: "2.0",
                                             storeIdentity: original.storeIdentity, isDisabled: true)
        try await transactions.commit(staged, updatedMetadata: JSONEncoder().encode(candidate), retainPrevious: true)
        installationStore.add(candidate)
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let pixels = WebExtensionUpdatePixelFiringMock()
        let manager = makeManager(loader: loader, permissions: permissions, fileManager: FailingTransactionRollbackFileManager(), pixels: pixels)

        let failed = try await manager.recoverExtensionUpdates(isAllowed: { _ in false })

        XCTAssertEqual(failed, [identifier])
        XCTAssertEqual(pixels.events, [.failed(.other, .rollbackFailure, .failure)])
        XCTAssertEqual(installationStore.installedExtensions, [candidate])
        XCTAssertNotNil(try permissionStore.settings(for: identifier))
    }

    func testCanceledRecoveryStillReportsRawRollbackFilesystemFailure() async throws {
        let staged = try await stage()
        try await transactions.replace(staged)
        let candidate = InstalledWebExtension(uniqueIdentifier: identifier, filename: identifier, name: original.name, version: "2.0",
                                             storeIdentity: original.storeIdentity, isDisabled: true)
        try await transactions.commit(staged, updatedMetadata: JSONEncoder().encode(candidate), retainPrevious: true)
        installationStore.add(candidate)
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory))
        let pixels = WebExtensionUpdatePixelFiringMock()
        let manager = makeManager(loader: loader, fileManager: FailingTransactionRollbackFileManager(), pixels: pixels)
        let operation = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await manager.recoverExtensionUpdates(isAllowed: { _ in false })
        }

        let failed = try await operation.value

        XCTAssertTrue(operation.isCancelled)
        XCTAssertEqual(failed, [identifier])
        XCTAssertEqual(pixels.events, [.failed(.other, .rollbackFailure, .failure)])
        XCTAssertEqual(installationStore.installedExtensions, [candidate])
    }

    func testDelegateRevokingUpdatePolicyIsObservedBeforeNativeActivation() async throws {
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let manager = makeManager(loader: loader, permissions: permissions)
        installationStore.add(original)
        var revoked = false
        var gateObservedBeforeNativeLoad = false
        let delegate = WebExtensionLoadingDelegateMock()
        delegate.onWillLoad = { context in
            manager.webExtensionLoader(loader, willLoad: context, identifier: self.identifier)
            if context.webExtension.version == "2.0" { revoked = true }
        }
        loader.delegate = delegate

        do {
            _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: {
                if revoked { gateObservedBeforeNativeLoad = manager.context(for: self.identifier) == nil }
                return !revoked
            })
            XCTFail("Delegate policy revocation must prevent activation")
        } catch WebExtensionManager.UpdateInstallationError.installationChanged { }

        XCTAssertTrue(gateObservedBeforeNativeLoad)
        XCTAssertNil(manager.context(for: identifier))
        XCTAssertEqual(installationStore.installedExtensions, [original])
    }

    func testDelegateRemovingConsentInstallsDisabledWithoutExecutingOrRecreatingApproval() async throws {
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let manager = makeManager(loader: loader, permissions: permissions)
        installationStore.add(original)
        let delegate = WebExtensionLoadingDelegateMock()
        delegate.onWillLoad = { context in
            manager.webExtensionLoader(loader, willLoad: context, identifier: self.identifier)
            do { try permissionStore.removeSettings(for: self.identifier) } catch { XCTFail("\(error)") }
            context.hasAccessToPrivateData = true
        }
        loader.delegate = delegate

        let result = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })

        guard case .installedDisabled = result else { return XCTFail("Missing current approval must disable the new package") }
        XCTAssertNil(manager.context(for: identifier))
        XCTAssertEqual(installationStore.installedExtensions.first?.version, "2.0")
        XCTAssertTrue(try XCTUnwrap(installationStore.installedExtensions.first).isDisabled)
        XCTAssertNil(try permissionStore.settings(for: identifier))
    }

    func testRollbackActivationIgnoresUpdateFlagDisableAndRestoresTheStillInstalledIncumbent() async throws {
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let manager = makeManager(loader: loader, permissions: permissions)
        installationStore.add(original)
        _ = try await loader.loadWebExtension(identifier: identifier, into: manager.controller)
        var enabled = true
        loader.beforeLoadAsync = { version in
            if version == "2.0" {
                enabled = false
                throw RejectingUpdateLoader.LoadError.injected
            }
        }

        do {
            _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { enabled })
            XCTFail("Injected candidate failure must propagate")
        } catch RejectingUpdateLoader.LoadError.injected { }

        XCTAssertFalse(enabled)
        XCTAssertEqual(manager.context(for: identifier)?.webExtension.version, "1.0")
        XCTAssertEqual(installationStore.installedExtensions, [original])
        try loader.unloadExtension(identifier: identifier, from: manager.controller)
    }

    func testRollbackDelegateUninstallPreventsNativeActivationAndConsentResurrection() async throws {
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let manager = makeManager(loader: loader, permissions: permissions)
        installationStore.add(original)
        _ = try await loader.loadWebExtension(identifier: identifier, into: manager.controller)
        loader.rejectedVersion = "2.0"
        let delegate = WebExtensionLoadingDelegateMock()
        delegate.onWillLoad = { context in
            manager.webExtensionLoader(loader, willLoad: context, identifier: self.identifier)
            do { try manager.uninstallExtension(identifier: self.identifier) } catch { XCTFail("\(error)") }
        }
        loader.delegate = delegate

        do {
            _ = try await manager.applyVerifiedUpdate(makeUpdate(), replacing: original, isEligible: { true })
            XCTFail("Uninstalled rollback target must not reactivate")
        } catch WebExtensionManager.UpdateInstallationError.installationChanged { }

        XCTAssertTrue(installationStore.installedExtensions.isEmpty)
        XCTAssertNil(manager.context(for: identifier))
        XCTAssertNil(try permissionStore.settings(for: identifier))
    }

    func testExplicitEnableDelegateUninstallRejectsActivationWithoutRecreatingConsent() async throws {
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let manager = makeManager(loader: loader, permissions: permissions)
        installationStore.add(original)
        _ = try await manager.applyVerifiedUpdate(makeUpdate(permissions: ["storage"]), replacing: original, isEligible: { true })
        let delegate = WebExtensionLoadingDelegateMock()
        delegate.onWillLoad = { context in
            manager.webExtensionLoader(loader, willLoad: context, identifier: self.identifier)
            do { try manager.uninstallExtension(identifier: self.identifier) } catch { XCTFail("\(error)") }
        }
        loader.delegate = delegate

        do {
            try await manager.enableExtension(identifier: identifier)
            XCTFail("The later uninstall must win before native activation")
        } catch WebExtensionManager.UpdateInstallationError.installationChanged { }

        XCTAssertTrue(installationStore.installedExtensions.isEmpty)
        XCTAssertNil(manager.context(for: identifier))
        XCTAssertNil(try permissionStore.settings(for: identifier))
    }

    private func retainedCandidateForFallback() async throws -> (WebExtensionManager, RejectingUpdateLoader, WebExtensionPermissionStore) {
        let permissionStore = WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore())
        try permissionStore.save(WebExtensionPermissionSettings(), for: identifier)
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: NoUpdatePrompt())
        let loader = RejectingUpdateLoader(storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory), permissionController: permissions)
        let manager = makeManager(loader: loader, permissions: permissions)
        installationStore.add(original)
        _ = try await manager.applyVerifiedUpdate(makeUpdate(permissions: ["storage"]), replacing: original, isEligible: { true })
        // Model a successful enable whose backup cleanup failed, followed by a later full load failure.
        var enabled = try XCTUnwrap(installationStore.installedExtensions.first)
        enabled.isDisabled = false
        installationStore.update(enabled)
        loader.rejectedVersion = "2.0"
        return (manager, loader, permissionStore)
    }

    private func stage(previousMetadata: Data? = nil) async throws -> WebExtensionUpdateTransactionStore.Staged {
        try await transactions.stage(makeUpdate(), installationID: identifier, previousVersion: original.version,
                                     previousMetadata: previousMetadata ?? JSONEncoder().encode(original))
    }

    private func onlyJournal() async throws -> WebExtensionUpdateTransactionStore.Journal {
        let journals = try await transactions.journals()
        XCTAssertEqual(journals.count, 1)
        return try XCTUnwrap(journals.first)
    }

    private func persistRollbackIntent() async throws -> WebExtensionUpdateTransactionStore.Journal {
        var journal = try await onlyJournal()
        journal.phase = .rollingBack
        try JSONEncoder().encode(journal).write(to: transactionDirectory(journal.transactionID).appendingPathComponent("journal.json"), options: .atomic)
        return journal
    }

    private func assertRollbackIntent(file: StaticString = #filePath, line: UInt = #line) async throws {
        let journal = try await onlyJournal()
        XCTAssertEqual(journal.phase, .rollingBack, file: file, line: line)
    }

    private func transactionDirectory(_ identifier: UUID) -> URL {
        directory.appendingPathComponent(".update-transactions").appendingPathComponent(identifier.uuidString)
    }

    private func makeUpdate(version: String = "2.0", permissions: [String] = [], hostPermissions: [String] = []) throws -> ChromeWebStoreVerifiedUpdate {
        let source = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try writePackage(version: version, at: source, permissions: permissions, hostPermissions: hostPermissions)
        let archive = source.appendingPathExtension("zip")
        try FileManager.default.zipItem(at: source, to: archive, shouldKeepParent: false)
        return .init(extensionID: storeID, version: version, fileURL: archive)
    }

    private func writePackage(version: String, at url: URL, permissions: [String] = [], hostPermissions: [String] = []) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Update fixture", "version": version,
                                       "permissions": permissions, "host_permissions": hostPermissions]
        try JSONSerialization.data(withJSONObject: manifest).write(to: url.appendingPathComponent("manifest.json"))
    }

    private func installedVersion() throws -> String? {
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: currentDirectory.appendingPathComponent("manifest.json"))) as? [String: Any]
        return manifest?["version"] as? String
    }

    private func makeManager(loader: WebExtensionLoading, permissions: WebExtensionPermissionController? = nil,
                             fileManager: FileManager = .default, pixels: WebExtensionPixelFiring = NoOpWebExtensionPixelFiring()) -> WebExtensionManager {
        WebExtensionManager(configuration: WebExtensionConfigurationProvidingMock(), controllerConfiguration: .nonPersistent(),
                            windowTabProvider: WebExtensionWindowTabProvidingMock(), storageProvider: WebExtensionStorageProvider(extensionsDirectory: directory, fileManager: fileManager),
                            installationStore: installationStore, permissionController: permissions, loader: loader, pixelFiring: pixels)
    }
}

private final class ReadOnlyTransactionAfterRollbackFileManager: FileManager, @unchecked Sendable {
    override func moveItem(at source: URL, to destination: URL) throws {
        try super.moveItem(at: source, to: destination)
        if source.lastPathComponent == "previous" {
            try setAttributes([.posixPermissions: 0o555], ofItemAtPath: source.deletingLastPathComponent().path)
        }
    }
}

private final class FailingTransactionCleanupFileManager: FileManager, @unchecked Sendable {
    override func removeItem(at url: URL) throws {
        if url.deletingLastPathComponent().lastPathComponent == ".update-transactions" { throw CocoaError(.fileWriteNoPermission) }
        try super.removeItem(at: url)
    }
}

private final class FailingTransactionRollbackFileManager: FileManager, @unchecked Sendable {
    override func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        if sourceURL.lastPathComponent == "previous" { throw CocoaError(.fileWriteNoPermission) }
        try super.moveItem(at: sourceURL, to: destinationURL)
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class RejectingUpdateLoader: WebExtensionLoading {
    enum LoadError: Error { case injected, injectedUnload }
    private let base: WebExtensionLoader
    private let storage: WebExtensionStorageProviding
    var rejectedVersion: String?
    var rejectedUnloadVersion: String?
    var beforeLoad: ((String) -> Void)?
    var beforeLoadAsync: ((String) async throws -> Void)?
    var loadedVersions: [String] = []
    var delegate: WebExtensionLoadingDelegate? {
        get { base.delegate }
        set { base.delegate = newValue }
    }

    init(storageProvider: WebExtensionStorageProviding, permissionController: WebExtensionPermissionController? = nil) {
        storage = storageProvider
        base = WebExtensionLoader(storageProvider: storageProvider, permissionController: permissionController)
    }

    @MainActor
    func loadWebExtension(identifier: String, into controller: WKWebExtensionController) async throws -> WebExtensionLoadResult {
        try await loadWebExtension(identifier: identifier, into: controller, beforeActivation: { _ in })
    }

    @MainActor
    func loadWebExtension(identifier: String, into controller: WKWebExtensionController,
                          beforeActivation: @MainActor (WKWebExtension) throws -> Void) async throws -> WebExtensionLoadResult {
        let url = try XCTUnwrap(storage.resolveInstalledExtension(identifier: identifier))
        let candidate = try await WKWebExtension(resourceBaseURL: url)
        loadedVersions.append(try XCTUnwrap(candidate.version))
        if candidate.version == rejectedVersion { throw LoadError.injected }
        beforeLoad?(try XCTUnwrap(candidate.version))
        try await beforeLoadAsync?(XCTUnwrap(candidate.version))
        return try await base.loadWebExtension(identifier: identifier, into: controller, beforeActivation: beforeActivation)
    }

    @MainActor
    func loadWebExtensions(identifiers: [String], into controller: WKWebExtensionController) async -> [Result<WebExtensionLoadResult, Error>] {
        var results: [Result<WebExtensionLoadResult, Error>] = []
        for identifier in identifiers {
            do { results.append(.success(try await loadWebExtension(identifier: identifier, into: controller))) } catch { results.append(.failure(error)) }
        }
        return results
    }

    @MainActor
    func unloadExtension(identifier: String, from controller: WKWebExtensionController) throws {
        if let rejectedUnloadVersion, controller.extensionContexts.first?.webExtension.version == rejectedUnloadVersion { throw LoadError.injectedUnload }
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
        XCTFail("Automated replacement must not request installation consent")
        return .denied
    }
    func confirmPermissions(_ permissions: WebExtensionPermissionRequest, for context: WKWebExtensionContext) async -> WebExtensionPermissionPromptResult {
        XCTFail("Automated replacement must not request new permissions")
        return .denied
    }
}
