//
//  XCTestCase+Helpers.swift
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

extension XCTestCase {

    /// Builds the Memory `Measurement Metric + Options + Block`
    /// Please do invoke `measure(metrics:options:block:)` in your test, with the results of this API
    ///
    /// - Important:
    ///     This API does NOT invoke  `measure(...)`  directly, as the Xcode measurement reports would end up being printed right here,
    ///     rather than in the caller Test. Unfortunately, there's no API that accepts the `line number` / `class`.
    ///
    func buildMemoryMeasurement(application: XCUIApplication, iterations: Int, work: @escaping (_ application: XCUIApplication) -> Void) -> (metric: MemoryAllocationStatsMetric, options: XCTMeasureOptions, block: () -> Void) {
        let metric = MemoryAllocationStatsMetric(memoryStatsURL: application.memoryStatsURL)
        let options = XCTMeasureOptions.buildOptions(iterations: iterations, manualEvents: true)

        let block: () -> Void = {
            application.cleanExportMemoryStats()
            self.startMeasuring()

            work(application)

            application.cleanExportMemoryStats()
            self.stopMeasuring()
        }

        return (metric, options, block)
    }
}
