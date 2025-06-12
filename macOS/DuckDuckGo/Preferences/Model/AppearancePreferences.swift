//
//  AppearancePreferences.swift
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

import AppKit
import Bookmarks
import BrowserServicesKit
import Common
import FeatureFlags
import Foundation
import NewTabPage
import Persistence
import PixelKit
import os.log

protocol AppearancePreferencesPersistor {
    var showFullURL: Bool { get set }
    var currentThemeName: String { get set }
    var favoritesDisplayMode: String? { get set }
    var isSearchVisible: Bool { get set }
    var isFavoriteVisible: Bool { get set }
    var isProtectionsReportVisible: Bool { get set }
    var isContinueSetUpVisible: Bool { get set }
    var continueSetUpCardsLastDemonstrated: Date? { get set }
    var continueSetUpCardsNumberOfDaysDemonstrated: Int { get set }
    var continueSetUpCardsClosed: Bool { get set }
    var showBookmarksBar: Bool { get set }
    var bookmarksBarAppearance: BookmarksBarAppearance { get set }
    var homeButtonPosition: HomeButtonPosition { get set }
    var homePageCustomBackground: String? { get set }
    var centerAlignedBookmarksBar: Bool { get set }
    var showTabsAndBookmarksBarOnFullScreen: Bool { get set }
}

struct AppearancePreferencesUserDefaultsPersistor: AppearancePreferencesPersistor {

    enum Key: String {
        case newTabPageIsProtectionsReportVisible = "new-tab-page.protections-report.is-visible"
        case newTabPageIsSearchVisible = "new-tab-page.search.is-visible"
    }

    var isProtectionsReportVisible: Bool {
        get {
            guard let value = try? keyValueStore.object(forKey: Key.newTabPageIsProtectionsReportVisible.rawValue) as? Bool else {
                // Retrieve the initial value from pre-Protections-Report settings.
                let initialValue = NewTabPageProtectionsReportSettingsMigrator(legacyKeyValueStore: legacyKeyValueStore).isProtectionsReportVisible
                try? keyValueStore.set(initialValue, forKey: Key.newTabPageIsProtectionsReportVisible.rawValue)
                return initialValue
            }
            return value
        }
        set { try? keyValueStore.set(newValue, forKey: Key.newTabPageIsProtectionsReportVisible.rawValue) }
    }

    var isSearchVisible: Bool {
        get { (try? keyValueStore.object(forKey: Key.newTabPageIsSearchVisible.rawValue) as? Bool) ?? true }
        set { try? keyValueStore.set(newValue, forKey: Key.newTabPageIsSearchVisible.rawValue) }
    }

    @UserDefaultsWrapper(key: .showFullURL, defaultValue: false)
    var showFullURL: Bool

    @UserDefaultsWrapper(key: .currentThemeName, defaultValue: ThemeName.systemDefault.rawValue)
    var currentThemeName: String

    @UserDefaultsWrapper(key: .favoritesDisplayMode, defaultValue: FavoritesDisplayMode.displayNative(.desktop).description)
    var favoritesDisplayMode: String?

    @UserDefaultsWrapper(key: .homePageIsFavoriteVisible, defaultValue: true)
    var isFavoriteVisible: Bool

    @UserDefaultsWrapper(key: .homePageIsContinueSetupVisible, defaultValue: true)
    var isContinueSetUpVisible: Bool

    @UserDefaultsWrapper(key: .continueSetUpCardsLastDemonstrated)
    var continueSetUpCardsLastDemonstrated: Date?

    @UserDefaultsWrapper(key: .continueSetUpCardsNumberOfDaysDemonstrated, defaultValue: 0)
    var continueSetUpCardsNumberOfDaysDemonstrated: Int

    @UserDefaultsWrapper(key: .continueSetUpCardsClosed, defaultValue: false)
    var continueSetUpCardsClosed: Bool

    @UserDefaultsWrapper(key: .showBookmarksBar, defaultValue: false)
    var showBookmarksBar: Bool

    @UserDefaultsWrapper(key: .bookmarksBarAppearance, defaultValue: BookmarksBarAppearance.alwaysOn.rawValue)
    private var bookmarksBarValue: String
    var bookmarksBarAppearance: BookmarksBarAppearance {
        get {
            return BookmarksBarAppearance(rawValue: bookmarksBarValue) ?? .alwaysOn
        }

        set {
            bookmarksBarValue = newValue.rawValue
        }
    }

    @UserDefaultsWrapper(key: .homeButtonPosition, defaultValue: .right)
    var homeButtonPosition: HomeButtonPosition

    @UserDefaultsWrapper(key: .homePageCustomBackground, defaultValue: nil)
    var homePageCustomBackground: String?

