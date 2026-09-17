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

private enum SimulatorDeviceAuthentication {
    static let passcode = "password"
}

extension XCUIApplication {

    /// Call on the SpringBoard application to enter the passcode configured on the UI-test simulator.
    func enterSimulatorPasscode(file: StaticString = #filePath, line: UInt = #line) {
        let passcodeField = secureTextFields.firstMatch
        guard passcodeField.waitForExistence(timeout: UITestTimeouts.elementExistence) else {
            XCTFail("System passcode field did not appear.", file: file, line: line)
            return
        }
        passcodeField.typeText(SimulatorDeviceAuthentication.passcode + "\n")
    }
}
