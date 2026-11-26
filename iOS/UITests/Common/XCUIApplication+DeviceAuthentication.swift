//
//  XCUIApplication+DeviceAuthentication.swift
//  DuckDuckGo
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
import UITestingSupport

extension XCUIApplication {

    /// Waits for SpringBoard's authentication prompt and passcode field to close.
    func waitForSystemAuthenticationToDismiss(
        reason: XCUIElement,
        passcodeField: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let authenticationDismissed = NSPredicate { _, _ in
            !reason.exists && !passcodeField.exists
        }
        XCTAssertTrue(
            wait(for: authenticationDismissed, timeout: UITestTimeouts.navigation),
            "System authentication UI did not close after entering the passcode.",
            file: file,
            line: line)
    }
}
