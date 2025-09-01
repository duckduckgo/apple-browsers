//
//  NewTabPageLoadMetricsTests.swift
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
@testable import DuckDuckGo_Privacy_Browser
@testable import NewTabPage
import PixelKit

final class NewTabPageLoadMetricsTests: XCTestCase {

    func testOnNTPWillPresentSetsStateToLoadingAndStoresStartTime() {
        let metrics = NewTabPageLoadMetrics(firePixel: { _ in })
        metrics.onNTPWillPresent()
        let loadTime = metrics.calculateLoadTime()
        XCTAssertNil(loadTime, "Load time should be nil before the page is shown")
    }

    func testOnNTPDidPresentCalculatesLoadTimeAndFiresPixel() {
        let expectation = self.expectation(description: "Pixel fired")
        var pixelFired = false

        let metrics = NewTabPageLoadMetrics { pixel in
            if let event = pixel as? NewTabPagePixel,
               case .newTabPageLoadingTime(let duration, _) = event {
                XCTAssertGreaterThan(duration, 0)
                pixelFired = true
                expectation.fulfill()
            }
        }

        metrics.onNTPWillPresent()
        usleep(100_000) // 100ms delay to simulate load time
        metrics.onNTPDidPresent()

        waitForExpectations(timeout: 1)
        XCTAssertTrue(pixelFired)
    }

    func testOnNTPDidPresentWithoutWillPresentDoesNotFirePixel() {
        let metrics = NewTabPageLoadMetrics { _ in
            XCTFail("Pixel should not fire if NTP was not initiated")
        }
        metrics.onNTPDidPresent()
    }

    func testOnNTPAlreadyPresentedFiresPixelWithZeroDuration() {
        let expectation = self.expectation(description: "Pixel fired with 0 duration")

        let metrics = NewTabPageLoadMetrics { pixel in
            if let event = pixel as? NewTabPagePixel,
               case .newTabPageLoadingTime(let duration, _) = event {
                XCTAssertEqual(duration, 0)
                expectation.fulfill()
            }
        }

        metrics.onNTPAlreadyPresented()
        waitForExpectations(timeout: 1)
    }
}
