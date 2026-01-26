//
//  MemoryUsageTests.swift
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
import Foundation

final class MemoryUsageTests: XCTestCase {

    private var application: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        application = XCUIApplication.setUp(featureFlags: ["memoryUsageMonitor": true])
    }

    override func tearDown() {
        super.tearDown()
        application.terminate()
    }

    func testMemoryAllocationsWhenOpeningSingleNewTab() throws {
        let memoryMetric = MemoryAllocationStatsMetric(memoryStatsURL: application.memoryStatsURL)

        application.openNewWindow()

        measure(metrics: [memoryMetric], options: .buildOptions(iterations: 5, manualEvents: true)) {
            application.cleanExportMemoryStats()
            startMeasuring()

            /// We're explicitly **not** closing Tabs among Iterations to avoid interference from both, malloc re-using released blocks, or retain cycles themselves.
            /// The purpose of this Test is to measure the memory impact of opening a single Tab.
            ///
            application.openNewTab()

            application.cleanExportMemoryStats()
            stopMeasuring()
        }
    }
}
