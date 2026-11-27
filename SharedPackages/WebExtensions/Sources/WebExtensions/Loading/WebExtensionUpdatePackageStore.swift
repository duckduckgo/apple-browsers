//
//  WebExtensionUpdatePackageStore.swift
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

/// Prepares unselected packages. The existing installed list is the only commit authority.
@available(macOS 15.4, iOS 18.4, *)
actor WebExtensionUpdatePackageStore {
    enum PackageError: Error { case invalidInstallationIdentifier, invalidPackageLocation, missingPackage }

    struct Prepared: Sendable {
        let identifier: UUID
        let directory: URL
        let bundleURL: URL
        let validationURL: URL
    }

    private let root: URL
    private let fileManager: FileManager

    init(extensionsDirectory: URL, fileManager: FileManager = .default) {
        root = extensionsDirectory
        self.fileManager = fileManager
    }

    func prepare(_ update: ChromeWebStoreVerifiedUpdate, installationID: String) throws -> Prepared {
        guard UUID(uuidString: installationID) != nil else { throw PackageError.invalidInstallationIdentifier }
        try Task.checkCancellation()
        let identifier = UUID()
        let relativePath = InstalledWebExtension.resourceIdentifier(for: installationID, packageIdentifier: identifier)
        let directory = root.appendingPathComponent(relativePath, isDirectory: true)
        let installationDirectory = root.appendingPathComponent(installationID, isDirectory: true)
        guard !isSymbolicLink(root), !isSymbolicLink(installationDirectory), !isSymbolicLink(directory.deletingLastPathComponent()) else {
            throw PackageError.invalidPackageLocation
        }
        do {
            let storage = WebExtensionStorageProvider(extensionsDirectory: root, fileManager: fileManager)
            _ = try storage.extractExtension(from: update.fileURL, identifier: relativePath)
            guard let bundleURL = storage.resolveInstalledExtension(identifier: relativePath) else { throw PackageError.missingPackage }
            try Task.checkCancellation()
            let validationURL = WebExtensionBackgroundPagePatcher(fileManager: fileManager).loadableExtensionURL(for: bundleURL, installFolder: directory)
            return Prepared(identifier: identifier, directory: directory, bundleURL: bundleURL, validationURL: validationURL)
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    func discard(_ prepared: Prepared) {
        do { try fileManager.removeItem(at: prepared.directory) } catch {
            Logger.webExtensions.error("Extension update unselected package cleanup failed: \(error.localizedDescription)")
        }
    }

    /// Run once from the fresh startup inventory, before preparing new packages. Never collect in the publishing session.
    func cleanup(activatedPackages: [String: UUID]) {
        guard isRealDirectory(root) else { return }
        let storage = WebExtensionStorageProvider(extensionsDirectory: root, fileManager: fileManager)
        for (installationID, packageID) in activatedPackages where UUID(uuidString: installationID) != nil {
            let installation = root.appendingPathComponent(installationID, isDirectory: true)
            let packages = installation.appendingPathComponent(InstalledWebExtension.packagesDirectoryName, isDirectory: true)
            let selected = packages.appendingPathComponent(packageID.uuidString, isDirectory: true)
            let resource = InstalledWebExtension.resourceIdentifier(for: installationID, packageIdentifier: packageID)
            guard isRealDirectory(installation), isRealDirectory(packages), isRealDirectory(selected),
                  storage.resolveInstalledExtension(identifier: resource) != nil else { continue }

            removeContents(of: packages, keeping: packageID.uuidString)
            removeContents(of: installation, keeping: InstalledWebExtension.packagesDirectoryName)
        }
    }

    private func removeContents(of directory: URL, keeping name: String) {
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for item in contents where item.lastPathComponent != name {
            do { try fileManager.removeItem(at: item) } catch {
                Logger.webExtensions.error("Extension update unused payload cleanup failed: \(error.localizedDescription)")
            }
        }
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func isRealDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }
}
