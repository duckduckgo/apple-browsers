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

import Foundation
import Combine
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class ThemeManagerTests: XCTestCase {

    func testInitializationEffectivelyPicksLatestPersistedThemeName() {
        let (manager, _, _) = buildThemeManager(initialTheme: .green)
        XCTAssertEqual(manager.theme.name, .green)
    }

    func testThemeManagerRefreshesActiveThemeWhenAppearancePreferencesMutate() async {
        let (manager, preferences, _) = buildThemeManager(initialTheme: .default)

        let themeUpdated = expectation(description: "Theme updated")
        var updatedTheme: (any ThemeStyleProviding)?
        let cancellable = manager.themePublisher.dropFirst().first().sink { theme in
            updatedTheme = theme
            themeUpdated.fulfill()
        }

        preferences.themeName = .violet

        await fulfillment(of: [themeUpdated], timeout: 5)
        XCTAssertEqual(updatedTheme?.name, .violet)
        withExtendedLifetime(cancellable) {}
    }

    func testThemeManagerRefreshesActiveAppearanceWhenAppearancePreferencesMutate() async {
        let (manager, preferences, _) = buildThemeManager(initialAppearance: .dark)
        XCTAssertEqual(manager.appearance, .dark)

        let appearanceUpdated = expectation(description: "Appearance updated")
        var updatedAppearance: ThemeAppearance?
        let cancellable = manager.appearancePublisher.dropFirst().first().sink { appearance in
            updatedAppearance = appearance
            appearanceUpdated.fulfill()
        }

        preferences.themeAppearance = .systemDefault

        await fulfillment(of: [appearanceUpdated], timeout: 5)
        XCTAssertEqual(updatedAppearance, .systemDefault)
        withExtendedLifetime(cancellable) {}
    }

    func testFigmaThemeIsRemappedToDefaultTheme() {
        let (manager, _, _) = buildThemeManager(initialTheme: "figma", initialAppearance: "dark")

        XCTAssertEqual(manager.theme.name, .default)
    }
}

private extension ThemeManagerTests {

    func buildThemeManager(initialTheme: ThemeName = .default, initialAppearance: ThemeAppearance = .systemDefault) -> (ThemeManaging, AppearancePreferences, MockFeatureFlagger) {
        buildThemeManager(initialTheme: initialTheme.rawValue, initialAppearance: initialAppearance.rawValue)
    }

    func buildThemeManager(initialTheme: String, initialAppearance: String) -> (ThemeManaging, AppearancePreferences, MockFeatureFlagger) {
        let persistor = AppearancePreferencesPersistorMock(themeAppearance: initialAppearance, themeName: initialTheme)
        let featureFlagger = MockFeatureFlagger()

        let preferences = AppearancePreferences(
            persistor: persistor,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: featureFlagger,
            aiChatMenuConfig: MockAIChatConfig()
        )

        let manager = ThemeManager(appearancePreferences: preferences, featureFlagger: featureFlagger)

        return (manager, preferences, featureFlagger)
    }
}
