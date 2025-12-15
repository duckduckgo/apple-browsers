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
import BrowserServicesKit
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class ThemeManagerTests: XCTestCase {

    func testInitializationEffectivelyPicksLatestPersistedThemeName() {
        let persistor = AppearancePreferencesPersistorMock(themeName: ThemeName.green.rawValue)
        let featureFlagger = MockFeatureFlagger()
        let preferences = AppearancePreferences(
            persistor: persistor,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: featureFlagger
        )
        let internalUserDecider = MockInternalUserDecider()

        let manager = ThemeManager(appearancePreferences: preferences, internalUserDecider: internalUserDecider, featureFlagger: featureFlagger)
        XCTAssertEqual(manager.theme.name, .green)
    }

    func testThemeManagerRefreshesActiveThemeWhenAppearancePreferencesMutate() {
        let persistor = AppearancePreferencesPersistorMock(themeName: ThemeName.default.rawValue)
        let featureFlagger = MockFeatureFlagger()
        let preferences = AppearancePreferences(
            persistor: persistor,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: featureFlagger
        )

        preferences.themeName = .orange
        let internalUserDecider = MockInternalUserDecider()

        let manager = ThemeManager(appearancePreferences: preferences, internalUserDecider: internalUserDecider, featureFlagger: featureFlagger)
        XCTAssertEqual(manager.theme.name, .orange)
    }

    func testInternalUsersWithFigmaThemeSetAreRemappedToDefaultTheme() {
        let persistor = AppearancePreferencesPersistorMock(themeName: "figma")
        let featureFlagger = MockFeatureFlagger()
        let preferences = AppearancePreferences(
            persistor: persistor,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: featureFlagger
        )

        let internalUserDecider = MockInternalUserDecider(isInternalUser: true)
        let manager = ThemeManager(appearancePreferences: preferences, internalUserDecider: internalUserDecider, featureFlagger: featureFlagger)

        XCTAssertEqual(manager.theme.name, .default)
    }

    func testLoosingInternalUserStateSetsTheLegacyTheme() async {
        let persistor = AppearancePreferencesPersistorMock(themeName: ThemeName.green.rawValue)
        let featureFlagger = MockFeatureFlagger()
        let preferences = AppearancePreferences(
            persistor: persistor,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: featureFlagger
        )

        let internalUserDecider = MockInternalUserDecider(isInternalUser: true)
        let manager = ThemeManager(appearancePreferences: preferences, internalUserDecider: internalUserDecider, featureFlagger: featureFlagger)

        internalUserDecider.isInternalUserSubject.send(false)

        let updatedTheme = await manager.$theme.nextValue()
        XCTAssertEqual(updatedTheme.name, .default)
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
