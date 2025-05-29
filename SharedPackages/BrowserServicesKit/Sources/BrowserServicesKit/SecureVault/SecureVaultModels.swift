//
//  SecureVaultModels.swift
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

import Foundation
import Common

/// The models used by the secure vault.
///
/// Future models include:
///  * Generated Password - a password generated for a site, but not used yet
///  * Duck Address - a duck address used on a partcular site
public struct SecureVaultModels {

    /// A username and password was saved for a given site.  Password is stored seperately so that
    ///  it can be queried independently.
    public struct WebsiteCredentials {

        public var account: WebsiteAccount
        public var password: Data?

        public init(account: WebsiteAccount, password: Data?) {
            self.account = account
            self.password = password
        }
    }

    /// The username associated with a domain.
    public struct WebsiteAccount: Equatable, Decodable {

        public var id: String?
        public var title: String?
        public var username: String?
        public var domain: String?
        public var signature: String?
        public var notes: String?
        public let created: Date
        public let lastUpdated: Date
        public var lastUsed: Date?

        public enum CommonTitlePatterns: String, CaseIterable {
            /*
             Matches the following title patterns
             duck.com (test@duck.com) -> duck.com
             signin.duck.com -> signin.duck.com
             signin.duck.com (test@duck.com.co) -> signin.duck.com
             https://signin.duck.com -> signin.duck.com
             https://signin.duck.com (test@duck.com.co) -> signin.duck.com
             (See SecureVaultModelTests.testPatternMatchedTitle() for more examples)
             */
            case hostFromTitle = #"^(?:https?:\/\/?)?(?:www\.)?([^\s\/\?]+?\.[^\s\/\?]+)(?=\s*\(|\s*\/|\s*\?|$)"#
        }

        public init(title: String? = nil, username: String?, domain: String?, signature: String? = nil, notes: String? = nil, lastUsed: Date? = nil) {
            self.id = nil
            self.title = title
            self.username = username
            self.domain = domain
            self.signature = signature
            self.notes = notes
            self.created = Date()
            self.lastUpdated = self.created
            self.lastUsed = lastUsed
        }

        public init(id: String,
                    title: String? = nil,
                    username: String?,
                    domain: String?,
                    signature: String? = nil,
                    notes: String? = nil,
                    created: Date,
                    lastUpdated: Date,
                    lastUsed: Date? = nil) {
            self.id = id
            self.title = title
            self.username = username
            self.domain = domain
            self.signature = signature
            self.notes = notes
            self.created = created
            self.lastUpdated = lastUpdated
            self.lastUsed = lastUsed
        }

        private var tld: String {
            guard let domain else {
                return ""
            }
            let components = domain.split(separator: ".")
            if components.count >= 2 {
                let tldIndex = components.count - 2
                let baseTLD = components[tldIndex]
                return String(baseTLD)
            }
            return ""
        }

        // djb2 hash from the account
        var hashValue: Data {
            var hash = 5381
            for char in "\(username ?? "")\(tld)".utf8 {
                hash = ((hash << 5) &+ hash) &+ Int(char)
            }
            let hashString = String(format: "%02x", hash)
            guard let hash = hashString.data(using: .utf8) else {
                return Data()
            }
            return hash
        }

        public func name(tld: TLD, autofillDomainNameUrlMatcher: AutofillDomainNameUrlMatcher) -> String {
            if let title = self.title, !title.isEmpty {
                return title
            } else {
                return autofillDomainNameUrlMatcher.normalizeUrlForWeb(domain ?? "")
            }
        }

        public func firstTLDLetter(tld: TLD, autofillDomainNameUrlSort: AutofillDomainNameUrlSort) -> String? {
            return autofillDomainNameUrlSort.firstCharacterForGrouping(self, tld: tld)?.uppercased()
        }

        public func patternMatchedTitle() -> String {
            guard let title = title, !title.isEmpty else {
                return ""
            }

            for pattern in SecureVaultModels.WebsiteAccount.CommonTitlePatterns.allCases {
                if let regex = try? NSRegularExpression(pattern: pattern.rawValue, options: [.caseInsensitive]) {
                    let matches = regex.matches(in: title, options: [], range: NSRange(title.startIndex..., in: title))

                    if let firstMatch = matches.first,
                       let range = Range(firstMatch.range(at: 1), in: title) { // range(at: 1) gets the first capturing group
                        let host = String(title[range]).lowercased()

                        // Drop the title if equal to the domain
                        if host.caseInsensitiveCompare(domain ?? "") == .orderedSame {
                            return ""
                        }

                        return host.isEmpty ? "" : host
                    }
                }
            }

            // If no pattern matched, return the original title
            return title
        }

    }

