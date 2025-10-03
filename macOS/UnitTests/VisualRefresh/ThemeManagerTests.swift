//
//  ThemeManagerTests.swift
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
import Combine
import AppKit
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class ThemeManagerTests: XCTestCase {

    func testInitializationEffectivelyPicksLatestPersistedThemeName() {
        let persistor = AppearancePreferencesPersistorMock(themeName: ThemeName.green.rawValue)
        let preferences = AppearancePreferences(
            persistor: persistor,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger()
        )

        let manager = ThemeManager(appearancePreferences: preferences)
        XCTAssertEqual(manager.theme.name, .green)
    }

    func testThemeManagerRefreshesActiveThemeWhenAppearancePreferencesMutate() {
        let persistor = AppearancePreferencesPersistorMock(themeName: ThemeName.default.rawValue)
        let preferences = AppearancePreferences(
            persistor: persistor,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger()
        )

        preferences.themeName = .orange

        let manager = ThemeManager(appearancePreferences: preferences)
        XCTAssertEqual(manager.theme.name, .orange)
    }
}
