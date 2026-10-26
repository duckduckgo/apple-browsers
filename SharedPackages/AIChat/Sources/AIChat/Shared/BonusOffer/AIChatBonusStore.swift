//
//  AIChatBonusStore.swift
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
import FoundationExtensions

/// Represent a store operation failure.
public enum AIChatBonusStoreError: Error, Equatable {
    /// The file exists but couldn't be read, e.g. the device is locked before its first unlock.
    case readFailed(domain: String, code: Int)
    /// The file couldn't be written.
    case writeFailed(domain: String, code: Int)
    /// The file couldn't be deleted. A missing file is not a failure.
    case deleteFailed(domain: String, code: Int)
    /// The record's directory couldn't be created or excluded from backup, so nothing was written.
    case excludeFromBackupFailed(domain: String, code: Int)
    /// The stored bytes aren't valid JSON, or don't match the layout of their schema version.
    case decodingFailed
    /// The record couldn't be turned into JSON.
    case encodingFailed
    /// The record was written in a layout this build doesn't know, by a newer build.
    case unsupportedSchemaVersion(Int)
    /// The record breaks `AIChatBonusRecord.breaksInvariant`. Raised before a write and after a read.
    case invariantViolated
}

/// A type that can persist AI Chat Bonus data.
public protocol AIChatBonusStoring {
    /// The stored record, or `nil` only when there's no stored record.
    ///
    /// Any other failure throws, e.g. the device is locked or the stored data can't be decoded.
    /// If read fails do not attempt to write or delete the record and don't push anything to Duck.ai, not even `record: null`.
    func read() throws -> AIChatBonusRecord?

    /// Saves `record` in the current layout, replacing whatever is stored.
    ///
    /// Throws `invariantViolated` without storing anything if `record` is one Duck.ai would reject.
    func write(_ record: AIChatBonusRecord) throws

    /// Removes the record. Succeeds when there was nothing to remove.
    func delete() throws
}

/// Storage for AI Chat Offer data, kept as one JSON file in the app's own Application Support directory.
///
/// The `AIChatBonus` directory is excluded from backup. Each write replaces the file atomically.
public struct AIChatBonusStore: AIChatBonusStoring {
    // The help page explaining the Bonus ID, saved next to the record so anyone who opens the file can find it.
    // To be updated: ASANA https://app.asana.com/1/137249556945/project/72649045549333/task/1219865286901981?focus=true
    static let helpPage = URL(string: "https://duckduckgo.com/duckduckgo-help-pages/placeholder/")!

    private let directoryURL: URL
    private let fileSystem: AIChatBonusFileStoring
    private let helpPage: URL

    private var fileURL: URL {
        directoryURL.appendingPathComponent("record.json")
    }

    public init() {
        self.init(
            directoryURL: FileManager.default.applicationSupportDirectoryForComponent(named: "AIChatBonus"),
            fileSystem: AIChatBonusFileSystem()
        )
    }

    init(directoryURL: URL, fileSystem: AIChatBonusFileStoring, helpPage: URL = Self.helpPage) {
        self.directoryURL = directoryURL
        self.fileSystem = fileSystem
        self.helpPage = helpPage
    }

    public func read() throws -> AIChatBonusRecord? {
        let data: Data
        do {
            data = try fileSystem.read(fileURL)
        } catch {
            if error.isFileNotFound {
                return nil
            }
            let error = error as NSError
            throw AIChatBonusStoreError.readFailed(domain: error.domain, code: error.code)
        }

        return try decode(data)
    }

    public func write(_ record: AIChatBonusRecord) throws {
        // If record is in an inconsistent state do not store it.
        guard !record.breaksInvariant else {
            throw AIChatBonusStoreError.invariantViolated
        }

        let data = try encode(record)

        // Exclude the directory on every write, so a recreated directory is never backed up.
        do {
            try fileSystem.prepareDirectory(directoryURL)
        } catch let error as NSError  {
            throw AIChatBonusStoreError.excludeFromBackupFailed(domain: error.domain, code: error.code)
        }

        do {
            try fileSystem.write(data, to: fileURL)
        } catch let error as NSError {
            throw AIChatBonusStoreError.writeFailed(domain: error.domain, code: error.code)
        }
    }

