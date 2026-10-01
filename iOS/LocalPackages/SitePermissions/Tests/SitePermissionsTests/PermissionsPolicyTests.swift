//
//  PermissionsPolicyTests.swift
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

final class PermissionsPolicyTests: XCTestCase {
    private let pageURL = URL(string: "https://www.example.com/path")!

    func testAbsentGeolocationDeclarationDoesNotBlock() {
        for header in [nil, "", "camera=()", "unknown=()"] {
            XCTAssertFalse(PermissionsPolicy(header: header).blocksGeolocation(for: pageURL), header ?? "nil")
        }
    }

    func testSelfWildcardAndMatchingSourcesAllowTheResponseOrigin() {
        for value in ["*", "self", "(self)", "(*)", "(self \"https://other.example\")",
                      #""https://www.example.com""#, #"("https://WWW.example.com:443/")"#,
                      #"("www.example.com")"#, #"("https:")"#, #"("http:")"#,
                      #"("http://www.example.com")"#, #"("https://*.example.com")"#,
                      #"("https://www.example.com:*")"#, #"("https://*:*")"#] {
            XCTAssertFalse(PermissionsPolicy(header: "geolocation=\(value)").blocksGeolocation(for: pageURL), value)
        }
    }

    func testEmptyAndNonmatchingAllowlistsBlockTheResponseOrigin() {
        for value in ["()", #"("")"#, #"("https://other.example")"#, #"("https://www.example.com:8443")"#,
                      #"("https://*.www.example.com")"#, #"("https://*.ample.com")"#,
                      #"("https://www.example.com/path")"#, #"("https://user@www.example.com")"#,
                      #"("https://www.example.com?query")"#, #"("https://www.example.com#fragment")"#,
                      #"("https://%77ww.example.com")"#, #"("https://www.example.com:")"#,
                      #"("https://*.*")"#, #"("https://.www.example.com")"#, #"("https://www..example.com")"#,
                      #"("https://www.example.com.")"#, #"("https://www.example.com:65536")"#,
                      #"("https://www.example.com:+443")"#, #"("https://www.example.com:443:80")"#,
                      "(SELF)", #"("self")"#, "(https://www.example.com)"] {
            XCTAssertTrue(PermissionsPolicy(header: "geolocation=\(value)").blocksGeolocation(for: pageURL), value)
        }
    }

