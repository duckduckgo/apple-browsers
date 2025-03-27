//
//  AutofillDomainNameUrlSortTests.swift
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
import BrowserServicesKit
import Common

final class AutofillDomainNameUrlSortTests: XCTestCase {

    private let autofillDomainNameUrlSort = AutofillDomainNameUrlSort()
    private let tld = TLD()

    func testWhenTitleIsSetAndDomainIsMissingThenReturnsFirstCharacterOfTitle() {
        let account1 = websiteAccountFor(domain: "", title: "Xyz")
        let firstCharForGrouping = autofillDomainNameUrlSort.firstCharacterForGrouping(account1, tld: tld)
        XCTAssertEqual(firstCharForGrouping, "x")
    }

    func testWhenTitleAndDomainAreSetThenReturnsFirstCharacterOfTitle() {
        let account1 = websiteAccountFor(domain: "example.com", title: "Xyz")
        let firstCharForGrouping = autofillDomainNameUrlSort.firstCharacterForGrouping(account1, tld: tld)
        XCTAssertEqual(firstCharForGrouping, "x")
    }

    func testWhenDomainIsExactMatchToTldsListItemThenReturnsFirstCharacterOfDomain() {
        let account1 = websiteAccountFor(domain: "github.io")
        let firstCharForGrouping = autofillDomainNameUrlSort.firstCharacterForGrouping(account1, tld: tld)
        XCTAssertEqual(firstCharForGrouping, "g")
    }

    func testWhenDomainIsPartialMatchToTldsListItemThenReturnsFirstCharacterOfDomain() {
        let account1 = websiteAccountFor(domain: "mysite.github.io")
        let firstCharForGrouping = autofillDomainNameUrlSort.firstCharacterForGrouping(account1, tld: tld)
        XCTAssertEqual(firstCharForGrouping, "m")
    }

    func testWhenDomainIsNotInTldsListThenReturnsFirstCharacterOfDomain() {
        let account1 = websiteAccountFor(domain: "example.com")
        let firstCharForGrouping = autofillDomainNameUrlSort.firstCharacterForGrouping(account1, tld: tld)
        XCTAssertEqual(firstCharForGrouping, "e")
    }

    func testWhenDomainIsNotInTldsListAndSubdomainIsSetThenFirstReturnsCharacterOfDomain() {
        let account1 = websiteAccountFor(domain: "sub.example.com")
        let firstCharForGrouping = autofillDomainNameUrlSort.firstCharacterForGrouping(account1, tld: tld)
        XCTAssertEqual(firstCharForGrouping, "e")
    }

    func testWhenDomainIsInvalidThenFirstReturnsCharacterOfDomain() {
        let account1 = websiteAccountFor(domain: "xyz")
        let firstCharForGrouping = autofillDomainNameUrlSort.firstCharacterForGrouping(account1, tld: tld)
        XCTAssertEqual(firstCharForGrouping, "x")
    }

    func testWhenComparingTitlesCaseIsIgnored() {
        let account1 = websiteAccountFor(domain: "C.COM")
        let account2 = websiteAccountFor(domain: "b.com")
        let account3 = websiteAccountFor(domain: "A.Com")

        let accounts = [account1, account2, account3]
        let sortedAccounts = accounts.sorted(by: {
            autofillDomainNameUrlSort.compareAccountsForSortingAutofill(lhs: $0, rhs: $1, tld: tld) == .orderedAscending
        })
        XCTAssertEqual(sortedAccounts.map { $0.domain }, [account3.domain, account2.domain, account1.domain])
    }

    func testWhenComparingSubdomainsCaseIsIgnored() {
        let account1 = websiteAccountFor(domain: "C.example.COM")
        let account2 = websiteAccountFor(domain: "b.example.com")
        let account3 = websiteAccountFor(domain: "a.example.Com")

        let accounts = [account1, account2, account3]
        let sortedAccounts = accounts.sorted(by: {
            autofillDomainNameUrlSort.compareAccountsForSortingAutofill(lhs: $0, rhs: $1, tld: tld) == .orderedAscending
        })
        XCTAssertEqual(sortedAccounts.map { $0.domain }, [account3.domain, account2.domain, account1.domain])
    }

