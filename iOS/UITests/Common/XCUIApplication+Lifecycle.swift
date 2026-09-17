//
//  XCUIApplication+Lifecycle.swift
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

    func backgroundAndActivate(
        minimumBackgroundDuration: TimeInterval = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCUIDevice.shared.press(.home)

        let leftForeground = NSPredicate { object, _ in
            guard let application = object as? XCUIApplication else { return false }
            return application.state == .runningBackground || application.state == .runningBackgroundSuspended
        }
        XCTAssertTrue(
            wait(for: leftForeground, timeout: UITestTimeouts.navigation),
            "App did not enter the background.",
            file: file,
            line: line)
        XCTAssertNotEqual(state, .notRunning, "App terminated while entering the background.", file: file, line: line)

        if minimumBackgroundDuration > 0 {
            Thread.sleep(forTimeInterval: minimumBackgroundDuration)
        }

        activate()

        XCTAssertTrue(
            wait(for: .runningForeground, timeout: UITestTimeouts.navigation),
            "App did not return to the foreground.",
            file: file,
            line: line)
    }
}