    public struct NeverPromptWebsites {
        public var id: Int64?
        public var domain: String

        public init(id: Int64? = nil,
                    domain: String) {
            self.id = id
            self.domain = domain
        }

    }

    public struct CreditCard {

        private enum Constants {
            static let creditCardsKey = "creditCards"
            static let cardNumberKey = "cardNumber"
            static let cardNameKey = "cardName"
            static let cardSecurityCodeKey = "cardSecurityCode"
            static let expirationMonthKey = "expirationMonth"
            static let expirationYearKey = "expirationYear"
        }

        public var id: Int64?
        public var title: String
        public let created: Date
        public let lastUpdated: Date

        public var cardNumberData: Data
        public var cardSuffix: String // Stored as L1 data, used when presenting a list of cards in the Autofill UI
        public var cardholderName: String?
        public var cardSecurityCode: String?
        public var expirationMonth: Int?
        public var expirationYear: Int?

        public var cardNumber: String {
            return String(data: cardNumberData, encoding: .utf8)!
        }

        public var displayName: String {
            let type = CreditCardValidation.type(for: cardNumber)
            return "\(type.displayName) (\(cardSuffix))"
        }
        
        public var displayCardType: String {
            let type = CreditCardValidation.type(for: cardNumber)
            return type.displayCardType
        }

        static func suffix(from cardNumber: String) -> String {
            let trimmedCardNumber = cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmedCardNumber.suffix(4))
        }

        public init(id: Int64? = nil,
                    title: String? = nil,
                    cardNumber: String,
                    cardholderName: String?,
                    cardSecurityCode: String?,
                    expirationMonth: Int?,
                    expirationYear: Int?) {
            self.id = id
            self.title = title ?? ""
            self.created = Date()
            self.lastUpdated = self.created

            self.cardNumberData = cardNumber.data(using: .utf8)!
            self.cardSuffix = Self.suffix(from: cardNumber)
            self.cardholderName = cardholderName
            self.cardSecurityCode = cardSecurityCode
            self.expirationMonth = expirationMonth
            self.expirationYear = expirationYear
        }

        public init?(autofillDictionary: [String: Any]) {
            guard let creditCardsDictionary = autofillDictionary[Constants.creditCardsKey] as? [String: Any] else {
                return nil
            }

            self.init(creditCardsDictionary: creditCardsDictionary)
        }