    func testWhenTitleStartsWithANumberThenSortedBeforeLetters() {
        let account1 = websiteAccountFor(title: "b")
        let account2 = websiteAccountFor(title: "1")
        let account3 = websiteAccountFor(title: "A")
        let account4 = websiteAccountFor(title: "2")

        let accounts = [account1, account2, account3, account4]
        let sortedAccounts = accounts.sorted(by: {
            autofillDomainNameUrlSort.compareAccountsForSortingAutofill(lhs: $0, rhs: $1, tld: tld) == .orderedAscending
        })
        XCTAssertEqual(sortedAccounts.map { $0.title }, ["1", "2", "A", "b"])
    }

    func testWhenTitleMissingThenSortedBeforeLetters() {
        let account1 = websiteAccountFor(title: "b")
        let account2 = websiteAccountFor(title: nil)
        let account3 = websiteAccountFor(title: "A")

        let accounts = [account1, account2, account3]
        let sortedAccounts = accounts.sorted(by: {
            autofillDomainNameUrlSort.compareAccountsForSortingAutofill(lhs: $0, rhs: $1, tld: tld) == .orderedAscending
        })
        XCTAssertEqual(sortedAccounts.map { $0.title }, [nil, "A", "b"])
    }

    func testWhenTitlesAllMissingThenDomainUsedInstead() {
        let account1 = websiteAccountFor(domain: "b.com")
        let account2 = websiteAccountFor(domain: "a.com")
        let account3 = websiteAccountFor(domain: "c.com")

        let accounts = [account1, account2, account3]
        let sortedAccounts = accounts.sorted(by: {
            autofillDomainNameUrlSort.compareAccountsForSortingAutofill(lhs: $0, rhs: $1, tld: tld) == .orderedAscending
        })
        XCTAssertEqual(sortedAccounts.map { $0.domain }, [account2.domain, account1.domain, account3.domain])
    }

    func testWhenTitlesEqualThenDomainUsedAsSecondarySort() {
        let account1 = websiteAccountFor(domain: "b.com", title: "Example")
        let account2 = websiteAccountFor(domain: "a.com", title: "Example")
        let account3 = websiteAccountFor(domain: "c.com", title: "Example")

        let accounts = [account1, account2, account3]
        let sortedAccounts = accounts.sorted(by: {
            autofillDomainNameUrlSort.compareAccountsForSortingAutofill(lhs: $0, rhs: $1, tld: tld) == .orderedAscending
        })
        XCTAssertEqual(sortedAccounts.map { $0.domain }, [account2.domain, account1.domain, account3.domain])
    }

    func testWhenTitlesDifferThenDomainSortingNotUsed() {
        let account1 = websiteAccountFor(domain: "b.com", title: "Example")
        let account2 = websiteAccountFor(domain: "a.com", title: "Test")
        let account3 = websiteAccountFor(domain: "c.com", title: "Hello World")

        let accounts = [account1, account2, account3]
        let sortedAccounts = accounts.sorted(by: {
            autofillDomainNameUrlSort.compareAccountsForSortingAutofill(lhs: $0, rhs: $1, tld: tld) == .orderedAscending
        })
        XCTAssertEqual(sortedAccounts.map { $0.title }, [account1.title, account3.title, account2.title])
    }

    func testWhenComparingDomainsThenSchemeIgnored() {
        let account1 = websiteAccountFor(domain: "http://www.b.com")
        let account2 = websiteAccountFor(domain: "https://www.a.com")
        let account3 = websiteAccountFor(domain: "www.c.com")

        let accounts = [account1, account2, account3]
        let sortedAccounts = accounts.sorted(by: {
            autofillDomainNameUrlSort.compareAccountsForSortingAutofill(lhs: $0, rhs: $1, tld: tld) == .orderedAscending
        })
        XCTAssertEqual(sortedAccounts.map { $0.domain }, [account2.domain, account1.domain, account3.domain])
    }

    func testWhenComparingSubdomainsThenWwwNotTreatedAsSpecialForSorting() {
        let account1 = websiteAccountFor(domain: "www.b.com")
        let account2 = websiteAccountFor(domain: "a.com")
        let account3 = websiteAccountFor(domain: "www.c.com")

        let accounts = [account1, account2, account3]
        let sortedAccounts = accounts.sorted(by: {
            autofillDomainNameUrlSort.compareAccountsForSortingAutofill(lhs: $0, rhs: $1, tld: tld) == .orderedAscending
        })
        XCTAssertEqual(sortedAccounts.map { $0.domain }, [account2.domain, account1.domain, account3.domain])
    }

