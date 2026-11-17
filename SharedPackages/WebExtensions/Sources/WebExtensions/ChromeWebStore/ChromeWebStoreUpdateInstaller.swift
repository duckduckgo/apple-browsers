//
//  ChromeWebStoreUpdateInstaller.swift
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

import Foundation
import os.log

/// Bounded local installation failures; no package contents, identities or system error text enter pixels.
public enum WebExtensionUpdateInstallFailure: String, CaseIterable, Sendable {
    case invalidPackage = "invalid_package"
    case storageFailure = "storage_failure"
    case loadFailure = "load_failure"
}

/// Applies startup packages and serializes pending updates during explicitly allowed inactive periods.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class ChromeWebStoreUpdateInstaller {
    nonisolated static let idleDelay: TimeInterval = 5

    private weak var manager: WebExtensionManager?
    private let pendingUpdates: any ChromeWebStorePendingUpdateStoring
    private let isEnabled: () -> Bool
    private let isCatalogExtension: (String) -> Bool
    private var initialization: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var startupSnapshot: [ChromeWebStoreVerifiedUpdate] = []
    private var didRunStartup = false
    private let canApplyWhileInactive: (@MainActor (String) -> Bool)?
    private let sleep: (TimeInterval) async throws -> Void
    private let idleDelay: TimeInterval
    private var runtimeTask: Task<Void, Never>?
    private var hasPendingWork = false
    private var isApplyingRuntimeUpdate = false
    private var shouldReconsiderRuntime = false
    private var isCancelling = false
    private var activityRevision: UInt64 = 0
    private var eligibleRuntimeIdentifiers: Set<String>?

    private(set) var isSnapshotReady = false
    var onSnapshotReady: (() -> Void)?
    var versionOverride: (InstalledWebExtension) -> (reportedVersion: String, identifier: UUID)? = { _ in nil }

    init(manager: WebExtensionManager, pendingUpdates: any ChromeWebStorePendingUpdateStoring,
         isEnabled: @escaping () -> Bool, isCatalogExtension: @escaping (String) -> Bool,
         canApplyWhileInactive: (@MainActor (String) -> Bool)? = nil,
         idleDelay: TimeInterval = ChromeWebStoreUpdateInstaller.idleDelay,
         sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.manager = manager
        self.pendingUpdates = pendingUpdates
        self.isEnabled = isEnabled
        self.isCatalogExtension = isCatalogExtension
        self.canApplyWhileInactive = canApplyWhileInactive
        self.idleDelay = idleDelay
        self.sleep = sleep
        initialization = Task { [weak self] in
            guard let self else { return }
            await self.captureStartupSnapshot()
        }
    }

    deinit {
        initialization?.cancel()
        startupTask?.cancel()
        runtimeTask?.cancel()
    }

    /// Discovery waits for this snapshot, not for network or installation work.
    private func captureStartupSnapshot() async {
        await pendingUpdates.setUpdateStoredHandler { [weak self] update in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.prune(update)
                self.hasPendingWork = true
                self.activityDidChange(force: true)
            }
        }
        do {
            try await pendingUpdates.cleanupAbandonedInstallationCopies()
            startupSnapshot = try await pendingUpdates.allPendingUpdates()
            for update in startupSnapshot { await prune(update) }
        } catch {
            if !Task.isCancelled, !WebExtensionManager.isUpdateInstallationDeferral(error) {
                manager?.reportUpdateInstallationFailure(.storageFailure, storeIdentity: nil)
            }
            Logger.webExtensions.error("Extension update installation: startup snapshot failed=\(error.localizedDescription)")
        }
        isSnapshotReady = true
        onSnapshotReady?()
    }

    func runOnce() async {
        if didRunStartup { await startupTask?.value; return }
        didRunStartup = true
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performStartup()
        }
        startupTask = task
        await task.value
        startupTask = nil
        hasPendingWork = true
        activityDidChange(force: true)
    }

    /// Activity cancels only the waiting phase. A committed update must finish activation.
    func activityDidChange(force: Bool = false) {
        guard let canApplyWhileInactive, !isCancelling, hasPendingWork else { return }
        let eligible = Set(manager?.installationStore.installedExtensions.compactMap { installed -> String? in
            guard installed.storeIdentity?.store == .chromeWebStore, canApplyWhileInactive(installed.uniqueIdentifier) else { return nil }
            return installed.uniqueIdentifier
        } ?? [])
        guard force || eligible != eligibleRuntimeIdentifiers else { return }
        eligibleRuntimeIdentifiers = eligible
        activityRevision &+= 1
        if runtimeTask != nil {
            shouldReconsiderRuntime = true
            if !isApplyingRuntimeUpdate { runtimeTask?.cancel() }
            return
        }
        guard didRunStartup, startupTask == nil, hasPendingWork, isEnabled(),
              manager?.isLoadingInstalledExtensions == false else { return }
        shouldReconsiderRuntime = false
        runtimeTask = Task { [weak self] in
            guard let self else { return }
            await self.performRuntimeApplications()
            self.runtimeTask = nil
            self.isApplyingRuntimeUpdate = false
            if self.shouldReconsiderRuntime, !self.isCancelling { self.activityDidChange(force: true) }
        }
    }

    private func performRuntimeApplications() async {
        do {
            let pending = try await pendingUpdates.allPendingUpdates()
            try Task.checkCancellation()
            hasPendingWork = !pending.isEmpty
            guard pending.contains(where: canApplyAtRuntime) else { return }
            let graceRevision = activityRevision
            try await sleep(idleDelay)
            try Task.checkCancellation()
            isApplyingRuntimeUpdate = true
            for update in try await pendingUpdates.allPendingUpdates() {
                guard !Task.isCancelled, isEnabled() else { break }
                guard activityRevision == graceRevision else {
                    shouldReconsiderRuntime = true
                    break
                }
                await prune(update)
                guard canApplyAtRuntime(update), let installed = matchingInstallation(update) else { continue }
                await apply(update, installed: installed, application: .whileInactive)
            }
            let revision = activityRevision
            let remaining = try await pendingUpdates.allPendingUpdates()
            // A newly accepted package can notify us before this older actor snapshot returns.
            hasPendingWork = revision != activityRevision || !remaining.isEmpty
        } catch {
            if !Task.isCancelled {
                Logger.webExtensions.error("Extension update installation: inactive application failed=\(error.localizedDescription)")
            }
        }
    }

    private func canApplyAtRuntime(_ update: ChromeWebStoreVerifiedUpdate) -> Bool {
        guard manager?.isLoadingInstalledExtensions == false, canApply(update),
              let identifier = update.installationIdentifier else { return false }
        return canApplyWhileInactive?(identifier) == true
    }

    private func performStartup() async {
        await initialization?.value
        guard let manager else { return }
        await manager.cleanupUnselectedUpdatePackages()
        for update in startupSnapshot {
            guard !Task.isCancelled, isEnabled() else { break }
            guard let installed = matchingInstallation(update), manager.context(for: installed.uniqueIdentifier) == nil else { continue }
            await apply(update, installed: installed)
        }
    }

    private func apply(_ source: ChromeWebStoreVerifiedUpdate, installed: InstalledWebExtension,
                       application: WebExtensionManager.UpdateApplication = .startup) async {
        guard isVersionEligible(source.version, installed: installed) else {
            try? await pendingUpdates.remove(source)
            return
        }
        let revision = activityRevision
        do {
            guard let copy = try await pendingUpdates.copyForInstallation(source) else { return }
            await installCopy(copy, source: source, installed: installed, application: application, activityRevision: revision)
            try? await pendingUpdates.removeInstallationCopy(copy)
        } catch {
            if !Task.isCancelled, !WebExtensionManager.isUpdateInstallationDeferral(error) {
                manager?.reportUpdateInstallationFailure(.storageFailure, storeIdentity: .init(store: .chromeWebStore, id: source.extensionID))
            }
            Logger.webExtensions.error("Extension update installation: \(source.extensionID, privacy: .public) package copy failed=\(error.localizedDescription)")
        }
    }

    private func installCopy(_ copy: ChromeWebStoreVerifiedUpdate, source: ChromeWebStoreVerifiedUpdate, installed: InstalledWebExtension,
                             application: WebExtensionManager.UpdateApplication, activityRevision: UInt64) async {
        guard let manager else { return }
        do {
            try Task.checkCancellation()
            guard canApply(source), matchingInstallation(source) == installed,
                  application == .whileInactive || manager.context(for: installed.uniqueIdentifier) == nil else { return }
            guard isVersionEligible(copy.version, installed: installed) else { return }
            let override = versionOverride(installed)
            try Task.checkCancellation()
            guard canApply(source) else { return }
            let outcome = try await manager.applyVerifiedUpdate(copy, replacing: installed, reportedInstalledVersion: override?.reportedVersion,
                                                                versionOverrideIdentifier: override?.identifier,
                                                                application: application,
                                                                isEligible: { [weak self] in
                                                                    guard let self else { return false }
                                                                    return application == .whileInactive
                                                                        ? self.activityRevision == activityRevision && self.canApplyAtRuntime(source)
                                                                        : self.canApply(source)
                                                                })
            try? await pendingUpdates.remove(source)
            switch outcome {
            case .applied:
                Logger.webExtensions.info("Extension update installation: \(source.extensionID, privacy: .public) applied version=\(source.version, privacy: .public)")
            case .installedDisabled:
                Logger.webExtensions.info("Extension update installation: \(source.extensionID, privacy: .public) installed disabled version=\(source.version, privacy: .public)")
            }
        } catch {
            if !Task.isCancelled, !WebExtensionManager.isUpdateInstallationDeferral(error) {
                try? await pendingUpdates.remove(source)
                Logger.webExtensions.error("Extension update installation: \(source.extensionID, privacy: .public) failed=\(error.localizedDescription)")
            }
            await prune(source)
        }
    }

    private func canApply(_ update: ChromeWebStoreVerifiedUpdate) -> Bool {
        guard !Task.isCancelled, isEnabled(), let installed = matchingInstallation(update) else { return false }
        return isVersionEligible(update.version, installed: installed)
    }

    private func isVersionEligible(_ offeredVersion: String, installed: InstalledWebExtension) -> Bool {
        WebExtensionManager.isVersionEligibleForUpdate(offeredVersion, installedVersion: installed.version,
                                                       reportedInstalledVersion: versionOverride(installed)?.reportedVersion)
    }

    private func matchingInstallation(_ update: ChromeWebStoreVerifiedUpdate) -> InstalledWebExtension? {
        guard let manager, let identifier = update.installationIdentifier,
              let installed = manager.installationStore.installedExtension(withUniqueIdentifier: identifier),
              installed.storeIdentity == .init(store: .chromeWebStore, id: update.extensionID),
              isCatalogExtension(update.extensionID), !manager.isRemotelyDisabled(identifier: identifier) else { return nil }
        return installed
    }

    private func prune(_ update: ChromeWebStoreVerifiedUpdate) async {
        guard manager != nil else { return }
        guard matchingInstallation(update) == nil else { return }
        try? await pendingUpdates.remove(update)
    }

    func configurationDidChange() {
        Task { [weak self] in
            guard let self else { return }
            for update in (try? await pendingUpdates.allPendingUpdates()) ?? [] { await prune(update) }
            self.hasPendingWork = true
            self.activityDidChange(force: true)
        }
    }

    func cancelAndWait() async {
        isCancelling = true
        defer { isCancelling = false }
        shouldReconsiderRuntime = false
        activityRevision &+= 1
        // Stop uncommitted work through revision checks; let committed activation finish.
        if !isApplyingRuntimeUpdate { runtimeTask?.cancel() }
        startupTask?.cancel()
        _ = await startupTask?.value
        _ = await runtimeTask?.value
    }

    func cancelStartup() {
        shouldReconsiderRuntime = false
        runtimeTask?.cancel()
        startupTask?.cancel()
    }

    func uninstalling(_ identifier: String) {
        shouldReconsiderRuntime = false
        activityRevision &+= 1
        if !isApplyingRuntimeUpdate { runtimeTask?.cancel() }
        startupTask?.cancel()
        Task { [pendingUpdates] in
            for update in (try? await pendingUpdates.allPendingUpdates()) ?? [] where update.installationIdentifier == identifier {
                try? await pendingUpdates.remove(update)
            }
        }
    }
}
