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


    private func makeLegacyFireproofing() -> UserDefaultsFireproofing {
        UserDefaultsFireproofing(isFireproofingETLDPlus1Enabled: { false })
    }

    private func makeETLDPlus1Fireproofing() -> UserDefaultsFireproofing {
        UserDefaultsFireproofing(isFireproofingETLDPlus1Enabled: { true })
    }


    func testLegacy_WhenAllowedDomainsContainsFireproofedDomainThenReturnsTrue() {
        let fireproofing = makeLegacyFireproofing()
        XCTAssertFalse(fireproofing.isAllowed(fireproofDomain: "example.com"))
        fireproofing.addToAllowed(domain: "example.com")
        XCTAssertTrue(fireproofing.isAllowed(fireproofDomain: "example.com"))
    }

    func testLegacy_AllowedCookieDomains() {
        let fireproofing = makeLegacyFireproofing()
        fireproofing.addToAllowed(domain: "example.com")
        XCTAssertTrue(fireproofing.isAllowed(cookieDomain: ".example.com"))
        XCTAssertFalse(fireproofing.isAllowed(cookieDomain: "subdomain.example.com"))
        XCTAssertFalse(fireproofing.isAllowed(cookieDomain: ".subdomain.example.com"))
    }

    func testLegacy_WhenNewThenAllowedDomainsIsEmpty() {
        let fireproofing = makeLegacyFireproofing()
        XCTAssertTrue(fireproofing.allowedDomains.isEmpty)
    }

    func testLegacy_DuckDuckGoIsFireproofed() {
        let fireproofing = makeLegacyFireproofing()
        XCTAssertTrue(fireproofing.isAllowed(fireproofDomain: "duckduckgo.com"))
        XCTAssertTrue(fireproofing.isAllowed(cookieDomain: "duckduckgo.com"))
        XCTAssertFalse(fireproofing.isAllowed(cookieDomain: "test.duckduckgo.com"))
    }

    func testLegacy_DuckAiIsFireproofed() {
        let fireproofing = makeLegacyFireproofing()
        XCTAssertTrue(fireproofing.isAllowed(fireproofDomain: "duck.ai"))
        XCTAssertTrue(fireproofing.isAllowed(cookieDomain: "duck.ai"))
        XCTAssertFalse(fireproofing.isAllowed(cookieDomain: "test.duck.ai"))
    }


    func testETLDPlus1_WhenSubdomainFireproofed_ThenSiblingSubdomainIsAllowed() {
        let fireproofing = makeETLDPlus1Fireproofing()
        fireproofing.addToAllowed(domain: "login.example.com")
        XCTAssertTrue(fireproofing.isAllowed(fireproofDomain: "docs.example.com"))
        XCTAssertTrue(fireproofing.isAllowed(fireproofDomain: "example.com"))
    }

    func testETLDPlus1_WhenSubdomainFireproofed_ThenCookieForParentDomainIsAllowed() {
        let fireproofing = makeETLDPlus1Fireproofing()
        fireproofing.addToAllowed(domain: "login.example.com")
        XCTAssertTrue(fireproofing.isAllowed(cookieDomain: ".example.com"))
        XCTAssertTrue(fireproofing.isAllowed(cookieDomain: "example.com"))
        XCTAssertTrue(fireproofing.isAllowed(cookieDomain: "docs.example.com"))
    }

    func testETLDPlus1_WhenSubdomainFireproofed_ThenUnrelatedDomainIsNotAllowed() {
        let fireproofing = makeETLDPlus1Fireproofing()
        fireproofing.addToAllowed(domain: "login.example.com")
        XCTAssertFalse(fireproofing.isAllowed(fireproofDomain: "other.com"))
        XCTAssertFalse(fireproofing.isAllowed(cookieDomain: "other.com"))
    }

    func testETLDPlus1_WhenBarePublicSuffixAdded_ThenNotFireproofed() {
        let fireproofing = makeETLDPlus1Fireproofing()
        fireproofing.addToAllowed(domain: "github.io")
        XCTAssertFalse(fireproofing.isAllowed(fireproofDomain: "github.io"))
        XCTAssertFalse(fireproofing.isAllowed(fireproofDomain: "myproject.github.io"))
    }

    func testETLDPlus1_WhenPSLSubdomainFireproofed_ThenOnlyThatSiteIsFireproofed() {
        let fireproofing = makeETLDPlus1Fireproofing()
        fireproofing.addToAllowed(domain: "myproject.github.io")
        XCTAssertTrue(fireproofing.isAllowed(fireproofDomain: "myproject.github.io"))
        XCTAssertFalse(fireproofing.isAllowed(fireproofDomain: "otherproject.github.io"))
    }

    func testETLDPlus1_WhenMultiPartTLDFireproofed_ThenMatchesCorrectly() {
        let fireproofing = makeETLDPlus1Fireproofing()
        fireproofing.addToAllowed(domain: "login.example.co.uk")
        XCTAssertTrue(fireproofing.isAllowed(fireproofDomain: "shop.example.co.uk"))
        XCTAssertFalse(fireproofing.isAllowed(fireproofDomain: "other.co.uk"))
    }

    func testETLDPlus1_WhenCookieDomainHasLeadingDot_ThenDotIsStrippedBeforeNormalization() {
        let fireproofing = makeETLDPlus1Fireproofing()
        fireproofing.addToAllowed(domain: "example.com")
        XCTAssertTrue(fireproofing.isAllowed(cookieDomain: ".example.com"))
    }

    func testETLDPlus1_WhenCookieDomainIsBareTLD_ThenNotAllowed() {
        let fireproofing = makeETLDPlus1Fireproofing()
        XCTAssertFalse(fireproofing.isAllowed(cookieDomain: ".com"))
        XCTAssertFalse(fireproofing.isAllowed(cookieDomain: ".co.uk"))
    }

    func testETLDPlus1_DuckDuckGoRemainsFireproofed() {
        let fireproofing = makeETLDPlus1Fireproofing()
        XCTAssertTrue(fireproofing.isAllowed(fireproofDomain: "duckduckgo.com"))
        XCTAssertTrue(fireproofing.isAllowed(cookieDomain: ".duckduckgo.com"))
        XCTAssertTrue(fireproofing.isAllowed(cookieDomain: "duckduckgo.com"))
    }

    func testETLDPlus1_DuckAiRemainsFireproofed() {
        let fireproofing = makeETLDPlus1Fireproofing()
        XCTAssertTrue(fireproofing.isAllowed(fireproofDomain: "duck.ai"))
        XCTAssertTrue(fireproofing.isAllowed(cookieDomain: "duck.ai"))
    }


    func testETLDPlus1_WhenDomainAdded_ThenAllowedDomainsShowsNormalized() {
        let fireproofing = makeETLDPlus1Fireproofing()
        fireproofing.addToAllowed(domain: "login.example.com")
        XCTAssertTrue(fireproofing.allowedDomains.contains("example.com"))
        XCTAssertFalse(fireproofing.allowedDomains.contains("login.example.com"))
    }

    func testETLDPlus1_WhenDomainRemoved_ThenAllowedDomainsIsEmpty() {
        let fireproofing = makeETLDPlus1Fireproofing()
        fireproofing.addToAllowed(domain: "login.example.com")
        fireproofing.remove(domain: "example.com")
        XCTAssertTrue(fireproofing.allowedDomains.isEmpty)
    }

    func testETLDPlus1_WhenClearAllCalled_ThenAllowedDomainsIsEmpty() {
        let fireproofing = makeETLDPlus1Fireproofing()
        fireproofing.addToAllowed(domain: "example.com")
        fireproofing.addToAllowed(domain: "other.org")
        fireproofing.clearAll()
        XCTAssertTrue(fireproofing.allowedDomains.isEmpty)
    }

    func testETLDPlus1_WhenPublicSuffixAdded_ThenNotInAllowedDomains() {
        let fireproofing = makeETLDPlus1Fireproofing()
        fireproofing.addToAllowed(domain: "github.io")
        XCTAssertTrue(fireproofing.allowedDomains.isEmpty)
    }

    func testETLDPlus1_WhenDuplicateSubdomainsAdded_ThenSingleEntryInAllowedDomains() {
        let fireproofing = makeETLDPlus1Fireproofing()
        fireproofing.addToAllowed(domain: "login.example.com")
        fireproofing.addToAllowed(domain: "docs.example.com")
        XCTAssertEqual(fireproofing.allowedDomains, ["example.com"])
    }


    func testMigration_NormalizesAndDeduplicates() {
        let fireproofing = makeLegacyFireproofing()
        fireproofing.addToAllowed(domain: "old.reddit.com")
        fireproofing.addToAllowed(domain: "www.reddit.com")
        fireproofing.addToAllowed(domain: "fantasy.premierleague.com")
        fireproofing.addToAllowed(domain: "myproject.github.io")
        fireproofing.etldPlus1AllowedDomains = []

        let didMigrate = fireproofing.migrateFireproofDomainsToETLDPlus1IfNeeded()

        XCTAssertTrue(didMigrate)
        let migrated = Set(fireproofing.etldPlus1AllowedDomains)
        XCTAssertEqual(migrated, ["reddit.com", "premierleague.com", "myproject.github.io"])
        XCTAssertEqual(migrated.count, 3, "Two reddit subdomains should collapse into one entry")
    }

    func testMigration_IsIdempotent() {
        let fireproofing = makeLegacyFireproofing()
        fireproofing.addToAllowed(domain: "example.com")
        fireproofing.etldPlus1AllowedDomains = []

        XCTAssertTrue(fireproofing.migrateFireproofDomainsToETLDPlus1IfNeeded())
        XCTAssertFalse(fireproofing.migrateFireproofDomainsToETLDPlus1IfNeeded())
    }

    func testMigration_SkipsUnresolvableDomains() {
        let fireproofing = makeLegacyFireproofing()
        fireproofing.addToAllowed(domain: "example.com")
        fireproofing.addToAllowed(domain: "github.io")
        fireproofing.etldPlus1AllowedDomains = []

        fireproofing.migrateFireproofDomainsToETLDPlus1IfNeeded()

        XCTAssertTrue(fireproofing.etldPlus1AllowedDomains.contains("example.com"))
        XCTAssertFalse(fireproofing.etldPlus1AllowedDomains.contains("github.io"))
        XCTAssertTrue(fireproofing.legacyAllowedDomains.contains("github.io"))
    }

    func testMigration_WithEmptyLegacyStore_SetsFlagAndReturnsFalse() {
        let fireproofing = makeLegacyFireproofing()

        XCTAssertFalse(fireproofing.migrateFireproofDomainsToETLDPlus1IfNeeded())
        XCTAssertFalse(fireproofing.migrateFireproofDomainsToETLDPlus1IfNeeded())
    }

}
