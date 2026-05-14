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
    /// - Parameters:
    ///     - application: Instance we'll be measuring
    ///     - iterations: Number of times the work closure will be invoked
    ///     - work: Closure that performs the action to be measured on the provided application instance
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

    /// Builds the Memory `Measurement Metric + Options + Block` to track the Memory Allocations at a specific point in time.
    ///
    /// - Important:
    ///     This will only track `com.duckduckgo.memory.allocations.used.final`, and was designed to measure Allocations right after Launch,
    ///     where the "delta" is meaningless, since we go from Memory Usage 0mb.
    ///
    /// - Parameters:
    ///     - iterations: Number of times the work closure will be invoked
    ///     - applicationProvider: Closure expected to return a (new) XCUIApplication instance
    ///     - completion: Closure to be invoked after Measurement is complete
    ///
    func buildSnapshotMeasurement(iterations: Int, applicationProvider: @escaping () -> XCUIApplication, completion: ((XCUIApplication) -> Void)? = nil) -> (metric: MemoryAllocationStatsMetric, options: XCTMeasureOptions, block: () -> Void) {
        let statsURLProvider = MemoryStatsURLProvider()
        let metric = MemoryAllocationStatsMetric(options: .measuresFinalState, memoryStatsURLProvider: statsURLProvider)
        let options = XCTMeasureOptions.buildOptions(iterations: iterations, manualEvents: true)

        let block: () -> Void = {
            self.startMeasuring()

            let application = applicationProvider()
            statsURLProvider.memoryStatsURL = application.memoryStatsURL
            application.cleanExportMemoryStats()

            self.stopMeasuring()
            completion?(application)
        }

        return (metric, options, block)
    }
}
