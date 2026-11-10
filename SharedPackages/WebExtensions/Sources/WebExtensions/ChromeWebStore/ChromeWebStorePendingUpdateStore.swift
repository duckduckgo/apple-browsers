//
//  ChromeWebStorePendingUpdateStore.swift
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

/// A verified ZIP archive ready for the installation flow. The receiver owns accepted files.
public struct ChromeWebStoreVerifiedUpdate: Equatable, Sendable {
    public let extensionID: String
    public let version: String
    public let fileURL: URL
    public let installationIdentifier: String?

    public init(extensionID: String, version: String, fileURL: URL, installationIdentifier: String? = nil) {
        self.extensionID = extensionID
        self.version = version
        self.fileURL = fileURL
        self.installationIdentifier = installationIdentifier
    }
}

public protocol ChromeWebStorePendingUpdateStoring: Sendable {
    func pendingUpdate(for extensionID: String) async -> ChromeWebStoreVerifiedUpdate?
    /// Takes ownership of the file only when returning true. An older or equal version is rejected.
    func store(_ update: ChromeWebStoreVerifiedUpdate) async throws -> Bool
    func allPendingUpdates() async throws -> [ChromeWebStoreVerifiedUpdate]
    func copyForInstallation(_ update: ChromeWebStoreVerifiedUpdate) async throws -> ChromeWebStoreVerifiedUpdate?
    func remove(_ update: ChromeWebStoreVerifiedUpdate) async throws
    func removeInstallationCopy(_ update: ChromeWebStoreVerifiedUpdate) async throws
    func cleanupAbandonedInstallationCopies() async throws
    func setUpdateStoredHandler(_ handler: (@Sendable (ChromeWebStoreVerifiedUpdate) -> Void)?) async
}

