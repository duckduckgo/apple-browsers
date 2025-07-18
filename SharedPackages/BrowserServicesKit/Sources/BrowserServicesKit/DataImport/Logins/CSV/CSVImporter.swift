//
//  CSVImporter.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import Common
import Foundation
import SecureStorage

final public class CSVImporter: DataImporter {

    public struct ColumnPositions {

        private enum Regex {
            // should end with "login" or "username"
            static let username = regex("(?:^|\\b|\\s|_)(?:login|username)$", .caseInsensitive)
            // should end with "password" or "pwd"
            static let password = regex("(?:^|\\b|\\s|_)(?:password|pwd)$", .caseInsensitive)
            // should end with "name" or "title"
            static let title = regex("(?:^|\\b|\\s|_)(?:name|title)$", .caseInsensitive)
            // should end with "url", "uri"
            static let url = regex("(?:^|\\b|\\s|_)(?:url|uri)$", .caseInsensitive)
            // should end with "notes" or "note"
            static let notes = regex("(?:^|\\b|\\s|_)(?:notes|note)$", .caseInsensitive)
        }

        static let rowFormatWithTitle = ColumnPositions(titleIndex: 0, urlIndex: 1, usernameIndex: 2, passwordIndex: 3)
        static let rowFormatWithoutTitle = ColumnPositions(titleIndex: nil, urlIndex: 0, usernameIndex: 1, passwordIndex: 2)

        let maximumIndex: Int

        public let titleIndex: Int?
        public let urlIndex: Int?

        public let usernameIndex: Int
        public let passwordIndex: Int

        let notesIndex: Int?

        let isZohoVault: Bool

        init(titleIndex: Int?, urlIndex: Int?, usernameIndex: Int, passwordIndex: Int, notesIndex: Int? = nil, isZohoVault: Bool = false) {
            self.titleIndex = titleIndex
            self.urlIndex = urlIndex
            self.usernameIndex = usernameIndex
            self.passwordIndex = passwordIndex
            self.notesIndex = notesIndex
            self.maximumIndex = max(titleIndex ?? -1, urlIndex ?? -1, usernameIndex, passwordIndex, notesIndex ?? -1)
            self.isZohoVault = isZohoVault
        }

        private enum Format {
            case general
            case zohoGeneral
            case zohoVault
        }

        public init?(csv: [[String]]) {
            guard csv.count > 1,
                  csv[1].count >= 3 else { return nil }
            var headerRow = csv[0]

            var format = Format.general

            let usernameIndex: Int
            if let idx = headerRow.firstIndex(where: { value in
                Regex.username.matches(in: value, range: value.fullRange).isEmpty == false
            }) {
                usernameIndex = idx
                headerRow[usernameIndex] = ""

            // Zoho
            } else if headerRow.first == "Password Name" {
                if let idx = csv[1].firstIndex(of: "SecretData") {
                    format = .zohoVault
                    usernameIndex = idx
                } else if csv[1].count == 7 {
                    format = .zohoGeneral
                    usernameIndex = 5
                } else {
                    return nil
                }
            } else {
                return nil
            }

            let passwordIndex: Int
            switch format {
            case .general:
                guard let idx = headerRow
                    .firstIndex(where: { !Regex.password.matches(in: $0, range: $0.fullRange).isEmpty }) else { return nil }
                passwordIndex = idx
                headerRow[passwordIndex] = ""

            case .zohoGeneral:
                passwordIndex = usernameIndex + 1
            case .zohoVault:
                passwordIndex = usernameIndex
            }

            let titleIndex = headerRow.firstIndex(where: { !Regex.title.matches(in: $0, range: $0.fullRange).isEmpty })
            titleIndex.map { headerRow[$0] = "" }

            let urlIndex = headerRow.firstIndex(where: { !Regex.url.matches(in: $0, range: $0.fullRange).isEmpty })
            urlIndex.map { headerRow[$0] = "" }

            let notesIndex = headerRow.firstIndex(where: { !Regex.notes.matches(in: $0, range: $0.fullRange).isEmpty })

            self.init(titleIndex: titleIndex,
                      urlIndex: urlIndex,
                      usernameIndex: usernameIndex,
                      passwordIndex: passwordIndex,
                      notesIndex: notesIndex,
                      isZohoVault: format == .zohoVault)
        }

