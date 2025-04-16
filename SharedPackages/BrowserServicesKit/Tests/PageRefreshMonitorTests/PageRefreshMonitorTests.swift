//
//  PageRefreshMonitorTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Common
@testable import PageRefreshMonitor

final class PageRefreshMonitorTests: XCTestCase {

    var monitor: PageRefreshMonitor!
    var detectionParameters: [Int] = []

    override func setUp() {
        super.setUp()
        monitor = PageRefreshMonitor(onDidDetectRefreshPattern: { patternCount in self.detectionParameters.append(patternCount)})
    }

    // MARK: - Pattern Detection Tests

    func testDoesNotDetectEventWhenRefreshesAreFewerThanTwo() {
        let url = URL(string: "https://example.com/pageA")!
        monitor.register(for: url)
        XCTAssertEqual(detectionParameters.count, 0)
    }

    func testDetectsEventWhenTwoRefreshesOccurOnSameURL() {
        let url = URL(string: "https://example.com/pageA")!
        monitor.register(for: url)
        monitor.register(for: url)
        XCTAssertEqual(detectionParameters.count, 1)
        XCTAssertEqual(detectionParameters, [2])
    }

    func testDetectsEventWhenThreeRefreshesOccurOnSameURL() {
        let url = URL(string: "https://example.com/pageA")!
        monitor.register(for: url)
        monitor.register(for: url)
        monitor.register(for: url)
        XCTAssertEqual(detectionParameters.count, 2)
        XCTAssertEqual(detectionParameters, [2, 3])
    }

    func testDetectsEventTwiceWhenSixRefreshesOccurOnSameURL() {
        let url = URL(string: "https://example.com/pageA")!
        for _ in 1...6 {
            monitor.register(for: url)
        }
        XCTAssertEqual(detectionParameters.count, 5)
        XCTAssertEqual(detectionParameters, [2, 3, 2, 2, 3])
    }

    // MARK: - URL Change Handling

    func testResetsCounterOnURLChangeSoEventIsNotDetected() {
        let urlA = URL(string: "https://example.com/pageA")!
        let urlB = URL(string: "https://example.com/pageB")!
        monitor.register(for: urlA)
        monitor.register(for: urlB)
        monitor.register(for: urlA)
        XCTAssertEqual(detectionParameters.count, 0)
    }

    func testStartsNewCounterWhenURLChangesAndRegistersNewRefreshes() {
        let urlA = URL(string: "https://example.com/pageA")!
        let urlB = URL(string: "https://example.com/pageB")!
        monitor.register(for: urlA)
        monitor.register(for: urlA)
        monitor.register(for: urlB)
        XCTAssertEqual(detectionParameters.count, 1)
        XCTAssertEqual(detectionParameters, [2])
        monitor.register(for: urlB)
        monitor.register(for: urlB)
        XCTAssertEqual(detectionParameters.count, 3)
        XCTAssertEqual(detectionParameters, [2, 2, 3])
    }

    // MARK: - Timed Pattern Detection

    func testDoesNotDetectEventIfThreeRefreshesOccurAfter12Seconds() {
        let url = URL(string: "https://example.com/pageA")!
        let date = Date()
        monitor.register(for: url, date: date)
        monitor.register(for: url, date: date + 13) // 13 seconds after the first event
        XCTAssertEqual(detectionParameters.count, 0)
    }

    func testDoesDetect2xEventIfSecondRefreshesOccurAfter12SecondsAndThirdAfter20Seconds() {
        let url = URL(string: "https://example.com/pageA")!
        let date = Date()
        monitor.register(for: url, date: date)
        monitor.register(for: url, date: date + 13) // 13 seconds after the first event
        monitor.register(for: url, date: date + 21) // 21 seconds after the first event 8 seconds after second event
        XCTAssertEqual(detectionParameters.count, 1)
        XCTAssertEqual(detectionParameters, [2])
    }

    func testDoesDetect2xEventIfThreeRefreshesOccurAfter20Seconds() {
        let url = URL(string: "https://example.com/pageA")!
        let date = Date()
        monitor.register(for: url, date: date)
        monitor.register(for: url, date: date)
        monitor.register(for: url, date: date + 21) // 21 seconds after the first event
        XCTAssertEqual(detectionParameters.count, 1)
        XCTAssertEqual(detectionParameters, [2])
    }

    func testDetectsEventIfThreeRefreshesOccurWithin20Seconds() {
        let url = URL(string: "https://example.com/pageA")!
        let date = Date()
        monitor.register(for: url, date: date)
        monitor.register(for: url, date: date)
        monitor.register(for: url, date: date + 19) // 19 seconds after the first event
        XCTAssertEqual(detectionParameters.count, 2)
        XCTAssertEqual(detectionParameters, [2, 3])
    }

    func testDetectsEventIfRefreshesAreWithinOverall20SecondWindow() {
        let url = URL(string: "https://example.com/pageA")!
        let date = Date()
        monitor.register(for: url, date: date)
        monitor.register(for: url, date: date + 19) // 19 seconds after the first event
        monitor.register(for: url, date: date + 21) // 21 seconds after the first event (2 seconds after second event)
        XCTAssertEqual(detectionParameters.count, 1)
        XCTAssertEqual(detectionParameters, [2])
        monitor.register(for: url, date: date + 23) // 23 seconds after the first event (4 seconds after second event)
        XCTAssertEqual(detectionParameters.count, 2)
        XCTAssertEqual(detectionParameters, [2, 3])
    }

}
