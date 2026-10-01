//
//  WebExtensionPermissionControllerTests.swift
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
final class WebExtensionPermissionControllerTests: XCTestCase {
    private let keyValueStore = InMemoryThrowingKeyValueStore()
    private let installationStore = InstalledWebExtensionStoringMock()
    private let prompter = PermissionPrompterMock()
    private var store: WebExtensionPermissionStore { WebExtensionPermissionStore(keyValueStore: keyValueStore) }

    private func makeController(permissionStore: (any WebExtensionPermissionStoring)? = nil) -> WebExtensionPermissionController {
        WebExtensionPermissionController(store: permissionStore ?? store, installationStore: installationStore, prompter: prompter)
    }

    func testRepeatedNotificationsSkipUnchangedSettingsButPersistGrantsAndRevocations() async throws {
        let countingStore = CountingPermissionStore(wrapping: store)
        let controller = makeController(permissionStore: countingStore)
        let context = try await makeContext()
        try await controller.prepare(context)
        XCTAssertEqual(countingStore.saveAttempts, 1)

        for _ in 0..<15 {
            NotificationCenter.default.post(name: WKWebExtensionContext.permissionsWereGrantedNotification, object: context)
            NotificationCenter.default.post(name: WKWebExtensionContext.permissionMatchPatternsWereGrantedNotification, object: context)
        }
        XCTAssertEqual(countingStore.saveAttempts, 1)

        let granted = await controller.request(.init(permissions: [.clipboardWrite]), for: context)
        XCTAssertTrue(granted)
        NotificationCenter.default.post(name: WKWebExtensionContext.permissionsWereGrantedNotification, object: context)
        XCTAssertEqual(countingStore.saveAttempts, 2)
        XCTAssertNotNil(try store.settings(for: context.uniqueIdentifier)?.grantedPermissions["clipboardWrite"])

        context.setPermissionStatus(.unknown, for: WKWebExtension.Permission.clipboardWrite)
        for _ in 0..<3 {
            NotificationCenter.default.post(name: WKWebExtensionContext.grantedPermissionsWereRemovedNotification, object: context)
        }
        XCTAssertEqual(countingStore.saveAttempts, 3)
        XCTAssertNil(try store.settings(for: context.uniqueIdentifier)?.grantedPermissions["clipboardWrite"])
    }

    func testFailedNotificationSaveIsRetriedUntilSuccessful() async throws {
        let countingStore = CountingPermissionStore(wrapping: store)
        let controller = makeController(permissionStore: countingStore)
        let context = try await makeContext()
        try await controller.prepare(context)
        context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.Permission.clipboardWrite)
        keyValueStore.shouldThrowOnSet = true
        NotificationCenter.default.post(name: WKWebExtensionContext.permissionsWereGrantedNotification, object: context)
        XCTAssertEqual(countingStore.saveAttempts, 2)
        XCTAssertNil(try store.settings(for: context.uniqueIdentifier)?.grantedPermissions["clipboardWrite"])

