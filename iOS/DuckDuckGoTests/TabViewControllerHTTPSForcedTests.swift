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

    // Regression: hosts with no Public Suffix List match (IP literals, .local, .lan, single-label)
    // must not report an upgrade when none happened. Previously tld.domain(...) returned nil on both
    // sides so nil == nil falsely read as upgraded (~6% of flagged iOS reports, May–Jul 2026).
    func test_noPriorUpgrade_returnsFalseForHostsWithoutPSLMatch() {
        for host in ["http://printer.local/", "http://192.168.1.10/", "http://nas.lan/", "http://intranet/"] {
            let url = URL(string: host)!
            XCTAssertFalse(
                TabViewController.isHTTPSForced(lastUpgradedURL: nil, currentURL: url, tld: tld),
                "\(host) with no prior upgrade should not be reported as HTTPS-forced"
            )
        }
    }

    func test_noPriorUpgrade_returnsFalseForNormalHost() {
        let url = URL(string: "https://example.com/")!
        XCTAssertFalse(TabViewController.isHTTPSForced(lastUpgradedURL: nil, currentURL: url, tld: tld))
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
}
