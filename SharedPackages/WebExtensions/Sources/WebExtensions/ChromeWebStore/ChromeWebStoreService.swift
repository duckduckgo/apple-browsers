//
//  ChromeWebStoreService.swift
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
import PrivacyConfig
import WebKit

@available(macOS 15.4, iOS 18.4, *)
@MainActor
public protocol ChromeWebStoreManaging: AnyObject {
    /// Identifiers of the extensions the store may offer for install.
    var catalogExtensionIDs: [String] { get }
    func status(for identifier: String) -> ChromeWebStoreStatus
    func install(identifier: String, downloadURL: URL) async -> Bool
    func remove(identifier: String) async -> Bool
    /// The catalog's entry for the extension with the Chrome Web Store `identifier`, such as `.bitwarden`,
    /// or `nil` for an extension the catalog doesn't list.
    func catalogEntry(of identifier: String) -> ExtensionsCatalogSubfeature?
    /// The entry's store listing, or `nil` when its `name` or `cwsUri` is missing.
    func listing(of subfeature: ExtensionsCatalogSubfeature) -> ChromeWebStoreListing?
    /// The help page about adding extensions, or `nil` when the configuration doesn't set one.
    var learnMoreURL: URL? { get }
}

@available(macOS 15.4, iOS 18.4, *)
public extension ChromeWebStoreManaging {
    func catalogEntry(of identifier: String) -> ExtensionsCatalogSubfeature? {
        nil
    }
}

@MainActor
public protocol ChromeWebStorePresenting {
    func showDownloadProgress(cancel: @escaping () -> Void)
    func dismissDownloadProgress()
    func confirmRemoval(name: String) async -> Bool
    func showError(_ error: Error) async
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
public final class ChromeWebStoreService: ChromeWebStoreManaging {
    private struct UpdateVersionOverride {
        let installationIdentifiers: Set<String>
        let installedVersion: String
        let reportedVersion: String
    }

    private weak var manager: WebExtensionManager?
    private let catalog: ChromeWebStoreCatalogProviding
    private let downloader: ChromeWebStoreDownloading
    private let presenter: ChromeWebStorePresenting
    private let verifier: ChromeWebStorePackageVerifier
    // The service is shared by all tabs. Only one install/removal can own the browser's UI at a time.
    private var isPerformingOperation = false
    private var updateCheckTask: Task<Void, Never>?
    private var updateVersionOverrides: [String: UpdateVersionOverride] = [:]

    public convenience init(manager: WebExtensionManager, catalog: ChromeWebStoreCatalogProviding,
                            downloader: ChromeWebStoreDownloading = ChromeWebStoreDownloader(), presenter: ChromeWebStorePresenting) {
        let checker = ChromeWebStoreUpdateChecker()
        self.init(manager: manager, catalog: catalog, downloader: downloader, presenter: presenter,
                  verifier: ChromeWebStorePackageVerifier(), updateCheck: checker.check)
    }

    init(manager: WebExtensionManager, catalog: ChromeWebStoreCatalogProviding,
         downloader: ChromeWebStoreDownloading, presenter: ChromeWebStorePresenting, verifier: ChromeWebStorePackageVerifier,
         updateCheck: ((String, String) async -> ChromeWebStoreUpdateChecker.CheckResult)? = nil,
         updateCheckInterval: TimeInterval = 10) {
        self.manager = manager
        self.catalog = catalog
        self.downloader = downloader
        self.presenter = presenter
        self.verifier = verifier
        if let updateCheck {
            startUpdateChecks(check: updateCheck, interval: updateCheckInterval)
        }
    }

    deinit {
        updateCheckTask?.cancel()
    }

    public func updateCheckVersionOverride(forInstallationIdentifier identifier: String) -> String? {
        guard let installed = manager?.installationStore.installedExtension(withUniqueIdentifier: identifier),
              let identity = installed.storeIdentity, identity.store == .chromeWebStore,
              let version = eligibleInstalledVersions()?[identity.id] else { return nil }
        return versionOverride(for: identity.id, installedVersion: version)
    }

