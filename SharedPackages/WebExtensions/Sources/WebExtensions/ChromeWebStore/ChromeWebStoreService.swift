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
import WebKit

@available(macOS 15.4, iOS 18.4, *)
@MainActor
public protocol ChromeWebStoreManaging: AnyObject {
    func status(for identifier: String) -> ChromeWebStoreStatus
    func install(identifier: String, downloadURL: URL) async -> Bool
    func remove(identifier: String) async -> Bool
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
    private weak var manager: WebExtensionManager?
    private let catalog: ChromeWebStoreCatalogProviding
    private let downloader: ChromeWebStoreDownloading
    private let presenter: ChromeWebStorePresenting
    // The service is shared by all tabs. Only one install/removal can own the browser's UI at a time.
    private var isPerformingOperation = false

    public init(manager: WebExtensionManager, catalog: ChromeWebStoreCatalogProviding,
                downloader: ChromeWebStoreDownloading = ChromeWebStoreDownloader(), presenter: ChromeWebStorePresenting) {
        self.manager = manager
        self.catalog = catalog
        self.downloader = downloader
        self.presenter = presenter
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
            let archive = try await Task.detached {
                try ChromeWebStorePackageVerifier().verifiedArchive(in: package, extensionID: identifier)
            }.value
            try Task.checkCancellation()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent("extension.zip")
            try archive.write(to: file, options: .atomic)
            let webExtension = try await WKWebExtension(resourceBaseURL: file)

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
        if case WebExtensionPermissionController.PermissionError.installationDenied = error { return true }
        if case WebExtensionError.failedToLoadWebExtension(let underlying) = error { return isCancellation(underlying) }
        return false
    }
}
