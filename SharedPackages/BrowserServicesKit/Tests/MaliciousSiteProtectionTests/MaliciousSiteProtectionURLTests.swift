//
//  MaliciousSiteProtectionURLTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

@testable import MaliciousSiteProtection

class MaliciousSiteProtectionURLTests: XCTestCase {

    let testURLs = [
        "http://www.example.com/security/badware/phishing.html#frags",
        "http://www.example.com/security/badware/phishing.html#frag#anotherfrag",
        "http://www.example.com/security/../security/badware/phishing.html",
        "http://www.example.com/security/./badware/phishing.html",
        "http://www.example.com/%73%65%63%75%72%69%74%79/%62%61%64%77%61%72%65/%70%68%69%73%68%69%6e%67%2e%68%74%6d%6c",
        "http://www.example.com/SECURITY/BADWARE/PHISHING.HTML",
        "http://www.example.com/security/badware/phishing.html////",
        "http://www.example.com//security//badware//phishing.html",
    ]

    func testCanonicalizeURL() {
        let expectedURL = "http://example.com/security/badware/phishing.html"
        for testURL in testURLs {
            let url = URL(string: testURL)!
            let canonicalizedURL = url.canonicalURL()
            XCTAssertEqual(canonicalizedURL?.absoluteString, expectedURL)
        }
    }

    func testWhenURLHasLargeFragmentThenCanonicalizationDiscardsIt() throws {
        let url = try XCTUnwrap(URL(string: "http://www.example.com/PHISHING#" + String(repeating: "A", count: 1_000_000)))

        XCTAssertEqual(url.canonicalURL()?.absoluteString, "http://example.com/phishing")
    }

    func testWhenURLHasEncodedFragmentDelimiterThenItRemainsInCanonicalization() throws {
        let url = try XCTUnwrap(URL(string: "http://www.example.com/PHISHING%23SECTION#discarded"))

        XCTAssertEqual(url.canonicalURL()?.absoluteString, "http://example.com/phishing#section")
    }

    func testWhenURLHasRepeatedSlashesThenCanonicalizationPreservesSchemeAndCollapsesSlashScalars() throws {
        let cases = [
            ("https://example.com/", "https://example.com/"),
            ("https://example.com//A///B?q=HTTPS://OTHER.COM///C", "https://example.com/a/b?q=https:/other.com/c"),
            ("https://example.com/%2F%2FA?q=%2F%2FB", "https://example.com/a?q=/b"),
            ("https://example.com//\u{0301}A?q=//\u{0301}B", "https://example.com/%CC%81a?q=/%CC%81b")
        ]

        for (input, expected) in cases {
            let url = try XCTUnwrap(URL(string: input))

            XCTAssertEqual(url.canonicalURL()?.absoluteString, expected)
        }
    }

    func testWhenURLHasLargeQueryThenCanonicalizationPreservesItsEndWithOrWithoutRepeatedSlashes() throws {
        for segment in ["A", "A/", "A///"] {
            let payload = String(repeating: segment, count: 1_000_000)
            let url = try XCTUnwrap(URL(string: "https://example.com/PHISHING?q=\(payload)&MARKER=THREAT"))
            let expectedSegment = segment == "A" ? "a" : "a/"
            let expected = "https://example.com/phishing?q=" + String(repeating: expectedSegment, count: 1_000_000) + "&marker=threat"

            XCTAssertEqual(url.canonicalURL()?.absoluteString, expected)
        }
    }

}
