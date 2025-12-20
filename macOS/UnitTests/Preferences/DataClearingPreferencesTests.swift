//
//  DataClearingPreferencesTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import FeatureFlags
import PixelKit
import PixelKitTestingUtilities
import PrivacyConfig
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

class MockFireButtonPreferencesPersistor: FireButtonPreferencesPersistor {
    var isFireAnimationEnabled: Bool = false
    var autoClearEnabled: Bool = false
    var warnBeforeClearingEnabled: Bool = false
    var loginDetectionEnabled: Bool = false
    var shouldOpenFireWindowByDefault: Bool = false
    var autoClearAIChatHistoryEnabled: Bool = false
}

fileprivate extension DataClearingPreferences {
    @MainActor
    convenience init(persistor: FireButtonPreferencesPersistor,
                     featureFlagger: FeatureFlagger = MockFeatureFlagger(),
                     pixelFiring: PixelFiring? = nil,
                     aiChatHistoryCleaner: AIChatHistoryCleaning = MockAIChatHistoryCleaner()) {
        self.init(
            persistor: persistor,
            fireproofDomains: MockFireproofDomains(domains: []),
            faviconManager: FaviconManagerMock(),
            windowControllersManager: WindowControllersManagerMock(),
            featureFlagger: featureFlagger,
            pixelFiring: pixelFiring,
            aiChatHistoryCleaner: aiChatHistoryCleaner
        )
    }
}

class DataClearingPreferencesTests: XCTestCase {

    @MainActor
    func testWhenInitializedThenItLoadsPersistedLoginDetectionSetting() {
        let mockPersistor = MockFireButtonPreferencesPersistor()
        mockPersistor.loginDetectionEnabled = true
        let dataClearingPreferences = DataClearingPreferences(persistor: mockPersistor)

        XCTAssertTrue(dataClearingPreferences.isLoginDetectionEnabled)
    }

    @MainActor
    func testWhenIsLoginDetectionEnabledUpdatedThenPersistorUpdates() {
        let mockPersistor = MockFireButtonPreferencesPersistor()
        let dataClearingPreferences = DataClearingPreferences(persistor: mockPersistor)
        dataClearingPreferences.isLoginDetectionEnabled = true

        XCTAssertTrue(mockPersistor.loginDetectionEnabled)
    }

    @MainActor
    func testWhenisFireAnimationEnabledUpdatedThenPersistorUpdates() {
        let mockPersistor = MockFireButtonPreferencesPersistor()
        let dataClearingPreferences = DataClearingPreferences(persistor: mockPersistor)
        dataClearingPreferences.isFireAnimationEnabled = true

        XCTAssertTrue(mockPersistor.isFireAnimationEnabled)

        dataClearingPreferences.isFireAnimationEnabled = false

        XCTAssertFalse(mockPersistor.isFireAnimationEnabled)
    }

    @MainActor
    func testWhenOpenFireWindowByDefaultIsUpdatedThenPersistorUpdates() {
        let mockPersistor = MockFireButtonPreferencesPersistor()
        let dataClearingPreferences = DataClearingPreferences(persistor: mockPersistor)
        dataClearingPreferences.shouldOpenFireWindowByDefault = true

        XCTAssertTrue(mockPersistor.shouldOpenFireWindowByDefault)

        dataClearingPreferences.shouldOpenFireWindowByDefault = false

        XCTAssertFalse(mockPersistor.shouldOpenFireWindowByDefault)
    }

    @MainActor
    func testWhenAIChatHistoryCleanerDisplayOptionIsTrue_thenShouldShowAutoClearAIChatHistorySettingIsTrue() {
        let mockPersistor = MockFireButtonPreferencesPersistor()
        let mockAIChatHistoryCleaner = MockAIChatHistoryCleaner()
        mockAIChatHistoryCleaner.shouldDisplayCleanAIChatHistoryOption = true
        let sut = DataClearingPreferences(persistor: mockPersistor, aiChatHistoryCleaner: mockAIChatHistoryCleaner)

        XCTAssertTrue(sut.shouldShowAutoClearAIChatHistorySetting)
    }

    @MainActor
    func testWhenAIChatHistoryCleanerDisplayOptionIsFalse_thenShouldShowAutoClearAIChatHistorySettingIsFalse() {
        let mockPersistor = MockFireButtonPreferencesPersistor()
        let mockAIChatHistoryCleaner = MockAIChatHistoryCleaner()
        mockAIChatHistoryCleaner.shouldDisplayCleanAIChatHistoryOption = false
        let sut = DataClearingPreferences(persistor: mockPersistor, aiChatHistoryCleaner: mockAIChatHistoryCleaner)

        XCTAssertFalse(sut.shouldShowAutoClearAIChatHistorySetting)
    }

    @MainActor
    func testWhenAIChatHistoryCleanerDisplayOptionBecomesTrue_thenShouldShowAutoClearAIChatHistorySettingIsEnabled() {
        let mockPersistor = MockFireButtonPreferencesPersistor()
        let mockAIChatHistoryCleaner = MockAIChatHistoryCleaner()
        mockAIChatHistoryCleaner.shouldDisplayCleanAIChatHistoryOption = false
        let sut = DataClearingPreferences(persistor: mockPersistor, aiChatHistoryCleaner: mockAIChatHistoryCleaner)

        XCTAssertFalse(sut.shouldShowAutoClearAIChatHistorySetting)

        mockAIChatHistoryCleaner.shouldDisplayCleanAIChatHistoryOption = true

        XCTAssertTrue(sut.shouldShowAutoClearAIChatHistorySetting)

    }

    @MainActor
    func testWhenIsAutoClearAIChatHistoryEnabledIsUpdated_thenPersistorUpdates() {
        let mockPersistor = MockFireButtonPreferencesPersistor()
        let dataClearingPreferences = DataClearingPreferences(persistor: mockPersistor)
        dataClearingPreferences.isAutoClearAIChatHistoryEnabled = true

        XCTAssertTrue(mockPersistor.autoClearAIChatHistoryEnabled)

        dataClearingPreferences.isAutoClearAIChatHistoryEnabled = false

        XCTAssertFalse(mockPersistor.autoClearAIChatHistoryEnabled)
    }

    // MARK: - Pixel firing tests

    @MainActor
    func testWhenDataClearingSettingIsUpdatedThenPixelIsFired() {
        let pixelFiringMock = PixelKitMock()
        let mockPersistor = MockFireButtonPreferencesPersistor()
        let dataClearingPreferences = DataClearingPreferences(persistor: mockPersistor, pixelFiring: pixelFiringMock)

        dataClearingPreferences.isAutoClearEnabled = true
        dataClearingPreferences.isAutoClearEnabled = false

        pixelFiringMock.expectedFireCalls = [
            .init(pixel: SettingsPixel.dataClearingSettingToggled, frequency: .uniqueByName),
            .init(pixel: SettingsPixel.dataClearingSettingToggled, frequency: .uniqueByName)
        ]

        pixelFiringMock.verifyExpectations()
    }
}

extension MockAIChatHistoryCleaner: AIChatHistoryCleaning {}
