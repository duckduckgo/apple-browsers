//
//  NewAddressBarPickerDisplayValidatorTests.swift
//  DuckDuckGo
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
import Core
import Persistence
import BrowserServicesKit
import RemoteMessaging
import RemoteMessagingTestsUtils
import PersistenceTestingUtils
import AIChat
@testable import DuckDuckGo

final class NewAddressBarPickerDisplayValidatorTests: XCTestCase {
    private var mockAIChatSettings: MockAIChatSettingsProvider!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockAppSettings: AppSettingsMock!
    private var mockKeyValueStore: MockKeyValueStore!
    private var testUserDefaults: UserDefaults!
    private var experimentalAIChatManager: ExperimentalAIChatManager!
    private var pickerStorage: NewAddressBarPickerStore!
    private var validator: NewAddressBarPickerDisplayValidator!

    private let testSuiteName = "NewAddressBarPickerDisplayValidatorTests"

    override func setUp() {
        super.setUp()

        mockAIChatSettings = MockAIChatSettingsProvider()
        mockFeatureFlagger = MockFeatureFlagger()
        mockAppSettings = AppSettingsMock()
        mockKeyValueStore = MockKeyValueStore()

        testUserDefaults = UserDefaults(suiteName: testSuiteName)!
        testUserDefaults.removePersistentDomain(forName: testSuiteName)

        experimentalAIChatManager = ExperimentalAIChatManager(
            featureFlagger: mockFeatureFlagger,
            userDefaults: testUserDefaults
        )
        pickerStorage = NewAddressBarPickerStore(keyValueStore: mockKeyValueStore)

        // Note: tutorialSettings and launchSourceManager validation moved to ModalPromptCoordinationService
        validator = NewAddressBarPickerDisplayValidator(
            aiChatSettings: mockAIChatSettings,
            featureFlagger: mockFeatureFlagger,
            experimentalAIChatManager: experimentalAIChatManager,
            appSettings: mockAppSettings,
            pickerStorage: pickerStorage
        )
    }

    override func tearDown() {
        validator = nil
        pickerStorage = nil
        experimentalAIChatManager = nil
        testUserDefaults.removePersistentDomain(forName: testSuiteName)
        testUserDefaults = nil
        mockKeyValueStore = nil
        mockAppSettings = nil
        mockFeatureFlagger = nil
        mockAIChatSettings = nil
        super.tearDown()
    }

    // MARK: - Show Criteria Tests

    func testShouldDisplayPicker_WhenAllShowCriteriaMet_ReturnsTrue() {
        // Given
        setupShowCriteriaMet()
        setupNoExclusionCriteria()

        // When
        let result = validator.shouldDisplayNewAddressBarPicker()

        // Then
        XCTAssertTrue(result)
    }

    func testShouldDisplayPicker_WhenAIChatDisabled_ReturnsFalse() {
        // Given
        mockAIChatSettings.isAIChatEnabled = false
        mockFeatureFlagger.enabledFeatureFlags = [.showAIChatAddressBarChoiceScreen]
        setupNoExclusionCriteria()

        // When
        let result = validator.shouldDisplayNewAddressBarPicker()

        // Then
        XCTAssertFalse(result)
    }

    func testShouldDisplayPicker_WhenFeatureFlagDisabled_ReturnsFalse() {
        // Given
        mockAIChatSettings.isAIChatEnabled = true
        mockFeatureFlagger.enabledFeatureFlags = []
        setupNoExclusionCriteria()

        // When
        let result = validator.shouldDisplayNewAddressBarPicker()

        // Then
        XCTAssertFalse(result)
    }

    // MARK: - Exclusion Criteria Tests

    func testShouldDisplayPicker_WhenAddressBarPositionIsBottom_ReturnsFalse() {
        // Given
        setupShowCriteriaMet()
        mockAIChatSettings.isAIChatSearchInputUserSettingsEnabled = false
        mockAppSettings.currentAddressBarPosition = .bottom

        // When
        let result = validator.shouldDisplayNewAddressBarPicker()

        // Then
        XCTAssertFalse(result)
    }

    func testShouldDisplayPicker_WhenAddressBarPositionIsTop_ReturnsTrue() {
        // Given
        setupShowCriteriaMet()
        mockAIChatSettings.isAIChatSearchInputUserSettingsEnabled = false
        mockAppSettings.currentAddressBarPosition = .top

        // When
        let result = validator.shouldDisplayNewAddressBarPicker()

        // Then
        XCTAssertTrue(result)
    }

    func testShouldDisplayPicker_WhenAddressBarSearchInputDisabled_ReturnsTrue() {
        // Given
        setupShowCriteriaMet()
        mockAIChatSettings.isAIChatSearchInputUserSettingsEnabled = false

        // When
        let result = validator.shouldDisplayNewAddressBarPicker()

        // Then
        XCTAssertTrue(result)
    }

    func testShouldDisplayPicker_WhenAddressBarSearchInputEnabled_ReturnsFalse() {
        // Given
        setupShowCriteriaMet()
        mockAIChatSettings.isAIChatSearchInputUserSettingsEnabled = true

        // When
        let result = validator.shouldDisplayNewAddressBarPicker()

        // Then
        XCTAssertFalse(result)
    }

    func testShouldDisplayPicker_WhenAlreadyShown_ReturnsFalse() {
        // Given
        setupShowCriteriaMet()
        mockKeyValueStore.set(true, forKey: "aichat.storage.newAddressBarPickerShown")

        // When
        let result = validator.shouldDisplayNewAddressBarPicker()

        // Then
        XCTAssertFalse(result)
    }

    // MARK: - Complex Scenarios

    func testShouldDisplayPicker_WithMultipleExclusionCriteria_ReturnsFalse() {
        // Given
        setupShowCriteriaMet()
        mockAIChatSettings.isAIChatAddressBarUserSettingsEnabled = false
        testUserDefaults.set(true, forKey: "experimentalAIChatSettingsEnabled")
        mockKeyValueStore.set(true, forKey: "aichat.storage.newAddressBarPickerShown")

        // When
        let result = validator.shouldDisplayNewAddressBarPicker()

        // Then
        XCTAssertFalse(result)
    }

    func testShouldDisplayPicker_WithPartialShowCriteria_ReturnsFalse() {
        // Given
        mockAIChatSettings.isAIChatEnabled = false // AI Chat disabled
        mockFeatureFlagger.enabledFeatureFlags = [.showAIChatAddressBarChoiceScreen]
        setupNoExclusionCriteria()

        // When
        let result = validator.shouldDisplayNewAddressBarPicker()

        // Then
        XCTAssertFalse(result)
    }

    // MARK: - Helper Methods

    private func setupShowCriteriaMet() {
        mockAIChatSettings.isAIChatEnabled = true
        mockFeatureFlagger.enabledFeatureFlags = [.showAIChatAddressBarChoiceScreen]
    }

    private func setupNoExclusionCriteria() {
        mockAIChatSettings.isAIChatAddressBarUserSettingsEnabled = true
        testUserDefaults.set(false, forKey: "experimentalAIChatSettingsEnabled")
        mockKeyValueStore.set(false, forKey: "aichat.storage.newAddressBarPickerShown")
    }
}