    func testSourceWildcardsPreserveHostAndPortBoundaries() {
        let wildcardHost = PermissionsPolicy(header: #"geolocation=("https://*.example.com")"#)
        XCTAssertTrue(wildcardHost.blocksGeolocation(for: URL(string: "https://example.com")))
        XCTAssertTrue(wildcardHost.blocksGeolocation(for: URL(string: "https://evilexample.com")))
        XCTAssertFalse(wildcardHost.blocksGeolocation(for: URL(string: "https://a.b.example.com")))
        XCTAssertTrue(wildcardHost.blocksGeolocation(for: URL(string: "https://www.example.com:8443")))
        XCTAssertTrue(wildcardHost.blocksGeolocation(for: URL(string: "http://www.example.com")))

        let wildcardPort = PermissionsPolicy(header: #"geolocation=("https://www.example.com:*")"#)
        XCTAssertFalse(wildcardPort.blocksGeolocation(for: URL(string: "https://www.example.com:8443")))
        XCTAssertTrue(wildcardPort.blocksGeolocation(for: URL(string: "https://other.example:8443")))
        let explicitPort = PermissionsPolicy(header: #"geolocation=("https://www.example.com:8443")"#)
        XCTAssertFalse(explicitPort.blocksGeolocation(for: URL(string: "https://www.example.com:8443")))
    }

    func testSchemeUpgradeDoesNotRewriteAnExplicitSourcePort() {
        // CSP's port-part matching algorithm compares explicit ports to the target port.
        XCTAssertFalse(PermissionsPolicy(header: #"geolocation=("http://www.example.com")"#).blocksGeolocation(for: pageURL))
        XCTAssertTrue(PermissionsPolicy(header: #"geolocation=("http://www.example.com:80")"#).blocksGeolocation(for: pageURL))
        XCTAssertFalse(PermissionsPolicy(header: #"geolocation=("http://www.example.com:443")"#).blocksGeolocation(for: pageURL))
    }

    func testTrailingHostDotIsValidWithoutRemovingItFromTheOriginComparison() {
        let policy = PermissionsPolicy(header: #"geolocation=("https://www.example.com.")"#)
        XCTAssertFalse(policy.blocksGeolocation(for: URL(string: "https://www.example.com./path")))
        XCTAssertTrue(policy.blocksGeolocation(for: pageURL))
        XCTAssertTrue(PermissionsPolicy(header: #"geolocation=("https://www.example.com..")"#)
            .blocksGeolocation(for: URL(string: "https://www.example.com../path")))
    }

    func testUnsupportedMembersAreIgnoredButUnsupportedListItemsDoNotGrant() {
        // Section 5.2 ignores an unsupported member, but removes invalid items from an inner list.
        for value in ["?0", "42", "1.5", "unknown", "SELF", "@123", #"%"display""#] {
            XCTAssertFalse(PermissionsPolicy(header: "geolocation=\(value)").blocksGeolocation(for: pageURL), value)
            XCTAssertTrue(PermissionsPolicy(header: "geolocation=(\(value))").blocksGeolocation(for: pageURL), value)
            XCTAssertFalse(PermissionsPolicy(header: "geolocation=(\(value) self)").blocksGeolocation(for: pageURL), value)
        }
        XCTAssertFalse(PermissionsPolicy(header: "geolocation").blocksGeolocation(for: pageURL))
    }

    func testMalformedDictionaryContributesNoHeaderRestrictions() {
        for header in ["geolocation=() ,", "Geolocation=()", "geolocation =()", "geolocation=(self",
                       "geolocation=();broken=", "geolocation=();Uppercase", "geolocation=();flag=?2",
                       #"geolocation=();text="bad\escape""#, "geolocation=();text=\"literal\t tab\"",
                       "geolocation=();count=1234567890123456", "geolocation=();ratio=1.1234",
                       "geolocation=();token=é", "geolocation=(), unknown=((self))"] {
            let policy = PermissionsPolicy(header: "camera=(), \(header)")
            XCTAssertFalse(policy.blocksGeolocation(for: pageURL), header)
            XCTAssertEqual(policy.blockedMediaTypes, [], header)
        }
    }

    func testLastDuplicateDirectiveWins() {
        XCTAssertFalse(PermissionsPolicy(header: "geolocation=(), geolocation=*").blocksGeolocation(for: pageURL))
        XCTAssertTrue(PermissionsPolicy(header: "geolocation=*, geolocation=()").blocksGeolocation(for: pageURL))
        XCTAssertFalse(PermissionsPolicy(header: "geolocation=(), geolocation=?0").blocksGeolocation(for: pageURL))
        XCTAssertEqual(PermissionsPolicy(header: "camera=(), camera=*, microphone=()").blockedMediaTypes, [.microphone])
    }

    func testParametersDoNotChangeTheAllowlist() {
        for parameters in [";report-to=endpoint", #";report-to="endpoint, geolocation=(); \"quoted\"""#,
                           ";enabled;flag=?0;token=*;count=-123456789012345;ratio=-123456789012.123",
                           ";data=:YQ==:;more=:YWI:;empty=::", ";date=@123;display=%\"hello\"",
                           ";flag=?0;flag=?1"] {
            XCTAssertTrue(PermissionsPolicy(header: "geolocation=()\(parameters)").blocksGeolocation(for: pageURL), parameters)
            for value in ["*", "self", "(self)", #"("https://www.example.com")"#] {
                XCTAssertFalse(PermissionsPolicy(header: "geolocation=\(value)\(parameters)")
                    .blocksGeolocation(for: pageURL), value + parameters)
            }
        }
        XCTAssertFalse(PermissionsPolicy(header: "geolocation=(self;extension=?1)").blocksGeolocation(for: pageURL))
        XCTAssertTrue(PermissionsPolicy(header: #"camera=();report-to="geolocation=*", geolocation=()"#)
            .blocksGeolocation(for: pageURL))
        XCTAssertFalse(PermissionsPolicy(header: #"camera=();report-to="geolocation=()", geolocation=self"#)
            .blocksGeolocation(for: pageURL))
    }

    func testMediaPreflightBlocksOnlyExplicitEmptyLists() {
        XCTAssertEqual(PermissionsPolicy(header: "camera=(), microphone=();report-to=endpoint").blockedMediaTypes, [.camera, .microphone])
        XCTAssertEqual(PermissionsPolicy(header: "camera=(self), microphone=*, geolocation=()").blockedMediaTypes, [])
        XCTAssertEqual(PermissionsPolicy(header: "camera=?0, microphone=(unknown)").blockedMediaTypes, [])
        XCTAssertEqual(PermissionsPolicy(header: #"camera=*;report-to="microphone=()""#).blockedMediaTypes, [])
    }
}