    /// Sets an in-memory override for this installation's store identity. Pass nil to clear it.
    /// Replacing this extension also clears its override without affecting other extensions.
    public func setUpdateCheckVersionOverride(_ version: String?, forInstallationIdentifier identifier: String) {
        guard let installed = manager?.installationStore.installedExtension(withUniqueIdentifier: identifier),
              let identity = installed.storeIdentity, identity.store == .chromeWebStore else { return }
        guard let version else {
            updateVersionOverrides.removeValue(forKey: identity.id)
            return
        }
        guard let installedVersion = eligibleInstalledVersions()?[identity.id] else { return }
        updateVersionOverrides[identity.id] = UpdateVersionOverride(installationIdentifiers: installationIdentifiers(for: identity.id),
                                                                  installedVersion: installedVersion, reportedVersion: version)
    }

    private func startUpdateChecks(check: @escaping (String, String) async -> ChromeWebStoreUpdateChecker.CheckResult,
                                   interval: TimeInterval) {
        // Temporary ten-second interval for testing discovery against installed extensions.
        Logger.webExtensions.info("Extension update discovery: started (interval \(interval, privacy: .public)s)")
        updateCheckTask = Task { [weak self] in
            var retryNotBefore: Date?
            var lastCheckedIdentifier: String?
            while !Task.isCancelled {
                if retryNotBefore.map({ $0 > Date() }) != true {
                    guard let candidates = self?.updateCandidates(after: lastCheckedIdentifier) else { return }
                    Logger.webExtensions.info("Extension update discovery: checking \(candidates.count) installed extensions")
                    for (identifier, _) in candidates {
                        guard !Task.isCancelled, self != nil else { return }
                        // Installs and removals can happen while an earlier request is suspended.
                        guard let version = self?.eligibleInstalledVersions()?[identifier] else { continue }
                        guard let reportedVersion = self?.reportedVersion(for: identifier, installedVersion: version) else { return }
                        let result = await check(identifier, reportedVersion)
                        guard !Task.isCancelled else { return }
                        lastCheckedIdentifier = identifier
                        self?.logUpdateCheck(result, identifier: identifier, installedVersion: version, reportedVersion: reportedVersion)
                        if let deadline = result.retryNotBefore, deadline > Date() {
                            retryNotBefore = deadline
                            break
                        }
                    }
                }
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
            }
        }
    }

    private func updateCandidates(after identifier: String?) -> [(String, String)]? {
        guard let versions = eligibleInstalledVersions() else { return nil }
        let candidates = versions.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        guard let identifier, let next = candidates.firstIndex(where: { $0.0 > identifier }) else { return candidates }
        return Array(candidates[next...]) + Array(candidates[..<next])
    }

    private func eligibleInstalledVersions() -> [String: String]? {
        guard let manager else { return nil }
        var versions: [String: String] = [:]
        for installed in manager.installationStore.installedExtensions {
            guard let identity = installed.storeIdentity, identity.store == .chromeWebStore,
                  catalog.contains(identity.id), let version = installed.version else { continue }
            if let previous = versions[identity.id], !SemanticVersionComparator().isVersion(version, newerThan: previous) { continue }
            versions[identity.id] = version
        }
        return versions
    }

    private func installationIdentifiers(for identifier: String) -> Set<String> {
        let identity = WebExtensionStoreIdentity(store: .chromeWebStore, id: identifier)
        return Set(manager?.installationStore.installedExtensions(withStoreIdentity: identity).map(\.uniqueIdentifier) ?? [])
    }

    private func reportedVersion(for identifier: String, installedVersion: String) -> String {
        versionOverride(for: identifier, installedVersion: installedVersion) ?? installedVersion
    }

    private func versionOverride(for identifier: String, installedVersion: String) -> String? {
        guard let override = updateVersionOverrides[identifier] else { return nil }
        guard override.installedVersion == installedVersion,
              override.installationIdentifiers == installationIdentifiers(for: identifier) else {
            updateVersionOverrides.removeValue(forKey: identifier)
            return nil
        }
        return override.reportedVersion
    }

    private func logUpdateCheck(_ result: ChromeWebStoreUpdateChecker.CheckResult, identifier: String,
                                installedVersion: String, reportedVersion: String) {
        switch result.outcome {
        case .update(let update):
            Logger.webExtensions.info("Extension update discovery: \(identifier, privacy: .public) installed=\(installedVersion, privacy: .public) reported=\(reportedVersion, privacy: .public) available=\(update.version, privacy: .public)")
        case .noUpdate:
            Logger.webExtensions.info("Extension update discovery: \(identifier, privacy: .public) installed=\(installedVersion, privacy: .public) reported=\(reportedVersion, privacy: .public) noUpdate")
        case .failure(let failure):
            Logger.webExtensions.error("Extension update discovery: \(identifier, privacy: .public) installed=\(installedVersion, privacy: .public) reported=\(reportedVersion, privacy: .public) failed=\(String(describing: failure), privacy: .public)")
        }
        if let deadline = result.retryNotBefore {
            Logger.webExtensions.info("Extension update discovery: server retry deadline=\(deadline, privacy: .public)")
        }
    }

