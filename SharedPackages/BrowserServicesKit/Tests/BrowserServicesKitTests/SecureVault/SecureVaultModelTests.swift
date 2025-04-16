//
//  SecureVaultModelTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import XCTest
import Common
@testable import BrowserServicesKit

class SecureVaultModelTests: XCTestCase {

    // MARK: - Identities

    func testWhenCreatingIdentities_ThenTheyHaveCachedAutofillProperties() {
        let identity = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")

        XCTAssertEqual(identity.autofillEqualityName, "firstmiddlelast")
        XCTAssertEqual(identity.autofillEqualityAddressStreet, "addressstreet")
    }

    func testWhenCreatingIdentities_AndTheyHaveCachedAutofillProperties_ThenMutatingThePropertiesUpdatesTheCachedVersions() {
        var identity = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")

        XCTAssertEqual(identity.autofillEqualityName, "firstmiddlelast")
        XCTAssertEqual(identity.autofillEqualityAddressStreet, "addressstreet")

        identity.firstName = "Dax"
        identity.middleName = "The"
        identity.lastName = "Duck"
        identity.addressStreet = "New Street"

        XCTAssertEqual(identity.autofillEqualityName, "daxtheduck")
        XCTAssertEqual(identity.autofillEqualityAddressStreet, "newstreet")
    }

    func testWhenIdentitiesHaveTheSameNames_ThenAutoFillEqualityIsTrue() {
        let identity1 = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")
        let identity2 = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")

        XCTAssertTrue(identity1.hasAutofillEquality(comparedTo: identity2))
    }

    func testWhenIdentitiesHaveTheSameNames_AndNoAddress_ThenAutoFillEqualityIsTrue() {
        let identity1 = identity(named: ("First", "Middle", "Last"), addressStreet: nil)
        let identity2 = identity(named: ("First", "Middle", "Last"), addressStreet: nil)

        XCTAssertTrue(identity1.hasAutofillEquality(comparedTo: identity2))
    }

    func testWhenIdentitiesHaveTheSameNames_AndDifferentAddresses_ThenAutoFillEqualityIsFalse() {
        let identity1 = identity(named: ("First", "Middle", "Last"), addressStreet: "First Address")
        let identity2 = identity(named: ("First", "Middle", "Last"), addressStreet: "Second Address")

        XCTAssertFalse(identity1.hasAutofillEquality(comparedTo: identity2))
    }

    func testWhenIdentitiesHaveTheSameNames_AndHaveArbitraryWhitespace_ThenAutoFillEqualityIsTrue() {
        let identity1 = identity(named: ("First ", " Middle", " Last"), addressStreet: " Address Street ")
        let identity2 = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")

        XCTAssertTrue(identity1.hasAutofillEquality(comparedTo: identity2))
    }

    func testWhenIdentitiesHaveTheSameNames_AndSomeNamesHaveDiacritics_ThenAutoFillEqualityIsTrue() {
        let identity1 = identity(named: ("Fírst", "Mïddlé", "Lâst"), addressStreet: "Address Street")
        let identity2 = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")

        XCTAssertTrue(identity1.hasAutofillEquality(comparedTo: identity2))
    }

    func testWhenIdentitiesHaveTheSameNames_AndSomeNamesHaveEmoji_ThenAutoFillEqualityIsTrue() {
        let identity1 = identity(named: ("First 😎", "Middle", "Last"), addressStreet: "Address Street")
        let identity2 = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")

        XCTAssertTrue(identity1.hasAutofillEquality(comparedTo: identity2))
    }

    func testWhenIdentitiesHaveTheFullNameInOneField_ThenAutoFillEqualityIsTrue() {
        let identity1 = identity(named: ("First Middle Last", "", ""), addressStreet: "Address Street")
        let identity2 = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")

        XCTAssertTrue(identity1.hasAutofillEquality(comparedTo: identity2))
    }

    func testWhenIdentitiesHaveDifferentNames_ButOtherValuesMatch_ThenAutofillEqualityIsFalse() {
        let identity1 = identity(named: ("One", "Two", "Three"), addressStreet: "Address Street")
        let identity2 = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")

        XCTAssertFalse(identity1.hasAutofillEquality(comparedTo: identity2))
    }

    func testIdentityEqualityPerformance() {
        let identity = identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street")

        let identitiesToCheck = (1...10000).map {
            return self.identity(named: ("First", "Middle", "Last"), addressStreet: "Address Street \($0)")
        }

        measure {
            for identityToCheck in identitiesToCheck {
                _ = identity.hasAutofillEquality(comparedTo: identityToCheck)
            }
        }
    }

    // MARK: - Payment Methods

    func testWhenCardNumbersAreTheSame_ThenAutofillEqualityIsTrue() {
        let card1 = paymentMethod(cardNumber: "5555555555555557", cardholderName: "Name", cvv: "123", month: 1, year: 3000)
        let card2 = paymentMethod(cardNumber: "5555555555555557", cardholderName: "Name", cvv: "123", month: 1, year: 3000)

        XCTAssertTrue(card1.hasAutofillEquality(comparedTo: card2))
    }

