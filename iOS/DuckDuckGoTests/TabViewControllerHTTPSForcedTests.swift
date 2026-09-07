//
//  TabViewControllerHTTPSForcedTests.swift
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

import Common
import XCTest
@testable import DuckDuckGo

final class TabViewControllerHTTPSForcedTests: XCTestCase {

    private let tld = TLD()

    // No upgrade recorded → never forced. https:// so we test the nil guard, not the scheme guard.
    func test_noPriorUpgrade_returnsFalse() {
        for host in ["https://printer.local/", "https://192.168.1.10/", "https://intranet/", "https://example.com/"] {
            let url = URL(string: host)!
            XCTAssertFalse(
                TabViewController.isHTTPSForced(lastUpgradedURL: nil, currentURL: url, tld: tld),
                "\(host) with no prior upgrade should not be reported as HTTPS-forced"
            )
        }
    }

    // The reported bug: printer.local committed over HTTP shouldn't count as forced. Before the fix,
    // tld.domain was nil on both sides so nil == nil read as upgraded.
    func test_priorUpgrade_httpCommitOnNoPSLHost_returnsFalse() {
        let upgraded = URL(string: "https://printer.local/")!
        let httpCommit = URL(string: "http://printer.local/")!
        XCTAssertFalse(TabViewController.isHTTPSForced(lastUpgradedURL: upgraded, currentURL: httpCommit, tld: tld))
    }

    func test_priorUpgradeToSameDomain_returnsTrue() {
        let upgraded = URL(string: "https://example.com/")!
        let current = URL(string: "https://www.example.com/page")!
        XCTAssertTrue(TabViewController.isHTTPSForced(lastUpgradedURL: upgraded, currentURL: current, tld: tld))
    }

    func test_priorUpgradeToDifferentDomain_returnsFalse() {
        let upgraded = URL(string: "https://example.com/")!
        let current = URL(string: "https://other.com/")!
        XCTAssertFalse(TabViewController.isHTTPSForced(lastUpgradedURL: upgraded, currentURL: current, tld: tld))
    }

    // A same-domain sibling keeps the stale lastUpgradedURL, but an HTTP commit still isn't forced.
    func test_staleUpgrade_httpSiblingOnSameDomain_returnsFalse() {
        let upgraded = URL(string: "https://www.example.com/")!
        let current = URL(string: "http://legacy.example.com/")!
        XCTAssertFalse(TabViewController.isHTTPSForced(lastUpgradedURL: upgraded, currentURL: current, tld: tld))
    }

    // No known TLD, so we fall back to matching the raw host.
    func test_priorUpgradeToNoPSLHost_matchesByRawHost() {
        let upgraded = URL(string: "https://printer.local/")!
        XCTAssertTrue(TabViewController.isHTTPSForced(lastUpgradedURL: upgraded, currentURL: upgraded, tld: tld))

        let otherHost = URL(string: "https://scanner.local/")!
        XCTAssertFalse(TabViewController.isHTTPSForced(lastUpgradedURL: upgraded, currentURL: otherHost, tld: tld))
    }
}