    @UserDefaultsWrapper(key: .centerAlignedBookmarksBar, defaultValue: true)
    var centerAlignedBookmarksBar: Bool

    @UserDefaultsWrapper(key: .showTabsAndBookmarksBarOnFullScreen, defaultValue: true)
    var showTabsAndBookmarksBarOnFullScreen: Bool

    /**
     * Initializes Appearance Preferences persistor.
     *
     * - Parameters:
     *   - keyValueStore: An instance of `ThrowingKeyValueStoring` that is supposed to hold all newly added preferences.
     *   - legacyKeyValueStore: An instance of `KeyValueStoring` (wrapper for `UserDefaults`) that can be used for migrating existing
     *                          preferences to the new store.
     *
     *  `keyValueStore` is an opt-in mechanism, in that all pre-existing properties of the persistor (especially those using `@UserDefaultsWrapper`)
     *  continue using `legacyKeyValueStore` (a.k.a. `UserDefaults`) and only new properties should use `keyValueStore` by default
     *  (see `isProtectionsReportVisible`).
     */
    init(keyValueStore: ThrowingKeyValueStoring, legacyKeyValueStore: KeyValueStoring = UserDefaultsWrapper<Any>.sharedDefaults) {
        self.keyValueStore = keyValueStore
        self.legacyKeyValueStore = legacyKeyValueStore
    }

    private let keyValueStore: ThrowingKeyValueStoring
    private let legacyKeyValueStore: KeyValueStoring
}

protocol NewTabPageNavigator {
    func openNewTabPageBackgroundCustomizationSettings()
}

final class DefaultNewTabPageNavigator: NewTabPageNavigator {
    func openNewTabPageBackgroundCustomizationSettings() {
        Task { @MainActor in
            Application.appDelegate.windowControllersManager.showTab(with: .newtab)
            try? await Task.sleep(interval: 0.2)
            if let window = Application.appDelegate.windowControllersManager.lastKeyMainWindowController {
                let newTabPageViewModel = window.mainViewController.browserTabViewController.newTabPageWebViewModel
                NSApp.delegateTyped.newTabPageCustomizationModel.customizerOpener.openSettings(for: newTabPageViewModel.webView)
            }
        }
    }
}

enum HomeButtonPosition: String, CaseIterable {
    case hidden
    case left
    case right
}

enum ThemeName: String, Equatable, CaseIterable {
    case light
    case dark
    case systemDefault

    var appearance: NSAppearance? {
        switch self {
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        default:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .light:
            return UserText.themeLight
        case .dark:
            return UserText.themeDark
        case .systemDefault:
            return UserText.themeSystem
        }
    }

    var imageName: String {
        switch self {
        case .light:
            return "LightModePreview"
        case .dark:
            return "DarkModePreview"
        case .systemDefault:
            return "SystemDefaultPreview"
        }
    }
}

extension FavoritesDisplayMode: @retroactive LosslessStringConvertible {
    static let `default` = FavoritesDisplayMode.displayNative(.desktop)

    public init?(_ description: String) {
        switch description {
        case FavoritesDisplayMode.displayNative(.desktop).description:
            self = .displayNative(.desktop)
        case FavoritesDisplayMode.displayUnified(native: .desktop).description:
            self = .displayUnified(native: .desktop)
        default:
            return nil
        }
    }
}

final class AppearancePreferences: ObservableObject {

    struct Notifications {
        static let showBookmarksBarSettingChanged = NSNotification.Name("ShowBookmarksBarSettingChanged")
        static let bookmarksBarSettingAppearanceChanged = NSNotification.Name("BookmarksBarSettingAppearanceChanged")
        static let bookmarksBarAlignmentChanged = NSNotification.Name("BookmarksBarAlignmentChanged")
        static let showTabsAndBookmarksBarOnFullScreenChanged = NSNotification.Name("ShowTabsAndBookmarksBarOnFullScreenChanged")
    }

    struct Constants {
        static let bookmarksBarAlignmentChangedIsCenterAlignedParameter = "isCenterAligned"
        static let showTabsAndBookmarksBarOnFullScreenParameter = "showTabsAndBookmarksBarOnFullScreen"
        static let dismissNextStepsCardsAfterDays = 9
    }

    @Published var currentThemeName: ThemeName {
        didSet {
            persistor.currentThemeName = currentThemeName.rawValue
            updateUserInterfaceStyle()
            pixelFiring?.fire(SettingsPixel.themeSettingChanged, frequency: .uniqueByName)
        }
    }

    @Published var showFullURL: Bool {
        didSet {
            persistor.showFullURL = showFullURL
            pixelFiring?.fire(SettingsPixel.showFullURLSettingToggled, frequency: .uniqueByName)
        }
    }

