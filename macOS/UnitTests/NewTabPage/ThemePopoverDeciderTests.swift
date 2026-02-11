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

    func testWhenAllConditionsMetThenShouldShowPopoverIsTrue() {
        let (decider, _, featureFlagger) = buildThemePopoverDecider(initialTheme: .default, themePopoverDismissed: false, firstLaunchElapsedDays: 3)
        featureFlagger.enabledFeatureFlags = [.themes]

        XCTAssertTrue(decider.shouldShowPopover)
    }

    func testWhenThemesFeatureFlagDisabledThenShouldShowPopoverIsFalse() {
        let (decider, _, _) = buildThemePopoverDecider(initialTheme: .default, themePopoverDismissed: false, firstLaunchElapsedDays: 3)

        XCTAssertFalse(decider.shouldShowPopover)
    }

    func testWhenPopoverAlreadyShownThenShouldShowPopoverIsFalse() {
        let (decider, _, featureFlagger) = buildThemePopoverDecider(initialTheme: .default, themePopoverDismissed: true, firstLaunchElapsedDays: 3)
        featureFlagger.enabledFeatureFlags = [.themes]

        XCTAssertFalse(decider.shouldShowPopover)
    }

    func testWhenThemeIsNotDefaultThenShouldShowPopoverIsFalse() {
        let (decider, _, featureFlagger) = buildThemePopoverDecider(initialTheme: .violet, themePopoverDismissed: false, firstLaunchElapsedDays: 3)
        featureFlagger.enabledFeatureFlags = [.themes]

        XCTAssertFalse(decider.shouldShowPopover)
    }

    func testWhenLessThanTwoDaysSinceFirstLaunchThenShouldShowPopoverIsFalse() {
        for daysAgo in [0, 1] {
            let (decider, _, featureFlagger) = buildThemePopoverDecider(initialTheme: .default, themePopoverDismissed: false, firstLaunchElapsedDays: UInt(daysAgo))
            featureFlagger.enabledFeatureFlags = [.themes]

            XCTAssertFalse(decider.shouldShowPopover)
        }
    }

    func testMarkPopoverDismissedWhenShouldShowPopoverThenSetsThemePopoverDismissedPersistorFlag() {
        let (decider, persistor, featureFlagger) = buildThemePopoverDecider(initialTheme: .default, themePopoverDismissed: false, firstLaunchElapsedDays: 3)
        featureFlagger.enabledFeatureFlags = [.themes]

        decider.markPopoverDismissed()

        XCTAssertTrue(persistor.themePopoverDismissed)
    }
}

// MARK: - Helpers

private extension ThemePopoverDeciderTests {

    func buildThemePopoverDecider(initialTheme: ThemeName, themePopoverDismissed: Bool, firstLaunchElapsedDays: UInt) -> (ThemePopoverDeciding, ThemePopoverPersistor, MockFeatureFlagger) {
        let featureFlagger = MockFeatureFlagger()
        let firstLaunchDate = buildDate(daysAgo: firstLaunchElapsedDays)

        let appearancePersistor = MockAppearancePreferencesPersistor(themeName: initialTheme.rawValue)
        let appearancePreferences = AppearancePreferences(
            persistor: appearancePersistor,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: featureFlagger,
            aiChatMenuConfig: MockAIChatConfig()
        )

        let popoverPersistor = MockThemePopoverPersistor(themePopoverDismissed: themePopoverDismissed)
        let popoverDecider = ThemePopoverDecider(appearancePreferences: appearancePreferences, featureFlagger: featureFlagger, firstLaunchDate: firstLaunchDate, persistor: popoverPersistor)

        return (popoverDecider, popoverPersistor, featureFlagger)
    }

    func buildDate(daysAgo: UInt) -> Date {
        Date().addingTimeInterval(-1 * Double(daysAgo) * 24 * 60 * 60)
    }
}

// MARK: - MockThemePopoverPersistor

final class MockThemePopoverPersistor: ThemePopoverPersistor {
    var themePopoverDismissed: Bool

    init(themePopoverDismissed: Bool = false) {
        self.themePopoverDismissed = themePopoverDismissed
    }
}

// MARK: - MockThemePopoverDecider

struct MockThemePopoverDecider: ThemePopoverDeciding {
    var shouldShowPopover: Bool

    init(shouldShowPopover: Bool = false) {
        self.shouldShowPopover = shouldShowPopover
    }

    func markPopoverDismissed() {
        // No-op for mock
    }

    func shouldDismissPopover(newTabPageDidAppearCount: Int) -> Bool {
        false
    }
}