    public func delete() throws {
        do {
            try fileSystem.remove(fileURL)
        } catch {
            if error.isFileNotFound {
                return
            }
            let error = error as NSError
            throw AIChatBonusStoreError.deleteFailed(domain: error.domain, code: error.code)
        }
    }
}

// MARK: - File System

/// The file operations `AIChatBonusStore` needs, injectable for tests.
protocol AIChatBonusFileStoring {
    func read(_ url: URL) throws -> Data
    /// Replaces the file atomically. The file can't be read until the device is first unlocked.
    func write(_ data: Data, to url: URL) throws
    func remove(_ url: URL) throws
    /// Creates the directory if missing and excludes it from backup.
    func prepareDirectory(_ url: URL) throws
}

struct AIChatBonusFileSystem: AIChatBonusFileStoring {
    private let fileManager = FileManager.default

    func read(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL) throws {
        // Set explicitly so an app-wide default protection can't change it.
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func remove(_ url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func prepareDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        // Set on the directory: an atomic write replaces the file, which would drop a flag set on the file.
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

private extension Error {
    var isFileNotFound: Bool {
        let error = self as NSError
        switch error.domain {
        case NSCocoaErrorDomain:
            return error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError
        case NSPOSIXErrorDomain:
            return error.code == Int(ENOENT)
        default:
            return false
        }
    }
}

// MARK: - Encoding / Decoding

private extension AIChatBonusStore {

    // The record's storage format
    struct StoredRecord: Codable {
        /// The version of the current model layout.
        /// Bump it only for a change an older build would misread: a field renamed, removed, made required or given a new meaning or unit.
        /// A new optional field needs no bump, since older items decode it as `nil`.
        /// When bumping, keep the previous layout as a frozen `StoredRecordV<n>` type, decode it in
        /// `decode(_:)` and map it to the current `AIChatBonusRecord`.
        /// That migrates on read only: the item stays in the old layout until the next write saves it in the current one.
        static let currentSchemaVersion = 1

        /// The schema of the record
        let schemaVersion: Int
        /// The AI Chat Bonus record
        let record: AIChatBonusRecord
        /// The help page explaining the Bonus ID. Optional so files written before it was added still decode.
        let helpPage: URL?

        init(record: AIChatBonusRecord, helpPage: URL) {
            self.schemaVersion = Self.currentSchemaVersion
            self.record = record
            self.helpPage = helpPage
        }
    }

    struct StoredSchemaVersion: Decodable {
        let schemaVersion: Int
    }

    func encode(_ record: AIChatBonusRecord) throws -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes] // Put `helpPage` first, with readable slashes.
            return try encoder.encode(StoredRecord(record: record, helpPage: helpPage))
        } catch {
            throw AIChatBonusStoreError.encodingFailed
        }
    }

    func decode(_ data: Data) throws -> AIChatBonusRecord {
        let decoder = JSONDecoder()
        // Read the version on its own first, since each version may have a different layout.
        guard let version = try? decoder.decode(StoredSchemaVersion.self, from: data).schemaVersion else {
            throw AIChatBonusStoreError.decodingFailed
        }
        // Any version other than the current one is rejected:
        // - Older: none exists yet. When the layout changes, decode the old one here and map it to the
        //   current record (see `currentSchemaVersion`).
        // - Newer: a later build wrote it, then this build replaced that newer one, e.g. a release rolled back
        //   through Sparkle. Throwing means the service never writes over a record it can't read.
        guard version == StoredRecord.currentSchemaVersion else {
            throw AIChatBonusStoreError.unsupportedSchemaVersion(version)
        }
        guard let record = try? decoder.decode(StoredRecord.self, from: data).record else {
            throw AIChatBonusStoreError.decodingFailed
        }
        guard !record.breaksInvariant else {
            throw AIChatBonusStoreError.invariantViolated
        }
        return record
    }

}
