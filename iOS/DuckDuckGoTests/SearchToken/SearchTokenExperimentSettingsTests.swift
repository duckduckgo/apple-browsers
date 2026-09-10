//
//  SearchTokenExperimentSettingsTests.swift
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
import PrivacyConfig
import PrivacyConfigTestsUtils
@testable import DuckDuckGo

final class SearchTokenExperimentSettingsTests: XCTestCase {

    func testReadsValuesFromRemoteConfig() {
        let sut = makeSUT(json: "{\"tokenTTLSeconds\": 200, \"refreshWindowSeconds\": 30}")
        XCTAssertEqual(sut.tokenTTL, 200)
        XCTAssertEqual(sut.refreshWindow, 30)
    }

    func testDefaultsWhenSettingsMissing() {
        let sut = makeSUT(json: nil)
        XCTAssertEqual(sut.tokenTTL, 300)
        XCTAssertEqual(sut.refreshWindow, 120)
    }

    func testDefaultsWhenKeysAbsent() {
        let sut = makeSUT(json: "{}")
        XCTAssertEqual(sut.tokenTTL, 300)
        XCTAssertEqual(sut.refreshWindow, 120)
    }

    func testDefaultsWhenJSONMalformed() {
        let sut = makeSUT(json: "not json")
        XCTAssertEqual(sut.tokenTTL, 300)
        XCTAssertEqual(sut.refreshWindow, 120)
    }

    func testDefaultsWhenValuesWrongType() {
        // Non-numeric values (e.g. a quoted number) must fall back to defaults, not crash or coerce.
        let sut = makeSUT(json: "{\"tokenTTLSeconds\": \"abc\", \"refreshWindowSeconds\": \"300\"}")
        XCTAssertEqual(sut.tokenTTL, 300)
        XCTAssertEqual(sut.refreshWindow, 120)
    }

    private func makeSUT(json: String?) -> SearchTokenExperimentSettings {
        let config = MockPrivacyConfiguration()
        config.subfeatureSettings = json
        let manager = MockPrivacyConfigurationManager()
        manager.privacyConfig = config
        return SearchTokenExperimentSettings(privacyConfigurationManager: manager)
    }
}