    func testWhenCardNumbersAreTheSame_ButTheyHaveDifferentSpacing_ThenAutofillEqualityIsTrue() {
        let card1 = paymentMethod(cardNumber: "5555555555555557", cardholderName: "Name", cvv: "123", month: 1, year: 3000)
        let card2 = paymentMethod(cardNumber: "5555 5555 5555 5557", cardholderName: "Name", cvv: "123", month: 1, year: 3000)

        XCTAssertTrue(card1.hasAutofillEquality(comparedTo: card2))
    }

    func testWhenCardNumbersAreDifferent_ThenAutofillEqualityIsFalse() {
        let card1 = paymentMethod(cardNumber: "1234 1234 1234 1234", cardholderName: "Name", cvv: "123", month: 1, year: 3000)
        let card2 = paymentMethod(cardNumber: "5555 5555 5555 5557", cardholderName: "Name", cvv: "123", month: 1, year: 3000)

        XCTAssertFalse(card1.hasAutofillEquality(comparedTo: card2))
    }

    func testPaymentMethodEqualityPerformance() {
        let paymentMethod = paymentMethod(cardNumber: "5555555555555557", cardholderName: "Name", cvv: "123", month: 1, year: 3000)

        let cardsToCheck = (1...10000).map {
            return self.paymentMethod(cardNumber: "5555555555555557", cardholderName: "Name \($0)", cvv: "123", month: 1, year: 3000)
        }

        measure {
            for cardToCheck in cardsToCheck {
                _ = paymentMethod.hasAutofillEquality(comparedTo: cardToCheck)
            }
        }
    }

    // MARK: - Test Utilities

    private func identity(named name: (String, String, String), addressStreet: String?) -> SecureVaultModels.Identity {
        return SecureVaultModels.Identity(id: nil,
                                          title: nil,
                                          created: Date(),
                                          lastUpdated: Date(),
                                          firstName: name.0,
                                          middleName: name.1,
                                          lastName: name.2,
                                          birthdayDay: nil,
                                          birthdayMonth: nil,
                                          birthdayYear: nil,
                                          addressStreet: addressStreet,
                                          addressStreet2: nil,
                                          addressCity: nil,
                                          addressProvince: nil,
                                          addressPostalCode: nil,
                                          addressCountryCode: nil,
                                          homePhone: nil,
                                          mobilePhone: nil,
                                          emailAddress: nil)
    }

    private func paymentMethod(cardNumber: String,
                               cardholderName: String,
                               cvv: String,
                               month: Int,
                               year: Int) -> SecureVaultModels.CreditCard {
        return SecureVaultModels.CreditCard(id: nil,
                                            title: nil,
                                            cardNumber: cardNumber,
                                            cardholderName: cardholderName,
                                            cardSecurityCode: cvv,
                                            expirationMonth: month,
                                            expirationYear: year)
    }

    // MARK: WebsiteAccounts

    private var tld = TLD()
    private var days = 86400.0

    private func testAccount(_ username: String, _ domain: String, _ signature: String, _ lastUpdated: Double, _ lastUsed: Double? = nil) -> SecureVaultModels.WebsiteAccount {
        var lastUsedDate: Date?
        if let lastUsed = lastUsed {
            lastUsedDate = Date(timeIntervalSince1970: lastUsed)
        }
        return SecureVaultModels.WebsiteAccount(id: "1234567890",
                                                username: username,
                                                domain: domain,
                                                signature: signature,
                                                created: Date(timeIntervalSince1970: 0),
                                                lastUpdated: Date(timeIntervalSince1970: lastUpdated),
                                                lastUsed: lastUsedDate)

    }

    lazy var sortTestAccounts = [
        testAccount("", "appliances.amazon.com", "5678", 0),
        testAccount("mary", "garden.amazon.com", "12345", 50 * days),
        testAccount("daniel", "www.amazon.com", "23456", 0),
        testAccount("lisa", "books.amazon.com", "5678", 50  * days),
        testAccount("peter", "primevideo.amazon.com", "4567", 85 * days),
        testAccount("jane", "amazon.com", "7890", 0),
        testAccount("", "", "7890", 0),
        testAccount("", "amazon.com", "3456", 0),
        testAccount("william", "fashion.amazon.com", "1234", 50 * days),
        testAccount("olivia", "toys.amazon.com", "4567", 50 * days),
        testAccount("", "movies.amazon.com", "2345", 0),
        testAccount("jacob", "office.amazon.com", "12345", 0),
        testAccount("rachel", "amazon.com", "7890", 0),
        testAccount("james", "", "7890", 0),
        testAccount("", "grocery.amazon.com", "4567", 0),
        testAccount("frank", "sports.amazon.com", "23456", 0),
        testAccount("quinn", "www.amazon.com", "2345", 0),
        testAccount("oscar", "amazon.com", "7890", 0),
        testAccount("chris", "baby.amazon.com", "3456", 0),
        testAccount("anna", "amazon.com", "1234", 50 * days),
        testAccount("paul", "amazon.com", "3456", 0),
        testAccount("john", "www.amazon.com", "4567", 0),
        testAccount("ringo", "www.amazon.com", "1233", 0, 1 * days),
        testAccount("george", "www.amazon.com", "4488", 0, 0 * days),
        testAccount("pheobe", "amazon.com", "4488", 10 * days, 2 * days)
    ]