        public init?(source: DataImport.Source) {
            switch source {
            case .onePassword7, .onePassword8:
                self.init(titleIndex: 3, urlIndex: 5, usernameIndex: 6, passwordIndex: 2)
            case .lastPass, .firefox, .edge, .chrome, .chromium, .coccoc, .brave, .opera, .operaGX,
                 .safari, .safariTechnologyPreview, .tor, .vivaldi, .yandex, .csv, .bookmarksHTML, .bitwarden:
                return nil
            }
        }

    }

    struct ImportError: DataImportError {
        enum OperationType: Int {
            case cannotReadFile
        }

        var action: DataImportAction { .passwords }
        let type: OperationType
        let underlyingError: Error?

        var errorType: DataImport.ErrorType {
            .dataCorrupted
        }
    }

    private let fileURL: URL?
    private let csvContent: String?
    private let loginImporter: LoginImporter
    private let defaultColumnPositions: ColumnPositions?
    private let secureVaultReporter: SecureVaultReporting
    private let tld: TLD

    public init(fileURL: URL?, csvContent: String? = nil, loginImporter: LoginImporter, defaultColumnPositions: ColumnPositions?, reporter: SecureVaultReporting, tld: TLD) {
        self.fileURL = fileURL
        self.csvContent = csvContent
        self.loginImporter = loginImporter
        self.defaultColumnPositions = defaultColumnPositions
        self.secureVaultReporter = reporter
        self.tld = tld
    }

    static func totalValidLogins(in fileURL: URL, defaultColumnPositions: ColumnPositions?, tld: TLD) -> Int {
        guard let fileContents = try? String(contentsOf: fileURL, encoding: .utf8) else { return 0 }

        let logins = extractLogins(from: fileContents, defaultColumnPositions: defaultColumnPositions, tld: tld) ?? []

        return logins.count
    }

    static public func totalValidLogins(in csvContent: String, defaultColumnPositions: ColumnPositions?, tld: TLD) -> Int {
        let logins = extractLogins(from: csvContent, defaultColumnPositions: defaultColumnPositions, tld: tld) ?? []
        return logins.count
    }

    public static func extractLogins(from fileContents: String, defaultColumnPositions: ColumnPositions? = nil, tld: TLD) -> [ImportedLoginCredential]? {
        guard let parsed = try? CSVParser().parse(string: fileContents) else { return nil }

        let urlMatcher = AutofillDomainNameUrlMatcher()

        let columnPositions: ColumnPositions?
        var startRow = 0
        if let autodetected = ColumnPositions(csv: parsed) {
            columnPositions = autodetected
            startRow = 1
        } else {
            columnPositions = defaultColumnPositions
        }

        guard parsed.indices.contains(startRow) else { return [] } // no data

        let result = parsed[startRow...].compactMap { row in
            columnPositions.read(row, tld: tld, urlMatcher: urlMatcher)
        }

        guard !result.isEmpty else {
            if parsed.filter({ !$0.isEmpty }).isEmpty {
                return [] // no data
            } else {
                return nil // error: could not parse data
            }
        }

        return result.removeDuplicates()
    }

    public var importableTypes: [DataImport.DataType] {
        return [.passwords]
    }

    public func importData(types: Set<DataImport.DataType>) -> DataImportTask {
        .detachedWithProgress { updateProgress in
            do {
                let result = try await self.importLoginsSync(updateProgress: updateProgress)
                return [.passwords: result]
            } catch is CancellationError {
            } catch {
                assertionFailure("Only CancellationError should be thrown here")
            }
            return [:]
        }
    }

