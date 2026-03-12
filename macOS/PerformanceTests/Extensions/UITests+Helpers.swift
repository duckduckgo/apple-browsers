//
//  UITests+Helpers.swift
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

extension UITests {

    /// Adjusts the `Session Restoration` setting as required, and disables the `warn before quitting` feature.
    ///
    /// - Parameters:
    ///     - shouldRestoreSession: Indicates if Session Restoration should be enabled, or we should open a New Window after launch
    ///     - configurationClosure: Optional closure to be executed, before the `XCUIApplication` instance is terminated
    ///
    static func setupInitialState(shouldRestoreSession: Bool, _ configurationClosure: ((XCUIApplication) -> Void)? = nil) {
        let application = XCUIApplication.setUp()

        /// Ensure there's at least one window open
        let firstWindow = application.windows.firstMatch
        let windowAppeared = firstWindow.waitForExistence(timeout: 0.5)

        if !windowAppeared {
            application.openNewWindow()
        }

        /// Configure session restoration (enable/disable) based on shouldRestoreSession
        application.openPreferencesWindow()
        application.preferencesSetRestorePreviousSession(to: shouldRestoreSession ? .restoreLastSession : .newWindow)
        application.closePreferencesWindow()

        /// Disable warn before quit so Cmd+Q quits immediately
        application.disableWarnBeforeQuitting()

        /// Optionally create state to restore (for example, multiple windows/tabs) via the provided closure
        configurationClosure?(application)

        /// Quit properly to save state; the caller can relaunch the app to trigger restoration
        application.typeKey("q", modifierFlags: [.command])
        application.terminate()
    }
}