    lazy var sortTestAccountsWithPorts = [
        testAccount("", "appliances.amazon.com:1234", "5678", 0),
        testAccount("mary", "garden.amazon.com:1234", "12345", 50 * days),
        testAccount("daniel", "www.amazon.com:1234", "23456", 0),
        testAccount("lisa", "books.amazon.com:1234", "5678", 50  * days),
        testAccount("peter", "primevideo.amazon.com:1234", "4567", 85 * days),
        testAccount("jane", "amazon.com:1234", "7890", 0),
        testAccount("", "", "7890", 0),
        testAccount("", "amazon.com:1234", "3456", 0),
        testAccount("william", "fashion.amazon.com:1234", "1234", 50 * days),
        testAccount("olivia", "toys.amazon.com:1234", "4567", 50 * days),
        testAccount("", "movies.amazon.com:1234", "2345", 0),
        testAccount("jacob", "office.amazon.com:1234", "12345", 0),
        testAccount("rachel", "amazon.com:1234", "7890", 0),
        testAccount("james", "", "7890", 0),
        testAccount("", "grocery.amazon.com:1234", "4567", 0),
        testAccount("frank", "sports.amazon.com:1234", "23456", 0),
        testAccount("quinn", "www.amazon.com:1234", "2345", 0),
        testAccount("oscar", "amazon.com:1234", "7890", 0),
        testAccount("chris", "baby.amazon.com:1234", "3456", 0),
        testAccount("anna", "amazon.com:1234", "1234", 50 * days),
        testAccount("paul", "amazon.com:1234", "3456", 0),
        testAccount("john", "www.amazon.com:1234", "4567", 0),
        testAccount("ringo", "www.amazon.com:1234", "1233", 0, 1 * days),
        testAccount("george", "www.amazon.com:1234", "4488", 0, 0 * days),
        testAccount("pheobe", "amazon.com:1234", "4488", 10 * days, 2 * days)
    ]

    lazy var localHostWithPorts = [
        testAccount("ringo", "subdomain.localhost:1234", "5678", 0),
        testAccount("mary", "localhost:1234", "5678", 0),
        testAccount("daniel", "localhost:1234", "23456", 0),
        testAccount("lisa", "localhost:1234", "5678", 50  * days),
        testAccount("", "subdomain.localhost:1234", "4567", 85 * days),
        testAccount("jane", "subdomain.localhost:1234", "7890", 0),
    ]

    func testExactMatchAccountsAreShownFirst() {
        let sortedAccounts = sortTestAccounts.sortedForDomain("www.amazon.com", tld: tld)

        let controlAccounts = [
            testAccount("ringo", "www.amazon.com", "1233", 0, 1 * days),
            testAccount("george", "www.amazon.com", "4488", 0, 0 * days),
            testAccount("daniel", "www.amazon.com", "23456", 0),
            testAccount("john", "www.amazon.com", "4567", 0),
            testAccount("quinn", "www.amazon.com", "2345", 0),
            testAccount("pheobe", "amazon.com", "4488", 10 * days, 2 * days),
            testAccount("anna", "amazon.com", "1234", 50 * days),
            testAccount("jane", "amazon.com", "7890", 0),
            testAccount("oscar", "amazon.com", "7890", 0),
            testAccount("paul", "amazon.com", "3456", 0),
            testAccount("rachel", "amazon.com", "7890", 0),
            testAccount("", "amazon.com", "3456", 0),
            testAccount("peter", "primevideo.amazon.com", "4567", 85 * days),
            testAccount("lisa", "books.amazon.com", "5678", 50 * days),
            testAccount("william", "fashion.amazon.com", "1234", 50 * days),
            testAccount("mary", "garden.amazon.com", "12345", 50 * days),
            testAccount("olivia", "toys.amazon.com", "4567", 50 * days),
            testAccount("chris", "baby.amazon.com", "3456", 0),
            testAccount("jacob", "office.amazon.com", "12345", 0),
            testAccount("frank", "sports.amazon.com", "23456", 0),
            testAccount("", "appliances.amazon.com", "5678", 0),
            testAccount("", "grocery.amazon.com", "4567", 0),
            testAccount("", "movies.amazon.com", "2345", 0)
        ]
        for i in 0...controlAccounts.count - 1 {
            XCTAssertEqual(sortedAccounts[i], controlAccounts[i])
        }
    }

