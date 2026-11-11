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

/// Applies only the packages already pending at startup. Downloads accepted later wait for the next launch.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class ChromeWebStoreUpdateInstaller {
    private weak var manager: WebExtensionManager?
    private let pendingUpdates: any ChromeWebStorePendingUpdateStoring
    private let isEnabled: () -> Bool
    private let isCatalogExtension: (String) -> Bool
    private var initialization: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var startupSnapshot: [ChromeWebStoreVerifiedUpdate] = []
    private var didRunStartup = false

    private(set) var isSnapshotReady = false
    var onSnapshotReady: (() -> Void)?
    var versionOverride: (InstalledWebExtension) -> (reportedVersion: String, identifier: UUID)? = { _ in nil }

    init(manager: WebExtensionManager, pendingUpdates: any ChromeWebStorePendingUpdateStoring,
         isEnabled: @escaping () -> Bool, isCatalogExtension: @escaping (String) -> Bool) {
        self.manager = manager
        self.pendingUpdates = pendingUpdates
        self.isEnabled = isEnabled
        self.isCatalogExtension = isCatalogExtension
        initialization = Task { [weak self] in
            guard let self else { return }
            await self.captureStartupSnapshot()
        }
    }

    deinit {
        initialization?.cancel()
        startupTask?.cancel()
    }

    /// Discovery waits for this snapshot, not for network or installation work.
    private func captureStartupSnapshot() async {
        await pendingUpdates.setUpdateStoredHandler { [weak self] update in
            Task { @MainActor [weak self] in await self?.prune(update) }
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
    }

    private func performStartup() async {
        await initialization?.value
        guard let manager else { return }
        await manager.cleanupUnselectedUpdatePackages()
        for update in startupSnapshot {
            guard !Task.isCancelled, isEnabled() else { break }
            guard let installed = matchingInstallation(update), manager.context(for: installed.uniqueIdentifier) == nil else { continue }
            await applyAtStartup(update, installed: installed)
        }
    }

    private func applyAtStartup(_ source: ChromeWebStoreVerifiedUpdate, installed: InstalledWebExtension) async {
        guard isVersionEligible(source.version, installed: installed) else {
            try? await pendingUpdates.remove(source)
            return
        }
        do {
            guard let copy = try await pendingUpdates.copyForInstallation(source) else { return }
            await installCopy(copy, source: source, installed: installed)
            try? await pendingUpdates.removeInstallationCopy(copy)
        } catch {
            if !Task.isCancelled, !WebExtensionManager.isUpdateInstallationDeferral(error) {
                manager?.reportUpdateInstallationFailure(.storageFailure, storeIdentity: .init(store: .chromeWebStore, id: source.extensionID))
            }
            Logger.webExtensions.error("Extension update installation: \(source.extensionID, privacy: .public) startup copy failed=\(error.localizedDescription)")
        }
    }

    private func installCopy(_ copy: ChromeWebStoreVerifiedUpdate, source: ChromeWebStoreVerifiedUpdate, installed: InstalledWebExtension) async {
        guard let manager else { return }
        do {
            try Task.checkCancellation()
            guard canApply(source), matchingInstallation(source) == installed,
                  manager.context(for: installed.uniqueIdentifier) == nil else { return }
            guard isVersionEligible(copy.version, installed: installed) else { return }
            let override = versionOverride(installed)
            try Task.checkCancellation()
            guard canApply(source) else { return }
            let outcome = try await manager.applyVerifiedUpdate(copy, replacing: installed, reportedInstalledVersion: override?.reportedVersion,
                                                                versionOverrideIdentifier: override?.identifier,
                                                                isEligible: { [weak self] in self?.canApply(source) == true })
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
        }
    }

    func cancelAndWait() async {
        startupTask?.cancel()
        _ = await startupTask?.value
    }

    func cancelStartup() {
        startupTask?.cancel()
    }

    func uninstalling(_ identifier: String) {
        startupTask?.cancel()
        Task { [pendingUpdates] in
            for update in (try? await pendingUpdates.allPendingUpdates()) ?? [] where update.installationIdentifier == identifier {
                try? await pendingUpdates.remove(update)
            }
        }
    }
}
