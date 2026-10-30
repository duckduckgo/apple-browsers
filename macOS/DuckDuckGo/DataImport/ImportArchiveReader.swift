//
//  ImportArchiveReader.swift
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
import os.log
import BrowserServicesKit
import Common

public protocol ImportArchiveReading {
    func readContents(from archiveURL: URL) throws -> ImportArchiveContents
}

public typealias ImportArchiveContents = ImportArchiveReader.Contents

public struct ImportArchiveReader: ImportArchiveReading {

    public struct Contents {
        public enum ContentType {
            case passwordsOnly
            case bookmarksOnly
            case creditCardsOnly
            case none
            case other

            init(passwords: [String], bookmarks: [String], creditCards: [String]) {
                switch (passwords.isEmpty, bookmarks.isEmpty, creditCards.isEmpty) {
                case (false, true, true): self = .passwordsOnly
                case (true, false, true): self = .bookmarksOnly
                case (true, true, false): self = .creditCardsOnly
                case (true, true, true): self = .none
                default: self = .other
                }
            }
        }

        public let passwords: [String]  // CSV contents
        public let bookmarks: [String]  // HTML contents
        public let creditCards: [String] // JSON contents
        public let history: [String] // Safari History.json contents
        public let unrecognizedHistoryFileCount: Int // JSON files that look like history but aren't a history export we can read
        public var type: ContentType { ContentType(passwords: passwords, bookmarks: bookmarks, creditCards: creditCards) }

        public var isEmpty: Bool {
            passwords.isEmpty && bookmarks.isEmpty && creditCards.isEmpty && history.isEmpty
        }

        public func hasData(for types: Set<DataImport.DataType>) -> Bool {
            (types.contains(.passwords) && !passwords.isEmpty)
                || (types.contains(.bookmarks) && !bookmarks.isEmpty)
                || (types.contains(.creditCards) && !creditCards.isEmpty)
                || (types.contains(.history) && !history.isEmpty)
        }

        public init(
            passwords: [String],
            bookmarks: [String],
            creditCards: [String],
            history: [String] = [],
            unrecognizedHistoryFileCount: Int = 0
        ) {
            self.passwords = passwords
            self.bookmarks = bookmarks
            self.creditCards = creditCards
            self.history = history
            self.unrecognizedHistoryFileCount = unrecognizedHistoryFileCount
        }
    }

    private enum JSONExportType {
        case paymentCards(String)
        case history(String)
        case unrecognizedHistory
    }

    private enum Constants {
        static let csvExtension = ".csv"
        static let htmlExtension = ".html"
        static let jsonExtension = ".json"
    }

    public init() {}

    public func readContents(from url: URL) throws -> Contents {
        let archive = try Archive(url: url, accessMode: .read)

        var passwords = [String]()
        var bookmarks = [String]()
        var creditCards = [String]()
        var history = [String]()
        var unrecognizedHistoryFileCount = 0

        for entry in archive {
            let lowercasedPath = entry.path.lowercased()

            // Reject entries with a disguising double extension (e.g. foo.swift.html).
            guard !entry.path.hasMultipleFileExtensions else { continue }

            if lowercasedPath.hasSuffix(Constants.csvExtension),
               let content = extractFileContent(from: entry, in: archive) {
                passwords.append(content)
            } else if lowercasedPath.hasSuffix(Constants.htmlExtension),
                      let content = extractFileContent(from: entry, in: archive) {
                bookmarks.append(content)
            } else if lowercasedPath.hasSuffix(Constants.jsonExtension) {
                switch jsonExportType(of: extractFileContent(from: entry, in: archive), at: entry.path) {
                case .paymentCards(let content):
                    creditCards.append(content)
                case .history(let content):
                    history.append(content)
                case .unrecognizedHistory:
                    unrecognizedHistoryFileCount += 1
                case nil:
                    break
                }
            }
        }

        return Contents(
            passwords: passwords,
            bookmarks: bookmarks,
            creditCards: creditCards,
            history: history,
            unrecognizedHistoryFileCount: unrecognizedHistoryFileCount
        )
    }

    // MARK: - Private

    private func extractFileContent(from entry: Entry, in archive: Archive) -> String? {
        var data = Data()

        _ = try? archive.extract(entry) { chunk in
            data.append(chunk)
        }

        guard let content = String(data: data, encoding: .utf8) else {
            Logger.autofill.debug("Failed to decode archive contents")
            return nil
        }

        return content
    }

    private func jsonExportType(of content: String?, at path: String) -> JSONExportType? {
        let jsonObject = content.flatMap(jsonObject(from:))
        if let content, jsonObject?["payment_cards"] != nil {
            return .paymentCards(content)
        }
        // Safari's History.json identifies itself with `"metadata": { "data_type": "history" }`.
        if let content, let metadata = jsonObject?["metadata"] as? [String: Any], metadata["data_type"] as? String == "history" {
            return .history(content)
        }
        // A history file we can't read, e.g. after Safari changes its format.
        if jsonObject?["history"] != nil || isHistoryFileName(path) {
            return .unrecognizedHistory
        }
        return nil
    }

    private func jsonObject(from content: String) -> [String: Any]? {
        guard let data = content.data(using: .utf8) else {
            Logger.autofill.debug("Failed to convert json content to data")
            return nil
        }
        do {
            return try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        } catch {
            Logger.autofill.debug("Failed to parse JSON: \(error.localizedDescription)")
            return nil
        }
    }

    /// Safari names the file `History.json`, or `<Profile> - History.json` for other profiles.
    /// Zips made on macOS can also hold `._History.json` metadata files, which aren't history.
    private func isHistoryFileName(_ path: String) -> Bool {
        let fileName = (path as NSString).lastPathComponent
        return !fileName.hasPrefix("._") && fileName.lowercased().contains("history")
    }
}
