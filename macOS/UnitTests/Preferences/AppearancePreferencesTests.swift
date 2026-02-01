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
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class AppearancePreferencesTests: XCTestCase {

    func testWhenInitializedThenItLoadsPersistedValues() throws {
        var model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(
                showFullURL: false,
                themeAppearance: ThemeAppearance.systemDefault.rawValue,
                themeName: ThemeName.default.rawValue,
                favoritesDisplayMode: FavoritesDisplayMode.displayNative(.desktop).description,
                isContinueSetUpVisible: true,
                isFavoriteVisible: true,
                isProtectionsReportVisible: true,
                homeButtonPosition: .left,
                homePageCustomBackground: CustomBackground.gradient(.gradient01).description,
                centerAlignedBookmarksBar: true,
                showTabsAndBookmarksBarOnFullScreen: false,
                didChangeAnyNewTabPageCustomizationSetting: false
            ),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )

        XCTAssertEqual(model.showFullURL, false)
        XCTAssertEqual(model.themeAppearance, ThemeAppearance.systemDefault)
        XCTAssertEqual(model.themeName, ThemeName.default)
        XCTAssertEqual(model.favoritesDisplayMode, .displayNative(.desktop))
        XCTAssertEqual(model.isFavoriteVisible, true)
        XCTAssertEqual(model.isProtectionsReportVisible, true)
        XCTAssertEqual(model.isContinueSetUpVisible, true)
        XCTAssertEqual(model.homeButtonPosition, .left)
        XCTAssertEqual(model.homePageCustomBackground, .gradient(.gradient01))
        XCTAssertTrue(model.centerAlignedBookmarksBarBool)
        XCTAssertFalse(model.showTabsAndBookmarksBarOnFullScreen)
        XCTAssertFalse(model.syncAppIconWithTheme)
        XCTAssertFalse(model.didChangeAnyNewTabPageCustomizationSetting)

        model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(
                showFullURL: true,
                themeAppearance: ThemeAppearance.light.rawValue,
                themeName: ThemeName.green.rawValue,
                favoritesDisplayMode: FavoritesDisplayMode.displayUnified(native: .desktop).description,
                isContinueSetUpVisible: false,
                isFavoriteVisible: false,
                isProtectionsReportVisible: false,
                isSearchBarVisible: false,
                homeButtonPosition: .left,
                homePageCustomBackground: CustomBackground.gradient(.gradient05).description,
                centerAlignedBookmarksBar: false,
                showTabsAndBookmarksBarOnFullScreen: true,
                syncAppIconWithTheme: true,
                didChangeAnyNewTabPageCustomizationSetting: true
            ),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )
        XCTAssertEqual(model.showFullURL, true)
        XCTAssertEqual(model.themeAppearance, ThemeAppearance.light)
        XCTAssertEqual(model.themeName, ThemeName.green)
        XCTAssertEqual(model.favoritesDisplayMode, .displayUnified(native: .desktop))
        XCTAssertEqual(model.isFavoriteVisible, false)
        XCTAssertEqual(model.isProtectionsReportVisible, false)
        XCTAssertEqual(model.isContinueSetUpVisible, false)
        XCTAssertEqual(model.homeButtonPosition, .left)
        XCTAssertEqual(model.homePageCustomBackground, .gradient(.gradient05))
        XCTAssertFalse(model.centerAlignedBookmarksBarBool)
        XCTAssertTrue(model.showTabsAndBookmarksBarOnFullScreen)
        XCTAssertTrue(model.syncAppIconWithTheme)
        XCTAssertTrue(model.didChangeAnyNewTabPageCustomizationSetting)
    }

    func testWhenInitializedWithGarbageThenThemeAppearanceIsSetToSystemDefault() throws {
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(
                themeAppearance: "garbage",
                themeName: "garbage"
            ),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )

        XCTAssertEqual(model.themeAppearance, ThemeAppearance.systemDefault)
        XCTAssertEqual(model.themeName, ThemeName.default)
    }

    func testWhenInitializedWithGarbageThenThemeNameIsSetToSystemDefault() throws {
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(
                themeName: "garbage"
            ),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )

        XCTAssertEqual(model.themeName, ThemeName.default)
    }

    func testThemeAppearanceReturnsCorrectAppearanceObject() throws {
        XCTAssertEqual(ThemeAppearance.systemDefault.appearance, nil)
        XCTAssertEqual(ThemeAppearance.light.appearance, NSAppearance(named: .aqua))
        XCTAssertEqual(ThemeAppearance.dark.appearance, NSAppearance(named: .darkAqua))
    }

    func testWhenThemeAppearanceIsUpdatedThenApplicationAppearanceIsUpdated() throws {
        let model = AppearancePreferences(persistor: AppearancePreferencesPersistorMock(), privacyConfigurationManager: MockPrivacyConfigurationManager(), featureFlagger: MockFeatureFlagger(), aiChatMenuConfig: MockAIChatConfig())

        model.themeAppearance = ThemeAppearance.systemDefault
        XCTAssertEqual(NSApp.appearance?.name, ThemeAppearance.systemDefault.appearance?.name)

        model.themeAppearance = ThemeAppearance.light
        XCTAssertEqual(NSApp.appearance?.name, ThemeAppearance.light.appearance?.name)

        model.themeAppearance = ThemeAppearance.dark
        XCTAssertEqual(NSApp.appearance?.name, ThemeAppearance.dark.appearance?.name)

        model.themeAppearance = ThemeAppearance.systemDefault
        XCTAssertEqual(NSApp.appearance?.name, ThemeAppearance.systemDefault.appearance?.name)
    }

    func testWhenNewTabPreferencesAreUpdatedThenPersistedValuesAreUpdated() throws {
        let model = AppearancePreferences(persistor: AppearancePreferencesPersistorMock(), privacyConfigurationManager: MockPrivacyConfigurationManager(), featureFlagger: MockFeatureFlagger(), aiChatMenuConfig: MockAIChatConfig())

        model.isFavoriteVisible = true
        XCTAssertEqual(model.isFavoriteVisible, true)
        model.isProtectionsReportVisible = true
        XCTAssertEqual(model.isProtectionsReportVisible, true)
        model.isContinueSetUpVisible = true
        XCTAssertEqual(model.isContinueSetUpVisible, true)
        model.syncAppIconWithTheme = true
        XCTAssertEqual(model.syncAppIconWithTheme, true)

        model.isFavoriteVisible = false
        XCTAssertEqual(model.isFavoriteVisible, false)
        model.isProtectionsReportVisible = false
        XCTAssertEqual(model.isProtectionsReportVisible, false)
        model.isContinueSetUpVisible = false
        XCTAssertEqual(model.isContinueSetUpVisible, false)
        model.syncAppIconWithTheme = false
        XCTAssertEqual(model.syncAppIconWithTheme, false)
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
        persister2.syncAppIconWithTheme = false
        persister1.syncAppIconWithTheme = true

        XCTAssertTrue(persister2.isFavoriteVisible)
        XCTAssertTrue(persister2.isProtectionsReportVisible)
        XCTAssertTrue(persister2.isContinueSetUpVisible)
        XCTAssertTrue(persister2.syncAppIconWithTheme)
    }

    func testMaxNextStepsCardsDemonstrationDaysUpdatesWhenFeatureFlagIsUpdated() {
        let featureFlagger = MockFeatureFlagger()
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: featureFlagger,
            aiChatMenuConfig: MockAIChatConfig()
        )

        XCTAssertEqual(model.maxNextStepsCardsDemonstrationDays, 9)

        featureFlagger.enabledFeatureFlags = [.nextStepsListWidget]

        XCTAssertEqual(model.maxNextStepsCardsDemonstrationDays, 14)
    }

    func testWhenNextStepsCardsDemonstrationDaysIsAccessedThenReturnsPersistorValue() {
        let persistor = AppearancePreferencesPersistorMock()
        persistor.continueSetUpCardsNumberOfDaysDemonstrated = 5
        let model = AppearancePreferences(
            persistor: persistor,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )

        XCTAssertEqual(model.nextStepsCardsDemonstrationDays, 5)
    }

    func testContinueSetUpIsNotDismissedAfterSeveralDemonstrationsWithinSeveralDays() {
        // 1. app installed and launched
        var now = Date()

        // listen to AppearancePreferences.objectWillChange
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            dateTimeProvider: { now },
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )
        let c = model.objectWillChange.sink {
            XCTFail("Unexpected model.objectWillChange")
        }
        func incrementDate() {
            now = Calendar.current.date(byAdding: .hour, value: 1, to: now)!
        }

        // check during N hours
        // eObjectWillChange shouldn‘t be called until N days
        for i in 0..<max(model.maxNextStepsCardsDemonstrationDays, 48) {
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
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
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
        for i in 0..<model.maxNextStepsCardsDemonstrationDays {
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
        waitForExpectations(timeout: 5)

        // shouldn‘t change after being set once
        for i in (model.maxNextStepsCardsDemonstrationDays + 1)..<(model.maxNextStepsCardsDemonstrationDays + 20) {
            XCTAssertFalse(model.isContinueSetUpVisible, "\(i)")
            XCTAssertTrue(model.isContinueSetUpCardsViewOutdated, "\(i)")
            incrementDate()
            model.continueSetUpCardsViewDidAppear()
        }

        withExtendedLifetime(c) {}
    }

    func testWhenCurrentThemeIsUpdatedThenDidChangeAnyNewTabPageCustomizationSettingIsTrue() {
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(themeName: ThemeName.default.rawValue,
                                                          didChangeAnyNewTabPageCustomizationSetting: false),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )

        let expectation = XCTestExpectation(description: "Register change to New Tab Page customization setting")
        let cancellable = model.$didChangeAnyNewTabPageCustomizationSetting
            .sink { didChange in
                guard didChange else { return }
                expectation.fulfill()
            }

        XCTAssertFalse(model.didChangeAnyNewTabPageCustomizationSetting)

        model.themeName = ThemeName.green

        wait(for: [expectation], timeout: 5)
        cancellable.cancel()

        XCTAssertTrue(model.didChangeAnyNewTabPageCustomizationSetting)
    }

    func testWhenThemeAppearanceIsUpdatedThenDidChangeAnyNewTabPageCustomizationSettingIsTrue() {
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(themeAppearance: ThemeAppearance.light.rawValue,
                                                          didChangeAnyNewTabPageCustomizationSetting: false),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )

        let expectation = XCTestExpectation(description: "Register change to New Tab Page customization setting")
        let cancellable = model.$didChangeAnyNewTabPageCustomizationSetting
            .sink { didChange in
                guard didChange else { return }
                expectation.fulfill()
            }

        XCTAssertFalse(model.didChangeAnyNewTabPageCustomizationSetting)

        model.themeAppearance = .dark

        wait(for: [expectation], timeout: 5)
        cancellable.cancel()

        XCTAssertTrue(model.didChangeAnyNewTabPageCustomizationSetting)
    }

    func testWhenCustomBackgroundIsUpdatedThenDidChangeAnyNewTabPageCustomizationSettingIsTrue() {
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(homePageCustomBackground: nil,
                                                          didChangeAnyNewTabPageCustomizationSetting: false),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )

        let expectation = XCTestExpectation(description: "Register change to New Tab Page customization setting")
        let cancellable = model.$didChangeAnyNewTabPageCustomizationSetting
            .sink { didChange in
                guard didChange else { return }
                expectation.fulfill()
            }

        XCTAssertFalse(model.didChangeAnyNewTabPageCustomizationSetting)

        model.homePageCustomBackground = CustomBackground.gradient(.gradient01)

        wait(for: [expectation], timeout: 5)
        cancellable.cancel()

        XCTAssertTrue(model.didChangeAnyNewTabPageCustomizationSetting)
    }

    func testWhenOmnibarVisibilityIsUpdatedThenDidChangeAnyNewTabPageCustomizationSettingIsTrue() {
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(isOmnibarVisible: true,
                                                          didChangeAnyNewTabPageCustomizationSetting: false),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )

        let expectation = XCTestExpectation(description: "Register change to New Tab Page customization setting")
        let cancellable = model.$didChangeAnyNewTabPageCustomizationSetting
            .sink { didChange in
                guard didChange else { return }
                expectation.fulfill()
            }

        XCTAssertFalse(model.didChangeAnyNewTabPageCustomizationSetting)

        model.isOmnibarVisible = false

        wait(for: [expectation], timeout: 5)
        cancellable.cancel()

        XCTAssertTrue(model.didChangeAnyNewTabPageCustomizationSetting)
    }

    func testWhenFavoritesVisibilityIsUpdatedThenDidChangeAnyNewTabPageCustomizationSettingIsTrue() {
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(isFavoriteVisible: true,
                                                          didChangeAnyNewTabPageCustomizationSetting: false),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )

        let expectation = XCTestExpectation(description: "Register change to New Tab Page customization setting")
        let cancellable = model.$didChangeAnyNewTabPageCustomizationSetting
            .sink { didChange in
                guard didChange else { return }
                expectation.fulfill()
            }

        XCTAssertFalse(model.didChangeAnyNewTabPageCustomizationSetting)

        model.isFavoriteVisible = false

        wait(for: [expectation], timeout: 5)
        cancellable.cancel()

        XCTAssertTrue(model.didChangeAnyNewTabPageCustomizationSetting)
    }

    func testWhenProtectionsReportVisibilityIsUpdatedThenDidChangeAnyNewTabPageCustomizationSettingIsTrue() {
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(isProtectionsReportVisible: true,
                                                          didChangeAnyNewTabPageCustomizationSetting: false),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )

        let expectation = XCTestExpectation(description: "Register change to New Tab Page customization setting")
        let cancellable = model.$didChangeAnyNewTabPageCustomizationSetting
            .sink { didChange in
                guard didChange else { return }
                expectation.fulfill()
            }

        XCTAssertFalse(model.didChangeAnyNewTabPageCustomizationSetting)

        model.isProtectionsReportVisible = false

        wait(for: [expectation], timeout: 5)
        cancellable.cancel()

        XCTAssertTrue(model.didChangeAnyNewTabPageCustomizationSetting)
    }

    func testWhenAIChatShortcutEnabledIsUpdatedThenDidChangeAnyNewTabPageCustomizationSettingIsTrue() {
        let mockAIChatConfig = MockAIChatConfig()
        mockAIChatConfig.shouldDisplayNewTabPageShortcut = true
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(didChangeAnyNewTabPageCustomizationSetting: false),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: mockAIChatConfig
        )

        let expectation = XCTestExpectation(description: "Register change to New Tab Page customization setting")
        let cancellable = model.$didChangeAnyNewTabPageCustomizationSetting
            .sink { didChange in
                guard didChange else { return }
                expectation.fulfill()
            }

        XCTAssertFalse(model.didChangeAnyNewTabPageCustomizationSetting)

        mockAIChatConfig.shouldDisplayNewTabPageShortcut = false
        mockAIChatConfig.valuesChangedPublisher.send()

        wait(for: [expectation], timeout: 5)
        cancellable.cancel()

        XCTAssertTrue(model.didChangeAnyNewTabPageCustomizationSetting)
    }

    // MARK: - Pixel firing tests

    func testWhenCurrentThemeIsUpdatedThenNoPixelIsFiredFromModel() {
        // Pixel firing has been moved to the call sites (Settings view and NTP customizer)
        // to track the source of the change. The model itself no longer fires pixels.
        let pixelFiringMock = PixelKitMock()
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            pixelFiring: pixelFiringMock,
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )

        model.themeAppearance = ThemeAppearance.systemDefault
        model.themeAppearance = ThemeAppearance.light
        model.themeAppearance = ThemeAppearance.dark
        model.themeAppearance = ThemeAppearance.systemDefault

        model.themeName = ThemeName.default
        model.themeName = ThemeName.green

        // No pixel should be fired from the model - pixels are fired at call sites
        pixelFiringMock.expectedFireCalls = []

        pixelFiringMock.verifyExpectations()
    }

    func testWhenShowFullURLIsUpdatedThenPixelIsFired() {
        let pixelFiringMock = PixelKitMock()
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            pixelFiring: pixelFiringMock,
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )

        model.showFullURL = true
        model.showFullURL = false

        pixelFiringMock.expectedFireCalls = [
            .init(pixel: SettingsPixel.showFullURLSettingToggled, frequency: .uniqueByName),
            .init(pixel: SettingsPixel.showFullURLSettingToggled, frequency: .uniqueByName)
        ]

        pixelFiringMock.verifyExpectations()
    }

    func testWhenSyncAppIconWithThemeIsUpdatedThenPixelIsFired() {
        let pixelFiringMock = PixelKitMock()
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            pixelFiring: pixelFiringMock,
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )

        model.syncAppIconWithTheme = true
        model.syncAppIconWithTheme = false

        pixelFiringMock.expectedFireCalls = [
            .init(pixel: SettingsPixel.syncAppIconWithThemeTurnedOn, frequency: .dailyAndCount),
            .init(pixel: SettingsPixel.syncAppIconWithThemeTurnedOff, frequency: .dailyAndCount)
        ]

        pixelFiringMock.verifyExpectations()
    }

    func testWhenFavoritesSectionIsHiddenThenPixelIsFired() {
        let pixelFiringMock = PixelKitMock()
        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            pixelFiring: pixelFiringMock,
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
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
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
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
            featureFlagger: featureFlagger,
            aiChatMenuConfig: MockAIChatConfig()
        )

        XCTAssertTrue(model.isOmnibarAvailable, "Omnibar should be available when feature flag is ON")
    }

    func testWhenOmnibarFeatureFlagIsOffThenIsOmnibarAvailableIsFalse() {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = []

        let model = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: featureFlagger,
            aiChatMenuConfig: MockAIChatConfig()
        )

        XCTAssertFalse(model.isOmnibarAvailable, "Omnibar should NOT be available when feature flag is OFF")
    }

    func testWhenIsOmnibarVisibleIsUpdatedThenValueChanges() {
        let persistor = AppearancePreferencesPersistorMock(isOmnibarVisible: true)
        let model = AppearancePreferences(
            persistor: persistor,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )

        XCTAssertTrue(model.isOmnibarVisible, "Initial value should be true")

        model.isOmnibarVisible = false
        XCTAssertFalse(model.isOmnibarVisible, "Value should change to false")
    }
}
