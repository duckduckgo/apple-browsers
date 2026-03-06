//
//  TrackerInfoTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@testable import PrivacyDashboard
import ContentBlocking

final class TrackerInfoTests: XCTestCase {

    // MARK: - isAssociatedWithPage

    func testIsAssociatedWithPage_exactStringMatch() {
        let url = URL(string: "https://example.com/page?q=1")!
        XCTAssertTrue(TrackerInfo.isAssociatedWithPage("https://example.com/page?q=1", tabURL: url))
    }

    func testIsAssociatedWithPage_differentPath_sameOrigin_returnsFalse() {
        let url = URL(string: "https://example.com/page")!
        XCTAssertFalse(
            TrackerInfo.isAssociatedWithPage("https://example.com/other", tabURL: url),
            "Same-origin URLs with different paths should not be associated to prevent cross-page leakage"
        )
    }

    func testIsAssociatedWithPage_trailingSlashDifference() {
        let url = URL(string: "https://example.com/page")!
        XCTAssertTrue(
            TrackerInfo.isAssociatedWithPage("https://example.com/page/", tabURL: url),
            "Trailing slash difference should not drop the event"
        )
    }

    func testIsAssociatedWithPage_fragmentDifference() {
        let url = URL(string: "https://example.com/page")!
        XCTAssertTrue(
            TrackerInfo.isAssociatedWithPage("https://example.com/page#section", tabURL: url),
            "Fragment-only difference should not drop the event"
        )
    }

    func testIsAssociatedWithPage_differentHost_returnsFalse() {
        let url = URL(string: "https://example.com/page")!
        XCTAssertFalse(
            TrackerInfo.isAssociatedWithPage("https://other-site.com/page", tabURL: url),
            "Different host should not be associated"
        )
    }

    func testIsAssociatedWithPage_differentScheme_returnsFalse() {
        let url = URL(string: "https://example.com/page")!
        XCTAssertFalse(
            TrackerInfo.isAssociatedWithPage("http://example.com/page", tabURL: url),
            "Different scheme should not be associated"
        )
    }

    func testIsAssociatedWithPage_differentPort_returnsFalse() {
        let url = URL(string: "https://example.com:8080/page")!
        XCTAssertFalse(
            TrackerInfo.isAssociatedWithPage("https://example.com:8443/page", tabURL: url),
            "Different port should not be associated"
        )
    }

    func testIsAssociatedWithPage_differentQuery_returnsFalse() {
        let url = URL(string: "https://example.com/search?q=cats")!
        XCTAssertFalse(
            TrackerInfo.isAssociatedWithPage("https://example.com/search?q=dogs", tabURL: url),
            "Different query parameters should not be associated to prevent cross-query leakage"
        )
    }

    func testIsAssociatedWithPage_invalidPageUrl_returnsFalse() {
        let url = URL(string: "https://example.com/page")!
        XCTAssertFalse(TrackerInfo.isAssociatedWithPage("not a url", tabURL: url))
    }

    // MARK: - addDetectedTracker with page association

    private func makeRequest(trackerUrl: String = "https://tracker.example/pixel.js",
                             pageUrl: String,
                             state: BlockingState = .blocked) -> DetectedRequest {
        DetectedRequest(url: trackerUrl, eTLDplus1: "tracker.example",
                        ownerName: "Tracker Inc", entityName: "Tracker Inc",
                        category: nil, prevalence: nil, state: state, pageUrl: pageUrl)
    }

    func testAddDetectedTracker_exactPageUrlMatch_succeeds() {
        var info = TrackerInfo()
        let url = URL(string: "https://example.com/page")!
        info.addDetectedTracker(makeRequest(pageUrl: "https://example.com/page"), onPageWithURL: url)
        XCTAssertEqual(info.trackers.count, 1)
    }

    func testAddDetectedTracker_sameOriginDifferentPath_dropsEvent() {
        var info = TrackerInfo()
        let url = URL(string: "https://example.com/real-page")!
        info.addDetectedTracker(makeRequest(pageUrl: "https://example.com/iframe-reported-url"), onPageWithURL: url)
        XCTAssertEqual(
            info.trackers.count, 0,
            "Same-origin event with different path should be dropped to prevent cross-page leakage"
        )
    }

    func testAddDetectedTracker_differentOrigin_dropsEvent() {
        var info = TrackerInfo()
        let url = URL(string: "https://example.com/page")!
        info.addDetectedTracker(makeRequest(pageUrl: "https://other-site.com/page"), onPageWithURL: url)
        XCTAssertEqual(info.trackers.count, 0)
    }

    func testAddDetectedTracker_differentQuery_dropsEvent() {
        var info = TrackerInfo()
        let url = URL(string: "https://example.com/search?q=dogs")!
        info.addDetectedTracker(makeRequest(pageUrl: "https://example.com/search?q=cats"), onPageWithURL: url)
        XCTAssertEqual(
            info.trackers.count, 0,
            "Event with different query parameters should be dropped to prevent cross-query leakage"
        )
    }

    // MARK: - addInstalledSurrogateHost with page association

    func testAddSurrogateHost_sameOriginDifferentPath_dropsEvent() {
        var info = TrackerInfo()
        let url = URL(string: "https://example.com/real-page")!
        let request = makeRequest(trackerUrl: "https://tracker.example/analytics.js",
                                  pageUrl: "https://example.com/iframe-reported-url")
        info.addInstalledSurrogateHost("tracker.example", for: request, onPageWithURL: url)
        XCTAssertEqual(
            info.installedSurrogates.count, 0,
            "Same-origin event with different path should be dropped to prevent cross-page leakage"
        )
    }

    func testAddSurrogateHost_differentOrigin_dropsEvent() {
        var info = TrackerInfo()
        let url = URL(string: "https://example.com/page")!
        let request = makeRequest(trackerUrl: "https://tracker.example/analytics.js",
                                  pageUrl: "https://other-site.com/page")
        info.addInstalledSurrogateHost("tracker.example", for: request, onPageWithURL: url)
        XCTAssertEqual(info.installedSurrogates.count, 0)
    }
}
