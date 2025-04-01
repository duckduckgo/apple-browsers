//
//  AutofillDomainNameUrlMatcherTests.swift
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

final class AutofillDomainNameUrlMatcherTests: XCTestCase {

    private let tld = TLD()
    private let autofillDomainNameUrlMatcher = AutofillDomainNameUrlMatcher()

    func testCleanRawUrl() {
        XCTAssertEqual("www.example.com", autofillDomainNameUrlMatcher.normalizeUrlForWeb("https://www.example.com"))
        XCTAssertEqual("login.example.com", autofillDomainNameUrlMatcher.normalizeUrlForWeb("https://login.example.com"))
        XCTAssertEqual("www.example.com:8080", autofillDomainNameUrlMatcher.normalizeUrlForWeb("https://www.example.com:8080"))
        XCTAssertEqual("ftp://www.example.com:8080", autofillDomainNameUrlMatcher.normalizeUrlForWeb("ftp://www.example.com:8080"))
        XCTAssertEqual("www.foo.com", autofillDomainNameUrlMatcher.normalizeUrlForWeb("https://www.foo.com/path/to/foo?key=value"))
        XCTAssertEqual("www.fuu.foo.com", autofillDomainNameUrlMatcher.normalizeUrlForWeb("https://www.fuu.foo.com/path/to/foo?key=value"))
        XCTAssertEqual("foo.com", autofillDomainNameUrlMatcher.normalizeUrlForWeb("http://foo.com/path/to/foo?key=value"))
        XCTAssertEqual("fuu.foo.com", autofillDomainNameUrlMatcher.normalizeUrlForWeb("http://fuu.foo.com/path/to/foo?key=value"))
        XCTAssertEqual("foo.com:9000", autofillDomainNameUrlMatcher.normalizeUrlForWeb("http://foo.com:9000/path/to/foo?key=value"))
        XCTAssertEqual("fuu.foo.com:9000", autofillDomainNameUrlMatcher.normalizeUrlForWeb("http://fuu.foo.com:9000/path/to/foo?key=value"))
        XCTAssertEqual("faa.fuu.foo.com:9000", autofillDomainNameUrlMatcher.normalizeUrlForWeb("http://faa.fuu.foo.com:9000/path/to/foo?key=value"))
        XCTAssertEqual("foo.com", autofillDomainNameUrlMatcher.normalizeUrlForWeb("foo.com/path/to/foo"))
        XCTAssertEqual("www.foo.com", autofillDomainNameUrlMatcher.normalizeUrlForWeb("www.foo.com/path/to/foo"))
        XCTAssertEqual("foo.com", autofillDomainNameUrlMatcher.normalizeUrlForWeb("foo.com"))
        XCTAssertEqual("foo.com:9000", autofillDomainNameUrlMatcher.normalizeUrlForWeb("foo.com:9000"))
        XCTAssertEqual("fuu.foo.com", autofillDomainNameUrlMatcher.normalizeUrlForWeb("fuu.foo.com"))
        XCTAssertEqual("192.168.0.1", autofillDomainNameUrlMatcher.normalizeUrlForWeb("192.168.0.1"))
        XCTAssertEqual("192.168.0.1:9000", autofillDomainNameUrlMatcher.normalizeUrlForWeb("192.168.0.1:9000"))
        XCTAssertEqual("192.168.0.1", autofillDomainNameUrlMatcher.normalizeUrlForWeb("http://192.168.0.1"))
        XCTAssertEqual("192.168.0.1:9000", autofillDomainNameUrlMatcher.normalizeUrlForWeb("http://192.168.0.1:9000"))
        XCTAssertEqual("fuu.foo.com:9000", autofillDomainNameUrlMatcher.normalizeUrlForWeb("fuu.foo.com:9000"))
        XCTAssertEqual("RandomText", autofillDomainNameUrlMatcher.normalizeUrlForWeb("thisIs@RandomText"))
    }

    func testWhenUrlsAreIdenticalThenMatchingForAutofill() {
        let currentUrl = "https://example.com"
        let savedUrl = "https://example.com"
        XCTAssertTrue(autofillDomainNameUrlMatcher.isMatchingForAutofill(currentSite: currentUrl, savedSite: savedUrl, tld: tld))
    }

    func testWhenUrlsAreIdenticalExceptForUppercaseVisitedSiteThenMatchingForAutofill() {
        let currentUrl = "https://example.com"
        let savedUrl = "https://EXAMPLE.COM"
        XCTAssertTrue(autofillDomainNameUrlMatcher.isMatchingForAutofill(currentSite: currentUrl, savedSite: savedUrl, tld: tld))
    }

    func testWhenUrlsAreIdenticalExceptForUppercaseSavedSiteThenMatchingForAutofill() {
        let currentUrl = "https://EXAMPLE.COM"
        let savedUrl = "https://example.com"
        XCTAssertTrue(autofillDomainNameUrlMatcher.isMatchingForAutofill(currentSite: currentUrl, savedSite: savedUrl, tld: tld))
    }

    func testWhenBothUrlsContainSameSubdomainThenMatchingForAutofill() {
        let currentUrl = "login.example.com"
        let savedUrl = "login.example.com"
        XCTAssertTrue(autofillDomainNameUrlMatcher.isMatchingForAutofill(currentSite: currentUrl, savedSite: savedUrl, tld: tld))
    }

    func testWhenBothUrlsContainWwwSubdomainThenMatchingForAutofill() {
        let currentUrl = "www.example.com"
        let savedUrl = "www.example.com"
        XCTAssertTrue(autofillDomainNameUrlMatcher.isMatchingForAutofill(currentSite: currentUrl, savedSite: savedUrl, tld: tld))
    }

