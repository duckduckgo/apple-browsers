//
//  WebExtensionUpdateTransactionStore.swift
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

/// Owns the files involved in replacing one installation. Runtime state and consent remain with the manager.
/// The journal is written before each destructive operation, so recovery can restore the predecessor.
@available(macOS 15.4, iOS 18.4, *)
actor WebExtensionUpdateTransactionStore {
    enum TransactionError: Error {
        case invalidInstallationIdentifier
        case invalidJournal
        case transactionAlreadyExists
        case invalidState
        case missingPackage
    }

    private enum Filename {
        static let transactions = ".update-transactions"
        static let journal = "journal.json"
        static let staged = "staged"
        static let previous = "previous"
    }

    struct Staged: Sendable {
        let transactionID: UUID
        let installationID: String
        let extensionID: String
        let version: String
        let bundleURL: URL
        let installedFilename: String
    }

    struct Journal: Codable, Sendable {
        enum Phase: String, Codable, Sendable { case prepared, replacing, committed, rollingBack }
        let transactionID: UUID
        let installationID: String
        let extensionID: String
        let previousVersion: String?
        let version: String
        let previousMetadata: Data
        var updatedMetadata: Data?
        var phase: Phase
        var retainsPrevious: Bool
        /// Same-version reinstalls need acknowledgement because version equality cannot identify the registry write.
        var registryCommitted: Bool?
        let versionOverrideIdentifier: UUID?
    }

    private let root: URL
    private let fileManager: FileManager
    private var transactionsDirectory: URL { root.appendingPathComponent(Filename.transactions, isDirectory: true) }

    init(extensionsDirectory: URL, fileManager: FileManager = .default) {
        root = extensionsDirectory
        self.fileManager = fileManager
    }

    /// The source archive must be owned by the caller for the duration of extraction.
    func stage(_ update: ChromeWebStoreVerifiedUpdate, installationID: String, previousVersion: String?, previousMetadata: Data,
               versionOverrideIdentifier: UUID? = nil) throws -> Staged {
        guard UUID(uuidString: installationID) != nil else { throw TransactionError.invalidInstallationIdentifier }
        guard try journals().allSatisfy({ $0.installationID != installationID }) else { throw TransactionError.transactionAlreadyExists }
        try Task.checkCancellation()
        let transactionID = UUID()
        let directory = transactionDirectory(transactionID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            let staging = WebExtensionStorageProvider(extensionsDirectory: directory, fileManager: fileManager)
            _ = try staging.extractExtension(from: update.fileURL, identifier: Filename.staged)
            guard let bundleURL = staging.resolveInstalledExtension(identifier: Filename.staged) else { throw TransactionError.missingPackage }
            try Task.checkCancellation()
            try save(Journal(transactionID: transactionID, installationID: installationID, extensionID: update.extensionID,
                             previousVersion: previousVersion, version: update.version, previousMetadata: previousMetadata,
                             phase: .prepared, retainsPrevious: false, registryCommitted: previousVersion == update.version ? false : nil,
                             versionOverrideIdentifier: versionOverrideIdentifier))
            let filename = bundleURL.lastPathComponent == Filename.staged ? installationID : bundleURL.lastPathComponent
            return Staged(transactionID: transactionID, installationID: installationID, extensionID: update.extensionID,
                          version: update.version, bundleURL: bundleURL, installedFilename: filename)
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    func replace(_ staged: Staged) throws {
        var journal = try read(staged.transactionID)
        guard journal.phase == .prepared else { throw TransactionError.invalidState }
        try Task.checkCancellation()
        let current = installationDirectory(journal.installationID)
        guard fileManager.fileExists(atPath: current.path) else { throw TransactionError.missingPackage }
        journal.phase = .replacing
        try save(journal)
        try fileManager.moveItem(at: current, to: previousDirectory(journal.transactionID))
        try fileManager.moveItem(at: stagedDirectory(journal.transactionID), to: current)
    }

    /// Commit the durable target metadata before the manager updates its registry. Recovery can finish that write.
    func commit(_ staged: Staged, updatedMetadata: Data, retainPrevious: Bool) throws {
        var journal = try read(staged.transactionID)
        guard journal.phase == .replacing else { throw TransactionError.invalidState }
        journal.updatedMetadata = updatedMetadata
        journal.retainsPrevious = retainPrevious
        journal.phase = .committed
        try save(journal)
    }

    /// Removes a transaction only after its file and registry state is reconciled, or when the incumbent was untouched.
    func finish(_ transactionID: UUID) throws {
        try fileManager.removeItem(at: transactionDirectory(transactionID))
    }

    /// An acknowledgement failure leaves a coherent package usable and its journal available for another launch.
    func acknowledgeRegistry(_ transactionID: UUID) -> Bool {
        do {
            var journal = try read(transactionID)
            guard journal.registryCommitted == false else { return true }
            journal.registryCommitted = true
            try save(journal)
            return true
        } catch {
            Logger.webExtensions.error("Extension update transaction registry acknowledgement failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Cleanup cannot invalidate an otherwise working package; leave its journal for another launch on failure.
    func cleanup(_ transactionID: UUID) {
        do { try finish(transactionID) } catch {
            Logger.webExtensions.error("Extension update transaction cleanup failed: \(error.localizedDescription)")
        }
    }

    /// Persists rollback intent before touching files. The caller must reconcile returned metadata, then call finish.
    /// Never restores files for an installation the manager has removed or replaced.
    @discardableResult
    func rollback(_ transactionID: UUID, restoreInstallation: Bool) throws -> Data? {
        var journal = try read(transactionID)
        guard restoreInstallation, journal.phase != .prepared else {
            cleanup(transactionID)
            return nil
        }
        let previous = previousDirectory(transactionID)
        let current = installationDirectory(journal.installationID)
        let hasPrevious = fileManager.fileExists(atPath: previous.path)
        // A committed candidate cannot be mistaken for a restored predecessor if its backup is unavailable.
        guard journal.phase != .committed || hasPrevious else { throw TransactionError.missingPackage }
        if journal.phase != .rollingBack, journal.registryCommitted != nil { journal.registryCommitted = false }
        journal.phase = .rollingBack
        try save(journal)
        if hasPrevious {
            if fileManager.fileExists(atPath: current.path) { try fileManager.removeItem(at: current) }
            try fileManager.moveItem(at: previous, to: current)
        }
        guard fileManager.fileExists(atPath: current.path) else { throw TransactionError.missingPackage }
        return journal.previousMetadata
    }

    /// Unreadable journals fail closed and retain their backups; deleting them could destroy the only working package.
    func journals() throws -> [Journal] {
        guard fileManager.fileExists(atPath: transactionsDirectory.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: transactionsDirectory, includingPropertiesForKeys: nil).compactMap { directory in
            guard let identifier = UUID(uuidString: directory.lastPathComponent) else { return nil }
            guard fileManager.fileExists(atPath: directory.appendingPathComponent(Filename.journal).path) else {
                // No destructive operation can begin before the initial journal exists.
                cleanup(identifier)
                return nil
            }
            return try read(identifier)
        }
    }

    /// Returns the metadata to reconcile before extensions load. The manager must recheck installation identity after awaiting.
    func recover(_ journal: Journal, installationStillMatches: Bool, rejectCandidate: Bool = false) throws -> Data? {
        guard installationStillMatches else {
            cleanup(journal.transactionID)
            return nil
        }
        if rejectCandidate, journal.phase != .prepared {
            return try rollback(journal.transactionID, restoreInstallation: true)
        }
        switch journal.phase {
        case .prepared:
            cleanup(journal.transactionID)
            return nil
        case .replacing, .rollingBack:
            return try rollback(journal.transactionID, restoreInstallation: true)
        case .committed:
            guard fileManager.fileExists(atPath: installationDirectory(journal.installationID).path),
                  let metadata = journal.updatedMetadata else { throw TransactionError.missingPackage }
            return metadata
        }
    }

    private func read(_ transactionID: UUID) throws -> Journal {
        let data = try Data(contentsOf: transactionDirectory(transactionID).appendingPathComponent(Filename.journal))
        let journal = try JSONDecoder().decode(Journal.self, from: data)
        guard journal.transactionID == transactionID, UUID(uuidString: journal.installationID) != nil else { throw TransactionError.invalidJournal }
        return journal
    }

    private func save(_ journal: Journal) throws {
        try JSONEncoder().encode(journal).write(to: transactionDirectory(journal.transactionID).appendingPathComponent(Filename.journal), options: .atomic)
    }

    private func transactionDirectory(_ identifier: UUID) -> URL { transactionsDirectory.appendingPathComponent(identifier.uuidString, isDirectory: true) }
    private func installationDirectory(_ identifier: String) -> URL { root.appendingPathComponent(identifier, isDirectory: true) }
    private func stagedDirectory(_ identifier: UUID) -> URL { transactionDirectory(identifier).appendingPathComponent(Filename.staged, isDirectory: true) }
    private func previousDirectory(_ identifier: UUID) -> URL { transactionDirectory(identifier).appendingPathComponent(Filename.previous, isDirectory: true) }
}
