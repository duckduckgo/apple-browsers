//
//  CPMSiteRankLookupTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
@testable import WebExtensions

/// The expected values come from the DDG extension: `tldts.getDomain()` and `@duckduckgo/jsbloom` with the same
/// `cpm-top-sites-bloom.json`. They must stay the same, so that the legacy CPM and the embedded extension send the same buckets.
final class CPMSiteRankLookupTests: XCTestCase {

    private let lookup = CPMSiteRankLookup()

    func testWhenSiteIsATopSiteThenRankIsTop10k() {
        XCTAssertEqual(lookup.siteRank(for: URL(string: "https://google.com/")), .top10k)
        XCTAssertEqual(lookup.siteRank(for: URL(string: "https://www.google.com/search?q=test")), .top10k)
        XCTAssertEqual(lookup.siteRank(for: URL(string: "https://m.youtube.com/watch")), .top10k)
        XCTAssertEqual(lookup.siteRank(for: URL(string: "https://en.wikipedia.org/wiki/Main_Page")), .top10k)
        XCTAssertEqual(lookup.siteRank(for: URL(string: "https://www.bbc.co.uk/news")), .top10k)
    }

    func testWhenSiteIsUnknownOrInvalidThenRankIsOther() {
        XCTAssertEqual(lookup.siteRank(for: URL(string: "https://www.a8f3k2j9x7q1.example/")), .other)
        XCTAssertEqual(lookup.siteRank(for: URL(string: "https://example.com/")), .other)
        XCTAssertEqual(lookup.siteRank(for: URL(string: "http://192.168.1.1/")), .other)
        XCTAssertEqual(lookup.siteRank(for: URL(string: "http://localhost:8080/")), .other)
        XCTAssertEqual(lookup.siteRank(for: URL(string: "about:blank")), .other)
        XCTAssertEqual(lookup.siteRank(for: nil), .other)
    }

    func testWhenDataCannotBeLoadedThenRankIsNil() {
        let lookup = CPMSiteRankLookup(data: { nil })
        XCTAssertNil(lookup.siteRank(for: URL(string: "https://www.google.com/")))
    }

    func testRegistrableDomainIsTheSameAsInTheExtension() throws {
        let publicSuffixList = try XCTUnwrap(CPMSiteRankLookup.loadPublicSuffixList())
        let cases: [(host: String, domain: String?)] = [
            ("www.google.com", "google.com"),
            ("google.com", "google.com"),
            ("www.bbc.co.uk", "bbc.co.uk"),
            ("a.b.c.example.com.au", "example.com.au"),
            ("WWW.Example.COM", "example.com"),
            ("example.com.", "example.com"),
            // private suffixes are not used
            ("user.github.io", "github.io"),
            ("shop.myshopify.com", "myshopify.com"),
            ("foo.blogspot.com", "blogspot.com"),
            // wildcard and exception rules: *.ck, !www.ck, *.kawasaki.jp, !city.kawasaki.jp
            ("bar.ck", nil),
            ("foo.bar.ck", "foo.bar.ck"),
            ("www.ck", "www.ck"),
            ("foo.www.ck", "www.ck"),
            ("kawasaki.jp", "kawasaki.jp"),
            ("bar.kawasaki.jp", nil),
            ("foo.bar.kawasaki.jp", "foo.bar.kawasaki.jp"),
            ("city.kawasaki.jp", "city.kawasaki.jp"),
            ("www.city.kawasaki.jp", "city.kawasaki.jp"),
            // IDN rules match punycode hosts
            ("foo.xn--55qx5d.cn", "foo.xn--55qx5d.cn"),
            ("xn--80aswg.xn--p1ai", "xn--80aswg.xn--p1ai"),
            // unknown TLD: the public suffix is the last label
            ("foo.unknowntld", "foo.unknowntld"),
            ("co.uk", nil),
            ("com", nil),
            ("localhost", nil),
            ("192.168.1.1", nil),
            ("::1", nil),
        ]
        for testCase in cases {
            XCTAssertEqual(publicSuffixList.registrableDomain(of: testCase.host), testCase.domain, testCase.host)
        }
    }

    func testHashesAreTheSameAsInJSBloom() {
        let cases: [(string: String, djb2: UInt32, sdbm: UInt32)] = [
            ("", 5381, 0),
            ("a", 177604, 97),
            ("google.com", 2128662947, 1986441324),
            ("bücher.de", 2760085576, 3309094019),
            ("example.😀", 3371728894, 2327081767),
            ("a-very-long-subdomain-name-to-overflow.example.co.uk", 3903400390, 2391304487),
        ]
        for testCase in cases {
            let codeUnits = Array(testCase.string.utf16)
            XCTAssertEqual(JSBloomFilter.djb2(codeUnits), testCase.djb2, testCase.string)
            XCTAssertEqual(JSBloomFilter.sdbm(codeUnits), testCase.sdbm, testCase.string)
        }
    }

    func testFalseMatchesAreTheSameAsInJSBloom() throws {
        let filter = try XCTUnwrap(CPMSiteRankLookup.loadBundledFilter())
        let matches = (0..<20000).filter { filter.contains("fp-test-\($0).com") }
        XCTAssertEqual(matches, [176, 2651, 5023, 5669, 8606, 9610, 9948, 10007, 10627, 10683, 12672, 14201, 14500, 17167, 17763, 19088])
    }
}