        public init?(creditCardsDictionary: [String: Any]) {
            guard let cardNumber = creditCardsDictionary[Constants.cardNumberKey] as? String else {
                return nil
            }

            self.init(id: nil,
                      title: nil,
                      cardNumber: cardNumber,
                      cardholderName: creditCardsDictionary[Constants.cardNameKey] as? String,
                      cardSecurityCode: creditCardsDictionary[Constants.cardSecurityCodeKey] as? String,
                      expirationMonth: Int(creditCardsDictionary[Constants.expirationMonthKey] as? String ?? ""),
                      expirationYear: Int(creditCardsDictionary[Constants.expirationYearKey] as? String ?? ""))
        }

    }

    public struct Note {

        public var id: Int64?
        public var title: String
        public let created: Date
        public let lastUpdated: Date

        public var associatedDomain: String?
        public var text: String {
            didSet {
                self.displayTitle = generateDisplayTitle()
                self.displaySubtitle = generateDisplaySubtitle()
            }
        }

        public init(title: String? = nil, associatedDomain: String? = nil, text: String) {
            self.id = nil
            self.title = title ?? ""
            self.created = Date()
            self.lastUpdated = self.created

            self.associatedDomain = associatedDomain
            self.text = text

            self.displayTitle = generateDisplayTitle()
            self.displaySubtitle = generateDisplaySubtitle()
        }

        // Display Properties:

        public internal(set) var displayTitle: String?
        public internal(set) var displaySubtitle: String = ""

        /// If a note has a title, it will be used when displaying the note in the UI. If it doesn't have a title and it has body text, the first non-empty line of the body text
        /// will be used. If it doesn't have a title or body text, a placeholder string is used.
        internal func generateDisplayTitle() -> String? {
            guard title.isEmpty else {
                return title
            }

            // If a note doesn't have a title, the first non-empty line will be used instead.
            let noteLines = text.components(separatedBy: .newlines)
            return noteLines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        }

        /// If a note has a title, the first non-empty line of the note is used as the subtitle. If it doesn't have a title, the first non-empty line will be used as a title, so the
        /// second non-empty line will then be used as the subtitle. If there is no title or body text, an empty string is returned.
        internal func generateDisplaySubtitle() -> String {
            guard title.isEmpty else {
                return firstNonEmptyLine ?? ""
            }

            // The title is empty, so assume that the first non-empty line is used as the title, and find the second non-empty line instead.
            let noteLines = text.components(separatedBy: .newlines)
            var alreadyFoundFirstNonEmptyLine = false

            for line in noteLines where !line.isEmpty {
                if !alreadyFoundFirstNonEmptyLine {
                    alreadyFoundFirstNonEmptyLine = true
                } else if alreadyFoundFirstNonEmptyLine {
                    return line
                }
            }

            return ""
        }

        private var firstNonEmptyLine: String? {
            let noteLines = text.components(separatedBy: .newlines)
            return noteLines.first(where: { !$0.isEmpty })
        }

    }

    public struct Identity {

        private static let mediumPersonNameComponentsFormatter: PersonNameComponentsFormatter = {
            let nameFormatter = PersonNameComponentsFormatter()
            nameFormatter.style = .medium
            return nameFormatter
        }()

        private static let longPersonNameComponentsFormatter: PersonNameComponentsFormatter = {
            let nameFormatter = PersonNameComponentsFormatter()
            nameFormatter.style = .long
            return nameFormatter
        }()

        private var nameComponents: PersonNameComponents {
            var nameComponents = PersonNameComponents()

            nameComponents.givenName = firstName
            nameComponents.middleName = middleName
            nameComponents.familyName = lastName

            return nameComponents
        }

        public var formattedName: String {
            return Self.mediumPersonNameComponentsFormatter.string(from: nameComponents)
        }

        public var longFormattedName: String {
            return Self.longPersonNameComponentsFormatter.string(from: nameComponents)
        }

        var autofillEqualityName: String?
        var autofillEqualityAddressStreet: String?

        public var id: Int64?
        public var title: String
        public let created: Date
        public let lastUpdated: Date

        public var firstName: String? {
            didSet {
                autofillEqualityName = normalizedAutofillName()
            }
        }

        public var middleName: String? {
            didSet {
                autofillEqualityName = normalizedAutofillName()
            }
        }

        public var lastName: String? {
            didSet {
                autofillEqualityName = normalizedAutofillName()
            }
        }

        public var birthdayDay: Int?
        public var birthdayMonth: Int?
        public var birthdayYear: Int?

        public var addressStreet: String? {
            didSet {
                autofillEqualityAddressStreet = addressStreet?.autofillNormalized()
            }
        }

        public var addressStreet2: String?
        public var addressCity: String?
        public var addressProvince: String?
        public var addressPostalCode: String?

        /// ISO country code, e.g. `CA`
        public var addressCountryCode: String?

        public var homePhone: String?
        public var mobilePhone: String?
        public var emailAddress: String?

        public init() {
            self.init(id: nil, title: "", created: Date(), lastUpdated: Date())
        }

        public init(id: Int64? = nil,
                    title: String? = nil,
                    created: Date,
                    lastUpdated: Date,
                    firstName: String? = nil,
                    middleName: String? = nil,
                    lastName: String? = nil,
                    birthdayDay: Int? = nil,
                    birthdayMonth: Int? = nil,
                    birthdayYear: Int? = nil,
                    addressStreet: String? = nil,
                    addressStreet2: String? = nil,
                    addressCity: String? = nil,
                    addressProvince: String? = nil,
                    addressPostalCode: String? = nil,
                    addressCountryCode: String? = nil,
                    homePhone: String? = nil,
                    mobilePhone: String? = nil,
                    emailAddress: String? = nil) {
            self.id = id
            self.title = title ?? ""
            self.created = created
            self.lastUpdated = lastUpdated
            self.firstName = firstName
            self.middleName = middleName
            self.lastName = lastName
            self.birthdayDay = birthdayDay
            self.birthdayMonth = birthdayMonth
            self.birthdayYear = birthdayYear
            self.addressStreet = addressStreet
            self.addressStreet2 = addressStreet2
            self.addressCity = addressCity
            self.addressProvince = addressProvince
            self.addressPostalCode = addressPostalCode
            self.addressCountryCode = addressCountryCode
            self.homePhone = homePhone
            self.mobilePhone = mobilePhone
            self.emailAddress = emailAddress

            self.autofillEqualityName = normalizedAutofillName()
            self.autofillEqualityAddressStreet = addressStreet?.autofillNormalized()
        }

        public init?(autofillDictionary: [String: Any]) {
            guard let dictionary = autofillDictionary["identities"] as? [String: Any] else {
                return nil
            }

            self.init(identityDictionary: dictionary)
        }

        public init(identityDictionary: [String: Any]) {
            self.init(id: nil,
                      title: nil,
                      created: Date(),
                      lastUpdated: Date(),
                      firstName: identityDictionary["firstName"] as? String,
                      middleName: identityDictionary["middleName"] as? String,
                      lastName: identityDictionary["lastName"] as? String,
                      birthdayDay: identityDictionary["birthdayDay"] as? Int,
                      birthdayMonth: identityDictionary["birthdayMonth"] as? Int,
                      birthdayYear: identityDictionary["birthdayYear"] as? Int,
                      addressStreet: identityDictionary["addressStreet"] as? String,
                      addressStreet2: identityDictionary["addressStreet2"] as? String,
                      addressCity: identityDictionary["addressCity"] as? String,
                      addressProvince: identityDictionary["addressProvince"] as? String,
                      addressPostalCode: identityDictionary["addressPostalCode"] as? String,
                      addressCountryCode: identityDictionary["addressCountryCode"] as? String,
                      homePhone: identityDictionary["phone"] as? String,
                      mobilePhone: nil,
                      emailAddress: identityDictionary["emailAddress"] as? String)
        }

        func normalizedAutofillName() -> String {
            let nameString = (firstName ?? "") + (middleName ?? "") + (lastName ?? "")
            return nameString.autofillNormalized()
        }

    }

    public struct CredentialsProvider {

        public enum Name: String {
            case duckduckgo
            case bitwarden
        }

        public var name: Name
        public var locked: Bool

    }

}

