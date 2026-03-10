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

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        /// Avoids First-Run State
        UITests.firstRun()
    }

    func testStartupSequenceDurationWithoutStateRestoration() throws {
        setupInitialState(shouldRestoreSession: false)

        let application = buildApplicationForPerformanceTesting()
        defer {
            application.terminate()
        }

        XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 10), "Window did not appear after launch")

        let attachment = try application.buildStartupMetricsAttachment()
        XCTContext.runActivity(named: "Attaching Startup Metrics") { activity in
            activity.add(attachment)
        }
    }

    func testStartupSequenceDurationWithStateRestoration() throws {
        setupInitialState(shouldRestoreSession: true) { application in
            application.openNewTab()
            application.openNewTab()
            application.openNewWindow()
            application.openNewTab()
            application.openNewTab()
        }

        let application = buildApplicationForPerformanceTesting()
        defer {
            application.terminate()
        }

        XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 10), "Window did not appear after launch")

        let attachment = try application.buildStartupMetricsAttachment()
        XCTContext.runActivity(named: "Attaching Startup Metrics") { activity in
            activity.add(attachment)
        }
    }
}

private extension StartupPerformanceTests {

    func buildApplicationForPerformanceTesting() -> XCUIApplication {
        XCUIApplication.setUp(environment: ["UITEST_MODE_STARTUP_PERFORMANCE": "1"])
    }

    func setupInitialState(shouldRestoreSession: Bool, _ configurationClosure: ((XCUIApplication) -> Void)? = nil) {
        let application = buildApplicationForPerformanceTesting()

        /// Enable session restoration
        application.openPreferencesWindow()
        application.preferencesSetRestorePreviousSession(to: shouldRestoreSession ? .restoreLastSession : .newWindow)
        application.closePreferencesWindow()

        /// Disable warn before quit so Cmd+Q quits immediately
        application.disableWarnBeforeQuitting()

        /// Create state to restore: 2 windows with multiple tabs
        configurationClosure?(application)

        /// Quit properly to save state, then relaunch to trigger restoration
        application.typeKey("q", modifierFlags: [.command])
        application.terminate()
    }
}

private extension XCUIApplication {

    func buildStartupMetricsAttachment() throws -> XCTAttachment {
        cleanExportStartupMetrics()

        let payload = try Data(contentsOf: startupMetricsURL)

        return buildAttachment(payload: payload, description: "Startup Metrics")
    }

    func buildAttachment(payload: Data, description: String) -> XCTAttachment {
        let attachment = XCTAttachment(data: payload, uniformTypeIdentifier: "public.json")
        attachment.name = description
        attachment.lifetime = .keepAlways
        return attachment
    }
}