    func testExactMatchAccountsWithPortAreShownFirst() {
        let sortedAccounts = sortTestAccountsWithPorts.sortedForDomain("www.amazon.com:1234", tld: tld)

        let controlAccounts = [
            testAccount("ringo", "www.amazon.com:1234", "1233", 0, 1 * days),
            testAccount("george", "www.amazon.com:1234", "4488", 0, 0 * days),
            testAccount("daniel", "www.amazon.com:1234", "23456", 0),
            testAccount("john", "www.amazon.com:1234", "4567", 0),
            testAccount("quinn", "www.amazon.com:1234", "2345", 0),
            testAccount("pheobe", "amazon.com:1234", "4488", 10 * days, 2 * days),
            testAccount("anna", "amazon.com:1234", "1234", 50 * days),
            testAccount("jane", "amazon.com:1234", "7890", 0),
            testAccount("oscar", "amazon.com:1234", "7890", 0),
            testAccount("paul", "amazon.com:1234", "3456", 0),
            testAccount("rachel", "amazon.com:1234", "7890", 0),
            testAccount("", "amazon.com:1234", "3456", 0),
            testAccount("peter", "primevideo.amazon.com:1234", "4567", 85 * days),
            testAccount("lisa", "books.amazon.com:1234", "5678", 50 * days),
            testAccount("william", "fashion.amazon.com:1234", "1234", 50 * days),
            testAccount("mary", "garden.amazon.com:1234", "12345", 50 * days),
            testAccount("olivia", "toys.amazon.com:1234", "4567", 50 * days),
            testAccount("chris", "baby.amazon.com:1234", "3456", 0),
            testAccount("jacob", "office.amazon.com:1234", "12345", 0),
            testAccount("frank", "sports.amazon.com:1234", "23456", 0),
            testAccount("", "appliances.amazon.com:1234", "5678", 0),
            testAccount("", "grocery.amazon.com:1234", "4567", 0),
            testAccount("", "movies.amazon.com:1234", "2345", 0)
        ]
        for i in 0...controlAccounts.count - 1 {
            XCTAssertEqual(sortedAccounts[i], controlAccounts[i])
        }
    }

    func testWWWAccountsAreConsideredTopLevel() {

        let sortedAccounts = sortTestAccounts.sortedForDomain("amazon.com", tld: tld)
        let controlAccounts = [
            testAccount("pheobe", "amazon.com", "4488", 10 * days, 2 * days),
            testAccount("anna", "amazon.com", "1234", 50 * days),
            testAccount("jane", "amazon.com", "7890", 0),
            testAccount("oscar", "amazon.com", "7890", 0),
            testAccount("paul", "amazon.com", "3456", 0),
            testAccount("rachel", "amazon.com", "7890", 0),
            testAccount("", "amazon.com", "3456", 0),
            testAccount("ringo", "www.amazon.com", "1233", 0, 1 * days),
            testAccount("george", "www.amazon.com", "4488", 0, 0 * days),
            testAccount("daniel", "www.amazon.com", "23456", 0),
            testAccount("john", "www.amazon.com", "4567", 0),
            testAccount("quinn", "www.amazon.com", "2345", 0),
        ]
        for i in 0...controlAccounts.count - 1 {
            XCTAssertEqual(sortedAccounts[i], controlAccounts[i])
        }
    }

    func testWWWAccountsWithPortAreConsideredTopLevel() {

        let sortedAccounts = sortTestAccountsWithPorts.sortedForDomain("amazon.com:1234", tld: tld)
        let controlAccounts = [
            testAccount("pheobe", "amazon.com:1234", "4488", 10 * days, 2 * days),
            testAccount("anna", "amazon.com:1234", "1234", 50 * days),
            testAccount("jane", "amazon.com:1234", "7890", 0),
            testAccount("oscar", "amazon.com:1234", "7890", 0),
            testAccount("paul", "amazon.com:1234", "3456", 0),
            testAccount("rachel", "amazon.com:1234", "7890", 0),
            testAccount("", "amazon.com:1234", "3456", 0),
            testAccount("ringo", "www.amazon.com:1234", "1233", 0, 1 * days),
            testAccount("george", "www.amazon.com:1234", "4488", 0, 0 * days),
            testAccount("daniel", "www.amazon.com:1234", "23456", 0),
            testAccount("john", "www.amazon.com:1234", "4567", 0),
            testAccount("quinn", "www.amazon.com:1234", "2345", 0),
        ]
        for i in 0...controlAccounts.count - 1 {
            XCTAssertEqual(sortedAccounts[i], controlAccounts[i])
        }
    }

