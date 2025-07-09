//
//  AppearancePreferencesTests.swift
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

import Bookmarks
import PersistenceTestingUtils
import PixelKitTestingUtilities
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class AppearancePreferencesTests: XCTestCase {

    func testWhenInitializedThenItLoadsPersistedValues() throws {
        var model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(
                showFullURL: false,
                currentThemeName: ThemeName.systemDefault.rawValue,
                favoritesDisplayMode: FavoritesDisplayMode.displayNative(.desktop).description,
                isContinueSetUpVisible: true,
                isFavoriteVisible: true,
                isProtectionsReportVisible: true,
                homeButtonPosition: .left,
                homePageCustomBackground: CustomBackground.gradient(.gradient01).description,
                centerAlignedBookmarksBar: true,
                showTabsAndBookmarksBarOnFullScreen: false
            ),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger()
        )

        XCTAssertEqual(model.showFullURL, false)
        XCTAssertEqual(model.currentThemeName, ThemeName.systemDefault)
        XCTAssertEqual(model.favoritesDisplayMode, .displayNative(.desktop))
        XCTAssertEqual(model.isFavoriteVisible, true)
        XCTAssertEqual(model.isProtectionsReportVisible, true)
        XCTAssertEqual(model.isContinueSetUpVisible, true)
        XCTAssertEqual(model.homeButtonPosition, .left)
        XCTAssertEqual(model.homePageCustomBackground, .gradient(.gradient01))
        XCTAssertTrue(model.centerAlignedBookmarksBarBool)
        XCTAssertFalse(model.showTabsAndBookmarksBarOnFullScreen)

        model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(
                showFullURL: true,
                currentThemeName: ThemeName.light.rawValue,
                favoritesDisplayMode: FavoritesDisplayMode.displayUnified(native: .desktop).description,
                isContinueSetUpVisible: false,
                isFavoriteVisible: false,
                isProtectionsReportVisible: false,
                isSearchBarVisible: false,
                homeButtonPosition: .left,
                homePageCustomBackground: CustomBackground.gradient(.gradient05).description,
                centerAlignedBookmarksBar: false,
                showTabsAndBookmarksBarOnFullScreen: true
            ),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger()
        )
        XCTAssertEqual(model.showFullURL, true)
        XCTAssertEqual(model.currentThemeName, ThemeName.light)
        XCTAssertEqual(model.favoritesDisplayMode, .displayUnified(native: .desktop))
        XCTAssertEqual(model.isFavoriteVisible, false)
        XCTAssertEqual(model.isProtectionsReportVisible, false)
        XCTAssertEqual(model.isContinueSetUpVisible, false)
        XCTAssertEqual(model.homeButtonPosition, .left)
        XCTAssertEqual(model.homePageCustomBackground, .gradient(.gradient05))
        XCTAssertFalse(model.centerAlignedBookmarksBarBool)
        XCTAssertTrue(model.showTabsAndBookmarksBarOnFullScreen)
    }

    func testWhenInitializedWithGarbageThenThemeIsSetToSystemDefault() throws {
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(
                currentThemeName: "garbage"
            ),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger()
        )

        XCTAssertEqual(model.currentThemeName, ThemeName.systemDefault)
    }

    func testThemeNameReturnsCorrectAppearanceObject() throws {
        XCTAssertEqual(ThemeName.systemDefault.appearance, nil)
        XCTAssertEqual(ThemeName.light.appearance, NSAppearance(named: .aqua))
        XCTAssertEqual(ThemeName.dark.appearance, NSAppearance(named: .darkAqua))
    }

    func testWhenThemeNameIsUpdatedThenApplicationAppearanceIsUpdated() throws {
        let model = AppearancePreferences(persistor: AppearancePreferencesPersistorMock(), privacyConfigurationManager: MockPrivacyConfigurationManager(), featureFlagger: MockFeatureFlagger())

        model.currentThemeName = ThemeName.systemDefault
        XCTAssertEqual(NSApp.appearance?.name, ThemeName.systemDefault.appearance?.name)

        model.currentThemeName = ThemeName.light
        XCTAssertEqual(NSApp.appearance?.name, ThemeName.light.appearance?.name)

        model.currentThemeName = ThemeName.dark
        XCTAssertEqual(NSApp.appearance?.name, ThemeName.dark.appearance?.name)

        model.currentThemeName = ThemeName.systemDefault
        XCTAssertEqual(NSApp.appearance?.name, ThemeName.systemDefault.appearance?.name)
    }

    func testWhenNewTabPreferencesAreUpdatedThenPersistedValuesAreUpdated() throws {
        let model = AppearancePreferences(persistor: AppearancePreferencesPersistorMock(), privacyConfigurationManager: MockPrivacyConfigurationManager(), featureFlagger: MockFeatureFlagger())

        model.isFavoriteVisible = true
        XCTAssertEqual(model.isFavoriteVisible, true)
        model.isProtectionsReportVisible = true
        XCTAssertEqual(model.isProtectionsReportVisible, true)
        model.isContinueSetUpVisible = true
        XCTAssertEqual(model.isContinueSetUpVisible, true)

        model.isFavoriteVisible = false
        XCTAssertEqual(model.isFavoriteVisible, false)
        model.isProtectionsReportVisible = false
        XCTAssertEqual(model.isProtectionsReportVisible, false)
        model.isContinueSetUpVisible = false
        XCTAssertEqual(model.isContinueSetUpVisible, false)
    }

    func testPersisterReturnsValuesFromDisk() throws {
        UserDefaultsWrapper<Any>.clearAll()
        let keyValueStore = try MockKeyValueFileStore()
        var persister1 = AppearancePreferencesUserDefaultsPersistor(keyValueStore: keyValueStore)
        var persister2 = AppearancePreferencesUserDefaultsPersistor(keyValueStore: keyValueStore)

        persister2.isFavoriteVisible = false
        persister1.isFavoriteVisible = true
        persister2.isProtectionsReportVisible = false
        persister1.isProtectionsReportVisible = true
        persister2.isContinueSetUpVisible = false
        persister1.isContinueSetUpVisible = true

        XCTAssertTrue(persister2.isFavoriteVisible)
        XCTAssertTrue(persister2.isProtectionsReportVisible)
        XCTAssertTrue(persister2.isContinueSetUpVisible)
    }

    func testContinueSetUpIsNotDismissedAfterSeveralDemonstrationsWithinSeveralDays() {
        // 1. app installed and launched
        var now = Date()

        // listen to AppearancePreferences.objectWillChange
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            dateTimeProvider: { now },
            featureFlagger: MockFeatureFlagger()
        )
        let c = model.objectWillChange.sink {
            XCTFail("Unexpected model.objectWillChange")
        }
        func incrementDate() {
            now = Calendar.current.date(byAdding: .hour, value: 1, to: now)!
        }

        // check during N hours
        // eObjectWillChange shouldn‘t be called until N days
        for i in 0..<max(AppearancePreferences.Constants.dismissNextStepsCardsAfterDays, 48) {
            XCTAssertTrue(model.isContinueSetUpVisible, "\(i)")
            XCTAssertFalse(model.isContinueSetUpCardsViewOutdated, "\(i)")
            incrementDate()
        }

        withExtendedLifetime(c) {}
    }

    func testContinueSetUpIsDismissedAfterNDays() {
        // 1. app installed and launched
        var now = Date()

        // listen to AppearancePreferences.objectWillChange
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            dateTimeProvider: { now },
            featureFlagger: MockFeatureFlagger()
        )
        var eObjectWillChange: XCTestExpectation!
        let c = model.objectWillChange.sink {
            eObjectWillChange.fulfill()
        }
        func incrementDate() {
            now = Calendar.current.date(byAdding: .day, value: 5, to: now)!
        }

        // check during N days
        // eObjectWillChange shouldn‘t be called until N days
        for i in 0..<AppearancePreferences.Constants.dismissNextStepsCardsAfterDays {
            XCTAssertTrue(model.isContinueSetUpVisible, "\(i)")
            XCTAssertFalse(model.isContinueSetUpCardsViewOutdated, "\(i)")
            model.continueSetUpCardsViewDidAppear()
            incrementDate()
        }
        // N days passed
        // eObjectWillChange should be called once
        eObjectWillChange = expectation(description: "AppearancePreferences.objectWillChange called")
        incrementDate()
        model.continueSetUpCardsViewDidAppear()
        XCTAssertFalse(model.isContinueSetUpVisible, "dismissNextStepsCardsAfterDays")
        waitForExpectations(timeout: 1)

        // shouldn‘t change after being set once
        for i in (AppearancePreferences.Constants.dismissNextStepsCardsAfterDays + 1)..<(AppearancePreferences.Constants.dismissNextStepsCardsAfterDays + 20) {
            XCTAssertFalse(model.isContinueSetUpVisible, "\(i)")
            XCTAssertTrue(model.isContinueSetUpCardsViewOutdated, "\(i)")
            incrementDate()
            model.continueSetUpCardsViewDidAppear()
        }

        withExtendedLifetime(c) {}
    }

    // MARK: - Pixel firing tests

    func testWhenCurrentThemeIsUpdatedThenPixelIsFired() {
        let pixelFiringMock = PixelKitMock()
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            pixelFiring: pixelFiringMock,
            featureFlagger: MockFeatureFlagger()
        )

        model.currentThemeName = ThemeName.systemDefault
        model.currentThemeName = ThemeName.light
        model.currentThemeName = ThemeName.dark
        model.currentThemeName = ThemeName.systemDefault

        pixelFiringMock.expectedFireCalls = [
            .init(pixel: SettingsPixel.themeSettingChanged, frequency: .uniqueByName),
            .init(pixel: SettingsPixel.themeSettingChanged, frequency: .uniqueByName),
            .init(pixel: SettingsPixel.themeSettingChanged, frequency: .uniqueByName),
            .init(pixel: SettingsPixel.themeSettingChanged, frequency: .uniqueByName)
        ]

        pixelFiringMock.verifyExpectations()
    }

    func testWhenShowFullURLIsUpdatedThenPixelIsFired() {
        let pixelFiringMock = PixelKitMock()
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            pixelFiring: pixelFiringMock,
            featureFlagger: MockFeatureFlagger()
        )

        model.showFullURL = true
        model.showFullURL = false

        pixelFiringMock.expectedFireCalls = [
            .init(pixel: SettingsPixel.showFullURLSettingToggled, frequency: .uniqueByName),
            .init(pixel: SettingsPixel.showFullURLSettingToggled, frequency: .uniqueByName)
        ]

        pixelFiringMock.verifyExpectations()
    }

    func testWhenFavoritesSectionIsHiddenThenPixelIsFired() {
        let pixelFiringMock = PixelKitMock()
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            pixelFiring: pixelFiringMock,
            featureFlagger: MockFeatureFlagger()
        )

        model.isFavoriteVisible = false
        model.isFavoriteVisible = true
        model.isFavoriteVisible = true
        model.isFavoriteVisible = false
        model.isFavoriteVisible = true
        model.isFavoriteVisible = true
        model.isFavoriteVisible = true
        model.isFavoriteVisible = true
        model.isFavoriteVisible = false
        model.isFavoriteVisible = true
        model.isFavoriteVisible = true

        pixelFiringMock.expectedFireCalls = [
            .init(pixel: NewTabPagePixel.favoriteSectionHidden, frequency: .dailyAndStandard),
            .init(pixel: NewTabPagePixel.favoriteSectionHidden, frequency: .dailyAndStandard),
            .init(pixel: NewTabPagePixel.favoriteSectionHidden, frequency: .dailyAndStandard)
        ]

        pixelFiringMock.verifyExpectations()
    }

    func testWhenProtectionsReportSectionIsHiddenThenPixelIsFired() {
        let pixelFiringMock = PixelKitMock()
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            pixelFiring: pixelFiringMock,
            featureFlagger: MockFeatureFlagger()
        )

        model.isProtectionsReportVisible = false
        model.isProtectionsReportVisible = true
        model.isProtectionsReportVisible = true
        model.isProtectionsReportVisible = false
        model.isProtectionsReportVisible = true
        model.isProtectionsReportVisible = true
        model.isProtectionsReportVisible = true
        model.isProtectionsReportVisible = true
        model.isProtectionsReportVisible = false
        model.isProtectionsReportVisible = true
        model.isProtectionsReportVisible = true

        pixelFiringMock.expectedFireCalls = [
            .init(pixel: NewTabPagePixel.protectionsSectionHidden, frequency: .dailyAndStandard),
            .init(pixel: NewTabPagePixel.protectionsSectionHidden, frequency: .dailyAndStandard),
            .init(pixel: NewTabPagePixel.protectionsSectionHidden, frequency: .dailyAndStandard)
        ]

        pixelFiringMock.verifyExpectations()
    }

    func testWhenOmnibarFeatureFlagIsOnThenIsOmnibarAvailableIsTrue() {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.newTabPageOmnibar]

        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: featureFlagger
        )

        XCTAssertTrue(model.isOmnibarAvailable, "Omnibar should be available when feature flag is ON")
    }

    func testWhenOmnibarFeatureFlagIsOffThenIsOmnibarAvailableIsFalse() {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = []

        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: featureFlagger
        )

        XCTAssertFalse(model.isOmnibarAvailable, "Omnibar should NOT be available when feature flag is OFF")
    }

    func testWhenIsOmnibarVisibleIsUpdatedThenValueChanges() {
        let persistor = AppearancePreferencesPersistorMock(isOmnibarVisible: true)
        let model = AppearancePreferences(
            persistor: persistor,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger()
        )

        XCTAssertTrue(model.isOmnibarVisible, "Initial value should be true")

        model.isOmnibarVisible = false
        XCTAssertFalse(model.isOmnibarVisible, "Value should change to false")
    }
}
