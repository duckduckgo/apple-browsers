//
//  AIChatDebugSettingsTests.swift
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

#if os(iOS)
import XCTest
@testable import AIChat

final class AIChatDebugSettingsTests: XCTestCase {

    private var userDefaults: UserDefaults!
    private var settings: AIChatDebugSettings!

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: #file)
        userDefaults.removePersistentDomain(forName: #file)
        settings = AIChatDebugSettings(userDefault: userDefaults)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: #file)
        super.tearDown()
    }

    func testMatchesCustomURL_WhenCustomURLUnset_ReturnsFalse() {
        XCTAssertFalse(settings.matchesCustomURL(URL(string: "https://dev.duck.ai/chat")!))
    }

    func testMatchesCustomURL_WhenPathDiffersOnSameHost_ReturnsTrue() {
        settings.customURL = "https://dev.duck.ai"

        XCTAssertTrue(settings.matchesCustomURL(URL(string: "https://dev.duck.ai/chat?placement=sidebar")!))
    }

    func testMatchesCustomURL_WhenHostDiffers_ReturnsFalse() {
        settings.customURL = "https://dev.duck.ai"

        XCTAssertFalse(settings.matchesCustomURL(URL(string: "https://duckduckgo.com/")!))
    }

    func testMatchesCustomURL_WhenSchemeDiffers_ReturnsFalse() {
        settings.customURL = "https://dev.duck.ai"

        XCTAssertFalse(settings.matchesCustomURL(URL(string: "http://dev.duck.ai/")!))
    }
}
#endif
