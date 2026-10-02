//
//  AIChatIndexedDBBlobCleaner.swift
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
import WebKit

/// Removes the IndexedDB blob files that WebKit leaves on disk after Duck.ai chat data is cleared.
///
/// The `duck-ai-data-clearing` content script clears the `chat-images` object store with
/// `IDBObjectStore.clear()`. WebKit's `SQLiteIDBBackingStore::clearObjectStore` only deletes the
/// `Records` and `IndexRecords` rows: it never removes the `N.blob` files (nor their `BlobFiles` /
/// `BlobRecords` rows), so every image ever attached to a chat stays readable on disk.
///
/// This cleaner must only run after a *full* clear. After a single-chat delete, the remaining chats'
/// images are still live and their blob files must stay.
public protocol AIChatIndexedDBBlobCleaning {
    /// Lists the IndexedDB blob files currently stored for the Duck.ai origins.
    func blobFiles() async -> [URL]

    /// Deletes `files`. Pass a list taken before the JS clear, so images added while it ran are kept.
    func removeBlobFiles(_ files: [URL]) async -> AIChatBlobCleanupResult
}

/// What one cleanup removed, so the app can report whether the cleanup is still needed.
public struct AIChatBlobCleanupResult {
    public let filesFound: Int
    public let filesRemoved: Int
    /// The first removal error; files that could not be removed are left for the next cleanup.
    public let error: Error?
}

public final class AIChatIndexedDBBlobCleaner: AIChatIndexedDBBlobCleaning, @unchecked Sendable {

    enum Constants {
        static let webKitDirectory = "WebKit"
        static let websiteDataDirectory = "WebsiteData"
        /// Origin storage directory of the default data store (`WebsiteDataStore::defaultGeneralStorageDirectory`).
        static let defaultOriginStorageDirectory = "Default"
        /// Origin storage directory of a data store created with `WKWebsiteDataStore(forIdentifier:)`.
        static let identifiedOriginStorageDirectory = "Origins"
        static let originFile = "origin"
        static let indexedDBDirectory = "IndexedDB"
        static let blobExtension = "blob"
        static let scheme = "https"
    }

    /// The hosts the `duck-ai-data-clearing` script runs against; only their storage is touched.
    static let duckAiHosts: Set<String> = Set(URL.aiChatDomains.compactMap(\.host))

    private let originStorageDirectories: [URL]
    private let hosts: Set<String>
    private let fileManager: FileManager

    /// Creates a cleaner for the on-disk storage of `websiteDataStore`. Non-persistent stores have no storage and yield a no-op cleaner.
    public convenience init(websiteDataStore: WKWebsiteDataStore, fileManager: FileManager = .default) {
        self.init(originStorageDirectories: Self.originStorageDirectories(for: websiteDataStore, fileManager: fileManager),
                  fileManager: fileManager)
    }

    init(originStorageDirectories: [URL],
         hosts: Set<String> = AIChatIndexedDBBlobCleaner.duckAiHosts,
         fileManager: FileManager = .default) {
        self.originStorageDirectories = originStorageDirectories
        self.hosts = hosts
        self.fileManager = fileManager
    }

    public func blobFiles() async -> [URL] {
        await Task.detached(priority: .utility) { [self] in
            blobFilesForMatchingOrigins()
        }.value
    }

    public func removeBlobFiles(_ files: [URL]) async -> AIChatBlobCleanupResult {
        await Task.detached(priority: .utility) { [self] in
            removeBlobFilesSync(files)
        }.value
    }

    // MARK: - Directory resolution

