//
//  UserDefaultsFireproofingTests.swift
//  UnitTests
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
@testable import Core
@testable import Subscription

class UserDefaultsFireproofingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        setupUserDefault(with: #file)
        UserDefaultsWrapper<Any>.clearAll()
    }

    private func makeFireproofing() -> UserDefaultsFireproofing {
        UserDefaultsFireproofing()
    }


    func testWhenSubdomainFireproofed_ThenSiblingSubdomainIsAllowed() {
        let fireproofing = makeFireproofing()
        fireproofing.addToAllowed(domain: "login.example.com")
        XCTAssertTrue(fireproofing.isAllowed(fireproofDomain: "docs.example.com"))
        XCTAssertTrue(fireproofing.isAllowed(fireproofDomain: "example.com"))
    }

    func testWhenSubdomainFireproofed_ThenCookieForParentDomainIsAllowed() {
        let fireproofing = makeFireproofing()
        fireproofing.addToAllowed(domain: "login.example.com")
        XCTAssertTrue(fireproofing.isAllowed(cookieDomain: ".example.com"))
        XCTAssertTrue(fireproofing.isAllowed(cookieDomain: "example.com"))
        XCTAssertTrue(fireproofing.isAllowed(cookieDomain: "docs.example.com"))
    }

    func testWhenSubdomainFireproofed_ThenUnrelatedDomainIsNotAllowed() {
        let fireproofing = makeFireproofing()
        fireproofing.addToAllowed(domain: "login.example.com")
        XCTAssertFalse(fireproofing.isAllowed(fireproofDomain: "other.com"))
        XCTAssertFalse(fireproofing.isAllowed(cookieDomain: "other.com"))
    }

    func testWhenBarePublicSuffixAdded_ThenNotFireproofed() {
        let fireproofing = makeFireproofing()
        fireproofing.addToAllowed(domain: "github.io")
        XCTAssertFalse(fireproofing.isAllowed(fireproofDomain: "github.io"))
        XCTAssertFalse(fireproofing.isAllowed(fireproofDomain: "myproject.github.io"))
    }

    func testWhenPSLSubdomainFireproofed_ThenOnlyThatSiteIsFireproofed() {
        let fireproofing = makeFireproofing()
        fireproofing.addToAllowed(domain: "myproject.github.io")
        XCTAssertTrue(fireproofing.isAllowed(fireproofDomain: "myproject.github.io"))
        XCTAssertFalse(fireproofing.isAllowed(fireproofDomain: "otherproject.github.io"))
    }

    func testWhenMultiPartTLDFireproofed_ThenMatchesCorrectly() {
        let fireproofing = makeFireproofing()
        fireproofing.addToAllowed(domain: "login.example.co.uk")
        XCTAssertTrue(fireproofing.isAllowed(fireproofDomain: "shop.example.co.uk"))
        XCTAssertFalse(fireproofing.isAllowed(fireproofDomain: "other.co.uk"))
    }

    func testWhenCookieDomainHasLeadingDot_ThenDotIsStrippedBeforeNormalization() {
        let fireproofing = makeFireproofing()
        fireproofing.addToAllowed(domain: "example.com")
        XCTAssertTrue(fireproofing.isAllowed(cookieDomain: ".example.com"))
    }

    func testWhenCookieDomainIsBareTLD_ThenNotAllowed() {
        let fireproofing = makeFireproofing()
        XCTAssertFalse(fireproofing.isAllowed(cookieDomain: ".com"))
        XCTAssertFalse(fireproofing.isAllowed(cookieDomain: ".co.uk"))
    }

    func testDuckDuckGoRemainsFireproofed() {
        let fireproofing = makeFireproofing()
        XCTAssertTrue(fireproofing.isAllowed(fireproofDomain: "duckduckgo.com"))
        XCTAssertTrue(fireproofing.isAllowed(cookieDomain: ".duckduckgo.com"))
        XCTAssertTrue(fireproofing.isAllowed(cookieDomain: "duckduckgo.com"))
    }

    func testDuckAiRemainsFireproofed() {
        let fireproofing = makeFireproofing()
        XCTAssertTrue(fireproofing.isAllowed(fireproofDomain: "duck.ai"))
        XCTAssertTrue(fireproofing.isAllowed(cookieDomain: "duck.ai"))
    }


    func testWhenDomainAdded_ThenAllowedDomainsShowsNormalized() {
        let fireproofing = makeFireproofing()
        fireproofing.addToAllowed(domain: "login.example.com")
        XCTAssertTrue(fireproofing.allowedDomains.contains("example.com"))
        XCTAssertFalse(fireproofing.allowedDomains.contains("login.example.com"))
    }

    func testWhenDomainRemoved_ThenAllowedDomainsIsEmpty() {
        let fireproofing = makeFireproofing()
        fireproofing.addToAllowed(domain: "login.example.com")
        fireproofing.remove(domain: "example.com")
        XCTAssertTrue(fireproofing.allowedDomains.isEmpty)
    }

    func testWhenClearAllCalled_ThenAllowedDomainsIsEmpty() {
        let fireproofing = makeFireproofing()
        fireproofing.addToAllowed(domain: "example.com")
        fireproofing.addToAllowed(domain: "other.org")
        fireproofing.clearAll()
        XCTAssertTrue(fireproofing.allowedDomains.isEmpty)
    }

    func testWhenPublicSuffixAdded_ThenNotInAllowedDomains() {
        let fireproofing = makeFireproofing()
        fireproofing.addToAllowed(domain: "github.io")
        XCTAssertTrue(fireproofing.allowedDomains.isEmpty)
    }

    func testWhenDuplicateSubdomainsAdded_ThenSingleEntryInAllowedDomains() {
        let fireproofing = makeFireproofing()
        fireproofing.addToAllowed(domain: "login.example.com")
        fireproofing.addToAllowed(domain: "docs.example.com")
        XCTAssertEqual(fireproofing.allowedDomains, ["example.com"])
    }


    func testMigration_NormalizesAndDeduplicates() {
        let fireproofing = makeFireproofing()
        fireproofing.legacyAllowedDomains = ["old.reddit.com", "www.reddit.com", "fantasy.premierleague.com", "myproject.github.io"]

        let didMigrate = fireproofing.migrateFireproofDomainsToETLDPlus1IfNeeded()

        XCTAssertTrue(didMigrate)
        let migrated = Set(fireproofing.etldPlus1AllowedDomains)
        XCTAssertEqual(migrated, ["reddit.com", "premierleague.com", "myproject.github.io"])
        XCTAssertEqual(migrated.count, 3, "Two reddit subdomains should collapse into one entry")
        XCTAssertTrue(fireproofing.legacyAllowedDomains.isEmpty)
    }

    func testMigration_IsIdempotent() {
        let fireproofing = makeFireproofing()
        fireproofing.legacyAllowedDomains = ["example.com"]

        XCTAssertTrue(fireproofing.migrateFireproofDomainsToETLDPlus1IfNeeded())
        XCTAssertFalse(fireproofing.migrateFireproofDomainsToETLDPlus1IfNeeded())
    }

    func testMigration_SkipsUnresolvableDomains() {
        let fireproofing = makeFireproofing()
        fireproofing.legacyAllowedDomains = ["example.com", "github.io"]

        fireproofing.migrateFireproofDomainsToETLDPlus1IfNeeded()

        XCTAssertTrue(fireproofing.etldPlus1AllowedDomains.contains("example.com"))
        XCTAssertFalse(fireproofing.etldPlus1AllowedDomains.contains("github.io"))
        XCTAssertTrue(fireproofing.legacyAllowedDomains.isEmpty)
    }

    func testMigration_WithEmptyLegacyStore_SetsFlagAndReturnsFalse() {
        let fireproofing = makeFireproofing()

        XCTAssertFalse(fireproofing.migrateFireproofDomainsToETLDPlus1IfNeeded())
        XCTAssertFalse(fireproofing.migrateFireproofDomainsToETLDPlus1IfNeeded())
    }

}