    @Published var favoritesDisplayMode: FavoritesDisplayMode {
        didSet {
            persistor.favoritesDisplayMode = favoritesDisplayMode.description
        }
    }

    @Published var isSearchVisible: Bool {
        didSet {
            persistor.isSearchVisible = isSearchVisible
        }
    }

    @Published var isFavoriteVisible: Bool {
        didSet {
            persistor.isFavoriteVisible = isFavoriteVisible
            if !isFavoriteVisible {
                pixelFiring?.fire(NewTabPagePixel.favoriteSectionHidden, frequency: .dailyAndStandard)
            }
        }
    }

    @Published var isContinueSetUpCardsViewOutdated: Bool

    @Published var continueSetUpCardsClosed: Bool {
        didSet {
            persistor.continueSetUpCardsClosed = continueSetUpCardsClosed
        }
    }

    var isContinueSetUpVisible: Bool {
        get {
            return persistor.isContinueSetUpVisible && !persistor.continueSetUpCardsClosed && !isContinueSetUpCardsViewOutdated
        }
        set {
            persistor.isContinueSetUpVisible = newValue
            // Temporary Pixel
            if !isContinueSetUpVisible {
                pixelFiring?.fire(GeneralPixel.continueSetUpSectionHidden)
            }
            self.objectWillChange.send()
        }
    }

    func continueSetUpCardsViewDidAppear() {
        guard isContinueSetUpVisible, !isContinueSetUpCardsViewOutdated else { return }

        if let continueSetUpCardsLastDemonstrated = persistor.continueSetUpCardsLastDemonstrated {
            // how many days has passed since last Continue Setup demonstration
            let daysSinceLastDemonstration = Calendar.current.dateComponents([.day], from: continueSetUpCardsLastDemonstrated, to: dateTimeProvider()).day!
            if daysSinceLastDemonstration > 0 {
                persistor.continueSetUpCardsLastDemonstrated = Date()
                persistor.continueSetUpCardsNumberOfDaysDemonstrated += 1

                if persistor.continueSetUpCardsNumberOfDaysDemonstrated >= Constants.dismissNextStepsCardsAfterDays {
                    self.isContinueSetUpCardsViewOutdated = true
                }
            }

        } else if persistor.continueSetUpCardsLastDemonstrated == nil {
            persistor.continueSetUpCardsLastDemonstrated = Date()
        }
    }

    @Published var isProtectionsReportVisible: Bool {
        didSet {
            persistor.isProtectionsReportVisible = isProtectionsReportVisible
            if !isProtectionsReportVisible {
                pixelFiring?.fire(NewTabPagePixel.protectionsSectionHidden, frequency: .dailyAndStandard)
            }
        }
    }

    @Published var showBookmarksBar: Bool {
        didSet {
            persistor.showBookmarksBar = showBookmarksBar
            NotificationCenter.default.post(name: Notifications.showBookmarksBarSettingChanged, object: nil)
        }
    }
    @Published var bookmarksBarAppearance: BookmarksBarAppearance {
        didSet {
            persistor.bookmarksBarAppearance = bookmarksBarAppearance
            NotificationCenter.default.post(name: Notifications.bookmarksBarSettingAppearanceChanged, object: nil)
        }
    }

    @Published var homeButtonPosition: HomeButtonPosition {
        didSet {
            persistor.homeButtonPosition = homeButtonPosition
        }
    }

    @Published var homePageCustomBackground: CustomBackground? {
        didSet {
            persistor.homePageCustomBackground = homePageCustomBackground?.description
        }
    }

    @Published var centerAlignedBookmarksBarBool: Bool {
        didSet {
            persistor.centerAlignedBookmarksBar = centerAlignedBookmarksBarBool
            NotificationCenter.default.post(name: Notifications.bookmarksBarAlignmentChanged,
                                            object: nil,
                                            userInfo: [Constants.bookmarksBarAlignmentChangedIsCenterAlignedParameter: centerAlignedBookmarksBarBool])
        }
    }

    @Published var showTabsAndBookmarksBarOnFullScreen: Bool {
        didSet {
            persistor.showTabsAndBookmarksBarOnFullScreen = showTabsAndBookmarksBarOnFullScreen
            NotificationCenter.default.post(name: Notifications.showTabsAndBookmarksBarOnFullScreenChanged,
                                            object: nil,
                                            userInfo: [Constants.showTabsAndBookmarksBarOnFullScreenParameter: showTabsAndBookmarksBarOnFullScreen])
        }
    }