    private func importLoginsSync(updateProgress: @escaping DataImportProgressCallback) async throws -> DataImportResult<DataImport.DataTypeSummary> {

        try updateProgress(.importingPasswords(numberOfPasswords: nil, fraction: 0.0))

        let fileContents: String
        do {
            if let csvContent = csvContent {
                fileContents = csvContent
            } else if let fileURL = fileURL {
                fileContents = try String(contentsOf: fileURL, encoding: .utf8)
            } else {
                throw ImportError(type: .cannotReadFile, underlyingError: nil)
            }
        } catch {
            return .failure(ImportError(type: .cannotReadFile, underlyingError: error))
        }

        do {
            try updateProgress(.importingPasswords(numberOfPasswords: nil, fraction: 0.2))

            let loginCredentials = try Self.extractLogins(from: fileContents, defaultColumnPositions: defaultColumnPositions, tld: tld) ?? {
                try Task.checkCancellation()
                throw LoginImporterError(error: nil, type: .malformedCSV)
            }()

            try updateProgress(.importingPasswords(numberOfPasswords: loginCredentials.count, fraction: 0.5))

            let summary = try loginImporter.importLogins(loginCredentials, reporter: secureVaultReporter) { count in
                try updateProgress(.importingPasswords(numberOfPasswords: count, fraction: 0.5 + 0.5 * (Double(count) / Double(loginCredentials.count))))
            }

            try updateProgress(.importingPasswords(numberOfPasswords: loginCredentials.count, fraction: 1.0))

            return .success(summary)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as any DataImportError {
            return .failure(error)
        } catch {
            return .failure(LoginImporterError(error: error))
        }
    }

}

extension ImportedLoginCredential {

    // Some browsers will export credentials with a header row. To detect this, the URL field on the first parsed row is checked whether it passes
    // the data detector test. If it doesn't, it's assumed to be a header row.
    fileprivate var isHeaderRow: Bool {
        let types: NSTextCheckingResult.CheckingType = [.link]

        guard let detector = try? NSDataDetector(types: types.rawValue),
              let url, !url.isEmpty else { return false }

        if detector.numberOfMatches(in: url, options: [], range: url.fullRange) > 0 {
            return false
        }

        return true
    }

}

extension CSVImporter.ColumnPositions {

    func read(_ row: [String], tld: TLD, urlMatcher: AutofillDomainNameUrlMatcher) -> ImportedLoginCredential? {
        let username: String
        let password: String

        if isZohoVault {
            // cell contents:
            // SecretType:Web Account
            // User Name:username
            // Password:password
            guard let lines = row[safe: usernameIndex]?.components(separatedBy: "\n"),
                  let usernameLine = lines.first(where: { $0.hasPrefix("User Name:") }),
                  let passwordLine = lines.first(where: { $0.hasPrefix("Password:") }) else { return nil }

            username = usernameLine.dropping(prefix: "User Name:")
            password = passwordLine.dropping(prefix: "Password:")

        } else if let user = row[safe: usernameIndex],
                  let pass = row[safe: passwordIndex] {

            username = user
            password = pass
        } else {
            return nil
        }

        var url: String? = row[safe: urlIndex ?? -1]
        var eTldPlusOne: String?

        if let urlString = url {
            url = urlMatcher.normalizeUrlForWeb(urlString)
            if let normalizedUrl = url {
                eTldPlusOne = urlMatcher.extractTLD(domain: URL(string: normalizedUrl)?.host ?? normalizedUrl, tld: tld) ?? normalizedUrl
            }
        }

        return ImportedLoginCredential(title: row[safe: titleIndex ?? -1],
                                       url: url,
                                       eTldPlusOne: eTldPlusOne,
                                       username: username,
                                       password: password,
                                       notes: row[safe: notesIndex ?? -1])

    }

}

extension CSVImporter.ColumnPositions? {

