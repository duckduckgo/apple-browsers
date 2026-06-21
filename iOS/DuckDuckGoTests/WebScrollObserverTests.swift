//
//  WebScrollObserverTests.swift
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
import UIKit
import Core
@testable import DuckDuckGo

/// Drives `WebScrollObserver.classifyDrag` directly (the synchronous classification entry) to validate the
/// symptom-pixel logic — failure streak, the ≥2-region spatial-spread gate, the 30s streak window, and
/// eligibility — without simulating real touches or the post-gesture async recheck.
@MainActor
final class WebScrollObserverTests: XCTestCase {

    private var container: UIView!
    private var scrollView: UIScrollView!
    private var url: URL?
    private var currentDate: Date!
    private var firedPixels: [(event: Pixel.Event, params: [String: String])] = []

    override func setUp() {
        super.setUp()
        // Container height 600 → screen regions are thirds at y<200 / 200..<400 / ≥400.
        container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        // A genuinely scrollable page: 2000pt content in a 600pt viewport → ~1400pt of range.
        scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        scrollView.contentSize = CGSize(width: 390, height: 2000)
        scrollView.contentOffset = CGPoint(x: 0, y: 100)
        url = URL(string: "https://example.com")
        currentDate = Date(timeIntervalSince1970: 1_000_000)
        firedPixels = []
    }

    override func tearDown() {
        container = nil
        scrollView = nil
        url = nil
        currentDate = nil
        firedPixels = []
        super.tearDown()
    }

    private func makeObserver() -> WebScrollObserver {
        WebScrollObserver(container: container,
                          scrollView: { [weak self] in self?.scrollView },
                          currentURL: { [weak self] in self?.url },
                          firePixelDailyAndCount: { [weak self] event, params in
                              self?.firedPixels.append((event, params))
                          },
                          now: { [weak self] in self?.currentDate ?? Date() })
    }

    /// A failed (non-moving) upward drag starting at the given screen-Y. `contentOffset` is left at the
    /// start offset so the observer sees zero movement.
    private func failedDrag(at startScreenY: CGFloat, on observer: WebScrollObserver) {
        scrollView.contentOffset = CGPoint(x: 0, y: 100)
        observer.classifyDrag(dx: 0, dy: -100, startOffsetY: 100, startScreenY: startScreenY)
    }

    func testThreeFailedDragsAcrossTwoRegionsFiresSymptomPixel() {
        let observer = makeObserver()

        failedDrag(at: 100, on: observer) // region 0
        failedDrag(at: 300, on: observer) // region 1
        XCTAssertTrue(firedPixels.isEmpty, "Should not fire before the streak threshold")

        failedDrag(at: 500, on: observer) // region 2 → streak 3, spans 3 regions

        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.event, .debugInteractionRepeatedFailedScroll)
        XCTAssertEqual(firedPixels.first?.params["attempt_count_bucket"], "3")
        XCTAssertEqual(firedPixels.first?.params["direction"], "up")
        XCTAssertEqual(firedPixels.first?.params["mechanism"], "none_wedged")
    }

    func testFailedDragsInOneRegionDoNotFire() {
        let observer = makeObserver()

        failedDrag(at: 100, on: observer)
        failedDrag(at: 100, on: observer)
        failedDrag(at: 100, on: observer)
        failedDrag(at: 100, on: observer)

        XCTAssertTrue(firedPixels.isEmpty, "A single-region streak is benign and must not fire")
    }

    func testSuccessfulDragResetsTheStreak() {
        let observer = makeObserver()

        failedDrag(at: 100, on: observer) // region 0, streak 1
        failedDrag(at: 300, on: observer) // region 1, streak 2

        // A drag that actually scrolls (content moved well beyond the 3pt threshold) resets the streak.
        scrollView.contentOffset = CGPoint(x: 0, y: 100)
        observer.classifyDrag(dx: 0, dy: -100, startOffsetY: 0, startScreenY: 100)

        // Two more failures across two regions → only streak 2 again, so still below threshold.
        failedDrag(at: 100, on: observer)
        failedDrag(at: 300, on: observer)

        XCTAssertTrue(firedPixels.isEmpty, "A successful scroll must reset the failure streak")
    }

    func testStreakWindowExpiryResetsBeforeFiring() {
        let observer = makeObserver()

        failedDrag(at: 100, on: observer) // region 0
        failedDrag(at: 300, on: observer) // region 1

        // More than the 30s streak window later, the next failure restarts the streak from 1.
        currentDate = currentDate.addingTimeInterval(31)
        failedDrag(at: 500, on: observer) // region 2, but streak reset to 1

        XCTAssertTrue(firedPixels.isEmpty, "A gap beyond the streak window must reset before firing")
    }

    func testNonHTTPPageIsIneligible() {
        url = URL(string: "duck://player")
        let observer = makeObserver()

        failedDrag(at: 100, on: observer)
        failedDrag(at: 300, on: observer)
        failedDrag(at: 500, on: observer)

        XCTAssertTrue(firedPixels.isEmpty, "Non-http(s) pages are not eligible for symptom detection")
    }

    func testShortOrHorizontalDragIsIgnored() {
        let observer = makeObserver()

        // Below the 48pt vertical threshold.
        observer.classifyDrag(dx: 0, dy: -20, startOffsetY: 100, startScreenY: 100)
        // Horizontally dominant.
        observer.classifyDrag(dx: -200, dy: -60, startOffsetY: 100, startScreenY: 300)
        observer.classifyDrag(dx: -200, dy: -60, startOffsetY: 100, startScreenY: 500)

        XCTAssertTrue(firedPixels.isEmpty, "Short or horizontal drags are not scroll attempts")
    }
}
