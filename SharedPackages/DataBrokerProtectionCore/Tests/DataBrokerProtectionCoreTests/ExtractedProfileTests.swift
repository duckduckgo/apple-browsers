//
//  ExtractedProfileTests.swift
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

import XCTest
import Foundation
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class ExtractedProfileTests: XCTestCase {

    func testWhenExtractedProfileDoesNotHaveAName_thenMergeAddsProfileQueryNameToIt() {
        let profileQuery = ProfileQuery(firstName: "John", lastName: "Doe", city: "Los Angeles", state: "CA", birthYear: 1980)
        let extractedProfile = ExtractedProfile()

        let sut = extractedProfile.merge(with: profileQuery)

        XCTAssertEqual(sut.name, "John Doe")
    }

    func testWhenExtractedProfileHasAName_thenMergeLeavesExtractedProfileName() {
        let profileQuery = ProfileQuery(firstName: "John", lastName: "Doe", city: "Los Angeles", state: "CA", birthYear: 1980)
        let extractedProfile = ExtractedProfile(name: "Ben Smith")

        let sut = extractedProfile.merge(with: profileQuery)

        XCTAssertEqual(sut.name, "Ben Smith")
    }

    func testWhenExtractedProfileDoesNotHaveAge_thenMergeAddsProfileQueryAgeToIt() {
        let birthYear = 1980
        let profileQuery = ProfileQuery(firstName: "John", lastName: "Doe", city: "Los Angeles", state: "CA", birthYear: birthYear)
        let extractedProfile = ExtractedProfile()

        let currentYear = Calendar.current.component(.year, from: Date())
        let age = currentYear - birthYear

        let sut = extractedProfile.merge(with: profileQuery)

        XCTAssertEqual(sut.age, "\(age)")
    }

    func testWhenExtractedProfileHasAge_thenMergeLeavesExtractedProfileAge() {
        let profileQuery = ProfileQuery(firstName: "John", lastName: "Doe", city: "Los Angeles", state: "CA", birthYear: 1980)
        let extractedProfile = ExtractedProfile(age: "52")

        let sut = extractedProfile.merge(with: profileQuery)

        XCTAssertEqual(sut.age, "52")
    }

    func testWhenExtractedProfileHasExtras_thenMergeKeepsThem() {
        let profileQuery = ProfileQuery(firstName: "John", lastName: "Doe", city: "Los Angeles", state: "CA", birthYear: 1980)
        let extractedProfile = ExtractedProfile(addresses: [AddressCityState(city: "Springfield", state: "IL", extras: ["zip": "62701"])],
                                                extras: ["county": "Sangamon"])

        let sut = extractedProfile.merge(with: profileQuery)

        XCTAssertEqual(sut.extras, ["county": "Sangamon"])
        XCTAssertEqual(sut.addresses?.first?.extras, ["zip": "62701"])
    }

    func testWhenExtractedProfileHasExtras_thenWithIdKeepsThem() {
        let extractedProfile = ExtractedProfile(addresses: [AddressCityState(city: "Springfield", state: "IL", extras: ["zip": "62701"])],
                                                extras: ["county": "Sangamon"])

        let sut = extractedProfile.with(id: 1)

        XCTAssertEqual(sut.extras, ["county": "Sangamon"])
        XCTAssertEqual(sut.addresses?.first?.extras, ["zip": "62701"])
    }

    // MARK: - Extras coding

    func testWhenExtractResponseContainsExtras_thenTheyAreDecodedAtProfileAndAddressLevel() throws {
        let json = """
            [
                {
                    "name": "Jane Smith",
                    "age": "38",
                    "addresses": [
                        { "city": "Springfield", "state": "IL", "extras": { "street": "100 Sample Dr", "zip": "62701" } }
                    ],
                    "profileUrl": "https://broker.example/id/jane-smith",
                    "identifier": "https://broker.example/id/jane-smith",
                    "extras": { "county": "Sangamon" }
                }
            ]
            """

        let profiles = try JSONDecoder().decode([ExtractedProfile].self, from: Data(json.utf8))

        XCTAssertEqual(profiles.first?.extras, ["county": "Sangamon"])
        XCTAssertEqual(profiles.first?.addresses?.first?.extras, ["street": "100 Sample Dr", "zip": "62701"])
    }

    func testWhenExtractResponseOmitsExtras_thenTheyDecodeAsNil() throws {
        let json = """
            [{ "name": "Jane Smith", "addresses": [{ "city": "Springfield", "state": "IL" }] }]
            """

        let profiles = try JSONDecoder().decode([ExtractedProfile].self, from: Data(json.utf8))

        XCTAssertNil(profiles.first?.extras)
        XCTAssertNil(profiles.first?.addresses?.first?.extras)
    }

    func testWhenExtrasContainANonStringValue_thenDecodingFails() {
        let json = """
            [{ "name": "Jane Smith", "extras": { "county": 42 } }]
            """

        XCTAssertThrowsError(try JSONDecoder().decode([ExtractedProfile].self, from: Data(json.utf8)))
    }

    func testWhenProfileHasNoExtras_thenTheKeyIsOmittedFromTheEncodedProfile() throws {
        let encoded = try JSONEncoder().encode(ExtractedProfile(name: "Jane Smith"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertNil(object["extras"])
    }

    func testWhenProfileHasExtras_thenTheyAreEncodedForFillForm() throws {
        let profile = ExtractedProfile(name: "Jane Smith",
                                       addresses: [AddressCityState(city: "Springfield", state: "IL", extras: ["zip": "62701"])],
                                       extras: ["county": "Sangamon"])

        let encoded = try JSONEncoder().encode(profile)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let address = try XCTUnwrap((object["addresses"] as? [[String: Any]])?.first)

        XCTAssertEqual(object["extras"] as? [String: String], ["county": "Sangamon"])
        XCTAssertEqual(address["extras"] as? [String: String], ["zip": "62701"])
    }

    func testWhenAddressesDifferOnlyByExtras_thenTheyAreEqual() {
        let address = AddressCityState(city: "Springfield", state: "IL")
        let addressWithExtras = AddressCityState(city: "Springfield", state: "IL", extras: ["zip": "62701"])

        XCTAssertEqual(address, addressWithExtras)
        XCTAssertEqual(Set([address, addressWithExtras]).count, 1)
    }

    // MARK: - Refreshing a stored profile from a re-scan

    func testRefreshedTakesTheScrapedFieldsAndKeepsTheFieldsTheBrokerDoesNotOwn() {
        let storedProfile = ExtractedProfile(id: 1,
                                             name: "Jane Smith",
                                             age: "38",
                                             email: "duck@duck.com",
                                             removedDate: Date(timeIntervalSince1970: 100),
                                             identifier: "https://broker.example/id/jane-smith")
        let scrapedProfile = ExtractedProfile(name: "Jane A Smith",
                                              relatives: ["John Smith"],
                                              age: "39",
                                              identifier: "https://broker.example/id/jane-smith")

        let sut = storedProfile.refreshed(from: scrapedProfile)

        XCTAssertEqual(sut.name, "Jane A Smith")
        XCTAssertEqual(sut.age, "39")
        XCTAssertEqual(sut.relatives, ["John Smith"])
        XCTAssertEqual(sut.id, 1)
        XCTAssertEqual(sut.email, "duck@duck.com")
        XCTAssertEqual(sut.removedDate, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(sut.identifier, "https://broker.example/id/jane-smith")
    }

    func testRefreshedOverwritesStoredExtrasWithScrapedOnesAndKeepsTheRest() {
        let storedProfile = ExtractedProfile(id: 1, extras: ["county": "Sangamon", "middleName": "A"])
        let scrapedProfile = ExtractedProfile(extras: ["county": "Cook"])

        let sut = storedProfile.refreshed(from: scrapedProfile)

        XCTAssertEqual(sut.extras, ["county": "Cook", "middleName": "A"])
    }

    func testRefreshedKeepsStoredExtrasWhenTheScrapeReturnsNone() {
        let storedProfile = ExtractedProfile(id: 1, extras: ["county": "Sangamon"])

        let sut = storedProfile.refreshed(from: ExtractedProfile())

        XCTAssertEqual(sut.extras, ["county": "Sangamon"])
    }

    func testRefreshedMergesAddressExtrasForTheSameCityAndState() {
        let storedProfile = ExtractedProfile(id: 1, addresses: [
            AddressCityState(city: "Springfield", state: "IL", extras: ["street": "100 Sample Dr", "zip": "62701"]),
            AddressCityState(city: "Chicago", state: "IL", extras: ["zip": "60601"])
        ])
        let scrapedProfile = ExtractedProfile(addresses: [
            AddressCityState(city: "Springfield", state: "IL", extras: ["zip": "62702"]),
            AddressCityState(city: "Peoria", state: "IL")
        ])

        let sut = storedProfile.refreshed(from: scrapedProfile)

        XCTAssertEqual(sut.addresses?.count, 2)
        XCTAssertEqual(sut.addresses?.first?.extras, ["street": "100 Sample Dr", "zip": "62702"])
        XCTAssertNil(sut.addresses?.last?.extras)
    }

    // MARK: - Test matching logic

    func testDoesMatchExtractedProfile_whenThereAnExactMatch_thenDoesMatchExtractedProfileIsTrue() {

        // Given
        let extractedProfile = ExtractedProfile.mockWithName("Steve Jones",
                                                             alternativeNames: ["Steven Jones",
                                                                                "Steven M Jones"],
                                                             age: "20",
                                                             addresses: [AddressCityState(city: "New York", state: "NY"),
                                                                         AddressCityState(city: "Miami", state: "FL")],
                                                             relatives: ["Steven Jones Jr",
                                                                         "Steven Jones Sr",
                                                                         "Steven Jones Staff",
                                                                         "Steven Jones Principle"])
        let matchingExtractedProfile = ExtractedProfile.mockWithName("Steve Jones",
                                                                     alternativeNames: ["Steven Jones",
                                                                                        "Steven M Jones"],
                                                                     age: "20",
                                                                     addresses: [AddressCityState(city: "New York", state: "NY"),
                                                                                 AddressCityState(city: "Miami", state: "FL")],
                                                                     relatives: ["Steven Jones Jr",
                                                                                 "Steven Jones Sr",
                                                                                 "Steven Jones Staff",
                                                                                 "Steven Jones Principle"])

        // Then
        XCTAssertTrue(extractedProfile.doesMatchExtractedProfile(matchingExtractedProfile))
    }

    func testDoesMatchExtractedProfile_whenThereIsANonMatch_thenDoesMatchExtractedProfileIsFalse() {

        // Given
        let extractedProfile = ExtractedProfile.mockWithName("Steve Jones",
                                                             alternativeNames: ["Steven Jones",
                                                                                "Steven M Jones"],
                                                             age: "20",
                                                             addresses: [AddressCityState(city: "New York", state: "NY"),
                                                                         AddressCityState(city: "Miami", state: "FL")],
                                                             relatives: ["Steven Jones Jr",
                                                                         "Steven Jones Sr",
                                                                         "Steven Jones Staff",
                                                                         "Steven Jones Principle"])
        let nonmatchingExtractedProfile = ExtractedProfile.mockWithName("James Smith",
                                                                        alternativeNames: ["James Jameson and The Legion of Doom"],
                                                                        age: "57",
                                                                        addresses: [AddressCityState(city: "Blackpool", state: "NY"),
                                                                                    AddressCityState(city: "Underneath a Volcano", state: "FL")],
                                                                        relatives: ["Beelzebub",
                                                                                    "Barney the Dinosaur"])

        // Then
        XCTAssertFalse(extractedProfile.doesMatchExtractedProfile(nonmatchingExtractedProfile))
    }

    func testDoesMatchExtractedProfile_whenThereAPartialMatch_thenDoesMatchExtractedProfileIsFalse() {

        // Given
        let extractedProfile = ExtractedProfile.mockWithName("Steve Jones",
                                                             alternativeNames: ["Steven Jones",
                                                                                "Steven M Jones"],
                                                             age: "20",
                                                             addresses: [AddressCityState(city: "New York", state: "NY"),
                                                                         AddressCityState(city: "Miami", state: "FL")],
                                                             relatives: ["Steven Jones Jr",
                                                                         "Steven Jones Sr",
                                                                         "Steven Jones Staff",
                                                                         "Steven Jones Principle"])
        let nonmatchingExtractedProfile = ExtractedProfile.mockWithName("Steve Jones",
                                                                        alternativeNames: ["Steven Jones",
                                                                                           "Steven M Jones"],
                                                                        age: "30",
                                                                        addresses: [AddressCityState(city: "New York", state: "NY"),
                                                                                    AddressCityState(city: "Miami", state: "FL")],
                                                                        relatives: ["Steven Jones Jr",
                                                                                    "Steven Jones Sr",
                                                                                    "Steven Jones Staff",
                                                                                    "Steven Jones Principle"])

        // Then
        XCTAssertFalse(extractedProfile.doesMatchExtractedProfile(nonmatchingExtractedProfile))
    }

    func testDoesMatchExtractedProfile_whenThereASubsetMatch_thenDoesMatchExtractedProfileIsTrue() {

        // Given
        let extractedProfile = ExtractedProfile.mockWithName("Steve Jones",
                                                             alternativeNames: ["Steven Jones",
                                                                                "Steven M Jones"],
                                                             age: "20",
                                                             addresses: [AddressCityState(city: "New York", state: "NY"),
                                                                         AddressCityState(city: "Miami", state: "FL")],
                                                             relatives: ["Steven Jones Jr",
                                                                         "Steven Jones Sr",
                                                                         "Steven Jones Staff",
                                                                         "Steven Jones Principle"])
        let matchingExtractedProfile = ExtractedProfile.mockWithName("Steve Jones",
                                                                     alternativeNames: ["Steven Jones"],
                                                                     age: "20",
                                                                     addresses: [AddressCityState(city: "Miami", state: "FL")],
                                                                     relatives: [])

        // Then
        XCTAssertTrue(extractedProfile.doesMatchExtractedProfile(matchingExtractedProfile))
    }

    func testDoesMatchExtractedProfile_whenThereIsASupersetMatch_thenDoesMatchExtractedProfileIsTrue() {

        // Given
        let extractedProfile = ExtractedProfile.mockWithName("Steve Jones",
                                                             alternativeNames: [],
                                                             age: "20",
                                                             addresses: [AddressCityState(city: "Miami", state: "FL")],
                                                             relatives: ["Steven Jones Staff",
                                                                         "Steven Jones Principle"])
        let matchingExtractedProfile = ExtractedProfile.mockWithName("Steve Jones",
                                                                     alternativeNames: ["Steven Jones",
                                                                                        "Steven M Jones"],
                                                                     age: "20",
                                                                     addresses: [AddressCityState(city: "New York", state: "NY"),
                                                                                 AddressCityState(city: "Miami", state: "FL")],
                                                                     relatives: ["Steven Jones Jr",
                                                                                 "Steven Jones Sr",
                                                                                 "Steven Jones Staff",
                                                                                 "Steven Jones Principle"])

        // Then
        XCTAssertTrue(extractedProfile.doesMatchExtractedProfile(matchingExtractedProfile))
    }

    // When some fields are subsets, and some are supersets
    func testDoesMatchExtractedProfile_whenThereAMixedSubsetSupersetMatch_thenDoesMatchExtractedProfileIsTrue() {

        // Given
        let extractedProfile = ExtractedProfile.mockWithName("Steve Jones",
                                                             alternativeNames: [],
                                                             age: "20",
                                                             addresses: [],
                                                             relatives: ["Steven Jones Jr",
                                                                         "Steven Jones Sr",
                                                                         "Steven Jones Staff",
                                                                         "Steven Jones Principle"])
        let matchingExtractedProfile = ExtractedProfile.mockWithName("Steve Jones",
                                                                     alternativeNames: ["Steven Jones",
                                                                                        "Steven M Jones"],
                                                                     age: "20",
                                                                     addresses: [AddressCityState(city: "New York", state: "NY"),
                                                                                 AddressCityState(city: "Miami", state: "FL")],
                                                                     relatives: ["Steven Jones Jr",
                                                                                 "Steven Jones Principle"])

        // Then
        XCTAssertTrue(extractedProfile.doesMatchExtractedProfile(matchingExtractedProfile))
    }
}
