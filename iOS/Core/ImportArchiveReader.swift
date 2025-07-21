//
//  ImportArchiveReader.swift
//  DuckDuckGo
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

public protocol ImportArchiveReading {
    func readContents(from archiveURL: URL, featureFlagger: FeatureFlagger) throws -> ImportArchiveContents
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
        public var type: ContentType { ContentType(passwords: passwords, bookmarks: bookmarks, creditCards: creditCards) }

        public init(passwords: [String], bookmarks: [String], creditCards: [String]) {
            self.passwords = passwords
            self.bookmarks = bookmarks
            self.creditCards = creditCards
        }
    }

    private enum Constants {
        static let csvExtension = ".csv"
        static let htmlExtension = ".html"
        static let jsonExtension = ".json"
    }

    public init() {}

    public func readContents(from url: URL, featureFlagger: FeatureFlagger) throws -> Contents {
        let archive = try Archive(url: url, accessMode: .read)

        var passwords = [String]()
        var bookmarks = [String]()
        var creditCards = [String]()

        for entry in archive {
            let lowercasedPath = entry.path.lowercased()

            if lowercasedPath.hasSuffix(Constants.csvExtension),
               let content = extractFileContent(from: entry, in: archive) {
                passwords.append(content)
            } else if lowercasedPath.hasSuffix(Constants.htmlExtension),
                      let content = extractFileContent(from: entry, in: archive) {
                bookmarks.append(content)
            } else if lowercasedPath.hasSuffix(Constants.jsonExtension),
                      featureFlagger.isFeatureOn(.autofillCreditCards),
                      let content = extractFileContent(from: entry, in: archive) {
                if isPaymentCardsJSON(content) {
                    creditCards.append(content)
                }
            }
        }

        return Contents(passwords: passwords, bookmarks: bookmarks, creditCards: creditCards)
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

    private func isPaymentCardsJSON(_ content: String) -> Bool {
        // Quick validation to ensure this is a payment cards JSON
        guard let data = content.data(using: .utf8) else {
            Logger.autofill.debug("Failed to convert json content to data")
            return false
        }
        do {
            if let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                return jsonObject["payment_cards"] != nil
            }
        } catch {
            Logger.autofill.debug("Failed to parse JSON: \(error.localizedDescription)")
        }
        return false
    }
}