    func read(_ row: [String], tld: TLD, urlMatcher: AutofillDomainNameUrlMatcher) -> ImportedLoginCredential? {
        let columnPositions = self ?? [
            .rowFormatWithTitle,
            .rowFormatWithoutTitle
        ].first(where: {
            row.count > $0.maximumIndex
        })

        return columnPositions?.read(row, tld: tld, urlMatcher: urlMatcher)
    }

}

extension Array where Element == ImportedLoginCredential {

    func removeDuplicates() -> [ImportedLoginCredential] {
        // First, group credentials by their identifying key
        var credentialGroups: [String: [ImportedLoginCredential]] = [:]

        forEach { credential in
            // special handling for titles with Safari format e.g. "example.com (username)"
            let title = titleMatchesSafariFormat(for: credential) ? "SAFARI_TITLE" : credential.title ?? ""
            let key = "\(credential.eTldPlusOne ?? "")|\(title)|\(credential.username)|\(credential.password)|\(credential.notes ?? "")"

            if credentialGroups[key] == nil {
                credentialGroups[key] = []
            }
            credentialGroups[key]?.append(credential)
        }

        var uniqueCredentials: [ImportedLoginCredential] = []

        // Process each group
        for (_, credentials) in credentialGroups {
            // Only process as duplicates if we have multiple credentials with the exact same key
            if credentials.count > 1 {
                // Among the duplicates, select the one with the highest level TLD
                if let selectedCredential = selectPreferredCredential(from: credentials) {
                    uniqueCredentials.append(selectedCredential)
                }
            } else if let singleCredential = credentials.first {
                // If there's only one credential with this key, it's automatically unique
                uniqueCredentials.append(singleCredential)
            }
        }

        return uniqueCredentials
    }

    private func selectPreferredCredential(from credentials: [ImportedLoginCredential]) -> ImportedLoginCredential? {
        guard !credentials.isEmpty else { return nil }

        // If there's only one credential, return it
        if credentials.count == 1 {
            return credentials[0]
        }

        // First, try to find a credential without subdomains (e.g. site.com or site.co.uk)
        if let noSubdomainCredential = credentials.first(where: { credential in
            guard let url = credential.url, let eTldPlusOne = credential.eTldPlusOne else { return false }
            // The URL should match the TLD exactly (meaning it's the base domain without subdomains)
            return url == eTldPlusOne
        }) {
            return noSubdomainCredential
        }

        // Look for www subdomain if no bare domain exists
        if let wwwCredential = credentials.first(where: { credential in
            guard let url = credential.url, let eTldPlusOne = credential.eTldPlusOne else { return false }
            let components = url.split(separator: ".")
            // Check first component is www AND rest matches TLD
            return components.first == "www" && components.dropFirst().joined(separator: ".") == eTldPlusOne
        }) {
            return wwwCredential
        }

        // If neither bare domain nor www exists, sort remaining by:
        // 1. Number of segments (fewer is better)
        // 2. Alphabetically by domain
        return credentials.min { credential1, credential2 in
            let segments1 = getDomainSegments(from: credential1.url)
            let segments2 = getDomainSegments(from: credential2.url)

            if segments1 != segments2 {
                return segments1 < segments2
            }

            // If segment counts are equal, compare URLs alphabetically
            let url1 = credential1.url ?? ""
            let url2 = credential2.url ?? ""
            return url1 < url2
        }
    }

    private func getDomainSegments(from url: String?) -> Int {
        guard let url = url else { return Int.max }
        return url.split(separator: ".").count
    }

    private func titleMatchesSafariFormat(for credential: ImportedLoginCredential) -> Bool {
       guard let title = credential.title, let url = credential.url else { return false }

       let components = title.components(separatedBy: " (")
       guard components.count == 2,
             components[1].hasSuffix(")"),
             let username = components[1].dropLast().toString else {
           return false
       }

       return url.contains(components[0]) && username == credential.username
   }

}

extension StringProtocol {
   var toString: String? { String(self) }
}
