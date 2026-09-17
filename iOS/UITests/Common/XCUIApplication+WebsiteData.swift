//
//  XCUIApplication+WebsiteData.swift
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

    private var cookieCounter: XCUIElement {
        webViews.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Cookie Counter:"))
            .firstMatch
    }

    private var storageCounter: XCUIElement {
        webViews.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Storage Counter:"))
            .firstMatch
    }

    func openStorageCounterPage(file: StaticString = #filePath, line: UInt = #line) {
        enterSearchText("https://privacy-test-pages.site/features/local-storage.html\r", file: file, line: line)
        XCTAssertTrue(
            webViews.buttons["Manual Increment"].waitForExistence(timeout: UITestTimeouts.navigation),
            "Storage counter page did not load.",
            file: file,
            line: line)
    }

    func incrementStorageCounters(file: StaticString = #filePath, line: UInt = #line) {
        webViews.descendants(matching: .any)["Manual Increment"].tapWhenHittable(file: file, line: line)
        assertStorageCountersIncremented(file: file, line: line)
    }

    func resetStorageCounters(file: StaticString = #filePath, line: UInt = #line) {
        // A failed data-clearing test can leave this fixture populated; app-default resets do not clear WebKit storage.
        webViews.buttons["Cleanup data"].tapWhenHittable(file: file, line: line)
        assertStorageCountersEmpty(file: file, line: line)
    }

    func assertStorageCountersEmpty(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            cookieCounter.waitForExistence(timeout: UITestTimeouts.navigation),
            "Cookie counter did not appear.",
            file: file,
            line: line)
        XCTAssertTrue(
            storageCounter.wait(for: \XCUIElement.label, equals: "Storage Counter: undefined", timeout: UITestTimeouts.navigation),
            "Local storage was not empty; found '\(storageCounter.label)'.",
            file: file,
            line: line)
        XCTAssertNotEqual(cookieCounter.label, "Cookie Counter: 1", "Cookie data was not empty.", file: file, line: line)
    }

    func assertStorageCountersIncremented(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            webViews.staticTexts["Cookie Counter: 1"].waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Cookie counter did not increment.",
            file: file,
            line: line)
        XCTAssertTrue(
            webViews.staticTexts["Storage Counter: 1"].waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Local storage counter did not increment.",
            file: file,
            line: line)
    }
}