    public var catalogExtensionIDs: [String] {
        catalog.extensionIDs
    }

    public func catalogEntry(of identifier: String) -> ExtensionsCatalogSubfeature? {
        catalog.catalogEntry(of: identifier)
    }

    public func listing(of subfeature: ExtensionsCatalogSubfeature) -> ChromeWebStoreListing? {
        catalog.listing(of: subfeature)
    }

    public var learnMoreURL: URL? {
        catalog.learnMoreURL
    }

    public func status(for identifier: String) -> ChromeWebStoreStatus {
        guard let manager else { return .unknown }
        guard catalog.contains(identifier) else { return .unsupported }
        return installedExtension(identifier, manager: manager) == nil ? .installable : .installed
    }

    public func install(identifier: String, downloadURL: URL) async -> Bool {
        guard !isPerformingOperation, let manager, manager.permissionController != nil,
              catalog.contains(identifier), ChromeWebStoreURL.isValidDownloadURL(downloadURL, for: identifier) else { return false }
        if installedExtension(identifier, manager: manager) != nil { return true }
        isPerformingOperation = true
        defer { isPerformingOperation = false }

        let download = Task { try await downloader.download(extensionID: identifier) }
        presenter.showDownloadProgress(cancel: { download.cancel() })
        do {
            let package = try await withTaskCancellationHandler {
                try await download.value
            } onCancel: {
                download.cancel()
            }
            try Task.checkCancellation()
            let archive = try await Task.detached { [verifier] in
                try verifier.verifiedArchive(in: package, extensionID: identifier)
            }.value
            try Task.checkCancellation()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let filename = archive.version.map { "\(identifier)-\($0).zip" } ?? "\(identifier).zip"
            let file = directory.appendingPathComponent(filename)
            try archive.data.write(to: file, options: .atomic)
            let webExtension = try await WKWebExtension.makeCopyingErrors(at: file)

            guard webExtension.errors.isEmpty else {
                throw ChromeWebStoreError.unsupportedManifest
            }

            // The configuration can change while the network request is in flight.
            guard !download.isCancelled, catalog.contains(identifier) else {
                presenter.dismissDownloadProgress()
                return false
            }
            presenter.dismissDownloadProgress()
            try await manager.installExtension(from: file, storeIdentity: .init(store: .chromeWebStore, id: identifier))
            return installedExtension(identifier, manager: manager) != nil
        } catch {
            presenter.dismissDownloadProgress()
            if !download.isCancelled && !isCancellation(error) {
                await presenter.showError(error)
            }
            return false
        }
    }

    public func remove(identifier: String) async -> Bool {
        guard !isPerformingOperation, let manager, catalog.contains(identifier),
              let installed = installedExtension(identifier, manager: manager) else { return false }
        isPerformingOperation = true
        defer { isPerformingOperation = false }
        guard await presenter.confirmRemoval(name: installed.name ?? identifier),
              catalog.contains(identifier) else { return false }
        // Another browser entry point (e.g. Debug) may have removed it while the sheet was open.
        guard installedExtension(identifier, manager: manager) != nil else { return true }
        do {
            try manager.uninstallExtension(identifier: installed.uniqueIdentifier)
            return installedExtension(identifier, manager: manager) == nil
        } catch {
            await presenter.showError(error)
            return false
        }
    }

    private func installedExtension(_ identifier: String, manager: WebExtensionManager) -> InstalledWebExtension? {
        manager.installationStore.installedExtensions(withStoreIdentity: .init(store: .chromeWebStore, id: identifier)).first
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return true }
        if case WebExtensionError.installationCancelled = error { return true }
        if case WebExtensionPermissionController.PermissionError.installationDenied = error { return true }
        if case WebExtensionError.failedToLoadWebExtension(let underlying) = error { return isCancellation(underlying) }
        if let error = error as? WebExtensionLoader.PermissionPreparationError {
            return isCancellation(error.underlyingError)
        }
        return false
    }
}