        keyValueStore.shouldThrowOnSet = false
        NotificationCenter.default.post(name: WKWebExtensionContext.permissionsWereGrantedNotification, object: context)
        XCTAssertEqual(countingStore.saveAttempts, 3)
        XCTAssertNotNil(try store.settings(for: context.uniqueIdentifier)?.grantedPermissions["clipboardWrite"])
        NotificationCenter.default.post(name: WKWebExtensionContext.permissionsWereGrantedNotification, object: context)
        XCTAssertEqual(countingStore.saveAttempts, 3)
    }

    func testRestoringAndUnloadingUnchangedSettingsDoesNotWriteAgain() async throws {
        let context = try await makeContext()
        try await makeController().prepare(context)
        let countingStore = CountingPermissionStore(wrapping: store)
        let controller = makeController(permissionStore: countingStore)
        let restored = WKWebExtensionContext(for: context.webExtension)
        restored.uniqueIdentifier = context.uniqueIdentifier
        try await controller.prepare(restored)
        NotificationCenter.default.post(name: WKWebExtensionContext.permissionsWereGrantedNotification, object: restored)
        controller.didUnload(restored.uniqueIdentifier)
        XCTAssertEqual(countingStore.saveAttempts, 0)
    }

    func testPrivateAccessChangesUpdateSavedSnapshot() async throws {
        let countingStore = CountingPermissionStore(wrapping: store)
        let controller = makeController(permissionStore: countingStore)
        let context = try await makeContext()
        try await controller.prepare(context)
        try controller.setHasAccessToPrivateData(true, for: context.uniqueIdentifier)
        NotificationCenter.default.post(name: WKWebExtensionContext.permissionsWereGrantedNotification, object: context)
        XCTAssertEqual(countingStore.saveAttempts, 2)
        try controller.setHasAccessToPrivateData(false, for: context.uniqueIdentifier)
        NotificationCenter.default.post(name: WKWebExtensionContext.permissionsWereGrantedNotification, object: context)
        XCTAssertEqual(countingStore.saveAttempts, 3)
        XCTAssertEqual(try store.settings(for: context.uniqueIdentifier)?.hasAccessToPrivateData, false)
    }

    func testReinstallationAfterForgettingConsentSavesIdenticalSettingsAgain() async throws {
        let countingStore = CountingPermissionStore(wrapping: store)
        let controller = makeController(permissionStore: countingStore)
        let context = try await makeContext()
        try await controller.prepare(context)
        try controller.forget(context.uniqueIdentifier)
        XCTAssertNil(try store.settings(for: context.uniqueIdentifier))
        try await controller.prepare(context)
        XCTAssertEqual(countingStore.saveAttempts, 2)
        XCTAssertNotNil(try store.settings(for: context.uniqueIdentifier))
    }

    func testWhenInstallationIsDeniedThenNoConsentIsStored() async throws {
        let controller = makeController()
        let context = try await makeContext()
        prompter.installationResponse = .denied

        do {
            try await controller.prepare(context)
            XCTFail("Expected installation to be denied")
        } catch WebExtensionPermissionController.PermissionError.installationDenied {
            XCTAssertNil(try store.settings(for: context.uniqueIdentifier))
            XCTAssertTrue(context.grantedPermissions.isEmpty)
            XCTAssertFalse(context.hasAccessToPrivateData)
        }
    }

    func testWhenInstallationIsApprovedThenOnlyRequiredPermissionsAreGranted() async throws {
        let controller = makeController()
        let context = try await makeContext()
        try await controller.prepare(context)

        XCTAssertTrue(context.hasPermission(.init("tabs")))
        XCTAssertFalse(context.hasPermission(.init("clipboardWrite")))
        XCTAssertFalse(context.hasAccessToPrivateData)
        XCTAssertEqual(prompter.installationRequests.first?.permissions, [.init("tabs")])
        XCTAssertTrue(context.hasAccess(to: URL(string: "https://example.com/page")!))
        XCTAssertFalse(context.hasAccess(to: URL(string: "https://optional.example/page")!))
        XCTAssertEqual(try store.settings(for: context.uniqueIdentifier)?.hasAccessToPrivateData, false)
    }

    func testWhenRelaunchedThenPrivateAccessAndGrantsAreRestoredWithoutPrompting() async throws {
        let context = try await makeContext()
        prompter.installationResponse = .granted(privateDataAccess: true)
        try await makeController().prepare(context)

        let restored = WKWebExtensionContext(for: context.webExtension)
        restored.uniqueIdentifier = context.uniqueIdentifier
        let controller = makeController()
        try await controller.prepare(restored)

        XCTAssertTrue(restored.hasAccessToPrivateData)
        XCTAssertTrue(restored.hasPermission(.init("tabs")))
        XCTAssertEqual(restored.grantedPermissionMatchPatterns, context.grantedPermissionMatchPatterns)
        XCTAssertEqual(prompter.installationRequests.count, 1)
    }

    func testWhenPrivateAccessIsChangedThenLoadedAndFutureContextsUseNewValue() async throws {
        let controller = makeController()
        let context = try await makeContext()
        try await controller.prepare(context)
        try controller.setHasAccessToPrivateData(true, for: context.uniqueIdentifier)
        XCTAssertTrue(context.hasAccessToPrivateData)

        let restored = WKWebExtensionContext(for: context.webExtension)
        restored.uniqueIdentifier = context.uniqueIdentifier
        try await makeController().prepare(restored)
        XCTAssertTrue(restored.hasAccessToPrivateData)
        try controller.setHasAccessToPrivateData(false, for: context.uniqueIdentifier)
        XCTAssertFalse(context.hasAccessToPrivateData)
        XCTAssertEqual(try store.settings(for: context.uniqueIdentifier)?.hasAccessToPrivateData, false)
    }

    func testWhenAdditionalPermissionsAreDeniedThenGrantsDoNotChange() async throws {
        let controller = makeController()
        let context = try await makeContext()
        try await controller.prepare(context)
        let previous = try store.settings(for: context.uniqueIdentifier)
        prompter.permissionResponse = .denied

        let granted = await controller.request(.init(permissions: [.init("clipboardWrite")]), for: context)

        XCTAssertFalse(granted)
        XCTAssertFalse(context.hasPermission(.init("clipboardWrite")))
        XCTAssertEqual(try store.settings(for: context.uniqueIdentifier), previous)
        XCTAssertEqual(prompter.permissionRequests.count, 1)
    }

    func testWhenAdditionalPermissionsAreApprovedThenAPIHostAndURLGrantsSurviveRelaunch() async throws {
        let controller = makeController()
        let context = try await makeContext()
        try await controller.prepare(context)
        let pattern = try WKWebExtension.MatchPattern(string: "https://optional.example/*")
        let url = try XCTUnwrap(URL(string: "https://another.example/page"))

        let apiGranted = await controller.request(.init(permissions: [.init("clipboardWrite")]), for: context)
        let hostGranted = await controller.request(.init(matchPatterns: [pattern]), for: context)
        let urlGranted = await controller.request(.init(urls: [url]), for: context)
        XCTAssertTrue(apiGranted && hostGranted && urlGranted)
        XCTAssertEqual(prompter.permissionRequests.count, 3)
        XCTAssertTrue(context.hasPermission(.clipboardWrite))
        XCTAssertNotNil(try store.settings(for: context.uniqueIdentifier)?.grantedPermissions["clipboardWrite"])

        let restored = WKWebExtensionContext(for: context.webExtension)
        restored.uniqueIdentifier = context.uniqueIdentifier
        try await makeController().prepare(restored)
        XCTAssertTrue(restored.hasPermission(.init("clipboardWrite")))
        XCTAssertEqual(restored.permissionStatus(for: pattern), .grantedExplicitly)
        XCTAssertTrue(restored.hasAccess(to: url))
    }

    func testWhenPermissionIsRevokedThenItIsNotRestored() async throws {
        let controller = makeController()
        let context = try await makeContext()
        try await controller.prepare(context)
        _ = await controller.request(.init(permissions: [.init("clipboardWrite")]), for: context)
        XCTAssertTrue(context.hasPermission(.clipboardWrite))
        context.setPermissionStatus(.unknown, for: WKWebExtension.Permission("clipboardWrite"))
        NotificationCenter.default.post(name: WKWebExtensionContext.grantedPermissionsWereRemovedNotification, object: context)

        let restored = WKWebExtensionContext(for: context.webExtension)
        restored.uniqueIdentifier = context.uniqueIdentifier
        try await makeController().prepare(restored)
        XCTAssertFalse(restored.hasPermission(.init("clipboardWrite")))
    }

    func testWhenSavingAdditionalConsentFailsThenRequestIsDenied() async throws {
        let controller = makeController()
        let context = try await makeContext()
        try await controller.prepare(context)
        keyValueStore.shouldThrowOnSet = true

        let granted = await controller.request(.init(permissions: [.init("clipboardWrite")]), for: context)

        XCTAssertFalse(granted)
        XCTAssertFalse(context.hasPermission(.init("clipboardWrite")))
    }

    func testWhenReadingConsentFailsThenExtensionDoesNotLoad() async throws {
        let context = try await makeContext()
        keyValueStore.shouldThrowOnGet = true
        do {
            try await makeController().prepare(context)
            XCTFail("Expected settings read failure")
        } catch {
            XCTAssertTrue(context.grantedPermissions.isEmpty)
            XCTAssertTrue(prompter.installationRequests.isEmpty)
        }
    }

    func testWhenRemovedThenAllConsentIsForgottenAndLateNotificationsCannotRestoreIt() async throws {
        let controller = makeController()
        let context = try await makeContext()
        prompter.installationResponse = .granted(privateDataAccess: true)
        try await controller.prepare(context)
        try controller.forget(context.uniqueIdentifier)
        NotificationCenter.default.post(name: WKWebExtensionContext.permissionsWereGrantedNotification, object: context)
        XCTAssertNil(try store.settings(for: context.uniqueIdentifier))

        let granted = await controller.request(.init(permissions: [.init("clipboardWrite")]), for: context)
        XCTAssertFalse(granted)
        XCTAssertTrue(prompter.permissionRequests.isEmpty)

        prompter.installationResponse = .granted(privateDataAccess: false)
        let reinstalled = WKWebExtensionContext(for: context.webExtension)
        reinstalled.uniqueIdentifier = context.uniqueIdentifier
        try await controller.prepare(reinstalled)
        XCTAssertFalse(reinstalled.hasAccessToPrivateData)
        XCTAssertEqual(prompter.installationRequests.count, 2)
    }

    func testWhenRemovedDuringPromptThenApprovalCannotRestoreSettings() async throws {
        let controller = makeController()
        let context = try await makeContext()
        try await controller.prepare(context)
        prompter.onPermissionRequest = { try? controller.forget(context.uniqueIdentifier) }

        let granted = await controller.request(.init(permissions: [.init("clipboardWrite")]), for: context)

        XCTAssertFalse(granted)
        XCTAssertNil(try store.settings(for: context.uniqueIdentifier))
    }

    func testWhenTrustedExtensionLoadsThenExistingDDGBehaviorIsPreserved() async throws {
        let controller = makeController()
        let context = try await makeContext()
        controller.trustedInstallations.insert(context.uniqueIdentifier)
        try await controller.prepare(context)

        XCTAssertTrue(context.hasAccessToPrivateData)
        XCTAssertTrue(context.hasPermission(.init("tabs")))
        XCTAssertTrue(prompter.installationRequests.isEmpty)
        let granted = await controller.request(.init(permissions: [.init("clipboardWrite")]), for: context)
        XCTAssertTrue(granted)
        XCTAssertTrue(prompter.permissionRequests.isEmpty)
    }

    func testWhenManifestClaimsToBeDDGThenUserConsentIsStillRequired() async throws {
        let context = try await makeContext(claimsDDGIdentity: true)
        try await makeController().prepare(context)
        XCTAssertEqual(prompter.installationRequests.count, 1)
        XCTAssertFalse(context.hasAccessToPrivateData)
    }

    func testWhenOneExtensionIsRemovedThenOtherExtensionSettingsArePreserved() throws {
        var settings = WebExtensionPermissionSettings()
        settings.hasAccessToPrivateData = true
        try store.save(settings, for: "first")
        try store.save(settings, for: "second")
        try store.removeSettings(for: "first")

        XCTAssertNil(try store.settings(for: "first"))
        XCTAssertEqual(try store.settings(for: "second"), settings)
    }

    func testWhenSavedPermissionsHaveExpiredThenTheyAreNotGrantedOnRelaunch() async throws {
        let context = try await makeContext()
        var settings = WebExtensionPermissionSettings()
        settings.grantedPermissions = ["clipboardWrite": .distantPast, "tabs": .distantFuture]
        settings.grantedMatchPatterns = ["https://optional.example/*": .distantPast]
        try store.save(settings, for: context.uniqueIdentifier)

        try await makeController().prepare(context)

        XCTAssertFalse(context.hasPermission(.init("clipboardWrite")))
        XCTAssertTrue(context.hasPermission(.init("tabs")))
        XCTAssertFalse(context.hasAccess(to: try XCTUnwrap(URL(string: "https://optional.example/"))))
        XCTAssertTrue(prompter.installationRequests.isEmpty)
    }

    func testWhenUnloadedThenPendingPermissionRequestsCannotBeGranted() async throws {
        let controller = makeController()
        let context = try await makeContext()
        try await controller.prepare(context)
        prompter.onPermissionRequest = { controller.didUnload(context.uniqueIdentifier) }

        let granted = await controller.request(.init(permissions: [.init("clipboardWrite")]), for: context)

        XCTAssertFalse(granted)
        XCTAssertNotNil(try store.settings(for: context.uniqueIdentifier))
    }

    func testWhenManagerInstallationIsDeniedThenNothingIsLoadedOrInstalled() async throws {
        let source = try makeExtensionURL()
        let storage = WebExtensionStorageProvidingMock()
        storage.resolvedExtensionURL = source
        let manager = makeManager(storage: storage)
        prompter.installationResponse = .denied

        do {
            try await manager.installExtension(from: source)
            XCTFail("Expected installation denial")
        } catch {
            XCTAssertTrue(manager.loadedExtensions.isEmpty)
            XCTAssertTrue(installationStore.installedExtensions.isEmpty)
            XCTAssertTrue(storage.removeExtensionCalled)
            let identifier = try XCTUnwrap(storage.copyExtensionIdentifier)
            XCTAssertNil(try store.settings(for: identifier))
        }
    }

    func testWhenManagerReloadsAfterDataClearingThenConsentSurvivesAndRemovalForgetsIt() async throws {
        let source = try makeExtensionURL()
        let storage = WebExtensionStorageProvidingMock()
        storage.resolvedExtensionURL = source
        let manager = makeManager(storage: storage)
        prompter.installationResponse = .granted(privateDataAccess: true)
        try await manager.installExtension(from: source)
        let identifier = try XCTUnwrap(manager.webExtensionIdentifiers.first)

        manager.unloadAllExtensions()
        await manager.reloadInstalledExtensions()

        XCTAssertEqual(manager.context(for: identifier)?.hasAccessToPrivateData, true)
        XCTAssertEqual(prompter.installationRequests.count, 1)
        XCTAssertNotNil(try store.settings(for: identifier))

        manager.unloadAllExtensions()
        try manager.uninstallExtension(identifier: identifier)
        await manager.reloadInstalledExtensions()
        XCTAssertNil(try store.settings(for: identifier))
        XCTAssertTrue(manager.loadedExtensions.isEmpty)
        XCTAssertTrue(manager.webExtensionIdentifiers.isEmpty)
    }

    func testWhenLegacyConsentIsDeniedAtLaunchThenInstalledExtensionIsPreservedButNotLoaded() async throws {
        let source = try makeExtensionURL()
        let storage = WebExtensionStorageProvidingMock()
        storage.resolvedExtensionURL = source
        let manager = makeManager(storage: storage)
        installationStore.add(InstalledWebExtension(uniqueIdentifier: "legacy", filename: "extension", name: nil, version: nil))
        prompter.installationResponse = .denied

        await manager.loadInstalledExtensions()

        XCTAssertTrue(manager.loadedExtensions.isEmpty)
        XCTAssertEqual(manager.webExtensionIdentifiers, ["legacy"])
        XCTAssertFalse(storage.removeExtensionCalled)
        XCTAssertEqual(storage.cleanupOrphanedExtensionsKnownIdentifiers, ["legacy"])
        XCTAssertNil(try store.settings(for: "legacy"))
    }

    func testWhenRuntimeDelegateReceivesRequestsThenAllThreePermissionKindsRequireConsent() async throws {
        let source = try makeExtensionURL()
        let storage = WebExtensionStorageProvidingMock()
        storage.resolvedExtensionURL = source
        let manager = makeManager(storage: storage)
        try await manager.installExtension(from: source)
        let context = try XCTUnwrap(manager.loadedExtensions.first)
        prompter.permissionResponse = .denied

        let (permissions, _) = await manager.webExtensionController(manager.controller,
                                                                  promptForPermissions: [.init("clipboardWrite")],
                                                                  in: nil, for: context)
        let (patterns, _) = await manager.webExtensionController(manager.controller,
                                                               promptForPermissionMatchPatterns: [try .init(string: "https://optional.example/*")],
                                                               in: nil, for: context)
        let (urls, _) = await manager.webExtensionController(manager.controller,
                                                           promptForPermissionToAccess: [try XCTUnwrap(URL(string: "https://optional.example/"))],
                                                           in: nil, for: context)

        XCTAssertTrue(permissions.isEmpty)
        XCTAssertTrue(patterns.isEmpty)
        XCTAssertTrue(urls.isEmpty)
        XCTAssertEqual(prompter.permissionRequests.count, 3)
        try manager.uninstallExtension(identifier: context.uniqueIdentifier)
    }

    func testDirectLoaderUnloadInvalidatesPendingPromptsAndLateNotificationsButPreservesConsent() async throws {
        let permissions = makeController()
        let storage = WebExtensionStorageProvidingMock()
        storage.resolvedExtensionURL = try makeExtensionURL()
        let loader = WebExtensionLoader(storageProvider: storage, permissionController: permissions)
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        let identifier = UUID().uuidString
        try await loader.loadWebExtension(identifier: identifier, into: controller)
        let context = try XCTUnwrap(controller.extensionContexts.first)
        let savedSettings = try XCTUnwrap(store.settings(for: identifier))
        prompter.onPermissionRequest = {
            do {
                try loader.unloadExtension(identifier: identifier, from: controller)
            } catch {
                XCTFail("Unload failed: \(error)")
            }
        }

        let granted = await permissions.request(.init(permissions: [.clipboardWrite]), for: context)

        XCTAssertFalse(granted)
        XCTAssertTrue(controller.extensionContexts.isEmpty)
        context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.Permission.clipboardWrite)
        NotificationCenter.default.post(name: WKWebExtensionContext.permissionsWereGrantedNotification, object: context)
        XCTAssertEqual(try store.settings(for: identifier), savedSettings)

        // Reloading still uses the saved consent and creates fresh tracking.
        prompter.onPermissionRequest = nil
        try await loader.loadWebExtension(identifier: identifier, into: controller)
        let reloaded = try XCTUnwrap(controller.extensionContexts.first)
        XCTAssertEqual(prompter.installationRequests.count, 1)
        XCTAssertFalse(reloaded.hasPermission(.clipboardWrite))
        let grantedAfterReload = await permissions.request(.init(permissions: [.clipboardWrite]), for: reloaded)
        XCTAssertTrue(grantedAfterReload)
        try loader.unloadExtension(identifier: identifier, from: controller)
    }

    func testFailedLoaderUnloadKeepsPermissionTrackingForTheLoadedContext() async throws {
        let permissions = makeController()
        let storage = WebExtensionStorageProvidingMock()
        storage.resolvedExtensionURL = try makeExtensionURL()
        let loader = WebExtensionLoader(storageProvider: storage, permissionController: permissions)
        let controller = FailingUnloadWebExtensionController(configuration: .nonPersistent())
        let identifier = UUID().uuidString
        try await loader.loadWebExtension(identifier: identifier, into: controller)
        let context = try XCTUnwrap(controller.extensionContexts.first)

        XCTAssertThrowsError(try loader.unloadExtension(identifier: identifier, from: controller))

        XCTAssertTrue(controller.extensionContexts.contains(context))
        let granted = await permissions.request(.init(permissions: [.clipboardWrite]), for: context)
        XCTAssertTrue(granted)
        XCTAssertNotNil(try store.settings(for: identifier)?.grantedPermissions["clipboardWrite"])
    }

    func testFailedConsentDeletionStillInvalidatesPendingPromptsAndNotifications() async throws {
        let controller = makeController()
        let context = try await makeContext()
        try await controller.prepare(context)
        let savedSettings = try XCTUnwrap(store.settings(for: context.uniqueIdentifier))
        keyValueStore.shouldThrowOnRemove = true
        prompter.onPermissionRequest = {
            do {
                try controller.forget(context.uniqueIdentifier)
                XCTFail("Expected consent deletion to fail")
            } catch {
                // The persistence failure must not keep the context active.
            }
        }

        let granted = await controller.request(.init(permissions: [.clipboardWrite]), for: context)

        XCTAssertFalse(granted)
        context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.Permission.clipboardWrite)
        NotificationCenter.default.post(name: WKWebExtensionContext.permissionsWereGrantedNotification, object: context)
        XCTAssertEqual(try store.settings(for: context.uniqueIdentifier), savedSettings)

        keyValueStore.shouldThrowOnRemove = false
        try controller.forget(context.uniqueIdentifier)
        XCTAssertNil(try store.settings(for: context.uniqueIdentifier))
    }

    func testUninstallContinuesAfterConsentDeletionFailsAndReinstallRequiresFreshConsent() async throws {
        let source = try makeExtensionURL()
        let storage = WebExtensionStorageProvidingMock()
        storage.resolvedExtensionURL = source
        let manager = makeManager(storage: storage)
        try await manager.installExtension(from: source)
        let identifier = try XCTUnwrap(manager.webExtensionIdentifiers.first)
        let savedSettings = try XCTUnwrap(store.settings(for: identifier))
        keyValueStore.shouldThrowOnRemove = true

        try manager.uninstallExtension(identifier: identifier)

        XCTAssertTrue(manager.loadedExtensions.isEmpty)
        XCTAssertTrue(manager.webExtensionIdentifiers.isEmpty)
        XCTAssertTrue(installationStore.removeCalled)
        XCTAssertTrue(storage.removeExtensionCalled)
        XCTAssertEqual(storage.removeExtensionIdentifier, identifier)
        // Disk failure leaves orphaned consent under the old installation UUID.
        XCTAssertEqual(try store.settings(for: identifier), savedSettings)

        keyValueStore.shouldThrowOnRemove = false
        try await manager.installExtension(from: source)
        let newIdentifier = try XCTUnwrap(manager.webExtensionIdentifiers.first)
        XCTAssertNotEqual(newIdentifier, identifier)
        XCTAssertEqual(prompter.installationRequests.count, 2)
        try manager.uninstallExtension(identifier: newIdentifier)
    }

    func testInstalledExtensionSurvivesSettingsReadFailureAndLoadsOnRetry() async throws {
        let storage = WebExtensionStorageProvidingMock()
        storage.resolvedExtensionURL = try makeExtensionURL()
        let manager = makeManager(storage: storage)
        installationStore.add(InstalledWebExtension(uniqueIdentifier: "existing", filename: "extension", name: nil, version: nil))
        keyValueStore.shouldThrowOnGet = true

        await manager.loadInstalledExtensions()

        XCTAssertEqual(manager.webExtensionIdentifiers, ["existing"])
        XCTAssertTrue(manager.loadedExtensions.isEmpty)
        XCTAssertFalse(storage.removeExtensionCalled)
        XCTAssertEqual(storage.cleanupOrphanedExtensionsKnownIdentifiers, ["existing"])
        keyValueStore.shouldThrowOnGet = false
        await manager.loadInstalledExtensions()
        XCTAssertEqual(manager.loadedExtensions.count, 1)
        try manager.uninstallExtension(identifier: "existing")
    }

    func testInstalledExtensionSurvivesConsentSaveFailure() async throws {
        let storage = WebExtensionStorageProvidingMock()
        storage.resolvedExtensionURL = try makeExtensionURL()
        let manager = makeManager(storage: storage)
        installationStore.add(InstalledWebExtension(uniqueIdentifier: "existing", filename: "extension", name: nil, version: nil))
        keyValueStore.shouldThrowOnSet = true

        await manager.loadInstalledExtensions()

        XCTAssertEqual(manager.webExtensionIdentifiers, ["existing"])
        XCTAssertTrue(manager.loadedExtensions.isEmpty)
        XCTAssertFalse(storage.removeExtensionCalled)
        XCTAssertEqual(prompter.installationRequests.count, 1)
    }

    func testCorruptManifestIsRemovedEvenWhenPermissionControllerIsEnabled() async throws {
        let source = try makeExtensionURL()
        try Data("invalid manifest".utf8).write(to: source.appendingPathComponent("manifest.json"))
        let storage = WebExtensionStorageProvidingMock()
        storage.resolvedExtensionURL = source
        let manager = makeManager(storage: storage)
        installationStore.add(InstalledWebExtension(uniqueIdentifier: "broken", filename: "extension", name: nil, version: nil))

        await manager.loadInstalledExtensions()

        XCTAssertTrue(manager.webExtensionIdentifiers.isEmpty)
        XCTAssertTrue(manager.loadedExtensions.isEmpty)
        XCTAssertEqual(storage.removeExtensionIdentifier, "broken")
        XCTAssertEqual(storage.cleanupOrphanedExtensionsKnownIdentifiers, [])
        XCTAssertTrue(prompter.installationRequests.isEmpty)
    }

    func testMissingBundleIsRemovedEvenWhenPermissionControllerIsEnabled() async {
        let storage = WebExtensionStorageProvidingMock()
        storage.shouldReturnNilForResolve = true
        let manager = makeManager(storage: storage)
        installationStore.add(InstalledWebExtension(uniqueIdentifier: "missing", filename: "extension", name: nil, version: nil))

        await manager.loadInstalledExtensions()

        XCTAssertTrue(manager.webExtensionIdentifiers.isEmpty)
        XCTAssertEqual(storage.removeExtensionIdentifier, "missing")
        XCTAssertEqual(storage.cleanupOrphanedExtensionsKnownIdentifiers, [])
    }

    func testMixedLoadFailuresPreserveOnlyTheExtensionWithPermissionFailure() async {
        let storage = WebExtensionStorageProvidingMock()
        let loader = WebExtensionLoadingMock()
        loader.mockLoadResults = [
            .failure(WebExtensionLoader.PermissionPreparationError(underlyingError: WebExtensionPermissionController.PermissionError.installationDenied)),
            .failure(NSError(domain: WKError.errorDomain, code: WKError.Code.webContentProcessTerminated.rawValue))
        ]
        let manager = WebExtensionManager(configuration: WebExtensionConfigurationProvidingMock(),
                                          windowTabProvider: WebExtensionWindowTabProvidingMock(),
                                          storageProvider: storage,
                                          installationStore: installationStore,
                                          permissionController: makeController(),
                                          loader: loader)
        installationStore.add(InstalledWebExtension(uniqueIdentifier: "denied", filename: "extension", name: nil, version: nil))
        installationStore.add(InstalledWebExtension(uniqueIdentifier: "broken", filename: "extension", name: nil, version: nil))

        await manager.loadInstalledExtensions()

        XCTAssertEqual(manager.webExtensionIdentifiers, ["denied"])
        XCTAssertEqual(storage.removeExtensionIdentifier, "broken")
        XCTAssertEqual(storage.cleanupOrphanedExtensionsKnownIdentifiers, ["denied"])
    }

    private func makeManager(storage: WebExtensionStorageProvidingMock) -> WebExtensionManager {
        WebExtensionManager(configuration: WebExtensionConfigurationProvidingMock(),
                            windowTabProvider: WebExtensionWindowTabProvidingMock(),
                            storageProvider: storage,
                            installationStore: installationStore,
                            permissionController: makeController())
    }

    private func makeContext(claimsDDGIdentity: Bool = false) async throws -> WKWebExtensionContext {
        let directory = try makeExtensionURL(claimsDDGIdentity: claimsDDGIdentity)
        let webExtension = try await WKWebExtension(resourceBaseURL: directory)
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = UUID().uuidString
        return context
    }

    private func makeExtensionURL(claimsDDGIdentity: Bool = false) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        var manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Permission Test",
            "version": "1.0",
            "permissions": ["tabs"],
            "optional_permissions": ["clipboardWrite"],
            "host_permissions": ["https://example.com/*"],
            "optional_host_permissions": ["https://optional.example/*"]
        ]
        if claimsDDGIdentity {
            manifest["browser_specific_settings"] = ["duckduckgo": ["id": DuckDuckGoWebExtensionType.embedded.rawValue]]
        }
        try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("manifest.json"))
        return directory
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class PermissionPrompterMock: WebExtensionPermissionPrompting {
    var installationResponse: WebExtensionPermissionInstallationPromptResult = .granted(privateDataAccess: false)
    var permissionResponse: WebExtensionPermissionPromptResult = .granted
    var installationRequests: [WebExtensionPermissionRequest] = []
    var permissionRequests: [WebExtensionPermissionRequest] = []
    var onPermissionRequest: (() -> Void)?

    func confirmInstallation(of webExtension: WKWebExtension, permissions: WebExtensionPermissionRequest) async -> WebExtensionPermissionInstallationPromptResult {
        installationRequests.append(permissions)
        return installationResponse
    }

    func confirmPermissions(_ permissions: WebExtensionPermissionRequest, for context: WKWebExtensionContext) async -> WebExtensionPermissionPromptResult {
        permissionRequests.append(permissions)
        onPermissionRequest?()
        return permissionResponse
    }
}

private final class CountingPermissionStore: WebExtensionPermissionStoring {
    private let wrapped: any WebExtensionPermissionStoring
    private(set) var saveAttempts = 0

    init(wrapping store: any WebExtensionPermissionStoring) {
        wrapped = store
    }

    func settings(for identifier: String) throws -> WebExtensionPermissionSettings? {
        try wrapped.settings(for: identifier)
    }

    func save(_ settings: WebExtensionPermissionSettings, for identifier: String) throws {
        saveAttempts += 1
        try wrapped.save(settings, for: identifier)
    }

    func removeSettings(for identifier: String) throws {
        try wrapped.removeSettings(for: identifier)
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class FailingUnloadWebExtensionController: WKWebExtensionController {
    override func unload(_ extensionContext: WKWebExtensionContext) throws {
        throw NSError(domain: "WebExtensionPermissionControllerTests", code: 1)
    }
}
