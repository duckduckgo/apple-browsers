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

        preferences.themeName = .violet

        let updatedTheme = await manager.themePublisher.nextValue()
        XCTAssertEqual(updatedTheme.name, .violet)
    }

    func testThemeManagerRefreshesActiveAppearanceWhenAppearancePreferencesMutate() async {
        let (manager, preferences, _) = buildThemeManager(initialAppearance: .dark)
        XCTAssertEqual(manager.appearance, .dark)

        preferences.themeAppearance = .systemDefault

        let updatedAppearance = await manager.appearancePublisher.nextValue()
        XCTAssertEqual(updatedAppearance, .systemDefault)
    }

    func testFigmaThemeIsRemappedToDefaultTheme() {
        let (manager, _, _) = buildThemeManager(initialTheme: "figma", initialAppearance: "dark")

        XCTAssertEqual(manager.theme.name, .default)
    }

    func testDisablingThemesFlagSetsTheLegacyTheme() async {
        let (manager, _, featureFlagger) = buildThemeManager(initialTheme: .green, initialAppearance: .light)

        featureFlagger.featuresStub["themes"] = false
        featureFlagger.triggerUpdate()

        let updatedTheme = await manager.themePublisher.nextValue()
        XCTAssertEqual(updatedTheme.name, .default)
        XCTAssertEqual(manager.appearance, .light)
    }
}

private extension ThemeManagerTests {

    func buildThemeManager(initialTheme: ThemeName = .default, initialAppearance: ThemeAppearance = .systemDefault) -> (ThemeManaging, AppearancePreferences, MockFeatureFlagger) {
        buildThemeManager(initialTheme: initialTheme.rawValue, initialAppearance: initialAppearance.rawValue)
    }

    func buildThemeManager(initialTheme: String, initialAppearance: String) -> (ThemeManaging, AppearancePreferences, MockFeatureFlagger) {
        let persistor = AppearancePreferencesPersistorMock(themeAppearance: initialAppearance, themeName: initialTheme)
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub["themes"] = true

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

// MARK: - Published.Publisher Private Testing Helpers
//
private extension Published.Publisher {

    /// Awaits until the `next` value is published
    ///
    func nextValue() async -> Output {
        await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?

            cancellable = dropFirst()
                .first()
                .sink { newValue in
                cancellable?.cancel()
                continuation.resume(returning: newValue)
            }
        }
    }
}
