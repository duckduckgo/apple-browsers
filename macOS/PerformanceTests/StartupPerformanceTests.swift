//
//  StartupPerformanceTests.swift
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

final class StartupPerformanceTests: XCTestCase {

    private var application: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        /// Avoids First-Run State
        UITests.firstRun()
    }

    func testStartupSequenceDuration() throws {
        let application = XCUIApplication.setUp()
        defer {
            application.terminate()
        }

        application.cleanExportStartupStats()

        let statsAsData = try Data(contentsOf: application.startupMetricsURL)
        let attachment = buildAttachment(payload: statsAsData, description: "Startup Metrics")

        XCTContext.runActivity(named: description) { activity in
            activity.add(attachment)
        }
    }

    func buildAttachment(payload: Data, description: String) -> XCTAttachment {
        let attachment = XCTAttachment(data: payload, uniformTypeIdentifier: "public.json")
        attachment.name = description
        attachment.lifetime = .keepAlways
        return attachment
    }
}
