//
//  OmnibarAccessoryHandlerTests.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import AIChat
@testable import DuckDuckGo

/// Only chat is supported for now.  This will all get refactored out in a future project for  browser customisation.
class OmnibarAccessoryHandlerTests: XCTestCase {

    static let DDGSearchURL = URL(string: "https://duckduckgo.com?q=hello")!
    static let DDGHomeURL = URL(string: "https://duckduckgo.com")!
    static let randomURL = URL(string: "https://potato.com")!

    func testOmnibarAccessoryWhenAIChatFeatureEnabledAndUserSettingsDisabled() {
        let settings = MockAIChatSettingsProvider()
        settings.isAIChatAddressBarUserSettingsEnabled = false
        let handler = OmnibarAccessoryHandler(settings: settings)

        let accessoryType = handler.omnibarAccessory(for: OmnibarAccessoryHandlerTests.DDGSearchURL)

        XCTAssertEqual(accessoryType, OmniBarAccessoryType.chat)
    }

    func testOmnibarAccessoryWhenAIChatFeatureAndUserSettingsEnabledWithDuckDuckGoURL() {
        let settings = MockAIChatSettingsProvider()
        settings.isAIChatAddressBarUserSettingsEnabled = true
        let handler = OmnibarAccessoryHandler(settings: settings)
        let accessoryType = handler.omnibarAccessory(for: OmnibarAccessoryHandlerTests.DDGSearchURL)

        XCTAssertEqual(accessoryType, OmniBarAccessoryType.chat)
    }

    func testOmnibarAccessoryWhenAIChatFeatureAndUserSettingsEnabledWithNonDuckDuckGoURL() {
        let settings = MockAIChatSettingsProvider()
        settings.isAIChatAddressBarUserSettingsEnabled = true
        let handler = OmnibarAccessoryHandler(settings: settings)
        let accessoryType = handler.omnibarAccessory(for: OmnibarAccessoryHandlerTests.randomURL)

        XCTAssertEqual(accessoryType, OmniBarAccessoryType.chat)
    }

    func testOmnibarAccessoryWhenAIChatFeatureAndUserSettingsEnabledWithDuckDuckGoHomeURL() {
        let settings = MockAIChatSettingsProvider()
        settings.isAIChatAddressBarUserSettingsEnabled = true
        let handler = OmnibarAccessoryHandler(settings: settings)
        let accessoryType = handler.omnibarAccessory(for: OmnibarAccessoryHandlerTests.DDGHomeURL)

        XCTAssertEqual(accessoryType, OmniBarAccessoryType.chat)
    }
}