    func testExactSubdomainMatchIsFirstFollowedByTLDAndWWW() {

        let sortedAccounts  = sortTestAccounts.sortedForDomain("toys.amazon.com", tld: tld)
        let controlAccounts  = [
            testAccount("olivia", "toys.amazon.com", "4567", 50 * days),
            testAccount("pheobe", "amazon.com", "4488", 10 * days, 2 * days),
            testAccount("ringo", "www.amazon.com", "1233", 0, 1 * days),
            testAccount("george", "www.amazon.com", "4488", 0, 0 * days),
            testAccount("anna", "amazon.com", "1234", 50 * days),
            testAccount("jane", "amazon.com", "7890", 0),
            testAccount("oscar", "amazon.com", "7890", 0),
            testAccount("paul", "amazon.com", "3456", 0),
            testAccount("rachel", "amazon.com", "7890", 0),
            testAccount("daniel", "www.amazon.com", "23456", 0),
            testAccount("john", "www.amazon.com", "4567", 0),
            testAccount("quinn", "www.amazon.com", "2345", 0),
            testAccount("", "amazon.com", "3456", 0),
            testAccount("peter", "primevideo.amazon.com", "4567", 85 * days),
            testAccount("lisa", "books.amazon.com", "5678", 50 * days),
            testAccount("william", "fashion.amazon.com", "1234", 50 * days),
            testAccount("mary", "garden.amazon.com", "12345", 50 * days),
            testAccount("chris", "baby.amazon.com", "3456", 0),
            testAccount("jacob", "office.amazon.com", "12345", 0),
            testAccount("frank", "sports.amazon.com", "23456", 0),
            testAccount("", "appliances.amazon.com", "5678", 0),
            testAccount("", "grocery.amazon.com", "4567", 0),
            testAccount("", "movies.amazon.com", "2345", 0)
        ]
        XCTAssertTrue(sortedAccounts.count == controlAccounts.count)
        for i in 0...controlAccounts.count - 1 {
            XCTAssertEqual(sortedAccounts[i], controlAccounts[i])
        }
    }

    func testExactSubdomainMatchWithPortIsFirstFollowedByTLDAndWWW() {

        let sortedAccounts  = sortTestAccountsWithPorts.sortedForDomain("toys.amazon.com:1234", tld: tld)
        let controlAccounts  = [
            testAccount("olivia", "toys.amazon.com:1234", "4567", 50 * days),
            testAccount("pheobe", "amazon.com:1234", "4488", 10 * days, 2 * days),
            testAccount("ringo", "www.amazon.com:1234", "1233", 0, 1 * days),
            testAccount("george", "www.amazon.com:1234", "4488", 0, 0 * days),
            testAccount("anna", "amazon.com:1234", "1234", 50 * days),
            testAccount("jane", "amazon.com:1234", "7890", 0),
            testAccount("oscar", "amazon.com:1234", "7890", 0),
            testAccount("paul", "amazon.com:1234", "3456", 0),
            testAccount("rachel", "amazon.com:1234", "7890", 0),
            testAccount("daniel", "www.amazon.com:1234", "23456", 0),
            testAccount("john", "www.amazon.com:1234", "4567", 0),
            testAccount("quinn", "www.amazon.com:1234", "2345", 0),
            testAccount("", "amazon.com:1234", "3456", 0),
            testAccount("peter", "primevideo.amazon.com:1234", "4567", 85 * days),
            testAccount("lisa", "books.amazon.com:1234", "5678", 50 * days),
            testAccount("william", "fashion.amazon.com:1234", "1234", 50 * days),
            testAccount("mary", "garden.amazon.com:1234", "12345", 50 * days),
            testAccount("chris", "baby.amazon.com:1234", "3456", 0),
            testAccount("jacob", "office.amazon.com:1234", "12345", 0),
            testAccount("frank", "sports.amazon.com:1234", "23456", 0),
            testAccount("", "appliances.amazon.com:1234", "5678", 0),
            testAccount("", "grocery.amazon.com:1234", "4567", 0),
            testAccount("", "movies.amazon.com:1234", "2345", 0)
        ]
        XCTAssertTrue(sortedAccounts.count == controlAccounts.count)
        for i in 0...controlAccounts.count - 1 {
            XCTAssertEqual(sortedAccounts[i], controlAccounts[i])
        }
    }

    func testDuplicatesAreProperlyRemoved() {
        // (Note Duplicates are removed exclusively based on signature -- Ignoring usernames/domains)
        let sortedAccounts  = sortTestAccounts.sortedForDomain("toys.amazon.com", tld: tld, removeDuplicates: true)
        let controlAccounts  = [
            testAccount("olivia", "toys.amazon.com", "4567", 50 * days),
            testAccount("pheobe", "amazon.com", "4488", 10 * days, 2 * days),
            testAccount("ringo", "www.amazon.com", "1233", 0, 1 * days),
            testAccount("anna", "amazon.com", "1234", 50 * days),
            testAccount("jane", "amazon.com", "7890", 0),
            testAccount("paul", "amazon.com", "3456", 0),
            testAccount("daniel", "www.amazon.com", "23456", 0),
            testAccount("quinn", "www.amazon.com", "2345", 0),
            testAccount("lisa", "books.amazon.com", "5678", 50 * days),
            testAccount("mary", "garden.amazon.com", "12345", 50 * days),
        ]

        for i in 0...controlAccounts.count - 1 {
            XCTAssertEqual(sortedAccounts[i], controlAccounts[i])
        }
    }

