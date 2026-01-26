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

        /// Avoids First-Run State
        UITests.firstRun()

        /// Launch + Open a single New Window
        application = XCUIApplication.setUp(featureFlags: ["memoryUsageMonitor": true])
        application.openNewWindow()

        /// # Workaround
        ///     Wait 10s for memory usage to settle, before running the actual measurements.
        ///     Ref. https://app.asana.com/1/137249556945/project/1211150618152277/task/1212891845324300?focus=true
        sleep(10)
    }

    override func tearDown() {
        super.tearDown()
        application.terminate()
    }

    func testMemoryAllocationsWhenOpeningSingleNewTab() throws {
        /// We're explicitly **not** closing Tabs between Iterations to avoid interference from both, malloc re-using released blocks, or retain cycles themselves.
        /// The purpose of this Test is to measure the memory impact of opening a single Tab.
        ///
        let (metric, options, work) = buildMemoryMeasurement(application: application, iterations: 5) { application in
            application.openNewTab()
        }

        measure(metrics: [metric], options: options, block: work)
    }

    func testMemoryAllocationsWhenOpeningSingleNewWindow() throws {
        /// We're explicitly **not** closing Windows between Iterations to avoid interference from both, malloc re-using released blocks, or retain cycles themselves.
        /// The purpose of this Test is to measure the memory impact of opening a single Window.
        ///
        let (metric, options, work) = buildMemoryMeasurement(application: application, iterations: 5) { application in
            application.openNewWindow()
        }

        measure(metrics: [metric], options: options, block: work)
    }
}
