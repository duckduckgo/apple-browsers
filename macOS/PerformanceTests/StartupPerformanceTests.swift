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
        let application = XCUIApplication.setUp()
        defer {
            application.terminate()
        }

        /// `UITests.firstRun()` closes the browser with no windows open. We'll manually open a new Window
        application.openNewWindow()
        XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 10), "Window did not appear after launch")

        let attachment = try application.buildStartupMetricsAttachment()
        XCTContext.runActivity(named: "Attaching Startup Metrics") { activity in
            activity.add(attachment)
        }
    }

    func testStartupSequenceDurationWithStateRestoration() throws {
        let application = XCUIApplication.setUp()

        /// Enable session restoration
        application.openPreferencesWindow()
        application.preferencesSetRestorePreviousSession(to: .restoreLastSession)
        application.closePreferencesWindow()

        /// Disable warn before quit so Cmd+Q quits immediately
        application.disableWarnBeforeQuitting()

        /// Create state to restore: 2 windows with multiple tabs
        application.openNewTab()
        application.openNewTab()
        application.openNewWindow()
        application.openNewTab()
        application.openNewTab()

        /// Quit properly to save state, then relaunch to trigger restoration
        application.typeKey("q", modifierFlags: [.command])

        /// Launch
        application.launch()
        XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 10), "Window did not appear after launch")

        let attachment = try application.buildStartupMetricsAttachment()
        XCTContext.runActivity(named: "Attaching Startup Metrics") { activity in
            activity.add(attachment)
        }

        /// Ensure State Restoration remains disabled
        application.openPreferencesWindow()
        application.preferencesSetRestorePreviousSession(to: .newWindow)
        application.closePreferencesWindow()
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
