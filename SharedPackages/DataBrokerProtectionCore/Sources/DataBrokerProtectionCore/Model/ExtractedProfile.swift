//
//  ExtractedProfile.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

public struct ProfileSelector: Codable, Sendable {
    let selector: String?
    let findElements: Bool?
    let afterText: String?
    let beforeText: String?
    let separator: String?
    let identifier: String?
    let identifierType: String?
}

public struct ExtractProfileSelectors: Codable, Sendable {
    let name: ProfileSelector?
    let alternativeNamesList: ProfileSelector?
    let addressFull: ProfileSelector?
    let addressCityStateList: ProfileSelector?
    let addressCityState: ProfileSelector?
    let phone: ProfileSelector?
    let phoneList: ProfileSelector?
    let relativesList: ProfileSelector?
    let profileUrl: ProfileSelector?
    let reportId: String?
    let age: ProfileSelector?

    enum CodingKeys: CodingKey {
        case name
        case alternativeNamesList
        case addressFull
        case addressCityStateList
        case addressCityState
        case phone
        case phoneList
        case relativesList
        case profileUrl
        case reportId
        case age
    }
}

/// Open map of config-defined fields with no dedicated property on the model. C-S-S extracts these
/// during a scan and reads them back during opt out; we store and forward them verbatim, so a new
/// broker field can ship as a config change alone. String values only, omitted when empty.
public typealias ProfileExtras = [String: String]

public struct AddressCityState: Codable, Hashable, Sendable {
    public let city: String
    public let state: String
    public let extras: ProfileExtras?

    public init(city: String, state: String, extras: ProfileExtras? = nil) {
        self.city = city
        self.state = state
        self.extras = extras
    }

    public var fullAddress: String {
        "\(city), \(state)"
    }

    /// Extras are opaque passthrough data, so two addresses for the same place remain equal
    /// regardless of which extras the broker config happened to scrape for each.
    public static func == (lhs: AddressCityState, rhs: AddressCityState) -> Bool {
        lhs.city == rhs.city && lhs.state == rhs.state
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(city)
        hasher.combine(state)
    }
}

public struct ExtractedProfile: Codable, Sendable {
    public let id: Int64?
    public let name: String?
    public let alternativeNames: [String]?
    public let addressFull: String?
    public let addresses: [AddressCityState]?
    public let phoneNumbers: [String]?
    public let relatives: [String]?
    public let profileUrl: String?
    public let reportId: String?
    public let age: String?
    public var email: String?
    public var removedDate: Date?
    public let fullName: String?
    public let identifier: String?
    public let extras: ProfileExtras?

    enum CodingKeys: CodingKey {
        case id
        case name
        case alternativeNames
        case addressFull
        case addresses
        case phoneNumbers
        case relatives
        case profileUrl
        case reportId
        case age
        case email
        case removedDate
        case fullName
        case identifier
        case extras
    }

    public init(id: Int64? = nil,
                name: String? = nil,
                alternativeNames: [String]? = nil,
                addressFull: String? = nil,
                addresses: [AddressCityState]? = nil,
                phoneNumbers: [String]? = nil,
                relatives: [String]? = nil,
                profileUrl: String? = nil,
                reportId: String? = nil,
                age: String? = nil,
                email: String? = nil,
                removedDate: Date? = nil,
                identifier: String? = nil,
                extras: ProfileExtras? = nil) {
        self.id = id
        self.name = name
        self.alternativeNames = alternativeNames
        self.addressFull = addressFull
        self.addresses = addresses
        self.phoneNumbers = phoneNumbers
        self.relatives = relatives
        self.profileUrl = profileUrl
        self.reportId = reportId
        self.age = age
        self.email = email
        self.removedDate = removedDate
        self.fullName = name
        self.identifier = identifier
        self.extras = extras
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int64.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        alternativeNames = try container.decodeIfPresent([String].self, forKey: .alternativeNames)
        addressFull = try container.decodeIfPresent(String.self, forKey: .addressFull)
        addresses = try container.decodeIfPresent([AddressCityState].self, forKey: .addresses)
        phoneNumbers = try container.decodeIfPresent([String].self, forKey: .phoneNumbers)
        relatives = try container.decodeIfPresent([String].self, forKey: .relatives)
        profileUrl = try container.decodeIfPresent(String.self, forKey: .profileUrl)
        reportId = try container.decodeIfPresent(String.self, forKey: .reportId)
        age = try container.decodeIfPresent(String.self, forKey: .age)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        removedDate = try container.decodeIfPresent(Date.self, forKey: .removedDate)
        fullName = try container.decodeIfPresent(String.self, forKey: .fullName)
        extras = try container.decodeIfPresent(ProfileExtras.self, forKey: .extras)
        if let identifier = try container.decodeIfPresent(String.self, forKey: .identifier) {
            self.identifier = identifier
        } else {
            self.identifier = profileUrl
        }
    }