    func testDomainWithPortIsSorted() {
        // (Note Duplicates are removed exclusively based on signature -- Ignoring usernames/domains)
        let sortedAccounts  = sortTestAccountsWithPorts.sortedForDomain("toys.amazon.com:1234", tld: tld, removeDuplicates: true)
        let controlAccounts  = [
            testAccount("olivia", "toys.amazon.com:1234", "4567", 50 * days),
            testAccount("pheobe", "amazon.com:1234", "4488", 10 * days, 2 * days),
            testAccount("ringo", "www.amazon.com:1234", "1233", 0, 1 * days),
            testAccount("anna", "amazon.com:1234", "1234", 50 * days),
            testAccount("jane", "amazon.com:1234", "7890", 0),
            testAccount("paul", "amazon.com:1234", "3456", 0),
            testAccount("daniel", "www.amazon.com:1234", "23456", 0),
            testAccount("quinn", "www.amazon.com:1234", "2345", 0),
            testAccount("lisa", "books.amazon.com:1234", "5678", 50 * days),
            testAccount("mary", "garden.amazon.com:1234", "12345", 50 * days),
        ]

        for i in 0...controlAccounts.count - 1 {
            XCTAssertEqual(sortedAccounts[i], controlAccounts[i])
        }
    }

    func testReturnsLocalhostWithPortSorted() {
        let sortedAccounts  = localHostWithPorts.sortedForDomain("localhost:1234", tld: tld, removeDuplicates: false)
        let controlAccounts  = [
            testAccount("lisa", "localhost:1234", "5678", 50  * days),
            testAccount("daniel", "localhost:1234", "23456", 0),
            testAccount("mary", "localhost:1234", "5678", 0),
            testAccount("jane", "subdomain.localhost:1234", "7890", 0),
            testAccount("ringo", "subdomain.localhost:1234", "5678", 0),
            testAccount("", "subdomain.localhost:1234", "4567", 85 * days)
        ]

        for i in 0...controlAccounts.count - 1 {
            XCTAssertEqual(sortedAccounts[i], controlAccounts[i])
        }
    }

    func testReturnsLocalhostWithPortSortedAndDuplicatedRemoved() {
        let sortedAccounts  = localHostWithPorts.sortedForDomain("localhost:1234", tld: tld, removeDuplicates: true)
        let controlAccounts  = [
            testAccount("lisa", "localhost:1234", "5678", 50  * days),
            testAccount("daniel", "localhost:1234", "23456", 0),
            testAccount("jane", "subdomain.localhost:1234", "7890", 0),
            testAccount("", "subdomain.localhost:1234", "4567", 85 * days)
        ]

        for i in 0...controlAccounts.count - 1 {
            XCTAssertEqual(sortedAccounts[i], controlAccounts[i])
        }
    }

    func testSortedAndDeduplicatedForSameSignatureReturnsTLD() {
        let controlAccounts = [
            testAccount("user1", "example.com", "sig1", 0),
            testAccount("user1", "sub1.example.com", "sig1", 0, 1 * days),
            testAccount("user1", "sub2.example.com", "sig1", 0),
        ]

        let sortedAccounts = controlAccounts.sortedAndDeduplicated(tld: tld)

        XCTAssertEqual(sortedAccounts[0].domain, "example.com")
        XCTAssertEqual(sortedAccounts.count, 1)
    }

    func testSortedAndDeduplicatedForSameSignatureReturnsWww() {
        let controlAccounts = [
            testAccount("user1", "sub.example.com", "sig1", 0, 1 * days),
            testAccount("user1", "sub1.example.com", "sig1", 0),
            testAccount("user1", "sub2.example.com", "sig1", 0),
            testAccount("user1", "www.example.com", "sig1", 0),
        ]

        let sortedAccounts = controlAccounts.sortedAndDeduplicated(tld: tld)

        XCTAssertEqual(sortedAccounts[0].domain, "www.example.com")
        XCTAssertEqual(sortedAccounts.count, 1)
    }

    func testSortedAndDeduplicatedForSameSignatureDifferentSubdomainsReturnsSortedLastUsed() {
        let controlAccounts = [
            testAccount("user1", "sub.example.com", "sig1", 0),
            testAccount("user1", "sub1.example.com", "sig1", 0),
            testAccount("user1", "sub2.example.com", "sig1", 0, 1 * days),
            testAccount("user1", "any.example.com", "sig1", 0),
        ]

        let sortedAccounts = controlAccounts.sortedAndDeduplicated(tld: tld)

        XCTAssertEqual(sortedAccounts[0].domain, "sub2.example.com")
        XCTAssertEqual(sortedAccounts.count, 1)
    }

    func testSortedAndDeduplicatedForSameSignatureDifferentDomainsReturnsUniqueDomains() {
        let controlAccounts = [
            testAccount("user1", "example.co.uk", "sig1", 0),
            testAccount("user1", "sub.example.co.uk", "sig1", 0),
            testAccount("user1", "domain.co.uk", "sig1", 0),
            testAccount("user1", "www.domain.co.uk", "sig1", 0),
        ]

        let sortedAccounts = controlAccounts.sortedAndDeduplicated(tld: tld)

        XCTAssertEqual(sortedAccounts[0].domain, "domain.co.uk")
        XCTAssertEqual(sortedAccounts[1].domain, "example.co.uk")
        XCTAssertEqual(sortedAccounts.count, 2)
    }

