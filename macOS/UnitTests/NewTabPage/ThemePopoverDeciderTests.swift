//
//  ThemePopoverDeciderTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class ThemePopoverDeciderTests: XCTestCase {

    func testWhenThemesFeatureFlagDisabledThenShouldShowPopoverIsFalse() {
        let (decider, _, _) = buildThemePopoverDecider(initialTheme: .default, themePopoverShown: false, firstLaunchElapsedDays: 3)

        XCTAssertFalse(decider.shouldShowPopover)
    }

    func testWhenPopoverAlreadyShownThenShouldShowPopoverIsFalse() {
        let (decider, _, featureFlagger) = buildThemePopoverDecider(initialTheme: .default, themePopoverShown: true, firstLaunchElapsedDays: 3)
        featureFlagger.enabledFeatureFlags = [.themes]

        XCTAssertFalse(decider.shouldShowPopover)
    }

    func testWhenThemeIsNotDefaultThenShouldShowPopoverIsFalse() {
        let (decider, _, featureFlagger) = buildThemePopoverDecider(initialTheme: .violet, themePopoverShown: false, firstLaunchElapsedDays: 3)
        featureFlagger.enabledFeatureFlags = [.themes]

        XCTAssertFalse(decider.shouldShowPopover)
    }

    func testWhenLessThanTwoDaysSinceFirstLaunchThenShouldShowPopoverIsFalse() {
        for daysAgo in [0, 1] {
            let (decider, _, featureFlagger) = buildThemePopoverDecider(initialTheme: .default, themePopoverShown: false, firstLaunchElapsedDays: UInt(daysAgo))
            featureFlagger.enabledFeatureFlags = [.themes]

            XCTAssertFalse(decider.shouldShowPopover)
        }
    }
}

// MARK: - Helpers

private extension ThemePopoverDeciderTests {

    func buildThemePopoverDecider(initialTheme: ThemeName, themePopoverShown: Bool, firstLaunchElapsedDays: UInt) -> (ThemePopoverDeciding, ThemePopoverPersistor, MockFeatureFlagger) {
        let featureFlagger = MockFeatureFlagger()
        let firstLaunchDate = buildDate(daysAgo: firstLaunchElapsedDays)

        let appearancePersistor = MockAppearancePreferencesPersistor(themeName: initialTheme.rawValue)
        let appearancePreferences = AppearancePreferences(
            persistor: appearancePersistor,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: featureFlagger
        )

        let popoverPersistor = MockThemePopoverPersistor(themePopoverShown: themePopoverShown)
        let popoverDecider = ThemePopoverDecider(appearancePreferences: appearancePreferences, featureFlagger: featureFlagger, firstLaunchDate: firstLaunchDate, persistor: popoverPersistor)

        return (popoverDecider, popoverPersistor, featureFlagger)
    }

    func buildDate(daysAgo: UInt) -> Date {
        Date().addingTimeInterval(-1 * Double(daysAgo) * 24 * 60 * 60)
    }
}

// MARK: - MockThemePopoverPersistor

final class MockThemePopoverPersistor: ThemePopoverPersistor {
    var themePopoverShown: Bool

    init(themePopoverShown: Bool = false) {
        self.themePopoverShown = themePopoverShown
    }
}

// MARK: - MockThemePopoverDecider

struct MockThemePopoverDecider: ThemePopoverDeciding {
    var shouldShowPopover: Bool

    init(shouldShowPopover: Bool = false) {
        self.shouldShowPopover = shouldShowPopover
    }

    func markPopoverShown() {
        // No-op for mock
    }
}
