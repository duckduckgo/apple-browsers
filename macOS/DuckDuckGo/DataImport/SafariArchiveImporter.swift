//
//  SafariArchiveImporter.swift
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
import BrowserServicesKit
import SecureStorage
import PixelKit
import Common

/// A DataImporter that can import bookmarks and passwords from a zip archive
/// by extracting the contents and using BookmarkHTMLImporter and CSVImporter.
final class SafariArchiveImporter: DataImporter {

    private let archiveURL: URL
    private let archiveReader: ImportArchiveReading
    private let bookmarkImporter: BookmarkImporter
    private let loginImporter: LoginImporter
    private let faviconManager: FaviconManagement
    private let featureFlagger: FeatureFlagger
    private let secureVaultReporter: SecureVaultReporting
    private let tld: TLD

    /// Initializes the SafariArchiveImporter with concrete dependencies
    /// - Parameters:
    ///   - archiveURL: The URL of the zip archive to import from
    ///   - archiveReader: The reader used to extract contents from the archive
    ///   - bookmarkImporter: The bookmark importer to use for importing bookmarks
    ///   - loginImporter: The login importer to use for importing passwords
    ///   - faviconManager: The favicon manager for handling favicons
    ///   - featureFlagger: Feature flagger for controlling import behavior
    ///   - secureVaultReporter: Reporter for secure vault operations
    ///   - tld: TLD helper for URL processing
    init(archiveURL: URL,
         archiveReader: ImportArchiveReading = ImportArchiveReader(),
         bookmarkImporter: BookmarkImporter,
         loginImporter: LoginImporter,
         faviconManager: FaviconManagement,
         featureFlagger: FeatureFlagger,
         secureVaultReporter: SecureVaultReporting,
         tld: TLD) {
        self.archiveURL = archiveURL
        self.archiveReader = archiveReader
        self.bookmarkImporter = bookmarkImporter
        self.loginImporter = loginImporter
        self.faviconManager = faviconManager
        self.featureFlagger = featureFlagger
        self.secureVaultReporter = secureVaultReporter
        self.tld = tld
    }

    // MARK: - DataImporter Protocol

    /// Returns the union of all importable types based on the archive contents
    var importableTypes: [DataImport.DataType] {
        guard let contents = try? archiveReader.readContents(from: archiveURL) else {
            return []
        }

        var types: [DataImport.DataType] = []
        if !contents.passwords.isEmpty {
            types.append(.passwords)
        }
        if !contents.bookmarks.isEmpty {
            types.append(.bookmarks)
        }
        #if os(iOS)
        if !contents.creditCards.isEmpty {
            types.append(.creditCards)
        }
        #endif
        return types
    }

    /// Validates access for the requested data types by extracting the archive
    /// - Parameter types: The data types to validate access for
    /// - Returns: A dictionary of validation errors, or nil if all validations pass
    func validateAccess(for types: Set<DataImport.DataType>) -> [DataImport.DataType: any DataImportError]? {
        do {
            let contents = try archiveReader.readContents(from: archiveURL)
            let tempFiles = try createTemporaryFiles(from: contents, for: types)
            defer {
                cleanupTemporaryFiles(tempFiles)
            }

            var errors: [DataImport.DataType: any DataImportError] = [:]

            // Validate bookmarks if requested and available
            if types.contains(.bookmarks), let bookmarkFile = tempFiles.bookmarks {
                let bookmarkHTMLImporter = BookmarkHTMLImporter(fileURL: bookmarkFile, bookmarkImporter: bookmarkImporter)
                if let bookmarkErrors = bookmarkHTMLImporter.validateAccess(for: [.bookmarks]) {
                    errors.merge(bookmarkErrors) { _, new in new }
                }
            }

            // CSV files generally don't need validation - they're validated during import

            return errors.isEmpty ? nil : errors

        } catch {
            // Return a generic error for each requested type if archive reading fails
            return Dictionary(uniqueKeysWithValues: types.map { ($0, GenericImportError(underlyingError: error)) })
        }
    }

    /// Imports data of the specified types by coordinating between the constituent importers
    /// - Parameter types: The data types to import
    /// - Returns: A DataImportTask that can be used to track progress and results
    func importData(types: Set<DataImport.DataType>) -> DataImportTask {
        .detachedWithProgress { updateProgress in
            do {
                let result = try await self.importDataSync(types: types, updateProgress: updateProgress)
                return result
            } catch is CancellationError {
            } catch {
                assertionFailure("Only CancellationError should be thrown here")
            }
            return [:]
        }
    }

