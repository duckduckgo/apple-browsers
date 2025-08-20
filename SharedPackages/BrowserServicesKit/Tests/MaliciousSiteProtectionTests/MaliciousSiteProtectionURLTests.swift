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
        let expectedURL = "http://www.example.com/security/badware/phishing.html"
        for testURL in testURLs {
            let url = URL(string: testURL)!
            let canonicalizedURL = url.canonicalURL()
            XCTAssertEqual(canonicalizedURL?.absoluteString, expectedURL)
        }
    }

    func testCanonicalizeURLRemovingWWW() {
        let expectedURL = "http://example.com/security/badware/phishing.html"
        for testURL in testURLs {
            let url = URL(string: testURL)!
            let canonicalizedURL = url.canonicalURL(shouldRemoveWWW: true)
            XCTAssertEqual(canonicalizedURL?.absoluteString, expectedURL)
        }
    }
}
