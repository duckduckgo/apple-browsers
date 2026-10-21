//
//  AIChatHistorySettingsTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import PrivacyConfigTestsUtils
@testable import AIChat

final class AIChatHistorySettingsTests: XCTestCase {

    // MARK: - maxHistoryCount Tests

    func testMaxHistoryCount_WhenPrivacyConfigIsNil_ReturnsDefaultValue() {
        // Given
        let settings = AIChatHistorySettings(privacyConfig: nil)

        // When
        let result = settings.maxHistoryCount

        // Then
        XCTAssertEqual(result, AIChatHistorySettings.SettingsKey.defaultMaxHistoryCount)
    }

    func testMaxHistoryCount_WhenSettingsContainsValue_ReturnsConfiguredValue() {
        // Given
        let mockConfig = MockPrivacyConfiguration()
        mockConfig.featureSettings = ["maxHistoryCount": 25]
        let mockManager = MockPrivacyConfigurationManager(privacyConfig: mockConfig)
        let settings = AIChatHistorySettings(privacyConfig: mockManager)

        // When
        let result = settings.maxHistoryCount

        // Then
        XCTAssertEqual(result, 25)
    }

    func testMaxHistoryCount_WhenSettingsDoesNotContainValue_ReturnsDefaultValue() {
        // Given
        let mockConfig = MockPrivacyConfiguration()
        mockConfig.featureSettings = [:]
        let mockManager = MockPrivacyConfigurationManager(privacyConfig: mockConfig)
        let settings = AIChatHistorySettings(privacyConfig: mockManager)

        // When
        let result = settings.maxHistoryCount

        // Then
        XCTAssertEqual(result, AIChatHistorySettings.SettingsKey.defaultMaxHistoryCount)
    }

    func testMaxHistoryCount_WhenSettingsContainsWrongType_ReturnsDefaultValue() {
        // Given
        let mockConfig = MockPrivacyConfiguration()
        mockConfig.featureSettings = ["maxHistoryCount": "not an int"]
        let mockManager = MockPrivacyConfigurationManager(privacyConfig: mockConfig)
        let settings = AIChatHistorySettings(privacyConfig: mockManager)

        // When
        let result = settings.maxHistoryCount

        // Then
        XCTAssertEqual(result, AIChatHistorySettings.SettingsKey.defaultMaxHistoryCount)
    }

    func testMaxHistoryCount_WhenSettingsContainsZero_ReturnsZero() {
        // Given
        let mockConfig = MockPrivacyConfiguration()
        mockConfig.featureSettings = ["maxHistoryCount": 0]
        let mockManager = MockPrivacyConfigurationManager(privacyConfig: mockConfig)
        let settings = AIChatHistorySettings(privacyConfig: mockManager)

        // When
        let result = settings.maxHistoryCount

        // Then
        XCTAssertEqual(result, 0)
    }

    func testMaxHistoryCount_WhenSettingsContainsNegativeValue_ReturnsZero() {
        // Given
        let mockConfig = MockPrivacyConfiguration()
        mockConfig.featureSettings = ["maxHistoryCount": -5]
        let mockManager = MockPrivacyConfigurationManager(privacyConfig: mockConfig)
        let settings = AIChatHistorySettings(privacyConfig: mockManager)

        // When
        let result = settings.maxHistoryCount

        // Then
        XCTAssertEqual(result, 0)
    }

    func testMaxHistoryCount_WhenSettingsContainsLargeValue_ReturnsConfiguredValue() {
        // Given
        let mockConfig = MockPrivacyConfiguration()
        mockConfig.featureSettings = ["maxHistoryCount": 1000]
        let mockManager = MockPrivacyConfigurationManager(privacyConfig: mockConfig)
        let settings = AIChatHistorySettings(privacyConfig: mockManager)

        // When
        let result = settings.maxHistoryCount

        // Then
        XCTAssertEqual(result, 1000)
    }
}
