//
//  SitePermissionSecurityOriginTests.swift
//  DuckDuckGo
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

import SitePermissions
import XCTest

final class SitePermissionSecurityOriginTests: XCTestCase {

    func testWhenOriginsAreComparedThenSchemeHostAndEffectivePortDetermineEquality() throws {
        let scenarios = [
            ("https://EXAMPLE.com/path", "https://example.com:443/other", true),
            ("http://example.com", "http://example.com:80", true),
            ("https://example.com", "http://example.com", false),
            ("https://example.com", "https://example.com:444", false),
            ("https://example.com", "https://www.example.com", false)
        ]

        for (first, second, expectedEquality) in scenarios {
            let firstOrigin = try XCTUnwrap(SitePermissionSecurityOrigin(XCTUnwrap(URL(string: first))))
            let secondOrigin = try XCTUnwrap(SitePermissionSecurityOrigin(XCTUnwrap(URL(string: second))))
            XCTAssertEqual(firstOrigin == secondOrigin, expectedEquality, "\(first), \(second)")
        }
    }

    func testWhenOriginTrustIsCheckedThenHTTPSAndHTTPLoopbackAreAccepted() throws {
        let scenarios = [
            ("https://EXAMPLE.com", true),
            ("http://example.com", false),
            ("http://localhost", true),
            ("http://subdomain.localhost:8080", true),
            ("http://127.0.0.1", true),
            ("http://127.42.0.1", true),
            ("http://[::1]", true),
            ("http://128.0.0.1", false),
            ("http://[::2]", false),
            ("http://localhost.example.com", false),
            ("ftp://localhost", false)
        ]

        for (urlString, expectedTrust) in scenarios {
            let origin = try XCTUnwrap(SitePermissionSecurityOrigin(XCTUnwrap(URL(string: urlString))))
            XCTAssertEqual(origin.isPotentiallyTrustworthy, expectedTrust, urlString)
        }

        let ipv6Origin = try XCTUnwrap(SitePermissionSecurityOrigin(XCTUnwrap(URL(string: "http://[::1]"))))
        XCTAssertEqual(ipv6Origin.host, "::1")
    }

    func testWhenURLHasNoHostThenNoOriginIsProduced() throws {
        for urlString in ["about:blank", "file:///example", "relative/path"] {
            XCTAssertNil(SitePermissionSecurityOrigin(try XCTUnwrap(URL(string: urlString))))
        }
    }
}
