//
//  SitePermissionKeyTests.swift
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

import Foundation
import XCTest
@testable import SitePermissions

final class SitePermissionKeyTests: XCTestCase {

    func testWhenCommittedURLHasLeadingWWWThenItIsRemoved() throws {
        let key = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://www.example.com/path")!))

        XCTAssertEqual(key.host, "example.com")
    }

    func testWhenCommittedURLHasTwoLeadingWWWLabelsThenOnlyOneIsRemoved() throws {
        let key = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://www.www.example.com")!))

        XCTAssertEqual(key.host, "www.example.com")
    }

    func testWhenCommittedURLUsesUppercaseHostThenHostIsCanonicalized() throws {
        let key = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://WWW.Example.COM")!))

        XCTAssertEqual(key.host, "example.com")
    }

    func testWhenCommittedURLContainsIDNThenHostUsesPunycode() throws {
        let key = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://bücher.example")!))

        XCTAssertEqual(key.host, "xn--bcher-kva.example")
    }

    func testWhenSchemeAndPortDifferThenKeysAreEqual() throws {
        let httpKey = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "http://example.com:8080/one")!))
        let httpsKey = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://example.com:443/two")!))

        XCTAssertEqual(httpKey, httpsKey)
    }

    func testWhenSubdomainsDifferThenKeysRemainDistinct() throws {
        let first = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://mail.example.com")!))
        let second = try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://calendar.example.com")!))

        XCTAssertNotEqual(first, second)
    }

    func testWhenURLIsNotAWebOriginThenNoKeyIsProduced() {
        // The iOS SiteLoadingPixel precedent identifies the browser error page as duck://error.
        let rejectedURLs = [
            URL(string: "duck://error")!,
            URL(string: "duck://settings")!,
            URL(string: "file:///tmp/example.html")!,
            URL(string: "about:blank")!,
            URL(string: "data:text/plain,hello")!,
            URL(string: "mailto:user@example.com")!
        ]

        for url in rejectedURLs {
            XCTAssertNil(SitePermissionKey(committedURL: url), "Unexpected key for \(url)")
        }
    }

    func testWhenWebURLHasNoHostThenNoKeyIsProduced() {
        XCTAssertNil(SitePermissionKey(committedURL: URL(string: "https:///missing-host")!))
    }
}
