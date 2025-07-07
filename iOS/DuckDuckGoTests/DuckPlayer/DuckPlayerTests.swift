//
//  DuckPlayerTests.swift
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

import BrowserServicesKit
import Combine
import XCTest
import Common

@testable import DuckDuckGo

final class DuckPlayerTests: XCTestCase {

    var duckPlayer: DuckPlayer!
    var mockAppSettings: AppSettingsMock!
    var mockPrivacyConfig: PrivacyConfigurationManagerMock!
    var mockFeatureFlagger: MockDuckPlayerFeatureFlagger!
    var mockSettings: MockDuckPlayerSettings!
    var mockNativeUIPresenter: MockDuckPlayerNativeUIPresenting!
    var mockInternalUserDecider: MockInternalUserDecider!

    override func setUp() {
        super.setUp()
        mockAppSettings = AppSettingsMock()
        mockPrivacyConfig = PrivacyConfigurationManagerMock()
        mockFeatureFlagger = MockDuckPlayerFeatureFlagger()
        mockInternalUserDecider = MockInternalUserDecider()
        mockNativeUIPresenter = MockDuckPlayerNativeUIPresenting()

        mockSettings = MockDuckPlayerSettings(
            appSettings: mockAppSettings,
            privacyConfigManager: mockPrivacyConfig,
            featureFlagger: mockFeatureFlagger,
            internalUserDecider: mockInternalUserDecider
        )

        duckPlayer = DuckPlayer(
            settings: mockSettings,
            featureFlagger: mockFeatureFlagger,
            nativeUIPresenter: mockNativeUIPresenter
        )
    }

    override func tearDown() {
        duckPlayer = nil
        mockSettings = nil
        mockAppSettings = nil
        mockPrivacyConfig = nil
        mockFeatureFlagger = nil
        mockNativeUIPresenter = nil
        mockInternalUserDecider = nil
        super.tearDown()
    }

    // MARK: - mapLegacySettings Tests

    /// Tests that mapLegacySettings correctly maps .enabled mode to .auto and enables SERP
    func testMapLegacySettings_WhenModeIsEnabled_MapsToAutoAndEnablesSERP() {
        // Given
        mockSettings.nativeUI = true
        mockSettings.nativeUISettingsMapped = false
        mockSettings.mode = .enabled

        // When
        duckPlayer.mapLegacySettings()

        // Then
        XCTAssertEqual(mockSettings.nativeUIYoutubeMode, .auto, "enabled mode should map to auto")
        XCTAssertTrue(mockSettings.nativeUISERPEnabled, "SERP should be enabled for enabled mode")
        XCTAssertTrue(mockSettings.nativeUISettingsMapped, "nativeUISettingsMapped should be set to true")
    }

    /// Tests that mapLegacySettings correctly maps .alwaysAsk mode to .ask and enables SERP
    func testMapLegacySettings_WhenModeIsAlwaysAsk_MapsToAskAndEnablesSERP() {
        // Given
        mockSettings.nativeUI = true
        mockSettings.nativeUISettingsMapped = false
        mockSettings.mode = .alwaysAsk

        // When
        duckPlayer.mapLegacySettings()

        // Then
        XCTAssertEqual(mockSettings.nativeUIYoutubeMode, .ask, "alwaysAsk mode should map to ask")
        XCTAssertTrue(mockSettings.nativeUISERPEnabled, "SERP should be enabled for alwaysAsk mode")
        XCTAssertTrue(mockSettings.nativeUISettingsMapped, "nativeUISettingsMapped should be set to true")
    }

    /// Tests that mapLegacySettings correctly maps .disabled mode to .never and disables SERP
    func testMapLegacySettings_WhenModeIsDisabled_MapsToNeverAndDisablesSERP() {
        // Given
        mockSettings.nativeUI = true
        mockSettings.nativeUISettingsMapped = false
        mockSettings.mode = .disabled

        // When
        duckPlayer.mapLegacySettings()

        // Then
        XCTAssertEqual(mockSettings.nativeUIYoutubeMode, .never, "disabled mode should map to never")
        XCTAssertFalse(mockSettings.nativeUISERPEnabled, "SERP should be disabled for disabled mode")
        XCTAssertTrue(mockSettings.nativeUISettingsMapped, "nativeUISettingsMapped should be set to true")
    }