    func testSortedAndDeduplicatedForNoSignatureReturnsAllAccounts() {
        let controlAccounts = [
            SecureVaultModels.WebsiteAccount(id: "1234567890",
                                             username: "username",
                                             domain: "example.co.uk",
                                             created: Date(),
                                             lastUpdated: Date()),
            SecureVaultModels.WebsiteAccount(id: "1234567890",
                                             username: "username",
                                             domain: "sub.example.co.uk",
                                             created: Date(),
                                             lastUpdated: Date()),
            SecureVaultModels.WebsiteAccount(id: "1234567890",
                                             username: "username",
                                             domain: "domain.co.uk",
                                             created: Date(),
                                             lastUpdated: Date()),
            SecureVaultModels.WebsiteAccount(id: "1234567890",
                                             username: "username",
                                             domain: "www.domain.co.uk",
                                             created: Date(),
                                             lastUpdated: Date())
        ]

        let sortedAccounts = controlAccounts.sortedAndDeduplicated(tld: tld)

        XCTAssertEqual(sortedAccounts.count, 4)
    }

    func testSortedAndDeduplicatedWithComplexDomains() {
        let accounts = [
            // Multiple subdomains
            testAccount("user1", "deep.sub.example.com", "sig1", 0),
            testAccount("user1", "other.sub.example.com", "sig1", 0),

            // Different ports
            testAccount("user2", "example.com:8080", "sig2", 0),
            testAccount("user2", "example.com:443", "sig2", 0),

            // Mix of www and non-www
            testAccount("user3", "www.example.com", "sig3", 0),
            testAccount("user3", "example.com", "sig3", 0),

            // Different TLDs
            testAccount("user4", "example.com", "sig4", 0),
            testAccount("user4", "example.net", "sig4", 0),
            testAccount("user4", "example.org", "sig4", 0)
        ]

        let sortedAccounts = accounts.sortedAndDeduplicated(tld: tld)

        // Verify subdomains are properly handled
        let sig1Accounts = sortedAccounts.filter { $0.signature == "sig1" }
        XCTAssertEqual(sig1Accounts[0].domain, "deep.sub.example.com")
        XCTAssertEqual(sig1Accounts.count, 1)

        // Verify ports are considered in deduplication
        let sig2Accounts = sortedAccounts.filter { $0.signature == "sig2" }
        XCTAssertEqual(sig2Accounts[0].domain, "example.com:443")
        XCTAssertEqual(sig2Accounts.count, 1)

        // Verify www and non-www are considered same domain
        let sig3Accounts = sortedAccounts.filter { $0.signature == "sig3" }
        XCTAssertEqual(sig3Accounts[0].domain, "example.com")
        XCTAssertEqual(sig3Accounts.count, 1)

        // Verify different TLDs are preserved
        let sig4Accounts = sortedAccounts.filter { $0.signature == "sig4" }
        XCTAssertEqual(sig4Accounts.count, 3)
    }

    func testSortedAndDeduplicatedWithLastUsedDates() {
        let accounts = [
            // Same signature, different last used dates
            testAccount("user1", "example.com", "sig1", 0, 3 * days),
            testAccount("user1", "sub.example.com", "sig1", 0, 1 * days),
            testAccount("user1", "other.example.com", "sig1", 0, 2 * days),

            // Different signatures, same domain, mixed dates
            testAccount("user2", "example.com", "sig2", 0, 1 * days),
            testAccount("user3", "example.com", "sig3", 0, 2 * days),
            testAccount("user4", "example.com", "sig4", 0) // No last used date
        ]

        let sortedAccounts = accounts.sortedAndDeduplicated(tld: tld)

        // Verify accounts are sorted by last used date
        XCTAssertEqual(sortedAccounts[0].domain, "example.com") // 3 days ago
        XCTAssertEqual(sortedAccounts[1].username, "user3") // 2 days ago
        XCTAssertEqual(sortedAccounts[2].username, "user2") // 1 day ago
        XCTAssertEqual(sortedAccounts[3].username, "user4") // No last used date

        // Verify deduplication still works with different dates
        let sig1Accounts = sortedAccounts.filter { $0.signature == "sig1" }
        XCTAssertEqual(sig1Accounts.count, 1)
        // Verify the most recently used account is kept
        XCTAssertEqual(sig1Accounts[0].lastUsed?.timeIntervalSince1970, 3 * days)
    }

