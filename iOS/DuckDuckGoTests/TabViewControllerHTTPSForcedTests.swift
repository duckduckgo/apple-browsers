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

import XCTest
@testable import DuckDuckGo

final class TabViewControllerHTTPSForcedTests: XCTestCase {

    private var tracker = HTTPSUpgradeNavigationTracker()

    // MARK: - No upgrade on record

    func test_noUpgrade_isNotForced() {
        for host in ["https://printer.local/", "https://192.168.1.10/", "https://intranet/", "https://example.com/"] {
            let url = URL(string: host)!
            XCTAssertFalse(
                tracker.isHTTPSForced(committedURL: url),
                "\(host) with no upgrade on record should not be reported as HTTPS-forced"
            )
        }
    }

    func test_noCommittedURL_isNotForced() {
        tracker.didUpgrade(to: URL(string: "https://example.com/")!)
        XCTAssertFalse(tracker.isHTTPSForced(committedURL: nil))
    }

    // MARK: - The upgraded page itself

    func test_upgradedPageCommits_isForced() {
        let upgraded = URL(string: "https://example.com/")!
        tracker.didUpgrade(to: upgraded)
        tracker.willNavigate(mainFrameTo: upgraded)

        XCTAssertTrue(tracker.isHTTPSForced(committedURL: upgraded))
    }

    // A host with no entry in the public suffix list is still matched, by whole URL.
    func test_upgradedNoPSLHostCommits_isForced() {
        let upgraded = URL(string: "https://printer.local/")!
        tracker.didUpgrade(to: upgraded)
        tracker.willNavigate(mainFrameTo: upgraded)

        XCTAssertTrue(tracker.isHTTPSForced(committedURL: upgraded))
    }

    // Reloading the upgraded page is still that page, so it stays forced. Matches Windows, which
    // compares each navigation exactly against the tab's latest upgrade.
    func test_upgradedPageReloaded_staysForced() {
        let upgraded = URL(string: "https://example.com/")!
        tracker.didUpgrade(to: upgraded)
        tracker.willNavigate(mainFrameTo: upgraded)
        tracker.willNavigate(mainFrameTo: upgraded)

        XCTAssertTrue(tracker.isHTTPSForced(committedURL: upgraded))
    }

    // MARK: - Pages reached after the upgrade

    // The over-reporting bug: one upgrade used to flag every later page on the same registrable domain.
    func test_pageNavigatedToAfterUpgrade_isNotForced() {
        tracker.didUpgrade(to: URL(string: "https://example.com/")!)

        let laterPage = URL(string: "https://example.com/page2")!
        tracker.willNavigate(mainFrameTo: laterPage)

        XCTAssertFalse(tracker.isHTTPSForced(committedURL: laterPage))
    }

    func test_subdomainNavigatedToAfterUpgrade_isNotForced() {
        tracker.didUpgrade(to: URL(string: "https://example.com/")!)

        let subdomain = URL(string: "https://www.example.com/page")!
        tracker.willNavigate(mainFrameTo: subdomain)

        XCTAssertFalse(tracker.isHTTPSForced(committedURL: subdomain))
    }

    func test_differentDomainNavigatedToAfterUpgrade_isNotForced() {
        tracker.didUpgrade(to: URL(string: "https://example.com/")!)

        let otherDomain = URL(string: "https://other.com/")!
        tracker.willNavigate(mainFrameTo: otherDomain)

        XCTAssertFalse(tracker.isHTTPSForced(committedURL: otherDomain))
    }

    // Regression guard for the nil-PSL case fixed in #6415: a later HTTP page on a host the public
    // suffix list doesn't know must not inherit the upgrade.
    func test_httpPageOnNoPSLHostAfterUpgrade_isNotForced() {
        tracker.didUpgrade(to: URL(string: "https://printer.local/")!)

        let httpPage = URL(string: "http://printer.local/")!
        tracker.willNavigate(mainFrameTo: httpPage)

        XCTAssertFalse(tracker.isHTTPSForced(committedURL: httpPage))
    }

    // MARK: - Link protection

    // Link protection strips tracking parameters and resolves AMP links between the upgrade and the
    // request, so the tracker is armed with the cleaned URL — the one the navigation actually carries.
    func test_upgradeArmedWithCleanedURL_isForced() {
        let cleaned = URL(string: "https://example.com/article")!
        tracker.didUpgrade(to: cleaned)
        tracker.willNavigate(mainFrameTo: cleaned)

        XCTAssertTrue(tracker.isHTTPSForced(committedURL: cleaned))
    }

    // Arming with the pre-cleaning URL is what broke reporting: the navigation carries the cleaned
    // URL, which clears the tracker before the page ever commits.
    func test_upgradeArmedWithPreCleaningURL_isNotForced() {
        tracker.didUpgrade(to: URL(string: "https://example.com/article?utm_source=newsletter")!)

        let cleaned = URL(string: "https://example.com/article")!
        tracker.willNavigate(mainFrameTo: cleaned)

        XCTAssertFalse(tracker.isHTTPSForced(committedURL: cleaned))
    }

    // MARK: - Redirects

    // A server redirect away from the upgraded URL reports false. macOS and Windows behave the same,
    // so we accept under-reporting here in exchange for never over-reporting.
    func test_serverRedirectAwayFromUpgradedURL_isNotForced() {
        let upgraded = URL(string: "https://example.com/")!
        tracker.didUpgrade(to: upgraded)
        tracker.willNavigate(mainFrameTo: upgraded)

        XCTAssertFalse(tracker.isHTTPSForced(committedURL: URL(string: "https://www.example.com/")!))
    }

    // MARK: - Reset

    func test_reset_clearsUpgrade() {
        let upgraded = URL(string: "https://example.com/")!
        tracker.didUpgrade(to: upgraded)

        tracker.reset()

        XCTAssertFalse(tracker.isHTTPSForced(committedURL: upgraded))
    }
}