    var isContinueSetUpAvailable: Bool {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        return privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .newTabContinueSetUp) && osVersion.majorVersion >= 12
    }

    func updateUserInterfaceStyle() {
        NSApp.appearance = currentThemeName.appearance
    }

    func openNewTabPageBackgroundCustomizationSettings() {
        newTabPageNavigator.openNewTabPageBackgroundCustomizationSettings()
    }

    convenience init(
        keyValueStore: ThrowingKeyValueStoring,
        privacyConfigurationManager: PrivacyConfigurationManaging,
        pixelFiring: PixelFiring? = nil,
        newTabPageNavigator: NewTabPageNavigator = DefaultNewTabPageNavigator(),
        dateTimeProvider: @escaping () -> Date = Date.init
    ) {
        self.init(
            persistor: AppearancePreferencesUserDefaultsPersistor(keyValueStore: keyValueStore),
            privacyConfigurationManager: privacyConfigurationManager,
            pixelFiring: pixelFiring,
            newTabPageNavigator: newTabPageNavigator,
            dateTimeProvider: dateTimeProvider
        )
    }

    init(
        persistor: AppearancePreferencesPersistor,
        privacyConfigurationManager: PrivacyConfigurationManaging,
        pixelFiring: PixelFiring? = nil,
        newTabPageNavigator: NewTabPageNavigator = DefaultNewTabPageNavigator(),
        dateTimeProvider: @escaping () -> Date = Date.init
    ) {
        self.persistor = persistor
        self.privacyConfigurationManager = privacyConfigurationManager
        self.pixelFiring = pixelFiring
        self.newTabPageNavigator = newTabPageNavigator
        self.dateTimeProvider = dateTimeProvider

        /// when adding new properties, make sure to update `reload()` to include them there.
        isContinueSetUpCardsViewOutdated = persistor.continueSetUpCardsNumberOfDaysDemonstrated >= Constants.dismissNextStepsCardsAfterDays
        continueSetUpCardsClosed = persistor.continueSetUpCardsClosed
        currentThemeName = .init(rawValue: persistor.currentThemeName) ?? .systemDefault
        showFullURL = persistor.showFullURL
        favoritesDisplayMode = persistor.favoritesDisplayMode.flatMap(FavoritesDisplayMode.init) ?? .default
        isSearchVisible = persistor.isSearchVisible
        isFavoriteVisible = persistor.isFavoriteVisible
        isProtectionsReportVisible = persistor.isProtectionsReportVisible
        showBookmarksBar = persistor.showBookmarksBar
        bookmarksBarAppearance = persistor.bookmarksBarAppearance
        homeButtonPosition = persistor.homeButtonPosition
        homePageCustomBackground = persistor.homePageCustomBackground.flatMap(CustomBackground.init)
        centerAlignedBookmarksBarBool = persistor.centerAlignedBookmarksBar
        showTabsAndBookmarksBarOnFullScreen = persistor.showTabsAndBookmarksBarOnFullScreen
    }

    /// This function reloads preferences with persisted values.
    ///
    /// - Note: This is only used in the debug menu and shouldn't need to be called in the production code.
    func reload() {
        isContinueSetUpCardsViewOutdated = persistor.continueSetUpCardsNumberOfDaysDemonstrated >= Constants.dismissNextStepsCardsAfterDays
        continueSetUpCardsClosed = persistor.continueSetUpCardsClosed
        currentThemeName = .init(rawValue: persistor.currentThemeName) ?? .systemDefault
        showFullURL = persistor.showFullURL
        favoritesDisplayMode = persistor.favoritesDisplayMode.flatMap(FavoritesDisplayMode.init) ?? .default
        isFavoriteVisible = persistor.isFavoriteVisible
        isProtectionsReportVisible = persistor.isProtectionsReportVisible
        showBookmarksBar = persistor.showBookmarksBar
        bookmarksBarAppearance = persistor.bookmarksBarAppearance
        homeButtonPosition = persistor.homeButtonPosition
        homePageCustomBackground = persistor.homePageCustomBackground.flatMap(CustomBackground.init)
        centerAlignedBookmarksBarBool = persistor.centerAlignedBookmarksBar
        showTabsAndBookmarksBarOnFullScreen = persistor.showTabsAndBookmarksBarOnFullScreen
    }

    private var persistor: AppearancePreferencesPersistor
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private var pixelFiring: PixelFiring?
    private var newTabPageNavigator: NewTabPageNavigator
    private let dateTimeProvider: () -> Date

    private func requestSync() {
        Task { @MainActor in
            guard let syncService = NSApp.delegateTyped.syncService else { return }
            Logger.sync.debug("Requesting sync if enabled")
            syncService.scheduler.notifyDataChanged()
        }
    }
}
