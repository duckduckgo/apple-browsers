//
//  WebExtensionStorageProviding.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import ZIPFoundation

/// Errors that can occur during web extension storage operations.
@available(macOS 15.4, iOS 18.4, *)
public enum WebExtensionStorageError: Error {
    case applicationSupportDirectoryNotFound
    case failedToCreateDirectory(Error)
    case failedToCopyExtension(Error)
    case failedToRemoveExtension(Error)
    case failedToExtractExtension(Error)
}

/// Protocol defining platform-specific storage for web extensions.
/// Each platform (iOS, macOS) provides its own implementation that determines
/// where extensions are stored on disk.
@available(macOS 15.4, iOS 18.4, *)
public protocol WebExtensionStorageProviding: AnyObject {

    /// File manager used for file operations.
    var fileManager: FileManager { get }

    /// Base directory where extensions are stored.
    var extensionsDirectory: URL { get }

    /// Resolves an extension identifier to its storage path if the extension exists.
    /// - Parameter identifier: The extension identifier (e.g., filename for zip files).
    /// - Returns: The full URL where the extension is stored, or nil if not found.
    func resolveInstalledExtension(identifier: String) -> URL?

    /// Copies an extension from a source URL to platform storage.
    /// This only handles file operations - it does not load the extension or persist metadata.
    /// - Parameters:
    ///   - sourceURL: The source URL of the extension (e.g., from document picker).
    ///   - identifier: The unique identifier used to build the destination path.
    /// - Returns: The destination URL where the extension was copied.
    /// - Throws: If the copy operation fails.
    func copyExtension(from sourceURL: URL, identifier: String) throws -> URL

    /// Extracts a zip extension to platform storage.
    /// Unlike `copyExtension`, this extracts the zip contents to the destination folder.
    /// - Parameters:
    ///   - sourceURL: The source URL of the zip file.
    ///   - identifier: The unique identifier used to build the destination path.
    /// - Returns: The destination folder URL where the extension was extracted.
    /// - Throws: If the extraction operation fails.
    func extractExtension(from sourceURL: URL, identifier: String) throws -> URL

    /// Removes an extension from storage.
    /// - Parameter identifier: The extension identifier to remove.
    /// - Throws: If the removal fails.
    func removeExtension(identifier: String) throws

    /// Cleans up orphaned extension folders that are not in the list of known extensions.
    /// This removes any subdirectories in the extensions directory that don't match
    /// the provided identifiers.
    /// - Parameter knownIdentifiers: Set of extension identifiers that should be kept.
    func cleanupOrphanedExtensions(keeping knownIdentifiers: Set<String>)
}

// MARK: - Default Implementations

@available(macOS 15.4, iOS 18.4, *)
public extension WebExtensionStorageProviding {

    func resolveInstalledExtension(identifier: String) -> URL? {
        let folderPath = extensionsDirectory.appendingPathComponent(identifier)
        guard fileManager.fileExists(atPath: folderPath.path) else {
            return nil
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: folderPath,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        // First, look for a zip file
        if let zipFile = contents.first(where: { $0.pathExtension.lowercased() == "zip" }) {
            return zipFile
        }

        // Check if manifest.json exists directly in the folder (flat zip extraction)
        let directManifestPath = folderPath.appendingPathComponent("manifest.json")
        if fileManager.fileExists(atPath: directManifestPath.path) {
            return folderPath
        }

        // Look for a subfolder containing manifest.json
        for item in contents {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                let manifestPath = item.appendingPathComponent("manifest.json")
                if fileManager.fileExists(atPath: manifestPath.path) {
                    return item
                }
            }
        }

        return nil
    }

    func copyExtension(from sourceURL: URL, identifier: String) throws -> URL {
        let identifierFolder = extensionsDirectory.appendingPathComponent(identifier)
        let originalFilename = sourceURL.lastPathComponent
        let destinationURL = identifierFolder.appendingPathComponent(originalFilename)

        do {
            try fileManager.createDirectory(at: identifierFolder,
                                            withIntermediateDirectories: true)
        } catch {
            throw WebExtensionStorageError.failedToCreateDirectory(error)
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw WebExtensionStorageError.failedToCopyExtension(error)
        }

        return destinationURL
    }

    func extractExtension(from sourceURL: URL, identifier: String) throws -> URL {
        let identifierFolder = extensionsDirectory.appendingPathComponent(identifier)

        do {
            try fileManager.createDirectory(at: identifierFolder, withIntermediateDirectories: true)
        } catch {
            throw WebExtensionStorageError.failedToCreateDirectory(error)
        }

        do {
            try fileManager.unzipItem(at: sourceURL, to: identifierFolder)
        } catch {
            throw WebExtensionStorageError.failedToExtractExtension(error)
        }

        return identifierFolder
    }

    func removeExtension(identifier: String) throws {
        let path = extensionsDirectory.appendingPathComponent(identifier)
        guard fileManager.fileExists(atPath: path.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: path)
        } catch {
            throw WebExtensionStorageError.failedToRemoveExtension(error)
        }
    }

    func cleanupOrphanedExtensions(keeping knownIdentifiers: Set<String>) {
        guard fileManager.fileExists(atPath: extensionsDirectory.path) else {
            return
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: extensionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for item in contents {
            let identifier = item.lastPathComponent
            if !knownIdentifiers.contains(identifier) {
                try? fileManager.removeItem(at: item)
            }
        }
    }
}
