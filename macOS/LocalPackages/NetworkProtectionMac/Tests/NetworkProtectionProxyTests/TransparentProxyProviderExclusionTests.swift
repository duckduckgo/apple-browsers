//
//  TransparentProxyProviderExclusionTests.swift
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
@testable import NetworkProtectionProxy
import XCTest

final class TransparentProxyProviderExclusionTests: XCTestCase {

    func testExactDomainMatches() {
        XCTAssertTrue(TransparentProxyProvider.isExcludedDomain("bank.com", excludedDomains: ["bank.com"]))
    }

    func testSubdomainMatches() {
        XCTAssertTrue(TransparentProxyProvider.isExcludedDomain("app.bank.com", excludedDomains: ["bank.com"]))
        XCTAssertTrue(TransparentProxyProvider.isExcludedDomain("login.app.bank.com", excludedDomains: ["bank.com"]))
    }

    func testLookalikeSuffixDoesNotMatch() {
        // Regression: a bare hasSuffix match would steer evilbank.com around the tunnel.
        XCTAssertFalse(TransparentProxyProvider.isExcludedDomain("evilbank.com", excludedDomains: ["bank.com"]))
        XCTAssertFalse(TransparentProxyProvider.isExcludedDomain("notbank.com", excludedDomains: ["bank.com"]))
    }

    func testPartialLabelDoesNotMatch() {
        XCTAssertFalse(TransparentProxyProvider.isExcludedDomain("bank.com.evil.com", excludedDomains: ["bank.com"]))
    }

    func testUnrelatedDomainDoesNotMatch() {
        XCTAssertFalse(TransparentProxyProvider.isExcludedDomain("example.com", excludedDomains: ["bank.com"]))
    }

    func testEmptyExclusionsMatchNothing() {
        XCTAssertFalse(TransparentProxyProvider.isExcludedDomain("bank.com", excludedDomains: []))
    }

    func testMatchesAnyEntryInList() {
        let exclusions = ["example.com", "bank.com"]
        XCTAssertTrue(TransparentProxyProvider.isExcludedDomain("app.bank.com", excludedDomains: exclusions))
        XCTAssertFalse(TransparentProxyProvider.isExcludedDomain("evilbank.com", excludedDomains: exclusions))
    }
}