/// Retains the newest package for each logical installation. Startup copies remain independent of pending replacement.
@available(macOS 15.4, iOS 18.4, *)
public actor ChromeWebStorePendingUpdateStore: ChromeWebStorePendingUpdateStoring {
    private let directory: URL
    private let persistsAcrossLaunches: Bool
    private var updates: [String: ChromeWebStoreVerifiedUpdate] = [:]
    private var hasLoaded = false
    private var updateStoredHandler: (@Sendable (ChromeWebStoreVerifiedUpdate) -> Void)?

    private enum Filename {
        static let metadata = "pending.json"
        static let installationCopies = ".startup-copies"
        static let archiveExtension = "zip"
    }
    private enum StorageError: Error { case invalidMetadata, invalidInstallationCopy }
    private static let maximumMetadataBytes = 1_048_576
    private static let maximumPendingCount = 256

    private struct Entry: Codable {
        let extensionID: String
        let version: String
        let installationIdentifier: String?
        let archiveName: String
    }

    private var copiesDirectory: URL { directory.appendingPathComponent(Filename.installationCopies, isDirectory: true) }

    public init(directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) {
        self.directory = directory
        persistsAcrossLaunches = false
    }

    public init(persistentDirectory: URL) {
        directory = persistentDirectory
        persistsAcrossLaunches = true
    }

    deinit {
        if !persistsAcrossLaunches { try? FileManager.default.removeItem(at: directory) }
    }

    public func pendingUpdate(for extensionID: String) -> ChromeWebStoreVerifiedUpdate? {
        do { try loadIfNeeded() } catch {
            Logger.webExtensions.error("Extension update pending metadata could not be read: \(error.localizedDescription)")
            return nil
        }
        guard let update = updates[extensionID] else { return nil }
        guard FileManager.default.fileExists(atPath: update.fileURL.path) else {
            try? remove(update)
            return nil
        }
        return update
    }

    public func store(_ update: ChromeWebStoreVerifiedUpdate) throws -> Bool {
        try loadIfNeeded()
        try Task.checkCancellation()
        if let previous = pendingUpdate(for: update.extensionID),
           previous.installationIdentifier == update.installationIdentifier,
           !SemanticVersionComparator().isVersion(update.version, newerThan: previous.version) { return false }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(Filename.archiveExtension)
        try FileManager.default.moveItem(at: update.fileURL, to: destination)
        let accepted = ChromeWebStoreVerifiedUpdate(extensionID: update.extensionID, version: update.version, fileURL: destination,
                                                   installationIdentifier: update.installationIdentifier)
        var next = updates
        let previous = next.updateValue(accepted, forKey: update.extensionID)
        do { try save(next) } catch {
            try? FileManager.default.moveItem(at: destination, to: update.fileURL)
            throw error
        }
        updates = next
        if let previous { try? FileManager.default.removeItem(at: previous.fileURL) }
        cleanupUnreferencedArchives()
        updateStoredHandler?(accepted)
        return true
    }

    public func allPendingUpdates() throws -> [ChromeWebStoreVerifiedUpdate] {
        try loadIfNeeded()
        return Array(updates.values)
    }

    public func setUpdateStoredHandler(_ handler: (@Sendable (ChromeWebStoreVerifiedUpdate) -> Void)?) {
        updateStoredHandler = handler
    }

    public func copyForInstallation(_ update: ChromeWebStoreVerifiedUpdate) throws -> ChromeWebStoreVerifiedUpdate? {
        try loadIfNeeded()
        guard updates[update.extensionID] == update else { return nil }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: copiesDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let copy = copiesDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(Filename.archiveExtension)
        try FileManager.default.copyItem(at: update.fileURL, to: copy)
        return .init(extensionID: update.extensionID, version: update.version, fileURL: copy, installationIdentifier: update.installationIdentifier)
    }

    public func remove(_ update: ChromeWebStoreVerifiedUpdate) throws {
        try loadIfNeeded()
        guard updates[update.extensionID] == update else { return }
        var next = updates
        next.removeValue(forKey: update.extensionID)
        try save(next)
        updates = next
        try? FileManager.default.removeItem(at: update.fileURL)
    }

    public func removeInstallationCopy(_ update: ChromeWebStoreVerifiedUpdate) throws {
        guard update.fileURL.deletingLastPathComponent().standardizedFileURL == copiesDirectory.standardizedFileURL,
              validArchiveName(update.fileURL.lastPathComponent) else { throw StorageError.invalidInstallationCopy }
        if FileManager.default.fileExists(atPath: update.fileURL.path) { try FileManager.default.removeItem(at: update.fileURL) }
    }

    public func cleanupAbandonedInstallationCopies() throws {
        if FileManager.default.fileExists(atPath: copiesDirectory.path) {
            do { try FileManager.default.removeItem(at: copiesDirectory) } catch {
                Logger.webExtensions.error("Extension update installation: abandoned-copy cleanup failed=\(error.localizedDescription)")
            }
        }
        try loadIfNeeded()
        cleanupUnreferencedArchives()
    }

    private func loadIfNeeded() throws {
        guard !hasLoaded else { return }
        hasLoaded = true
        let metadataURL = directory.appendingPathComponent(Filename.metadata)
        guard persistsAcrossLaunches, FileManager.default.fileExists(atPath: metadataURL.path) else { return }
        let size = try metadataURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Self.maximumMetadataBytes else { throw StorageError.invalidMetadata }
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: metadataURL))
        guard entries.count <= Self.maximumPendingCount else { throw StorageError.invalidMetadata }
        var restored: [String: ChromeWebStoreVerifiedUpdate] = [:]
        for entry in entries {
            guard validArchiveName(entry.archiveName), restored[entry.extensionID] == nil else { throw StorageError.invalidMetadata }
            let file = directory.appendingPathComponent(entry.archiveName)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            restored[entry.extensionID] = .init(extensionID: entry.extensionID, version: entry.version, fileURL: file,
                                               installationIdentifier: entry.installationIdentifier)
        }
        updates = restored
    }

    private func save(_ values: [String: ChromeWebStoreVerifiedUpdate]) throws {
        guard persistsAcrossLaunches else { return }
        guard values.count <= Self.maximumPendingCount else { throw StorageError.invalidMetadata }
        let entries = values.values.map { Entry(extensionID: $0.extensionID, version: $0.version, installationIdentifier: $0.installationIdentifier,
                                                archiveName: $0.fileURL.lastPathComponent) }
        let data = try JSONEncoder().encode(entries)
        guard data.count <= Self.maximumMetadataBytes else { throw StorageError.invalidMetadata }
        try data.write(to: directory.appendingPathComponent(Filename.metadata), options: .atomic)
    }

    private func validArchiveName(_ name: String) -> Bool {
        let url = URL(fileURLWithPath: name)
        return url.lastPathComponent == name && url.pathExtension == Filename.archiveExtension && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
    }

    private func cleanupUnreferencedArchives() {
        let referenced = Set(updates.values.map(\.fileURL))
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where validArchiveName(file.lastPathComponent) && !referenced.contains(file) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
