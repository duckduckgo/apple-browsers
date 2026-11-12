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
        let transactionRoot = extensionsDirectory.appendingPathComponent(installationID).appendingPathComponent(InstalledWebExtension.packagesDirectoryName)
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
        makeInstaller(store: proxy)

        await manager.loadInstalledExtensions()

        XCTAssertEqual(installationStore.installedExtensions.first?.version, "2.0")
        XCTAssertEqual(manager.context(for: installationID)?.webExtension.version, "2.0")
        let remaining = await pending.pendingUpdate(for: storeID)
        XCTAssertEqual(remaining?.version, "3.0")
        XCTAssertEqual(pixels.events, [.applied(.other)], "The later session download is not applied or reported yet")
    }

    func testNewestPackageReplacesDisabledCandidateWithoutRestoringAnOlderVersion() async throws {
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
        XCTAssertEqual(pixels.events, [.applied(.other)])

    }

    func testOfferOlderThanDisabledCandidateDoesNotChangeTheSelection() async throws {
        _ = try await manager.applyVerifiedUpdate(makeUpdate(version: "2.0", permissions: ["storage"]), replacing: original, isEligible: { true })
        _ = try await pending.store(makeUpdate(version: "1.5"))
        let owner = makeInstaller()

        _ = await owner.runOnce()

        XCTAssertEqual(installationStore.installedExtensions.first?.version, "2.0")
        XCTAssertEqual(installationStore.installedExtensions.first?.isDisabled, true)

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

    func testRuntimeReadyPackageAppliesWhenAlreadyInactive() async throws {
        let proxy = StartupPendingStoreProxy(base: pending)
        let applied = expectation(description: "runtime update applied")
        proxy.onRemove = { update in if update.version == "2.0" { applied.fulfill() } }
        let owner = makeInstaller(store: proxy, canApplyWhileInactive: { _ in true })
        await manager.loadInstalledExtensions()

        _ = try await pending.store(makeUpdate(version: "2.0"))
        await fulfillment(of: [applied], timeout: 2)

        XCTAssertTrue(owner.isSnapshotReady)
        XCTAssertEqual(manager.context(for: installationID)?.webExtension.version, "2.0")
        XCTAssertEqual(installationStore.installedExtensions.first?.needsInitialUpdateActivationValidation, false)
    }

    func testRuntimeApplicationWaitsForTheStartupApplicationAndInitialLoad() async throws {
        let pixels = WebExtensionUpdatePixelFiringMock()
        manager = makeManager(pixels: pixels)
        _ = try await pending.store(makeUpdate(version: "2.0"))
        let proxy = StartupPendingStoreProxy(base: pending)
        let copying = expectation(description: "startup installation copy in progress")
        let applied = expectation(description: "later runtime package applied")
        var resumeStartup: CheckedContinuation<Void, Never>?
        var copies = 0
        var activeCopies = 0
        var maximumActiveCopies = 0
        proxy.onCopy = {
            copies += 1
            activeCopies += 1
            maximumActiveCopies = max(maximumActiveCopies, activeCopies)
            if copies == 1 {
                copying.fulfill()
                await withCheckedContinuation { resumeStartup = $0 }
            }
        }
        proxy.onInstallationCopyRemoved = { activeCopies -= 1 }
        proxy.onRemove = { update in if update.version == "3.0" { applied.fulfill() } }
        let owner = makeInstaller(store: proxy, canApplyWhileInactive: { _ in true })
        let loading = Task { await manager.loadInstalledExtensions() }
        await fulfillment(of: [copying], timeout: 2)

        _ = try await pending.store(makeUpdate(version: "3.0"))
        owner.activityDidChange()
        XCTAssertEqual(copies, 1)
        resumeStartup?.resume()
        await loading.value
        await fulfillment(of: [applied], timeout: 2)

        XCTAssertEqual(maximumActiveCopies, 1)
        XCTAssertEqual(manager.context(for: installationID)?.webExtension.version, "3.0")
        XCTAssertFalse(pixels.events.contains { if case .failed = $0 { return true }; return false })
    }

    func testRuntimeActivityCancelsTheWaitingPhaseAndCanRetryLater() async throws {
        let proxy = StartupPendingStoreProxy(base: pending)
        let waiting = expectation(description: "inactive grace period started")
        let applied = expectation(description: "runtime update applied after another inactive event")
        proxy.onRemove = { update in if update.version == "2.0" { applied.fulfill() } }
        var allowed = true
        var pause = true
        let owner = makeInstaller(store: proxy, canApplyWhileInactive: { _ in allowed }, sleep: { _ in
            if pause {
                waiting.fulfill()
                try await Task.sleep(for: .seconds(60))
            }
        })
        await manager.loadInstalledExtensions()
        let incumbent = try XCTUnwrap(manager.context(for: installationID))
        _ = try await pending.store(makeUpdate(version: "2.0"))
        await fulfillment(of: [waiting], timeout: 2)

        allowed = false
        owner.activityDidChange()
        await owner.cancelAndWait()
        XCTAssertTrue(manager.context(for: installationID) === incumbent)
        XCTAssertEqual(installationStore.installedExtensions, [original])

        pause = false
        allowed = true
        owner.activityDidChange()
        await fulfillment(of: [applied], timeout: 2)
        XCTAssertEqual(manager.context(for: installationID)?.webExtension.version, "2.0")
    }

    func testRuntimeWithoutPendingPackagesDoesNotStartAnIdleDelay() async throws {
        let proxy = StartupPendingStoreProxy(base: pending)
        let checked = expectation(description: "runtime queue checked its pending store")
        var reads = 0
        proxy.onRead = {
            reads += 1
            if reads == 2 { checked.fulfill() }
        }
        _ = makeInstaller(store: proxy, canApplyWhileInactive: { _ in true }, sleep: { _ in
            XCTFail("No pending package means there must be no idle delay")
        })

        await manager.loadInstalledExtensions()
        await fulfillment(of: [checked], timeout: 2)

        XCTAssertEqual(installationStore.installedExtensions, [original])
    }

    func testRuntimeReactivationDuringCopyKeepsTheIncumbentAndPendingPackage() async throws {
        let proxy = StartupPendingStoreProxy(base: pending)
        let finished = expectation(description: "deferred installation copy cleaned")
        proxy.onInstallationCopyRemoved = { finished.fulfill() }
        var allowed = true
        proxy.onCopy = { allowed = false }
        _ = makeInstaller(store: proxy, canApplyWhileInactive: { _ in allowed })
        await manager.loadInstalledExtensions()
        let incumbent = try XCTUnwrap(manager.context(for: installationID))

        _ = try await pending.store(makeUpdate(version: "2.0"))
        await fulfillment(of: [finished], timeout: 2)

        XCTAssertTrue(manager.context(for: installationID) === incumbent)
        XCTAssertEqual(installationStore.installedExtensions, [original])
        let remaining = await pending.pendingUpdate(for: storeID)
        XCTAssertEqual(remaining?.version, "2.0")
    }

    func testRuntimeActivityFollowingPublicationDoesNotCancelActivation() async throws {
        let proxy = StartupPendingStoreProxy(base: pending)
        let applied = expectation(description: "committed runtime update finished activating")
        proxy.onRemove = { update in if update.version == "2.0" { applied.fulfill() } }
        var allowed = true
        weak var owner: ChromeWebStoreUpdateInstaller?
        let installer = makeInstaller(store: proxy, canApplyWhileInactive: { _ in allowed })
        owner = installer
        manager.didCommitStoreUpdate = { _, _ in
            allowed = false
            owner?.activityDidChange()
            return true
        }
        await manager.loadInstalledExtensions()

        _ = try await pending.store(makeUpdate(version: "2.0"))
        await fulfillment(of: [applied], timeout: 2)

        XCTAssertFalse(allowed)
        XCTAssertEqual(manager.context(for: installationID)?.webExtension.version, "2.0")
        XCTAssertEqual(installationStore.installedExtensions.first?.needsInitialUpdateActivationValidation, false)
    }

    func testRuntimeTransientActivityDuringCopyRequiresANewQuietPeriod() async throws {
        let proxy = StartupPendingStoreProxy(base: pending)
        let applied = expectation(description: "runtime update applied after a fresh quiet period")
        var allowed = true
        var copies = 0
        var delays = 0
        weak var owner: ChromeWebStoreUpdateInstaller?
        proxy.onCopy = {
            copies += 1
            if copies == 1 {
                allowed = false
                owner?.activityDidChange()
                allowed = true
                owner?.activityDidChange()
            }
        }
        proxy.onInstallationCopyRemoved = {
            if copies == 1 { XCTAssertEqual(self.manager.context(for: self.installationID)?.webExtension.version, "1.0") }
        }
        proxy.onRemove = { update in if update.version == "2.0" { applied.fulfill() } }
        let installer = makeInstaller(store: proxy, canApplyWhileInactive: { _ in allowed }, sleep: { _ in delays += 1 })
        owner = installer
        await manager.loadInstalledExtensions()

        _ = try await pending.store(makeUpdate(version: "2.0"))
        await fulfillment(of: [applied], timeout: 2)

        XCTAssertEqual(copies, 2)
        XCTAssertEqual(delays, 2)
        XCTAssertEqual(manager.context(for: installationID)?.webExtension.version, "2.0")
    }

    func testRuntimeTransientActivityDuringThePostDelaySnapshotRequiresANewQuietPeriod() async throws {
        let proxy = StartupPendingStoreProxy(base: pending)
        let applied = expectation(description: "runtime update applied after a new post-snapshot quiet period")
        var allowed = true
        var delays = 0
        var injectedAtDelay: Int?
        weak var owner: ChromeWebStoreUpdateInstaller?
        proxy.onRead = {
            if delays > 0, injectedAtDelay == nil {
                injectedAtDelay = delays
                allowed = false
                owner?.activityDidChange()
                allowed = true
                owner?.activityDidChange()
            }
        }
        proxy.onCopy = { XCTAssertGreaterThan(delays, try XCTUnwrap(injectedAtDelay)) }
        proxy.onRemove = { update in if update.version == "2.0" { applied.fulfill() } }
        let installer = makeInstaller(store: proxy, canApplyWhileInactive: { _ in allowed }, sleep: { _ in delays += 1 })
        owner = installer
        await manager.loadInstalledExtensions()

        _ = try await pending.store(makeUpdate(version: "2.0"))
        await fulfillment(of: [applied], timeout: 2)

        XCTAssertNotNil(injectedAtDelay)
        XCTAssertEqual(manager.context(for: installationID)?.webExtension.version, "2.0")
    }

    func testRuntimeActivityDuringTheFirstActivationRequiresANewQuietPeriodForTheNextExtension() async throws {
        let otherID = UUID().uuidString
        let otherStoreID = ChromeWebStoreID.onePassword.rawValue
        try writePackage(version: "1.0", at: extensionsDirectory.appendingPathComponent(otherID))
        installationStore.add(.init(uniqueIdentifier: otherID, filename: otherID, name: "Second fixture", version: "1.0",
                                     storeIdentity: .init(store: .chromeWebStore, id: otherStoreID)))
        try permissionStore.save(WebExtensionPermissionSettings(), for: otherID)
        let proxy = StartupPendingStoreProxy(base: pending)
        let applied = expectation(description: "both runtime updates applied")
        applied.expectedFulfillmentCount = 2
        var allowed = false
        var delays = 0
        var firstCommitDelay: Int?
        weak var owner: ChromeWebStoreUpdateInstaller?
        proxy.onCopy = {
            if let firstCommitDelay { XCTAssertGreaterThan(delays, firstCommitDelay) }
        }
        proxy.onRemove = { _ in applied.fulfill() }
        let installer = makeInstaller(store: proxy, canApplyWhileInactive: { _ in allowed }, sleep: { _ in delays += 1 })
        owner = installer
        manager.didCommitStoreUpdate = { _, _ in
            if firstCommitDelay == nil {
                firstCommitDelay = delays
                allowed = false
                owner?.activityDidChange()
                allowed = true
                owner?.activityDidChange()
            }
            return true
        }
        await manager.loadInstalledExtensions()
        let other = try makeUpdate(version: "2.0", binding: otherID)
        _ = try await pending.store(.init(extensionID: otherStoreID, version: other.version, fileURL: other.fileURL, installationIdentifier: otherID))
        _ = try await pending.store(makeUpdate(version: "2.0"))

        allowed = true
        owner?.activityDidChange()
        await fulfillment(of: [applied], timeout: 2)

        XCTAssertEqual(manager.context(for: installationID)?.webExtension.version, "2.0")
        XCTAssertEqual(manager.context(for: otherID)?.webExtension.version, "2.0")
    }

    func testRuntimeNewerArrivalRemainsPendingAndAppliesSeriallyAfterTheInFlightCopy() async throws {
        let proxy = StartupPendingStoreProxy(base: pending)
        let applied = expectation(description: "newest runtime package applied")
        var copied = 0
        proxy.onCopy = {
            copied += 1
            if copied == 1 { _ = try await self.pending.store(self.makeUpdate(version: "3.0")) }
        }
        proxy.onRemove = { update in if update.version == "3.0" { applied.fulfill() } }
        _ = makeInstaller(store: proxy, canApplyWhileInactive: { _ in true })
        await manager.loadInstalledExtensions()

        _ = try await pending.store(makeUpdate(version: "2.0"))
        await fulfillment(of: [applied], timeout: 2)

        XCTAssertEqual(copied, 2)
        XCTAssertEqual(manager.context(for: installationID)?.webExtension.version, "3.0")
        let remaining = await pending.pendingUpdate(for: storeID)
        XCTAssertNil(remaining)
    }

    func testUnchangedActivityDoesNotRestartThePendingGracePeriod() async throws {
        let proxy = StartupPendingStoreProxy(base: pending)
        let applied = expectation(description: "runtime update applied despite unchanged activity notifications")
        proxy.onRemove = { update in if update.version == "2.0" { applied.fulfill() } }
        var delays = 0
        weak var owner: ChromeWebStoreUpdateInstaller?
        let installer = makeInstaller(store: proxy, canApplyWhileInactive: { _ in true }, sleep: { _ in
            delays += 1
            owner?.activityDidChange()
            try Task.checkCancellation()
        })
        owner = installer
        await manager.loadInstalledExtensions()

        _ = try await pending.store(makeUpdate(version: "2.0"))
        await fulfillment(of: [applied], timeout: 2)

        XCTAssertEqual(delays, 1)
    }

    func testNewPackageDuringTheEmptyCompletionSnapshotCannotLoseItsWakeup() async throws {
        let proxy = StartupPendingStoreProxy(base: pending)
        let applied = expectation(description: "package accepted during completion snapshot applied")
        var finishedFirst = false
        var injected = false
        weak var owner: ChromeWebStoreUpdateInstaller?
        proxy.onRemove = { update in
            if update.version == "2.0" { finishedFirst = true }
            if update.version == "3.0" { applied.fulfill() }
        }
        proxy.onReadAsync = {
            if finishedFirst, !injected {
                injected = true
                _ = try await self.pending.store(self.makeUpdate(version: "3.0"))
                owner?.activityDidChange(force: true)
            }
        }
        let installer = makeInstaller(store: proxy, canApplyWhileInactive: { _ in true })
        owner = installer
        await manager.loadInstalledExtensions()

        _ = try await pending.store(makeUpdate(version: "2.0"))
        await fulfillment(of: [applied], timeout: 2)

        XCTAssertTrue(injected)
        XCTAssertEqual(manager.context(for: installationID)?.webExtension.version, "3.0")
    }

    private func makeManager(fileManager: FileManager = .default, pixels: WebExtensionPixelFiring = NoOpWebExtensionPixelFiring()) -> WebExtensionManager {
        let permissions = WebExtensionPermissionController(store: permissionStore, installationStore: installationStore, prompter: StartupNoPrompt())
        return WebExtensionManager(configuration: WebExtensionConfigurationProvidingMock(), controllerConfiguration: .nonPersistent(),
                                   windowTabProvider: WebExtensionWindowTabProvidingMock(),
                                   storageProvider: WebExtensionStorageProvider(extensionsDirectory: extensionsDirectory, fileManager: fileManager),
                                   installationStore: installationStore, permissionController: permissions, pixelFiring: pixels)
    }

    @discardableResult
    private func makeInstaller(store: (any ChromeWebStorePendingUpdateStoring)? = nil, isEnabled: @escaping () -> Bool = { true },
                               canApplyWhileInactive: ((String) -> Bool)? = nil,
                               sleep: @escaping (TimeInterval) async throws -> Void = { _ in }) -> ChromeWebStoreUpdateInstaller {
        let owner = ChromeWebStoreUpdateInstaller(manager: manager, pendingUpdates: store ?? pending,
                                                  isEnabled: isEnabled, isCatalogExtension: { _ in true },
                                                  canApplyWhileInactive: canApplyWhileInactive, sleep: sleep)
        installer = owner
        manager.updateInstaller = owner
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
    var onRead: (() -> Void)?
    var onReadAsync: (() async throws -> Void)?
    var onInstallationCopyRemoved: (() -> Void)?
    init(base: ChromeWebStorePendingUpdateStore) { self.base = base }
    func pendingUpdate(for extensionID: String) async -> ChromeWebStoreVerifiedUpdate? { await base.pendingUpdate(for: extensionID) }
    func store(_ update: ChromeWebStoreVerifiedUpdate) async throws -> Bool { try await base.store(update) }
    func allPendingUpdates() async throws -> [ChromeWebStoreVerifiedUpdate] {
        let updates = try await base.allPendingUpdates()
        onRead?()
        try await onReadAsync?()
        return updates
    }
    func copyForInstallation(_ update: ChromeWebStoreVerifiedUpdate) async throws -> ChromeWebStoreVerifiedUpdate? {
        let copy = try await base.copyForInstallation(update)
        try await onCopy?()
        return copy
    }
    func remove(_ update: ChromeWebStoreVerifiedUpdate) async throws { try await base.remove(update); onRemove?(update) }
    func removeInstallationCopy(_ update: ChromeWebStoreVerifiedUpdate) async throws {
        try await base.removeInstallationCopy(update)
        onInstallationCopyRemoved?()
    }
    func cleanupAbandonedInstallationCopies() async throws { try await base.cleanupAbandonedInstallationCopies() }
    func setUpdateStoredHandler(_ handler: (@Sendable (ChromeWebStoreVerifiedUpdate) -> Void)?) async { await base.setUpdateStoredHandler(handler) }
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
