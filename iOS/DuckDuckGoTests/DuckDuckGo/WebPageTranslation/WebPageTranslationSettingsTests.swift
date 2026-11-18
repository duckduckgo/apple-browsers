//
//  WebPageTranslationSettingsTests.swift
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

import XCTest
import PrivacyConfig
import PrivacyConfigTestsUtils
@testable import DuckDuckGo

final class WebPageTranslationSettingsTests: XCTestCase {

    func testReadsSampleLengthFromRemoteConfig() {
        XCTAssertEqual(makeSUT(json: "{\"sampleLength\": 2000}").sampleLength, 2000)
    }

    func testDefaultsWhenSettingsMissing() {
        XCTAssertEqual(makeSUT(json: nil).sampleLength, 4096)
    }

    func testDefaultsWhenKeyAbsent() {
        XCTAssertEqual(makeSUT(json: "{}").sampleLength, 4096)
    }

    func testDefaultsWhenJSONMalformed() {
        XCTAssertEqual(makeSUT(json: "not json").sampleLength, 4096)
    }

    func testDefaultsWhenValueWrongType() {
        XCTAssertEqual(makeSUT(json: "{\"sampleLength\": \"2000\"}").sampleLength, 4096)
    }

    func testDefaultsWhenValueNotPositive() {
        XCTAssertEqual(makeSUT(json: "{\"sampleLength\": 0}").sampleLength, 4096)
        XCTAssertEqual(makeSUT(json: "{\"sampleLength\": -5}").sampleLength, 4096)
    }

    private func makeSUT(json: String?) -> WebPageTranslationSettings {
        let config = MockPrivacyConfiguration()
        config.subfeatureSettings = json
        let manager = MockPrivacyConfigurationManager()
        manager.privacyConfig = config
        return WebPageTranslationSettings(privacyConfigurationManager: manager)
    }
}
