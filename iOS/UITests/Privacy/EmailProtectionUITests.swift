//
//  EmailProtectionUITests.swift
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

final class EmailProtectionUITests: UITestCase {

    func testEnablingEmailProtectionFromSettingsOpensSignupPage() {
        app.openSettings()

        let settingsList = app.descendants(matching: .any)["Settings.List.Main"]
        let emailProtection = settingsList.buttons["Settings.Privacy.EmailProtection"]
        settingsList.swipeUpToReveal(emailProtection, timeout: UITestTimeouts.navigation)
        emailProtection.tapWhenHittable()

        XCTAssertTrue(
            app.descendants(matching: .any)["Settings.List.EmailProtection"]
                .waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Email Protection settings did not appear.")

        app.buttons["Settings.EmailProtection.Enable"].tapWhenHittable()
        app.assertPageContains("Email protection, simplified.")

        XCTAssertTrue(
            app.searchEntry.wait(for: NSPredicate(format: "isHittable == true"), timeout: UITestTimeouts.navigation),
            "Browser address bar did not appear after opening Email Protection signup.")
        app.searchEntry.tap()
        XCTAssertTrue(
            app.searchEntry.wait(for: \.value, contains: "duckduckgo.com/email/", timeout: UITestTimeouts.elementExistence),
            "Email Protection signup URL did not appear in the address bar.")
    }
}