    func testWhenComparingDomainsThenMissingDomainSortedFirst() {
        let account1 = websiteAccountFor(domain: "b.com")
        let account2 = websiteAccountFor(domain: "")
        let account3 = websiteAccountFor(domain: "c.com")

        let accounts = [account1, account2, account3]
        let sortedAccounts = accounts.sorted(by: {
            autofillDomainNameUrlSort.compareAccountsForSortingAutofill(lhs: $0, rhs: $1, tld: tld) == .orderedAscending
        })
        XCTAssertEqual(sortedAccounts.map { $0.domain }, [account2.domain, account1.domain, account3.domain])
    }

    func testWhenComparingDomainsThenInvalidDomainInitialUsedForSorting() {
        let account1 = websiteAccountFor(domain: "b.com")
        let account2 = websiteAccountFor(domain: "An invalid domain")
        let account3 = websiteAccountFor(domain: "c.com")

        let accounts = [account1, account2, account3]
        let sortedAccounts = accounts.sorted(by: {
            autofillDomainNameUrlSort.compareAccountsForSortingAutofill(lhs: $0, rhs: $1, tld: tld) == .orderedAscending
        })
        XCTAssertEqual(sortedAccounts.map { $0.domain }, [account2.domain, account1.domain, account3.domain])
    }

    func testWhenCombinationOfDomainsAndTitlesThenTitlesTakePreferenceWhenTheyExist() {
        let account1 = websiteAccountFor(domain: "a.com", title: "Test")
        let account2 = websiteAccountFor(domain: "b.com")
        let account3 = websiteAccountFor(domain: "c.com", title: "Hello World")
        let account4 = websiteAccountFor(domain: "d.com", title: "")

        let accounts = [account1, account2, account3, account4]
        let sortedAccounts = accounts.sorted(by: {
            autofillDomainNameUrlSort.compareAccountsForSortingAutofill(lhs: $0, rhs: $1, tld: tld) == .orderedAscending
        })
        XCTAssertEqual(sortedAccounts.map { $0.title }, [account2.title, account4.title, account3.title, account1.title])
        XCTAssertEqual(sortedAccounts.map { $0.domain }, [account2.domain, account4.domain, account3.domain, account1.domain])
    }

    func testWhenSpecialCharactersInTitleThenSortedAmongLetters() {
        let account1 = websiteAccountFor(domain: "a.com", title: "èlephant")
        let account2 = websiteAccountFor(domain: "b.com", title: "elephant")
        let account3 = websiteAccountFor(domain: "c.com", title: "elephants")

        let accounts = [account1, account2, account3]
        let sortedAccounts = accounts.sorted(by: {
            autofillDomainNameUrlSort.compareAccountsForSortingAutofill(lhs: $0, rhs: $1, tld: tld) == .orderedAscending
        })
        XCTAssertEqual(sortedAccounts.map { $0.title }, [account2.title, account1.title, account3.title])
    }

    func testWhenComparingSubdomainsWithSitesFromSameDomainWithoutSubdomainThenTopSiteSortedFirst() {
        let account1 = websiteAccountFor(domain: "www.example.com")
        let account2 = websiteAccountFor(domain: "example.com")
        let account3 = websiteAccountFor(domain: "accounts.example.com")

        let accounts = [account1, account2, account3]
        let sortedAccounts = accounts.sorted(by: {
            autofillDomainNameUrlSort.compareAccountsForSortingAutofill(lhs: $0, rhs: $1, tld: tld) == .orderedAscending
        })
        XCTAssertEqual(sortedAccounts.map { $0.domain }, [account2.domain, account3.domain, account1.domain])
    }

    func testWhenComparingMixtureOfTitlesSitesWithSubdomainsAndSomeWithoutThenCorrectOrder() {
        let account1 = websiteAccountFor(domain: "www.google.com", title: "Google")
        let account2 = websiteAccountFor(domain: "google.com")
        let account3 = websiteAccountFor(domain: "www.godaddy.com")
        let account4 = websiteAccountFor(domain: "www.google.com")
        let account5 = websiteAccountFor(domain: "accounts.google.com")

        let accounts = [account1, account2, account3, account4, account5]
        let sortedAccounts = accounts.sorted(by: {
            autofillDomainNameUrlSort.compareAccountsForSortingAutofill(lhs: $0, rhs: $1, tld: tld) == .orderedAscending
        })
        XCTAssertEqual(sortedAccounts.map { $0.domain }, [account3.domain, account1.domain, account2.domain, account5.domain, account4.domain])
    }

    func websiteAccountFor(domain: String = "", title: String? = "") -> SecureVaultModels.WebsiteAccount {
        return SecureVaultModels.WebsiteAccount(id: "1", title: title, username: "", domain: domain, created: Date(), lastUpdated: Date())
    }
}