    /// Resolves the origin storage directories that may back `dataStore`.
    ///
    /// WebKit roots website data at `Library/WebKit/WebsiteData` when the process has a container (iOS device)
    /// and at `Library/WebKit/<bundle id>/WebsiteData` otherwise (macOS, iOS simulator); both are returned and
    /// missing ones are skipped when cleaning.
    static func originStorageDirectories(for dataStore: WKWebsiteDataStore, fileManager: FileManager) -> [URL] {
        guard dataStore.isPersistent,
              let libraryDirectory = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return []
        }
        var identifier: UUID?
        if #available(iOS 17.0, macOS 14.0, *) {
            identifier = dataStore.identifier
        }
        return originStorageDirectories(libraryDirectory: libraryDirectory,
                                        bundleIdentifier: Bundle.main.bundleIdentifier,
                                        dataStoreIdentifier: identifier)
    }

    static func originStorageDirectories(libraryDirectory: URL, bundleIdentifier: String?, dataStoreIdentifier: UUID?) -> [URL] {
        let webKitDirectory = libraryDirectory.appendingPathComponent(Constants.webKitDirectory)
        var roots = [webKitDirectory.appendingPathComponent(Constants.websiteDataDirectory)]
        if let bundleIdentifier {
            roots.append(webKitDirectory.appendingPathComponent(bundleIdentifier).appendingPathComponent(Constants.websiteDataDirectory))
        }

        guard let dataStoreIdentifier else {
            return roots.map { $0.appendingPathComponent(Constants.defaultOriginStorageDirectory) }
        }
        // WebKit writes the identifier with `UUID::toString()`; cover both casings rather than depend on it.
        let identifierNames = Set([dataStoreIdentifier.uuidString, dataStoreIdentifier.uuidString.lowercased()])
        return roots.flatMap { root in
            identifierNames.sorted().map {
                root.appendingPathComponent($0).appendingPathComponent(Constants.identifiedOriginStorageDirectory)
            }
        }
    }

    // MARK: - Removal

    private func removeBlobFilesSync(_ blobFiles: [URL]) -> AIChatBlobCleanupResult {
        var firstError: Error?
        var removedCount = 0

        for blobFile in blobFiles {
            do {
                try fileManager.removeItem(at: blobFile)
                removedCount += 1
            } catch {
                Logger.aiChat.error("AIChatIndexedDBBlobCleaner: failed to remove \(blobFile.lastPathComponent): \(error.localizedDescription)")
                firstError = firstError ?? error
            }
        }

        Logger.aiChat.debug("AIChatIndexedDBBlobCleaner: removed \(removedCount) of \(blobFiles.count) IndexedDB blob files")
        return AIChatBlobCleanupResult(filesFound: blobFiles.count, filesRemoved: removedCount, error: firstError)
    }

    /// Origin storage is laid out as `<storage>/<top origin hash>/<opening origin hash>/{origin, IndexedDB/<database hash>/*.blob}`.
    private func blobFilesForMatchingOrigins() -> [URL] {
        originStorageDirectories
            .flatMap(subdirectories)
            .flatMap(subdirectories)
            .filter { isMatchingOrigin($0.appendingPathComponent(Constants.originFile)) }
            .flatMap { subdirectories(of: $0.appendingPathComponent(Constants.indexedDBDirectory)) }
            .flatMap(files)
            .filter { $0.pathExtension == Constants.blobExtension }
    }

    private func subdirectories(of directory: URL) -> [URL] {
        contents(of: directory).filter { $0.hasDirectoryPath }
    }

    private func files(in directory: URL) -> [URL] {
        contents(of: directory).filter { !$0.hasDirectoryPath }
    }

    private func contents(of directory: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(at: directory,
                                              includingPropertiesForKeys: [.isDirectoryKey],
                                              options: [.skipsHiddenFiles])) ?? []
    }

    // MARK: - Origin matching

    private func isMatchingOrigin(_ originFile: URL) -> Bool {
        guard let data = try? Data(contentsOf: originFile) else { return false }
        return Self.isMatchingOrigin(data, hosts: hosts)
    }

    /// Checks that the *frame* origin in the serialized `origin` file is `https` on one of `hosts`.
    ///
    /// The file holds the top origin, then the frame origin, each as scheme, host and port. Only the frame origin
    /// owns the storage, so a third-party iframe inside duck.ai does not match. A file that can't be read
    /// as expected never matches.
    static func isMatchingOrigin(_ data: Data, hosts: Set<String>) -> Bool {
        var reader = OriginFileReader(data: data)
        guard reader.skipOrigin(),
              reader.readString() == Constants.scheme,
              let host = reader.readString() else {
            return false
        }
        return hosts.contains(host)
    }
}

/// Reads WebKit's `origin` file: each string is a little-endian `UInt32` length, a `0x01` "8-bit" marker and
/// Latin-1 bytes; each origin ends with its port, a single `0x00` when absent.
private struct OriginFileReader {

    private let bytes: [UInt8]
    private var offset = 0

    init(data: Data) {
        bytes = [UInt8](data)
    }

    /// Skips the top origin. Returns `false` for a port it can't size, so the file is treated as unreadable.
    mutating func skipOrigin() -> Bool {
        guard readString() != nil, readString() != nil, offset < bytes.count, bytes[offset] == 0x00 else {
            return false
        }
        offset += 1
        return true
    }

    mutating func readString() -> String? {
        let headerLength = MemoryLayout<UInt32>.size + 1
        guard offset + headerLength <= bytes.count, bytes[offset + 4] == 0x01 else { return nil }
        let length = (0..<4).reduce(0) { $0 | Int(bytes[offset + $1]) << (8 * $1) }
        let start = offset + headerLength
        guard start + length <= bytes.count else { return nil }
        offset = start + length
        return String(bytes: bytes[start..<offset], encoding: .isoLatin1)
    }
}
