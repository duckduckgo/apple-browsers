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

import Combine
import Foundation
import Persistence
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
    /// Whether discovery is supported and currently enabled. Manual checks can still join active work or defer for server backoff.
    var canCheckForUpdates: Bool { get }
    func checkForUpdatesNow() async
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
    var canCheckForUpdates: Bool { false }

    func catalogEntry(of identifier: String) -> ExtensionsCatalogSubfeature? {
        nil
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
public protocol ChromeWebStorePresenting {
    func confirmRemoval(name: String, webExtension: WKWebExtension?) async -> Bool
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
    private var updateCoordinator: ChromeWebStoreUpdateCoordinator?
    private let isUpdateDiscoveryEnabled: @MainActor @Sendable () -> Bool
    private var updateDiscoverySubscription: AnyCancellable?
    private var updateDiscoveryRevision: UInt64 = 0
    private var updateVersionOverrides: [String: UpdateVersionOverride] = [:]

    public convenience init(manager: WebExtensionManager, catalog: ChromeWebStoreCatalogProviding,
                            downloader: ChromeWebStoreDownloading = ChromeWebStoreDownloader(), presenter: ChromeWebStorePresenting,
                            supportsUpdateDiscovery: Bool = false,
                            isUpdateDiscoveryEnabled: @escaping @MainActor @Sendable () -> Bool = { true },
                            updateDiscoveryFeatureFlagUpdates: AnyPublisher<Void, Never>? = nil,
                            keyValueStore: (any ThrowingKeyValueStoring)? = nil,
                            pixelFiring: WebExtensionPixelFiring = NoOpWebExtensionPixelFiring()) {
        self.init(manager: manager, catalog: catalog, downloader: downloader, presenter: presenter,
                  verifier: ChromeWebStorePackageVerifier(), supportsUpdateDiscovery: supportsUpdateDiscovery,
                  isUpdateDiscoveryEnabled: isUpdateDiscoveryEnabled, updateDiscoveryFeatureFlagUpdates: updateDiscoveryFeatureFlagUpdates,
                  keyValueStore: keyValueStore, pixelFiring: pixelFiring, updateCheck: { identifier, version in
                      await ChromeWebStoreUpdateChecker().check(extensionID: identifier, installedVersion: version)
                  })
    }

    init(manager: WebExtensionManager, catalog: ChromeWebStoreCatalogProviding,
         downloader: ChromeWebStoreDownloading, presenter: ChromeWebStorePresenting, verifier: ChromeWebStorePackageVerifier,
         supportsUpdateDiscovery: Bool = true,
         isUpdateDiscoveryEnabled: @escaping @MainActor @Sendable () -> Bool = { true },
         updateDiscoveryFeatureFlagUpdates: AnyPublisher<Void, Never>? = nil,
         keyValueStore: (any ThrowingKeyValueStoring)? = nil,
         pixelFiring: WebExtensionPixelFiring = NoOpWebExtensionPixelFiring(),
         now: @escaping @Sendable () -> Date = Date.init,
         updateCheck: ChromeWebStoreUpdateCoordinator.Check? = nil,
         updateCheckInterval: TimeInterval = ChromeWebStoreUpdateCoordinator.defaultCheckInterval,
         updateSchedulerFactory: @escaping ChromeWebStoreUpdateCoordinator.SchedulerFactory = { ChromeWebStorePeriodicScheduler(interval: $0) }) {
        self.manager = manager
        self.catalog = catalog
        self.downloader = downloader
        self.presenter = presenter
        self.verifier = verifier
        self.isUpdateDiscoveryEnabled = isUpdateDiscoveryEnabled
        if supportsUpdateDiscovery, let updateCheck {
            let stateStore = keyValueStore.map { ChromeWebStoreUpdateStateStore(keyValueStore: $0) }
            let initialState = stateStore?.load() ?? .init()
            let coordinator = ChromeWebStoreUpdateCoordinator(interval: updateCheckInterval, schedulerFactory: updateSchedulerFactory,
                                                             initialState: initialState, isEnabled: false, now: now, persistState: { state in
                stateStore?.save(state)
            }, resultHandler: { identifier, outcome in
                guard isUpdateDiscoveryEnabled(), let pixelOutcome = WebExtensionUpdateCheckOutcome(checkOutcome: outcome) else { return }
                let pixelExtension = catalog.catalogEntry(of: identifier).map(WebExtensionPixelExtension.catalog) ?? .other
                pixelFiring.fire(.updateCheck(extension: pixelExtension, outcome: pixelOutcome))
            }, installedIdentifiers: { [weak self] in
                guard let self, self.manager != nil else { return nil }
                guard self.isUpdateDiscoveryEnabled() else { return [] }
                guard let versions = self.eligibleInstalledVersions() else { return nil }
                return Array(versions.keys)
            }, version: { [weak self] identifier in
                guard let self, self.isUpdateDiscoveryEnabled(), let version = self.eligibleInstalledVersions()?[identifier] else { return nil }
                return .init(installedVersion: version, reportedVersion: self.reportedVersion(for: identifier, installedVersion: version))
            }, check: updateCheck)
            updateCoordinator = coordinator
            updateDiscoverySubscription = updateDiscoveryFeatureFlagUpdates?
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in
                    MainActor.assumeIsolated {
                        _ = self?.refreshUpdateDiscovery()
                    }
                }
            refreshUpdateDiscovery()
        }
    }

    deinit {
        if let updateCoordinator {
            Task { await updateCoordinator.stop() }
        }
    }

    /// Checks now, joining an active batch and honoring the server's retry deadline.
    public func checkForUpdatesNow() async {
        guard !Task.isCancelled else { return }
        await refreshUpdateDiscovery()?.value
        guard canCheckForUpdates, !Task.isCancelled else { return }
        await updateCoordinator?.checkForUpdatesNow()
    }

    public var canCheckForUpdates: Bool {
        manager != nil && updateCoordinator != nil && isUpdateDiscoveryEnabled()
    }

    @discardableResult
    private func refreshUpdateDiscovery() -> Task<Void, Never>? {
        guard let updateCoordinator else { return nil }
        updateDiscoveryRevision += 1
        let revision = updateDiscoveryRevision
        let enabled = canCheckForUpdates
        return Task { await updateCoordinator.setEnabled(enabled, revision: revision) }
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
                return false
            }
            try await manager.installExtension(from: file, storeIdentity: .init(store: .chromeWebStore, id: identifier))
            return installedExtension(identifier, manager: manager) != nil
        } catch {
            if !download.isCancelled && !isCancellation(error) {
                await presenter.showError(error)
            }
            return false
        }
    }

    public func remove(identifier: String) async -> Bool {
        guard !isPerformingOperation, let manager,
              let installed = installedExtension(identifier, manager: manager) else { return false }
        isPerformingOperation = true
        defer { isPerformingOperation = false }
        let webExtension = manager.context(for: installed.uniqueIdentifier)?.webExtension
        guard await presenter.confirmRemoval(name: installed.name ?? identifier, webExtension: webExtension) else { return false }
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