    /// Tests that mapLegacySettings does nothing when nativeUI is false
    func testMapLegacySettings_WhenNativeUIIsFalse_DoesNotMapSettings() {
        // Given
        mockSettings.nativeUI = false
        mockSettings.nativeUISettingsMapped = false
        mockSettings.mode = .enabled
        let originalYoutubeMode = mockSettings.nativeUIYoutubeMode
        let originalSERPEnabled = mockSettings.nativeUISERPEnabled

        // When
        duckPlayer.mapLegacySettings()

        // Then
        XCTAssertEqual(mockSettings.nativeUIYoutubeMode, originalYoutubeMode, "YouTube mode should not change when nativeUI is false")
        XCTAssertEqual(mockSettings.nativeUISERPEnabled, originalSERPEnabled, "SERP enabled should not change when nativeUI is false")
        XCTAssertFalse(mockSettings.nativeUISettingsMapped, "nativeUISettingsMapped should remain false")
    }

    /// Tests that mapLegacySettings does nothing when settings are already mapped
    func testMapLegacySettings_WhenAlreadyMapped_DoesNotMapSettings() {
        // Given
        mockSettings.nativeUI = true
        mockSettings.nativeUISettingsMapped = true
        mockSettings.mode = .enabled
        mockSettings.nativeUIYoutubeMode = .never // Set to something different
        mockSettings.nativeUISERPEnabled = false  // Set to something different

        // When
        duckPlayer.mapLegacySettings()

        // Then
        XCTAssertEqual(mockSettings.nativeUIYoutubeMode, .never, "YouTube mode should not change when already mapped")
        XCTAssertFalse(mockSettings.nativeUISERPEnabled, "SERP enabled should not change when already mapped")
        XCTAssertTrue(mockSettings.nativeUISettingsMapped, "nativeUISettingsMapped should remain true")
    }

    /// Tests that mapLegacySettings does nothing when both nativeUI is false and settings are already mapped
    func testMapLegacySettings_WhenNativeUIIsFalseAndAlreadyMapped_DoesNotMapSettings() {
        // Given
        mockSettings.nativeUI = false
        mockSettings.nativeUISettingsMapped = true
        mockSettings.mode = .alwaysAsk
        let originalYoutubeMode = mockSettings.nativeUIYoutubeMode
        let originalSERPEnabled = mockSettings.nativeUISERPEnabled

        // When
        duckPlayer.mapLegacySettings()

        // Then
        XCTAssertEqual(mockSettings.nativeUIYoutubeMode, originalYoutubeMode, "YouTube mode should not change")
        XCTAssertEqual(mockSettings.nativeUISERPEnabled, originalSERPEnabled, "SERP enabled should not change")
        XCTAssertTrue(mockSettings.nativeUISettingsMapped, "nativeUISettingsMapped should remain true")
    }

    /// Tests that mapLegacySettings preserves other settings when mapping
    func testMapLegacySettings_PreservesOtherSettings() {
        // Given
        mockSettings.nativeUI = true
        mockSettings.nativeUISettingsMapped = false
        mockSettings.mode = .enabled
        mockSettings.askModeOverlayHidden = true
        mockSettings.allowFirstVideo = true
        mockSettings.openInNewTab = true
        mockSettings.autoplay = true
        let originalVariant = mockSettings.variant

        // When
        duckPlayer.mapLegacySettings()

        // Then
        XCTAssertTrue(mockSettings.askModeOverlayHidden, "askModeOverlayHidden should be preserved")
        XCTAssertTrue(mockSettings.allowFirstVideo, "allowFirstVideo should be preserved")
        XCTAssertTrue(mockSettings.openInNewTab, "openInNewTab should be preserved")
        XCTAssertTrue(mockSettings.autoplay, "autoplay should be preserved")
        XCTAssertEqual(mockSettings.variant, originalVariant, "variant should be preserved")
    }

    /// Tests that mapLegacySettings is called during DuckPlayer initialization
    func testMapLegacySettings_IsCalledDuringInitialization() {
        // Given
        mockSettings.nativeUI = true
        mockSettings.nativeUISettingsMapped = false
        mockSettings.mode = .alwaysAsk

        // When
        let newDuckPlayer = DuckPlayer(
            settings: mockSettings,
            featureFlagger: mockFeatureFlagger,
            nativeUIPresenter: mockNativeUIPresenter
        )

        // Then
        XCTAssertEqual(mockSettings.nativeUIYoutubeMode, .ask, "Settings should be mapped during initialization")
        XCTAssertTrue(mockSettings.nativeUISERPEnabled, "SERP should be enabled during initialization")
        XCTAssertTrue(mockSettings.nativeUISettingsMapped, "nativeUISettingsMapped should be set during initialization")
        XCTAssertNotNil(newDuckPlayer, "DuckPlayer should be created successfully")
    }
}