// MARK: - Autofill Equality

protocol SecureVaultAutofillEquatable {

    func hasAutofillEquality(comparedTo object: Self) -> Bool

}

extension SecureVaultModels.Identity: SecureVaultAutofillEquatable {

    func hasAutofillEquality(comparedTo otherIdentity: SecureVaultModels.Identity) -> Bool {
        let hasNameEquality = self.autofillEqualityName == otherIdentity.autofillEqualityName
        let hasAddressEquality = self.autofillEqualityAddressStreet == otherIdentity.autofillEqualityAddressStreet

        return hasNameEquality && hasAddressEquality
    }

}

extension SecureVaultModels.CreditCard: SecureVaultAutofillEquatable {

    func hasAutofillEquality(comparedTo object: Self) -> Bool {
        if self.cardNumber.autofillNormalized() == object.cardNumber.autofillNormalized() {
            return true
        }

        return false
    }

}

// MARK: - WebsiteAccount Array extensions
extension Array where Element == SecureVaultModels.WebsiteAccount {

    public func sortedForDomain(_ targetDomain: String, tld: TLD, removeDuplicates: Bool = false, urlMatcher: AutofillDomainNameUrlMatcher = AutofillDomainNameUrlMatcher()) -> [SecureVaultModels.WebsiteAccount] {

        guard let targetTLD = urlMatcher.extractTLD(domain: targetDomain, tld: tld) else {
            return []
        }

        typealias AccountGroup = [String: [SecureVaultModels.WebsiteAccount]]

        let accountGroups = self.reduce(into: AccountGroup()) { result, account in
            if account.domain == targetDomain {
                result["exactMatches", default: []].append(account)
            } else if account.domain == targetTLD || account.domain == "www.\(targetTLD)" {
                result["tldMatches", default: []].append(account)
            } else {
                result["other", default: []].append(account)
            }
        }

        let exactMatches = accountGroups["exactMatches"]?.sorted { compareAccount( $0, $1 ) } ?? []
        let tldMatches = accountGroups["tldMatches"]?.sorted { compareAccount( $0, $1 ) } ?? []
        let other = accountGroups["other"]?.sorted { compareAccount( $0, $1 ) } ?? []
        let result = exactMatches + tldMatches + other

        return (removeDuplicates ? result.removeDuplicates() : result).filter { $0.domain?.isEmpty == false }
    }

