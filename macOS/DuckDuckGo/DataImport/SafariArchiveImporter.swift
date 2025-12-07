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
import UniformTypeIdentifiers

/// A DataImporter that can import Safari archives as well as standalone Safari exports
/// (CSV, HTML, JSON) by delegating to the appropriate importer for each format.
final class SafariArchiveImporter: DataImporter {
    struct ImportError: DataImportError {
        enum OperationType: Int {
            case validateAccess
            case unarchive
            case createTempFiles
            case importContents
        }

        let action: DataImportAction
        let type: OperationType
        let underlyingError: Error?

        var errorType: DataImport.ErrorType {
            switch type {
            case .validateAccess:
                return .other
            case .createTempFiles:
                return .other
            case .importContents:
                return .noData
            case .unarchive:
                return .other
            }
        }
    }

    private enum SourceFileType {
        case archive
        case bookmarks
        case passwords
        case creditCards

        init(url: URL) {
            guard let fileType = SafariArchiveImporter.contentType(for: url) else {
                self = .archive
                return
            }

            if fileType.conforms(to: .commaSeparatedText) {
                self = .passwords
            } else if fileType.conforms(to: .html) {
                self = .bookmarks
            } else if fileType.conforms(to: .json) {
                self = .creditCards
            } else {
                self = .archive
            }
        }
    }