    private func importDataSync(types: Set<DataImport.DataType>, updateProgress: @escaping DataImportProgressCallback) async throws -> DataImportSummary {
        var summary = DataImportSummary()

        // Extract archive contents
        let contents = try archiveReader.readContents(from: archiveURL)
        let tempFiles = try createTemporaryFiles(from: contents, for: types)
        defer {
            cleanupTemporaryFiles(tempFiles)
        }

        let dataTypeFraction = 1.0 / Double(types.count)

        // Import passwords if requested and available
        if types.contains(.passwords), !contents.passwords.isEmpty {
            let csvContent = contents.passwords.joined(separator: "\n")
            let csvImporter = CSVImporter(fileURL: nil, csvContent: csvContent, loginImporter: loginImporter, defaultColumnPositions: nil, reporter: secureVaultReporter, tld: tld)
            let passwordTask = csvImporter.importData(types: [DataImport.DataType.passwords])
            let passwordResults = await passwordTask.task.value
            try updateProgress(.importingPasswords(numberOfPasswords: passwordResults.count, fraction: 1.0))
            summary.merge(passwordResults) { _, new in new }
        } else if types.contains(.passwords) {
            let passwordsResults: DataImportSummary = [.passwords: .failure(ImportError(action: .passwords, type: .importContents, underlyingError: nil))]
            try updateProgress(.importingPasswords(numberOfPasswords: 0, fraction: 1.0))
            summary.merge(passwordsResults) { _, new in new }
        }

        // Import bookmarks if requested and available
        if types.contains(.bookmarks), let bookmarkFile = tempFiles.bookmarks {
            let bookmarkHTMLImporter = BookmarkHTMLImporter(fileURL: bookmarkFile, bookmarkImporter: bookmarkImporter)
            let bookmarkTask = bookmarkHTMLImporter.importData(types: [.bookmarks])
            let bookmarkResults = await bookmarkTask.task.value
            try updateProgress(.importingBookmarks(numberOfBookmarks: bookmarkResults.count, fraction: 1.0))
            summary.merge(bookmarkResults) { _, new in new }
        } else if types.contains(.bookmarks) {
            let bookmarksResults: DataImportSummary = [.bookmarks: .failure(ImportError(action: .bookmarks, type: .importContents, underlyingError: nil))]
            try updateProgress(.importingBookmarks(numberOfBookmarks: 0, fraction: 1.0))
            summary.merge(bookmarksResults) { _, new in new }
        }

        try updateProgress(.done)
        return summary
    }

    /// Determines if keychain password is required for any of the selected data types
    /// - Parameter selectedDataTypes: The data types being imported
    /// - Returns: false since Safari archive imports don't require keychain passwords
    func requiresKeychainPassword(for selectedDataTypes: Set<DataImport.DataType>) -> Bool {
        // Safari archive exports are standalone files that don't require keychain access
        return false
    }

    // MARK: - Private

    private struct TemporaryFiles {
        let passwords: URL?
        let bookmarks: URL?

        var allFiles: [URL] {
            [passwords, bookmarks].compactMap { $0 }
        }
    }

    private func createTemporaryFiles(from contents: ImportArchiveContents, for types: Set<DataImport.DataType>) throws -> TemporaryFiles {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        let sessionDirectory = tempDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)

        var passwordFile: URL?
        var bookmarkFile: URL?

        // Create bookmark file if requested and content available
        if types.contains(.bookmarks), !contents.bookmarks.isEmpty {
            let htmlContent = contents.bookmarks.joined(separator: "\n")
            bookmarkFile = sessionDirectory.appendingPathComponent("bookmarks.html")
            try htmlContent.write(to: bookmarkFile!, atomically: true, encoding: .utf8)
        }

        // Passwords are handled directly via CSV content, no temp file needed

        return TemporaryFiles(passwords: passwordFile, bookmarks: bookmarkFile)
    }

    private func cleanupTemporaryFiles(_ tempFiles: TemporaryFiles) {
        let fileManager = FileManager.default
        var parentDirectories = Set<URL>()

        for file in tempFiles.allFiles {
            parentDirectories.insert(file.deletingLastPathComponent())
            try? fileManager.removeItem(at: file)
        }

        // Clean up parent directories if they're empty
        for directory in parentDirectories {
            try? fileManager.removeItem(at: directory)
        }
    }
}

// MARK: - Helper Error Type

private struct GenericImportError: DataImportError {
    let underlyingError: Error?

    var action: DataImportAction { .generic }
    var type: OperationType { OperationType(rawValue: (underlyingError as NSError?)?.code ?? 0) }
    var errorType: DataImport.ErrorType { .other }

    struct OperationType: RawRepresentable {
        let rawValue: Int
    }
}
