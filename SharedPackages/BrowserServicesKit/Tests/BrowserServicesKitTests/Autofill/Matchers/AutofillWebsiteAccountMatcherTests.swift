//
//  AutofillWebsiteAccountMatcherTests.swift
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

final class AutofillWebsiteAccountMatcherTests: XCTestCase {

    private let tld = TLD()
    private let autofillDomainNameUrlMatcher = AutofillDomainNameUrlMatcher()
    private var autofillWebsiteAccountMatcher: AutofillWebsiteAccountMatcher!

    override func setUp() {
        super.setUp()
        autofillWebsiteAccountMatcher = AutofillWebsiteAccountMatcher(autofillUrlMatcher: autofillDomainNameUrlMatcher,
                                                                      tld: tld)
    }

    override func tearDown() {
        autofillWebsiteAccountMatcher = nil
        super.tearDown()
    }

    func testWhenOnlyOnePerfectMatchThenCorrectlyPutIntoPerfectMatches() {
        let accounts = [websiteAccountFor(domain: "example.com")]
        let matches = autofillWebsiteAccountMatcher.findDeduplicatedSortedMatches(accounts: accounts, for: "example.com")
        XCTAssertEqual(matches.perfectMatches.count, 1)
        XCTAssertEqual(matches.partialMatches.count, 0)
    }

    func testWhenMultiplePerfectMatchesThenAllCorrectlyGroupedIntoPerfectMatches() {
        let accounts = [websiteAccountFor(domain: "example.com"),
                        websiteAccountFor(domain: "example.com"),
                        websiteAccountFor(domain: "example.com")]
        let matches = autofillWebsiteAccountMatcher.findDeduplicatedSortedMatches(accounts: accounts, for: "example.com")
        XCTAssertEqual(matches.perfectMatches.count, 3)
        XCTAssertEqual(matches.partialMatches.count, 0)
    }

    func testWhenNotAMatchThenNotIncludedInGroups() {
        let accounts = [websiteAccountFor(domain: "example.com")]
        let matches = autofillWebsiteAccountMatcher.findDeduplicatedSortedMatches(accounts: accounts, for: "example.org")
        XCTAssertEqual(matches.perfectMatches.count, 0)
        XCTAssertEqual(matches.partialMatches.count, 0)
    }

    func testWhenSinglePartialMatchThenGetsItsOwnGroup() {
        let accounts = [websiteAccountFor(domain: "foo.example.com")]
        let matches = autofillWebsiteAccountMatcher.findDeduplicatedSortedMatches(accounts: accounts, for: "example.com")
        XCTAssertEqual(matches.perfectMatches.count, 0)
        XCTAssertEqual(matches.partialMatches.count, 1)
    }

    func testWhenMultiplePartialMatchesWithSameSubdomainThenAllShareAGroup() {
        let accounts = [websiteAccountFor(domain: "foo.example.com"),
                        websiteAccountFor(domain: "foo.example.com")]
        let matches = autofillWebsiteAccountMatcher.findDeduplicatedSortedMatches(accounts: accounts, for: "example.com")
        XCTAssertEqual(matches.perfectMatches.count, 0)
        XCTAssertEqual(matches.partialMatches.count, 1)
        XCTAssertEqual(matches.partialMatches["foo.example.com"]?.count, 2)
    }

    func testWhenMultipleDifferentPartialMatchesThenEachGetsTheirOwnGroup() {
        let accounts = [websiteAccountFor(domain: "foo.example.com"),
                        websiteAccountFor(domain: "bar.example.com"),
                        websiteAccountFor(domain: "bar.example.com")]
        let matches = autofillWebsiteAccountMatcher.findDeduplicatedSortedMatches(accounts: accounts, for: "example.com")
        XCTAssertEqual(matches.perfectMatches.count, 0)
        XCTAssertEqual(matches.partialMatches.count, 2)
        XCTAssertEqual(matches.partialMatches["foo.example.com"]?.count, 1)
        XCTAssertEqual(matches.partialMatches["bar.example.com"]?.count, 2)
    }

    func testWhenSortingPerfectMatchesThenLastEditedSortedFirst() {
        let now = Date()
        let accounts = [websiteAccountFor(domain: "example.com", lastUpdated: now.addingTimeInterval(-24*60*60*2)),
                        websiteAccountFor(domain: "example.com", lastUpdated: now.addingTimeInterval(-24*60*60)),
                        websiteAccountFor(domain: "example.com", lastUpdated: now.addingTimeInterval(-1))]
        let matches = autofillWebsiteAccountMatcher.findDeduplicatedSortedMatches(accounts: accounts, for: "example.com")
        XCTAssertEqual(matches.perfectMatches[0].lastUpdated, now.addingTimeInterval(-1))
        XCTAssertEqual(matches.perfectMatches[1].lastUpdated, now.addingTimeInterval(-24*60*60))
        XCTAssertEqual(matches.perfectMatches[2].lastUpdated, now.addingTimeInterval(-24*60*60*2))
    }

    func testWhenSortingPartialMatchesThenLastEditedSortedFirst() {
        let now = Date()
        let accounts = [websiteAccountFor(domain: "foo.example.com", lastUpdated: now.addingTimeInterval(-24*60*60*2)),
                        websiteAccountFor(domain: "foo.example.com", lastUpdated: now.addingTimeInterval(-24*60*60)),
                        websiteAccountFor(domain: "foo.example.com", lastUpdated: now.addingTimeInterval(-1))]
        let matches = autofillWebsiteAccountMatcher.findDeduplicatedSortedMatches(accounts: accounts, for: "example.com")
        XCTAssertEqual(matches.partialMatches["foo.example.com"]?[0].lastUpdated, now.addingTimeInterval(-1))
        XCTAssertEqual(matches.partialMatches["foo.example.com"]?[1].lastUpdated, now.addingTimeInterval(-24*60*60))
        XCTAssertEqual(matches.partialMatches["foo.example.com"]?[2].lastUpdated, now.addingTimeInterval(-24*60*60*2))
    }

    func websiteAccountFor(domain: String = "", lastUpdated: Date = Date()) -> SecureVaultModels.WebsiteAccount {
        return SecureVaultModels.WebsiteAccount(id: "1", title: "", username: "", domain: domain, created: Date(), lastUpdated: lastUpdated)
    }
}
