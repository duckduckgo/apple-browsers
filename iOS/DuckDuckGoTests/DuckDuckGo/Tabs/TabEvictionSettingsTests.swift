//
//  TabEvictionSettingsTests.swift
//  DuckDuckGoTests
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

import PrivacyConfigTestsUtils
import XCTest
@testable import DuckDuckGo

final class TabEvictionSettingsTests: XCTestCase {

    func testTabEvictionSettingsReadRemoteValues() {
        let settings = makeSettings(json: "{\"maxCapacityPhone\": 12, \"maxCapacityPad\": 8}")

        XCTAssertEqual(settings.maximumCapacity(isPad: false), 12)
        XCTAssertEqual(settings.maximumCapacity(isPad: true), 8)
    }

    func testTabEvictionSettingsFallBackForInvalidValues() {
        let invalidSettings = [
            nil,
            "not json",
            "{}",
            "{\"maxCapacityPhone\": -1, \"maxCapacityPad\": 2.5}",
            "{\"maxCapacityPhone\": true, \"maxCapacityPad\": \"10\"}"
        ]

        for json in invalidSettings {
            let settings = makeSettings(json: json)
            XCTAssertEqual(settings.maximumCapacity(isPad: false), 20)
            XCTAssertEqual(settings.maximumCapacity(isPad: true), 10)
        }
    }

    private func makeSettings(json: String?) -> TabEvictionSettings {
        let config = MockPrivacyConfiguration()
        config.subfeatureSettings = json
        let manager = MockPrivacyConfigurationManager()
        manager.privacyConfig = config
        return TabEvictionSettings(privacyConfigurationManager: manager)
    }
}
