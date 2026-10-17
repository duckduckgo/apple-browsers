//
//  NewTabPagePixelTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

final class NewTabPagePixelTests: XCTestCase {

    func testNextStepsCards_daysSinceInstall_buckets() {
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.daysSinceInstall(0), 0)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.daysSinceInstall(1), 1)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.daysSinceInstall(2), 2)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.daysSinceInstall(3), 2)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.daysSinceInstall(4), 4)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.daysSinceInstall(5), 4)
    }

    func testNextStepsCards_activeUsageDays_buckets() {
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.activeUsageDays(0), 0)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.activeUsageDays(1), 1)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.activeUsageDays(2), 2)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.activeUsageDays(3), 3)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.activeUsageDays(4), 4)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.activeUsageDays(5), 4)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.activeUsageDays(6), 6)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.activeUsageDays(8), 6)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.activeUsageDays(9), 9)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.activeUsageDays(13), 9)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.activeUsageDays(14), 14)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.activeUsageDays(15), 14)
    }

    func testNextStepsCards_newTabPageImpressions_buckets() {
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.newTabPageImpressions(0), 1)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.newTabPageImpressions(1), 1)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.newTabPageImpressions(2), 2)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.newTabPageImpressions(3), 3)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.newTabPageImpressions(4), 4)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.newTabPageImpressions(5), 5)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.newTabPageImpressions(6), 6)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.newTabPageImpressions(7), 7)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.newTabPageImpressions(8), 8)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.newTabPageImpressions(9), 8)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.newTabPageImpressions(10), 10)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.newTabPageImpressions(14), 10)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.newTabPageImpressions(15), 15)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.newTabPageImpressions(24), 15)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.newTabPageImpressions(25), 25)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.newTabPageImpressions(49), 25)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.newTabPageImpressions(50), 50)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.newTabPageImpressions(51), 50)
    }

    func testNextStepsCards_cardImpressions_maximum() {
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.cardImpressions(9), 9)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.cardImpressions(10), 10)
        XCTAssertEqual(NewTabPagePixel.NextStepsCards.cardImpressions(11), 10)
    }

}
