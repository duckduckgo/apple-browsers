//
//  CookiePopupProtectionPreferencesTests.swift
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

import XCTest
import WebExtensions
@testable import DuckDuckGo_Privacy_Browser

class MockCookiePopupProtectionPreferencesPersistor: CookiePopupProtectionPreferencesPersistor {
    var autoconsentEnabled: Bool = false
    var cookiePopupPreferenceRawValue: String?
    var didMigrateCookiePopupPreference: Bool = false
}

class CookiePopupProtectionPreferencesTests: XCTestCase {

    @MainActor
    func testWhenInitializedWithMigratedPreferenceThenItLoadsPersistedValue() {
        let mockPersistor = MockCookiePopupProtectionPreferencesPersistor()
        mockPersistor.didMigrateCookiePopupPreference = true
        mockPersistor.cookiePopupPreferenceRawValue = CookiePopupPreference.max.rawValue
        let cookiePopupPreferences = CookiePopupProtectionPreferences(persistor: mockPersistor, windowControllersManager: WindowControllersManagerMock())

        XCTAssertEqual(cookiePopupPreferences.cookiePopupPreference, .max)
        XCTAssertTrue(cookiePopupPreferences.isAutoconsentEnabled)
    }

    @MainActor
    func testWhenMigratingFromDisabledAutoconsentThenPreferenceIsDoNotBlock() {
        let mockPersistor = MockCookiePopupProtectionPreferencesPersistor()
        mockPersistor.autoconsentEnabled = false
        let cookiePopupPreferences = CookiePopupProtectionPreferences(persistor: mockPersistor, windowControllersManager: WindowControllersManagerMock())

        XCTAssertEqual(cookiePopupPreferences.cookiePopupPreference, .off)
        XCTAssertFalse(cookiePopupPreferences.isAutoconsentEnabled)
        XCTAssertTrue(mockPersistor.didMigrateCookiePopupPreference)
    }

    @MainActor
    func testWhenMigratingFromEnabledAutoconsentThenPreferenceIsBlockStandard() {
        let mockPersistor = MockCookiePopupProtectionPreferencesPersistor()
        mockPersistor.autoconsentEnabled = true
        let cookiePopupPreferences = CookiePopupProtectionPreferences(persistor: mockPersistor, windowControllersManager: WindowControllersManagerMock())

        XCTAssertEqual(cookiePopupPreferences.cookiePopupPreference, .default)
        XCTAssertTrue(mockPersistor.didMigrateCookiePopupPreference)
    }

    @MainActor
    func testWhenCookiePopupPreferenceUpdatedThenPersistorUpdates() {
        let mockPersistor = MockCookiePopupProtectionPreferencesPersistor()
        mockPersistor.didMigrateCookiePopupPreference = true
        mockPersistor.cookiePopupPreferenceRawValue = CookiePopupPreference.default.rawValue
        let cookiePopupPreferences = CookiePopupProtectionPreferences(persistor: mockPersistor, windowControllersManager: WindowControllersManagerMock())
        cookiePopupPreferences.cookiePopupPreference = .off

        XCTAssertEqual(mockPersistor.cookiePopupPreferenceRawValue, CookiePopupPreference.off.rawValue)
    }

}