    func testWhenSavedSiteContainsSubdomainAndVisitedSiteDoesNotThenMatchingForAutofill() {
        let currentUrl = "example.com"
        let savedUrl = "login.example.com"
        XCTAssertTrue(autofillDomainNameUrlMatcher.isMatchingForAutofill(currentSite: currentUrl, savedSite: savedUrl, tld: tld))
    }

    func testWhenSavedSiteDoesNotContainSubdomainAndVisitedSiteDoesThenMatchingForAutofill() {
        let currentUrl = "login.example.com"
        let savedUrl = "example.com"
        XCTAssertTrue(autofillDomainNameUrlMatcher.isMatchingForAutofill(currentSite: currentUrl, savedSite: savedUrl, tld: tld))
    }

    func testWhenUrlsHaveDifferentSubdomainsThenMatchingForAutofill() {
        let currentUrl = "login.example.com"
        let savedUrl = "test.example.com"
        XCTAssertTrue(autofillDomainNameUrlMatcher.isMatchingForAutofill(currentSite: currentUrl, savedSite: savedUrl, tld: tld))
    }

    func testWhenSavedSiteContainsWwwSubdomainAndVisitedSiteDoesNotThenMatchingForAutofill() {
        let currentUrl = "example.com"
        let savedUrl = "www.example.com"
        XCTAssertTrue(autofillDomainNameUrlMatcher.isMatchingForAutofill(currentSite: currentUrl, savedSite: savedUrl, tld: tld))
    }

    func testWhenSavedSiteMatchesVisitedExceptForPortThenNotMatchingForAutofill() {
        let currentUrl = "example.com:443"
        let savedUrl = "example.com:8080"
        XCTAssertFalse(autofillDomainNameUrlMatcher.isMatchingForAutofill(currentSite: currentUrl, savedSite: savedUrl, tld: tld))
    }

    func testWhenSavedSiteMatchesVisitedAndEqualPortsThenMatchingForAutofill() {
        let currentUrl = "example.com:443"
        let savedUrl = "example.com:443"
        XCTAssertTrue(autofillDomainNameUrlMatcher.isMatchingForAutofill(currentSite: currentUrl, savedSite: savedUrl, tld: tld))
    }

    func testWhenSavedSiteMatchesVisitedAndSavedSiteMissingPortThenNotMatchingForAutofill() {
        let currentUrl = "example.com:443"
        let savedUrl = "example.com"
        XCTAssertFalse(autofillDomainNameUrlMatcher.isMatchingForAutofill(currentSite: currentUrl, savedSite: savedUrl, tld: tld))
    }

    func testWhenSavedSiteMatchesVisitedAndVisitedSiteMissingPortThenNotMatchingForAutofill() {
        let currentUrl = "example.com"
        let savedUrl = "example.com:443"
        XCTAssertFalse(autofillDomainNameUrlMatcher.isMatchingForAutofill(currentSite: currentUrl, savedSite: savedUrl, tld: tld))
    }

    func testWhenSavedSiteContainsUppercaseWwwSubdomainAndVisitedSiteDoesNotThenMatchingForAutofill() {
        let currentUrl = "example.com"
        let savedUrl = "WWW.example.com"
        XCTAssertTrue(autofillDomainNameUrlMatcher.isMatchingForAutofill(currentSite: currentUrl, savedSite: savedUrl, tld: tld))
    }

    func testWhenSavedSiteDoesNotContainSubdomainAndVisitedSiteDoesContainWwwSubdomainThenMatchingForAutofill() {
        let currentUrl = "www.example.com"
        let savedUrl = "example.com"
        XCTAssertTrue(autofillDomainNameUrlMatcher.isMatchingForAutofill(currentSite: currentUrl, savedSite: savedUrl, tld: tld))
    }

    func testWhenSavedSiteDoesNotContainSubdomainAndVisitedSiteDoesContainUppercaseWwwSubdomainThenMatchingForAutofill() {
        let currentUrl = "WWW.example.com"
        let savedUrl = "example.com"
        XCTAssertTrue(autofillDomainNameUrlMatcher.isMatchingForAutofill(currentSite: currentUrl, savedSite: savedUrl, tld: tld))
    }

    func testWhenSavedSiteContainNestedSubdomainsAndVisitedSiteContainsMatchingRootSubdomainThenMatchingForAutofill() {
        let currentUrl = "a.example.com"
        let savedUrl = "login.a.example.com"
        XCTAssertTrue(autofillDomainNameUrlMatcher.isMatchingForAutofill(currentSite: currentUrl, savedSite: savedUrl, tld: tld))
    }

    func testWhenSavedSiteContainSubdomainAndVisitedSiteContainsNestedSubdomainsThenMatchingForAutofill() {
        let currentUrl = "login.a.example.com"
        let savedUrl = "a.example.com"
        XCTAssertTrue(autofillDomainNameUrlMatcher.isMatchingForAutofill(currentSite: currentUrl, savedSite: savedUrl, tld: tld))
    }

    func testWhenSavedSiteHasNoSubdomainAndVisitedMaliciousSitePartiallyContainSavedSiteThenNoMatchingForAutofill() {
        let currentUrl = "example.com"
        let savedUrl = "example.com.evil.com"
        XCTAssertFalse(autofillDomainNameUrlMatcher.isMatchingForAutofill(currentSite: currentUrl, savedSite: savedUrl, tld: tld))
    }

    func testWhenSavedMaliciousSitePartiallyContainsVisitedSiteThenNoMatchingForAutofill() {
        let currentUrl = "example.com.evil.com"
        let savedUrl = "example.com"
        XCTAssertFalse(autofillDomainNameUrlMatcher.isMatchingForAutofill(currentSite: currentUrl, savedSite: savedUrl, tld: tld))
    }
}