    func merge(with profile: ProfileQuery) -> ExtractedProfile {
        ExtractedProfile(
            id: self.id,
            name: self.name ?? profile.fullName,
            alternativeNames: self.alternativeNames,
            addressFull: self.addressFull,
            addresses: self.addresses,
            phoneNumbers: self.phoneNumbers,
            relatives: self.relatives,
            profileUrl: self.profileUrl,
            reportId: self.reportId,
            age: self.age ?? String(profile.age),
            email: self.email,
            removedDate: self.removedDate,
            identifier: self.identifier,
            extras: self.extras
        )
    }

    /*
     Matching records are:
     1/ Completely identical records (same name, addresses, ages, etc)
     2/ Records that overlap completely (record A has all the data of record B, but might have
        extra information as well (e.g. an extra address, a middle name where record B doesn't)
        I.e. B is a subset of A, or vice versa
     However, we ignore some of the properties
     So, basically age == age, we ignore phone numbers and email, and then everything else one should be a subset of the other
     */
    func doesMatchExtractedProfile(_ extractedProfile: ExtractedProfile) -> Bool {
        if age != extractedProfile.age {
            return false
        }

        if name != extractedProfile.name {
            return false
        }

        if !(alternativeNames ?? []).isASubSetOrSuperSetOf(extractedProfile.alternativeNames ?? []) {
            return false
        }

        if !(addresses ?? []).isASubSetOrSuperSetOf(extractedProfile.addresses ?? []) {
            return false
        }

        if !(relatives ?? []).isASubSetOrSuperSetOf(extractedProfile.relatives ?? []) {
            return false
        }

        return true
    }
}

extension ExtractedProfile {
    public func with(id: Int64) -> ExtractedProfile {
        ExtractedProfile(id: id,
                         name: name,
                         alternativeNames: alternativeNames,
                         addressFull: addressFull,
                         addresses: addresses,
                         phoneNumbers: phoneNumbers,
                         relatives: relatives,
                         profileUrl: profileUrl,
                         reportId: reportId,
                         age: age,
                         email: email,
                         removedDate: removedDate,
                         identifier: identifier,
                         extras: extras)
    }

    /// Returns this stored record brought up to date with a re-scrape of the same profile, keeping
    /// the state the broker doesn't own (`id`, `email`, `removedDate`).
    ///
    /// Extras the re-scrape didn't return keep their stored value, so a broker changing its markup
    /// before we update the config doesn't strip fields the pending opt out still needs.
    func refreshed(from scrapedProfile: ExtractedProfile) -> ExtractedProfile {
        ExtractedProfile(id: id,
                         name: scrapedProfile.name,
                         alternativeNames: scrapedProfile.alternativeNames,
                         addressFull: scrapedProfile.addressFull,
                         addresses: scrapedProfile.addresses?.map { $0.mergingExtras(storedIn: addresses) },
                         phoneNumbers: scrapedProfile.phoneNumbers,
                         relatives: scrapedProfile.relatives,
                         profileUrl: scrapedProfile.profileUrl,
                         reportId: scrapedProfile.reportId,
                         age: scrapedProfile.age,
                         email: email,
                         removedDate: removedDate,
                         identifier: identifier,
                         extras: extras.merging(scrapedProfile.extras))
    }
}

private extension AddressCityState {
    func mergingExtras(storedIn storedAddresses: [AddressCityState]?) -> AddressCityState {
        let storedExtras = storedAddresses?.first { $0 == self }?.extras
        return AddressCityState(city: city, state: state, extras: storedExtras.merging(extras))
    }
}

private extension Optional where Wrapped == ProfileExtras {
    func merging(_ scrapedExtras: ProfileExtras?) -> ProfileExtras? {
        guard let storedExtras = self else { return scrapedExtras }
        guard let scrapedExtras else { return storedExtras }
        return storedExtras.merging(scrapedExtras) { _, scrapedValue in scrapedValue }
    }
}

extension ExtractedProfile: Equatable {
    public static func == (lhs: ExtractedProfile, rhs: ExtractedProfile) -> Bool {
        lhs.name == rhs.name
    }
}

private extension Sequence where Element: Hashable {
    func isASubSetOrSuperSetOf<Settable>(_ sequence: Settable) -> Bool where Settable: Sequence, Element == Settable.Element {
        let setA = Set(self)
        let setB = Set(sequence)
        return setA.isSubset(of: setB) || setB.isSubset(of: setA)
    }
}
