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

    static func setupInitialState(shouldRestoreSession: Bool, _ configurationClosure: ((XCUIApplication) -> Void)? = nil) {
        let application = XCUIApplication.buildApplicationForPerformanceTesting()

        /// Configure session restoration (enable/disable) based on shouldRestoreSession
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
