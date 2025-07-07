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

import PixelKit
import PixelKitTestingUtilities
import XCTest
@testable import DuckDuckGo_Privacy_Browser

class MockFireButtonPreferencesPersistor: FireButtonPreferencesPersistor {

    var autoClearEnabled: Bool = false
    var warnBeforeClearingEnabled: Bool = false
    var loginDetectionEnabled: Bool = false

}

fileprivate extension DataClearingPreferences {
    @MainActor
    convenience init(persistor: FireButtonPreferencesPersistor, pixelFiring: PixelFiring? = nil) {
        self.init(
            persistor: persistor,
            fireproofDomains: MockFireproofDomains(domains: []),
            faviconManager: FaviconManagerMock(),
            windowControllersManager: WindowControllersManagerMock(),
            pixelFiring: pixelFiring
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