    func testPatternMatchedTitle() {

        let domainTitles: [String] = [
            "duck.com",
            "duck.com (test@duck.com)",
            "https://duck.com",
            "https://duck.com (test@duck.com)",
            "https://duck.com?page.php?test=variable1&b=variable2",
            "https://duck.com/section/page.php?test=variable1&b=variable2",
            "www.duck.com",
            "www.duck.com (test@duck.com)",
            "https://www.duck.com",
            "https://www.duck.com (test@duck.com)",
            "https://www.duck.com?page.php?test=variable1&b=variable2",
            "https://www.duck.com/section/page.php?test=variable1&b=variable2",
            "https://WwW.dUck.com/section/page"
        ]

        let subdomainTitles: [String] = [
            "signin.duck.com",
            "signin.duck.com (test@duck.com.co)",
            "https://signin.duck.com",
            "https://signin.duck.com (test@duck.com.co)",
            "https://signin.duck.com?page.php?test=variable1&b=variable2",
            "https://signin.duck.com/section/page.php?test=variable1&b=variable2",
            "https://SiGnIn.dUck.com/section/page"
        ]

        let tldPlusOneTitles: [String] = [
            "signin.duck.com.co",
            "signin.duck.com.co (test@duck.com.co)",
            "https://signin.duck.com.co",
            "https://signin.duck.com.co (test@duck.com.co)",
            "https://signin.duck.com.co?page.php?test=variable1&b=variable2",
            "https://signin.duck.com.co/section/page.php?test=variable1&b=variable2",
            "https://SiGnIn.dUck.com.CO/section/page"
        ]

        let randomTitles: [String] = [
            "John's Work Gmail",
            "Chase Bank - Main Account",
            "FB - Old College Friends",
            "Amazon (signed up in 2010!)",
            "Netflix - Sharing with Family",
            "HSBC Savings (emergency funds)",
            "Reddit Secret Account 🤫",
            "LinkedIn (need to update resume)",
            "Google Drive - Trip Photos",
            "Spotify (got on sale)",
            "Airbnb Host Profile",
            "@JanePhotography on Insta",
            "PayPal (linked to Visa)",
            "eBay (mostly for vintage buys)",
            "Dropbox Pro Subscription",
            "Blogger - Childhood Diary",
            "Zoom Yoga Classes",
            "Slack for Uni Group Project",
            "Office 365 (from work)",
            "Github (learning Python projects)",
            "Adobe - Annual Subscription",
            "Steam Gamer Acct (JohnD_91)",
            "NYT Digital - Daily Reads",
            "Diet Tracker - Keto Journey",
            "UberEats (too many orders lol)",
            "Twitch (streaming on weekends)",
            "Pinterest Board - DIY Projects",
            "Disney+ Kids Account",
            "Squarespace Portfolio Site",
            "Apple ID (old email)",
            "Walmart Online Shopping Cart",
            "Duolingo - 100-day streak!",
            "Yelp (foodie reviews)",
            "My Uni Library Login",
            "Trello Board for Home Reno",
            "Asana (Team XYZ project)",
            "Bitbucket (web dev stuff)",
            "Hulu - free trial ending soon",
            "Starbucks Rewards Card",
            "PlayStation Network (PS5)",
            "Goodreads (reading challenge 2023)",
            "Skype Old Account",
            "Robinhood Stock Trades",
            "Minecraft (John's server)",
            "Postmates (frequent discounts)",
            "BestBuy Member Rewards",
            "Canva Pro Design Tools",
            "Groupon - Best Deals!",
            "Twitter (follows 500+)",
            "Zillow Home Searches",
            "twitter.com my account",
            "fill.dev  personal email"
        ]

        for title in domainTitles {
            let account = SecureVaultModels.WebsiteAccount(id: "", title: title, username: "", domain: "sometestdomain.com", created: Date(), lastUpdated: Date())
            XCTAssertEqual("duck.com", account.patternMatchedTitle(), "Failed for title: \(title)")

            let equalDomain = SecureVaultModels.WebsiteAccount(id: "", title: title, username: "", domain: "duck.com", created: Date(), lastUpdated: Date())
            XCTAssertEqual("", equalDomain.patternMatchedTitle(), "Failed for title: \(title)")
        }

        for title in subdomainTitles {
            let account = SecureVaultModels.WebsiteAccount(id: "", title: title, username: "", domain: "sometestdomain.com", created: Date(), lastUpdated: Date())
            XCTAssertEqual("signin.duck.com", account.patternMatchedTitle(), "Failed for title: \(title)")

            let equalDomain = SecureVaultModels.WebsiteAccount(id: "", title: title, username: "", domain: "signin.duck.com", created: Date(), lastUpdated: Date())
            XCTAssertEqual("", equalDomain.patternMatchedTitle(), "Failed for title: \(title)")
        }

        for title in tldPlusOneTitles {
            let account = SecureVaultModels.WebsiteAccount(id: "", title: title, username: "", domain: "sometestdomain.com", created: Date(), lastUpdated: Date())
            XCTAssertEqual("signin.duck.com.co", account.patternMatchedTitle(), "Failed for title: \(title)")

            let equalDomain = SecureVaultModels.WebsiteAccount(id: "", title: title, username: "", domain: "signin.duck.com.co", created: Date(), lastUpdated: Date())
            XCTAssertEqual("", equalDomain.patternMatchedTitle(), "Failed for title: \(title)")
        }

        for title in randomTitles {
            let account = SecureVaultModels.WebsiteAccount(id: "", title: title, username: "", domain: "sometestdomain.com", created: Date(), lastUpdated: Date())
            XCTAssertEqual(title, account.patternMatchedTitle(), "Failed for title: \(title)")
        }

    }

}
