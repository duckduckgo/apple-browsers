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
import ZIPFoundation
@testable import WebExtensions

/// Mirrors `unit-test/background/cpm-site-rank.js` and `unit-test/shared-utils/domain-hashes.js` in
/// duckduckgo-privacy-extension, so that the legacy CPM and the embedded extension send the same buckets.
final class CPMSiteRankLookupTests: XCTestCase {

    private let lookup = CPMSiteRankLookupTests.makeLookup(["google.com", "youtube.com", "wikipedia.org", "bbc.co.uk", "www.gov.uk"])

    func testHashesAreTheSameAsInTheExtension() {
        let cases: [(string: String, hash: UInt32)] = [
            ("", 0x811c9dc5),
            ("a", 0xe40c292c),
            ("foobar", 0xbf9cf968),
            ("example.com", 0x431ceb26),
            ("www.example.com", 0x88469fcb),
            ("bbc.co.uk", 0xe55ec88c),
            ("xn--bcher-kva.de", 0x0d16ee2d),
        ]
        for testCase in cases {
            XCTAssertEqual(CPMSiteRankLookup.fnv1a32(testCase.string.utf8), testCase.hash, testCase.string)
        }
    }

    func testWhenSiteOrItsSubdomainIsATopSiteThenRankIsTop10k() {
        let urls = [
            "https://google.com/",
            "https://www.google.com/search?q=test",
            "https://WWW.GOOGLE.COM./",
            "https://m.youtube.com/watch",
            "https://en.wikipedia.org/wiki/Main_Page",
            "https://www.bbc.co.uk/news",
            "https://www.gov.uk/",
            "https://assets.www.gov.uk/",
        ]
        for url in urls {
            XCTAssertEqual(lookup.siteRank(for: URL(string: url)), .top10k, url)
        }
    }

    func testWhenSiteIsNotATopSiteThenRankIsOther() {
        let urls = [
            "https://notgoogle.com/",
            "https://google.com.example.net/",
            "https://co.uk/",
            "https://gov.uk/",
            "http://localhost/",
            "http://192.168.1.1/",
            "http://[::1]/",
            "about:blank",
        ]
        for url in urls {
            XCTAssertEqual(lookup.siteRank(for: URL(string: url)), .other, url)
        }
        XCTAssertEqual(lookup.siteRank(for: nil), .other)
    }

    func testWhenHostIsInternationalizedThenItMatchesItsPunycodeEntry() {
        let lookup = Self.makeLookup(["xn--bcher-kva.de"])
        XCTAssertEqual(lookup.siteRank(for: URL(string: "https://www.bücher.de/")), .top10k)
        XCTAssertEqual(lookup.siteRank(for: URL(string: "https://WWW.BÜCHER.DE./")), .top10k)
        XCTAssertEqual(lookup.siteRank(for: URL(string: "https://www.xn--bcher-kva.de/")), .top10k)
        XCTAssertEqual(lookup.siteRank(for: URL(string: "https://www.bucher.de/")), .other)
    }

    func testWhenDataCannotBeLoadedThenRankIsNil() {
        let lookup = CPMSiteRankLookup(data: { nil })
        XCTAssertNil(lookup.siteRank(for: URL(string: "https://www.google.com/")))
    }

    func testWhenDataIsEmptyOrMalformedThenDecodingFails() {
        let (count, data) = Self.encode(["google.com", "youtube.com", "wikipedia.org"])
        XCTAssertNotNil(CPMSiteRankLookup.decode(count: count, base64: data))
        XCTAssertNil(CPMSiteRankLookup.decode(count: 0, base64: ""))
        XCTAssertNil(CPMSiteRankLookup.decode(count: count + 1, base64: data))
        XCTAssertNil(CPMSiteRankLookup.decode(count: count - 1, base64: data))
        XCTAssertNil(CPMSiteRankLookup.decode(count: count, base64: String(data.dropLast(4))))
        XCTAssertNil(CPMSiteRankLookup.decode(count: count, base64: "!not base64!"))
        XCTAssertNil(CPMSiteRankLookup.decode(count: -1, base64: data))
    }

#if os(macOS)
    func testBundledDataLoads() throws {
        let data = try XCTUnwrap(CPMSiteRankLookup.loadBundledData())
        XCTAssertGreaterThan(data.hashes.count, 5000)
        XCTAssertEqual(data.hashes, data.hashes.sorted())
        XCTAssertEqual(CPMSiteRankLookup().siteRank(for: URL(string: "https://www.google.com/")), .top10k)
    }

    /// `site-buckets.json` must be the list the bundled extension was built with, which esbuild inlines into its background script.
    func testBundledDataMatchesTheBundledExtension() throws {
        let file = try XCTUnwrap(CPMSiteRankLookup.loadBundledFile())
        guard #available(macOS 15.4, *) else { throw XCTSkip("The embedded extension needs macOS 15.4") }
        let zipURL = try XCTUnwrap(EmbeddedWebExtensionRegistry.descriptor(for: .embedded)?.bundledURL)
        let archive = try Archive(url: zipURL, accessMode: .read)
        let entry = try XCTUnwrap(archive["public/js/background-embedded.js"])
        var script = Data()
        _ = try archive.extract(entry) { script.append($0) }
        let source = try XCTUnwrap(String(data: script, encoding: .utf8))
        XCTAssertTrue(source.contains("\"\(file.data)\""), "site-buckets.json differs from the list in the bundled extension")
    }
#endif

    private static func makeLookup(_ domains: [String]) -> CPMSiteRankLookup {
        let (count, data) = encode(domains)
        let hashes = CPMSiteRankLookup.decode(count: count, base64: data)
        return CPMSiteRankLookup(data: { hashes.map { CPMSiteRankLookup.LookupData(hashes: $0) } })
    }

    /// Same encoding as `encodeDomainHashes` in the extension.
    private static func encode(_ domains: [String]) -> (count: Int, data: String) {
        let hashes = Array(Set(domains.map { CPMSiteRankLookup.fnv1a32($0.utf8) })).sorted()
        var bytes = [UInt8]()
        var previous: UInt32 = 0
        for hash in hashes {
            var gap = hash - previous
            previous = hash
            while gap >= 0x80 {
                bytes.append(UInt8(gap & 0x7f) | 0x80)
                gap >>= 7
            }
            bytes.append(UInt8(gap))
        }
        return (hashes.count, Data(bytes).base64EncodedString())
    }
}
