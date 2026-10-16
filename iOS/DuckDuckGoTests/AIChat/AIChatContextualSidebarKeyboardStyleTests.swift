//
//  AIChatContextualSidebarKeyboardStyleTests.swift
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
@testable import DuckDuckGo

final class AIChatContextualSidebarKeyboardStyleTests: XCTestCase {

    private var userDefaults: UserDefaults!
    private let suiteName = "AIChatContextualSidebarKeyboardStyleTests"

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        super.tearDown()
    }

    func testWhenNoKeyboardCoversTheSidebarThenNoStyleAdapts() {
        for style in AIChatContextualSidebarKeyboardStyle.allCases {
            XCTAssertEqual(style.adaptation(isKeyboardCovering: false, isLandscape: true), .none)
            XCTAssertEqual(style.adaptation(isKeyboardCovering: false, isLandscape: false), .none)
        }
    }

    func testWhenStyleIsStandardThenTheLayoutNeverAdapts() {
        XCTAssertEqual(AIChatContextualSidebarKeyboardStyle.standard.adaptation(isKeyboardCovering: true, isLandscape: true), .none)
        XCTAssertEqual(AIChatContextualSidebarKeyboardStyle.standard.adaptation(isKeyboardCovering: true, isLandscape: false), .none)
    }

    func testWhenStyleIsCompactInLandscapeThenOnlyLandscapeCompacts() {
        let style = AIChatContextualSidebarKeyboardStyle.compactInLandscape

        XCTAssertEqual(style.adaptation(isKeyboardCovering: true, isLandscape: true), .compact)
        XCTAssertEqual(style.adaptation(isKeyboardCovering: true, isLandscape: false), .none)
    }

    func testWhenStyleIsFloatingSuggestionsThenBothOrientationsFloat() {
        let style = AIChatContextualSidebarKeyboardStyle.floatingSuggestions

        XCTAssertEqual(style.adaptation(isKeyboardCovering: true, isLandscape: true), .floatingSuggestions)
        XCTAssertEqual(style.adaptation(isKeyboardCovering: true, isLandscape: false), .floatingSuggestions)
    }

    func testWhenNothingIsStoredThenSettingReturnsTheDefaultStyle() {
        let setting = AIChatContextualSidebarKeyboardStyleSetting(userDefaults: userDefaults)

        XCTAssertEqual(setting.keyboardStyle, AIChatContextualSidebarKeyboardStyle.default)
    }

    func testWhenStyleIsStoredThenANewSettingReadsItBack() {
        AIChatContextualSidebarKeyboardStyleSetting(userDefaults: userDefaults).keyboardStyle = .compactInLandscape

        XCTAssertEqual(AIChatContextualSidebarKeyboardStyleSetting(userDefaults: userDefaults).keyboardStyle, .compactInLandscape)
    }

    func testWhenStoredValueIsUnknownThenSettingFallsBackToTheDefaultStyle() {
        userDefaults.set("removedStyle", forKey: "aichat.debug.contextualSidebarKeyboardStyle")

        XCTAssertEqual(AIChatContextualSidebarKeyboardStyleSetting(userDefaults: userDefaults).keyboardStyle,
                       AIChatContextualSidebarKeyboardStyle.default)
    }
}