    public func sortedAndDeduplicated(tld: TLD, urlMatcher: AutofillDomainNameUrlMatcher = AutofillDomainNameUrlMatcher()) -> [SecureVaultModels.WebsiteAccount] {

        let groupedBySignature = Dictionary(grouping: self) { $0.signature ?? "" }

        let deduplicatedAccounts = groupedBySignature
            .flatMap { (signature, accounts) -> [SecureVaultModels.WebsiteAccount] in

                // no need to dedupe accounts with no signature, or where a signature group only has 1 account
                if signature.isEmpty || accounts.count == 1 {
                    return accounts
                }

                // This set is required as accounts can have duplicate signatures but different domains if the domain has a SLD + TLD like `co.uk`
                // e.g. accounts with the same username & password for `example.co.uk` and `domain.co.uk` will have the same signature
                var uniqueHosts = Set<String>()

                for account in accounts {
                    if let domain = account.domain,
                       let urlComponents = urlMatcher.normalizeSchemeForAutofill(domain),
                       let host = urlComponents.eTLDplus1(tld: tld) ?? urlComponents.host {
                        uniqueHosts.insert(host)
                    }
                }

                return uniqueHosts.flatMap { host in
                    accounts.sortedForDomain(host, tld: tld, removeDuplicates: true)
                }
            }

        return deduplicatedAccounts.sorted { compareAccount($0, $1) }
    }

    // Last Used > Last Updated > Alphabetical Domain > Alphabetical Username > Empty Usernames
    private func compareAccount(_ account1: SecureVaultModels.WebsiteAccount, _ account2: SecureVaultModels.WebsiteAccount) -> Bool {
        let username1 = account1.username ?? ""
        let username2 = account2.username ?? ""

        if !username1.isEmpty && username2.isEmpty {
            return true
        }

        if username1.isEmpty && !username2.isEmpty {
            return false
        }

        if let lastUsedComparisonResult = compareByLastUsed(account1: account1, account2: account2) {
            return lastUsedComparisonResult
        }

        if account1.lastUpdated.withoutTime != account2.lastUpdated.withoutTime {
            return account1.lastUpdated.withoutTime > account2.lastUpdated.withoutTime
        }

        if let domainComparisonResult = compareByDomain(domain1: account1.domain ?? "", domain2: account2.domain ?? "") {
            return domainComparisonResult
        }

        if !username1.isEmpty && !username2.isEmpty {
            return username1 < username2
        }

        return false
    }

    private func compareByLastUsed(account1: SecureVaultModels.WebsiteAccount, account2: SecureVaultModels.WebsiteAccount) -> Bool? {
        if account1.lastUsed != nil && account2.lastUsed == nil {
            return true
        } else if account1.lastUsed == nil && account2.lastUsed != nil {
            return false
        } else if let lastUsed1 = account1.lastUsed, let lastUsed2 = account2.lastUsed {
            if lastUsed1 != lastUsed2 {
                return lastUsed1 > lastUsed2
            }
        }

        return nil
    }

    private func compareByDomain(domain1: String, domain2: String) -> Bool? {
        if !domain1.isEmpty && domain2.isEmpty {
            return true
        }

        if domain1.isEmpty && !domain2.isEmpty {
            return false
        }

        if domain1 != domain2 {
            return domain1 < domain2
        }

        return nil
    }

    // Receives a sorted Array, and removes duplicate based signatures
    private func removeDuplicates() -> [SecureVaultModels.WebsiteAccount] {
        return self.reduce(into: [SecureVaultModels.WebsiteAccount]()) { result, account in
            if !result.contains(where: { $0.signature == account.signature && $0.signature != nil }) {
                result.append(account)
            }
        }
    }

}

private extension Date {

    // Removes time from date
    var withoutTime: Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: self)
        return calendar.date(from: dateComponents) ?? self
    }
}
