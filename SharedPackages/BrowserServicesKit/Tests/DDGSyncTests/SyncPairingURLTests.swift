//
//  SyncPairingURLTests.swift
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
@testable import DDGSync

final class SyncPairingURLTests: XCTestCase {

    func testAcceptedPairingURLsIdentifyTheHost() throws {
        let destinations: [(String, SyncPairingURL)] = [
            ("duck.com", .duckCom),
            ("duck.ai", .duckAI)
        ]
        for (host, destination) in destinations {
            for scheme in ["http", "https", "HTTPS"] {
                for acceptedHost in [host, "www.\(host)", host.uppercased()] {
                    for path in ["/pair", "/pair/", "/PAIR"] {
                        let input = "\(scheme)://\(acceptedHost)\(path)"
                        let url = try XCTUnwrap(URL(string: input))
                        XCTAssertEqual(SyncPairingURL(url: url), destination, input)
                    }
                }
            }
        }
    }

    func testQueryAndFragmentDoNotChangeTheDestination() throws {
        for (host, destination) in [("duck.com", SyncPairingURL.duckCom), ("duck.ai", .duckAI)] {
            for suffix in [
                "?", "?ref=test", "#test", "#code2=attacker-code", "?code2=attacker-code",
                "#entry=landing&code2=attacker-code", "?code2=query-code#code2=fragment-code"
            ] {
                let input = "https://\(host)/pair\(suffix)"
                let url = try XCTUnwrap(URL(string: input))
                XCTAssertEqual(SyncPairingURL(url: url), destination, input)
            }
        }
    }

    func testOtherURLsAreNotPairingDestinations() throws {
        let inputs = [
            "https://duck.com/",
            "https://duck.ai/",
            "https://duck.com/pairing",
            "https://duck.ai/chat",
            "https://duck.com/pair/extra",
            "https://duck.ai/pair/extra",
            "https://duck.com/pair//",
            "https://duck.ai/pair//",
            "https://sub.duck.com/pair",
            "https://sub.duck.ai/pair",
            "https://duckduckgo.com/pair",
            "https://duckduckgo.com/sync/pairing/#&code2=abc",
            "https://evil.com/pair",
            "https://duck.com.evil.com/pair",
            "https://duck.ai.evil.com/pair",
            "https://duck.com@evil.com/pair",
            "ftp://duck.com/pair",
            "ftp://duck.ai/pair",
            "duck.com/pair",
            "duck.ai/pair",
            "not-a-url"
        ]
        for input in inputs {
            let url = try XCTUnwrap(URL(string: input))
            XCTAssertNil(SyncPairingURL(url: url), input)
        }
    }
}