    private let archiveURL: URL
    private let archiveReader: ImportArchiveReading
    private let bookmarkImporter: BookmarkImporter
    private let loginImporter: LoginImporter
    private let creditCardImporter: CreditCardImporter
    private let vault: (any AutofillSecureVault)?
    private let faviconManager: FaviconManagement
    private let featureFlagger: FeatureFlagger
    private let secureVaultReporter: SecureVaultReporting
    private let tld: TLD
    private let sourceFileType: SourceFileType

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
         creditCardImporter: CreditCardImporter = SecureVaultCreditCardImporter(),
         vault: (any AutofillSecureVault)? = nil,
         faviconManager: FaviconManagement,
         featureFlagger: FeatureFlagger,
         secureVaultReporter: SecureVaultReporting,
         tld: TLD) {
        self.sourceFileType = SourceFileType(url: archiveURL)
        self.archiveURL = archiveURL
        self.archiveReader = archiveReader
        self.bookmarkImporter = bookmarkImporter
        self.loginImporter = loginImporter
        self.creditCardImporter = creditCardImporter
        self.vault = vault ?? (try? AutofillSecureVaultFactory.makeVault(reporter: secureVaultReporter))
        self.faviconManager = faviconManager
        self.featureFlagger = featureFlagger
        self.secureVaultReporter = secureVaultReporter
        self.tld = tld
    }

    // MARK: - DataImporter Protocol

    /// Returns the union of all importable types based on the archive contents
    var importableTypes: [DataImport.DataType] {
        switch sourceFileType {
        case .archive:
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
            if !contents.creditCards.isEmpty {
                types.append(.creditCards)
            }
            return types
        case .passwords:
            return [.passwords]
        case .bookmarks:
            return [.bookmarks]
        case .creditCards:
            return [.creditCards]
        }
    }

    /// Validates access for the requested data types by extracting the archive
    /// - Parameter types: The data types to validate access for
    /// - Returns: A dictionary of validation errors, or nil if all validations pass
    func validateAccess(for types: Set<DataImport.DataType>) -> [DataImport.DataType: any DataImportError]? {
        switch sourceFileType {
        case .archive:
            return validateArchiveAccess(for: types)
        case .bookmarks, .passwords, .creditCards:
            return nil
        }
    }

    private func validateArchiveAccess(for types: Set<DataImport.DataType>) -> [DataImport.DataType: any DataImportError]? {
        do {
            let contents = try archiveReader.readContents(from: archiveURL)
            let tempFile = try createTemporaryBookmarksFile(from: contents.bookmarks)
            defer {
                if let tempFile {
                    cleanupTemporaryFile(tempFile)
                }
            }

            var errors: [DataImport.DataType: any DataImportError] = [:]

            // Validate bookmarks if requested and available
            if types.contains(.bookmarks), let bookmarkFile = tempFile {
                let bookmarkHTMLImporter = BookmarkHTMLImporter(fileURL: bookmarkFile, bookmarkImporter: bookmarkImporter)
                if let bookmarkErrors = bookmarkHTMLImporter.validateAccess(for: [.bookmarks]) {
                    errors.merge(bookmarkErrors) { _, new in new }
                }
            }

            // CSV files generally don't need validation - they're validated during import

            return errors.isEmpty ? nil : errors

        } catch {
            // Return a generic error for each requested type if archive reading fails
            return Dictionary(uniqueKeysWithValues: types.map { ($0, ImportError(action: .generic, type: .validateAccess, underlyingError: error)) })
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
        var finalSummary = DataImportSummary()

        // Extract archive contents
        let contents: ImportArchiveContents
        do {
            contents = try readContentsForSelectedFile()
        } catch {
            for type in types {
                finalSummary[type] = DataImportResult.failure(ImportError(action: .generic, type: .unarchive, underlyingError: error))
            }
            return finalSummary
        }

        guard !contents.isEmpty else {
            for type in types {
                finalSummary[type] = .failure(ImportError(action: .generic, type: .importContents, underlyingError: nil))
            }
            return finalSummary
        }

        var cumulativeFraction = 0.0

        // Import passwords if requested and available
        if types.contains(.passwords), !contents.passwords.isEmpty {
            let summary = try await importPasswords(contents, types, updateProgress, &cumulativeFraction)
            finalSummary.merge(summary) { (_, new) in new }
        }

        // Import bookmarks if requested and available
        if types.contains(.bookmarks), !contents.bookmarks.isEmpty {
            let originalHTMLFile = sourceFileType == .bookmarks ? archiveURL : nil
            let summary = try await importBookmarks(contents.bookmarks, originalHTMLFile, types, updateProgress, &cumulativeFraction)
            finalSummary.merge(summary) { (_, new) in new }
        }

        // Import credit cards if requested and available
        if types.contains(.creditCards), let content = contents.creditCards.first {
            let summary = try await importCreditCards(content, types, updateProgress, &cumulativeFraction)
            finalSummary.merge(summary) { (_, new) in new }
        }

        try updateProgress(.done)
        return finalSummary
    }

    /// Determines if keychain password is required for any of the selected data types
    /// - Parameter selectedDataTypes: The data types being imported
    /// - Returns: false since Safari archive imports don't require keychain passwords
    func requiresKeychainPassword(for selectedDataTypes: Set<DataImport.DataType>) -> Bool {
        // Safari archive exports are standalone files that don't require keychain access
        return false
    }

    // MARK: - Private

    private func readContentsForSelectedFile() throws -> ImportArchiveContents {
        switch sourceFileType {
        case .archive:
            return try archiveReader.readContents(from: archiveURL)
        case .passwords:
            let csvContent = try String(contentsOf: archiveURL, encoding: .utf8)
            return ImportArchiveReader.Contents(passwords: [csvContent], bookmarks: [], creditCards: [])
        case .bookmarks:
            let bookmarkContent = try String(contentsOf: archiveURL, encoding: .utf8)
            return ImportArchiveReader.Contents(passwords: [], bookmarks: [bookmarkContent], creditCards: [])
        case .creditCards:
            let jsonContent = try String(contentsOf: archiveURL, encoding: .utf8)
            return ImportArchiveReader.Contents(passwords: [], bookmarks: [], creditCards: [jsonContent])
        }
    }

    private func createTemporaryBookmarksFile(from contents: [String]) throws -> URL? {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        let sessionDirectory = tempDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)

        var bookmarkFile: URL?

        // Create bookmark file if requested and content available
        if !contents.isEmpty {
            let htmlContent = contents.joined(separator: "\n")
            bookmarkFile = sessionDirectory.appendingPathComponent("bookmarks.html")
            try htmlContent.write(to: bookmarkFile!, atomically: true, encoding: .utf8)
        }

        return bookmarkFile
    }

    private func cleanupTemporaryFile(_ tempFile: URL) {
        let fileManager = FileManager.default

        let parentDirectory = tempFile.deletingLastPathComponent()
        try? fileManager.removeItem(at: tempFile)

        // Clean up parent directory if empty. Throws if not
        try? fileManager.removeItem(at: parentDirectory)
    }

    private func importPasswords(_ contents: ImportArchiveContents, _ types: Set<DataImport.DataType>, _ updateProgress: DataImportProgressCallback, _ cumulativeFraction: inout Double) async throws -> DataImportSummary {
        let csvContent = contents.passwords.joined(separator: "\n")
        let csvImporter = CSVImporter(fileURL: nil, csvContent: csvContent, loginImporter: loginImporter, defaultColumnPositions: nil, reporter: secureVaultReporter, tld: tld)
        let passwordTask = csvImporter.importData(types: [DataImport.DataType.passwords])
        let currentTotalFraction = cumulativeFraction
        for await update in passwordTask.progress {
            if case .progress(.importingPasswords(let numberOfPasswords, let fraction)) = update {
                let currentFraction = fraction / Double(types.count)
                cumulativeFraction = currentTotalFraction + currentFraction
                try updateProgress(.importingPasswords(numberOfPasswords: numberOfPasswords, fraction: cumulativeFraction))
            }
        }
        let passwordResults = await passwordTask.task.value
        return passwordResults
    }

    private func importBookmarks(_ bookmarkContent: [String], _ originalFileURL: URL?, _ types: Set<DataImport.DataType>, _ updateProgress: DataImportProgressCallback, _ cumulativeFraction: inout Double) async throws -> DataImportSummary {
        var temporaryFile: URL?
        let bookmarkFile: URL

        if let originalFileURL {
            bookmarkFile = originalFileURL
        } else {
            do {
                temporaryFile = try createTemporaryBookmarksFile(from: bookmarkContent)
            } catch {
                return [.bookmarks: .failure(ImportError(action: .generic, type: .createTempFiles, underlyingError: error))]
            }

            guard let generatedFile = temporaryFile else {
                return [.bookmarks: .failure(ImportError(action: .generic, type: .createTempFiles, underlyingError: nil))]
            }

            bookmarkFile = generatedFile
        }

        defer {
            if let temporaryFile {
                cleanupTemporaryFile(temporaryFile)
            }
        }

        let bookmarkHTMLImporter = BookmarkHTMLImporter(fileURL: bookmarkFile, bookmarkImporter: bookmarkImporter)
        let bookmarkTask = bookmarkHTMLImporter.importData(types: [.bookmarks])
        let currentTotalFraction = cumulativeFraction
        for await update in bookmarkTask.progress {
            if case .progress(.importingBookmarks(let numberOfBookmarks, let fraction)) = update {
                let currentFraction = fraction / Double(types.count)
                cumulativeFraction = currentTotalFraction + currentFraction
                try updateProgress(.importingBookmarks(numberOfBookmarks: numberOfBookmarks, fraction: cumulativeFraction))
            }
        }
        let bookmarkResults = await bookmarkTask.task.value
        return bookmarkResults
    }

    private func importCreditCards(_ content: String, _ types: Set<DataImport.DataType>, _ updateProgress: DataImportProgressCallback, _ cumulativeFraction: inout Double) async throws -> DataImportSummary {
        let safariCreditCardImporter = SafariPaymentCardsImporter(fileURL: nil, jsonContent: content, creditCardImporter: creditCardImporter, vault: vault)
        let creditCardTask = safariCreditCardImporter.importData(types: [.creditCards])
        let currentTotalFraction = cumulativeFraction
        for await update in creditCardTask.progress {
            if case .progress(.importingCreditCards(let numberOfCreditCards, let fraction)) = update {
                let currentFraction = fraction / Double(types.count)
                cumulativeFraction = currentTotalFraction + currentFraction
                try updateProgress(.importingCreditCards(numberOfCreditCards: numberOfCreditCards, fraction: cumulativeFraction))
            }
        }
        let creditCardResults = await creditCardTask.task.value
        return creditCardResults
    }

    private static func contentType(for url: URL) -> UTType? {
        UTType(filenameExtension: url.pathExtension)
    }
}
