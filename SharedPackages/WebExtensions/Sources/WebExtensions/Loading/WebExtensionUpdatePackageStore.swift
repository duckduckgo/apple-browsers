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
        let relativePath = installationID + "/" + InstalledWebExtension.packagesDirectoryName + "/" + identifier.uuidString
        let directory = root.appendingPathComponent(relativePath, isDirectory: true)
        guard (try? directory.deletingLastPathComponent().resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
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
    func cleanup(installationIDs: Set<String>, selectedPackages: [String: UUID]) {
        for installationID in installationIDs where UUID(uuidString: installationID) != nil {
            let directory = root.appendingPathComponent(installationID).appendingPathComponent(InstalledWebExtension.packagesDirectoryName)
            guard (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { continue }
            guard let packages = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
            for package in packages {
                guard let identifier = UUID(uuidString: package.lastPathComponent), identifier != selectedPackages[installationID] else { continue }
                do { try fileManager.removeItem(at: package) } catch {
                    Logger.webExtensions.error("Extension update orphan package cleanup failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
