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
import PrivacyConfig
import Common
import FeatureFlags
import Foundation
import NewTabPage
import Persistence
import PixelKit
import os.log
import Combine

protocol AppearancePreferencesPersistor {
    var showFullURL: Bool { get set }
    var themeAppearance: String { get set }
    var themeName: String { get set }
    var syncAppIconWithTheme: Bool { get set }
    var favoritesDisplayMode: String? { get set }
    var isOmnibarVisible: Bool { get set }
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
    var didChangeAnyNewTabPageCustomizationSetting: Bool { get set }
}

struct AppearancePreferencesUserDefaultsPersistor: AppearancePreferencesPersistor {

    enum Key: String {
        case newTabPageIsOmnibarVisible = "new-tab-page.omnibar.is-visible"
        case newTabPageIsProtectionsReportVisible = "new-tab-page.protections-report.is-visible"
        case newTabPageDidChangeAnyCustomizationSetting = "new-tab-page.did-change-any-customization-setting"
    }

    var didChangeAnyNewTabPageCustomizationSetting: Bool {
        get { (try? keyValueStore.object(forKey: Key.newTabPageDidChangeAnyCustomizationSetting.rawValue) as? Bool) ?? false }
        set { try? keyValueStore.set(newValue, forKey: Key.newTabPageDidChangeAnyCustomizationSetting.rawValue) }
    }

    var isOmnibarVisible: Bool {
        get { (try? keyValueStore.object(forKey: Key.newTabPageIsOmnibarVisible.rawValue) as? Bool) ?? true }
        set { try? keyValueStore.set(newValue, forKey: Key.newTabPageIsOmnibarVisible.rawValue) }
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

    @UserDefaultsWrapper(key: .showFullURL, defaultValue: false)
    var showFullURL: Bool

    @UserDefaultsWrapper(key: .themeAppearance, defaultValue: ThemeAppearance.systemDefault.rawValue)
    var themeAppearance: String

    @UserDefaultsWrapper(key: .themeName, defaultValue: ThemeName.default.rawValue)
    var themeName: String

    @UserDefaultsWrapper(key: .syncAppIconWithTheme, defaultValue: false)
    var syncAppIconWithTheme: Bool

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
            if Application.appDelegate.windowControllersManager.selectedTab?.content != .newtab {
                Application.appDelegate.windowControllersManager.showTab(with: .newtab)
                try? await Task.sleep(interval: 0.2)
            }
            if let window = Application.appDelegate.windowControllersManager.lastKeyMainWindowController {
                if Application.appDelegate.featureFlagger.isFeatureOn(.newTabPagePerTab) {
                    if let webView = window.mainViewController.browserTabViewController.webView {
                        Application.appDelegate.newTabPageCustomizationModel.customizerOpener.openSettings(for: webView)
                    }
                } else {
                    let newTabPageViewModel = window.mainViewController.browserTabViewController.newTabPageWebViewModel
                    NSApp.delegateTyped.newTabPageCustomizationModel.customizerOpener.openSettings(for: newTabPageViewModel.webView)
                }
            }
        }
    }
}

enum HomeButtonPosition: String, CaseIterable {
    case hidden
    case left
    case right
}

enum ThemeAppearance: String, Equatable, CaseIterable {
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
        static let legacyDismissNextStepsCardsAfterDays = 9
        static let maxNextStepsCardsDemonstrationDays = 14
    }

    @Published var themeAppearance: ThemeAppearance {
        didSet {
            persistor.themeAppearance = themeAppearance.rawValue
            updateUserInterfaceStyle()
        }
    }

    @Published var themeName: ThemeName {
        didSet {
            persistor.themeName = themeName.rawValue
        }
    }

    @Published var syncAppIconWithTheme: Bool {
        didSet {
            persistor.syncAppIconWithTheme = syncAppIconWithTheme
            let pixel: SettingsPixel = syncAppIconWithTheme ? .syncAppIconWithThemeTurnedOn : .syncAppIconWithThemeTurnedOff
            pixelFiring?.fire(pixel, frequency: .dailyAndCount)
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

    var isOmnibarAvailable: Bool {
        return featureFlagger?.isFeatureOn(.newTabPageOmnibar) ?? true
    }

    var areThemesAvailable: Bool {
        return featureFlagger?.isFeatureOn(.themes) ?? true
    }

    @Published var isOmnibarVisible: Bool {
        didSet {
            persistor.isOmnibarVisible = isOmnibarVisible
            if isOmnibarVisible {
                pixelFiring?.fire(NewTabPagePixel.omnibarShown, frequency: .dailyAndStandard)
            } else {
                pixelFiring?.fire(NewTabPagePixel.omnibarHidden, frequency: .dailyAndStandard)
            }
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

    var maxNextStepsCardsDemonstrationDays: Int {
        (featureFlagger?.isFeatureOn(.nextStepsListWidget) ?? true) ? Constants.maxNextStepsCardsDemonstrationDays : Constants.legacyDismissNextStepsCardsAfterDays
    }

    /// Number of active usage days the New Tab Page "Next Steps" cards have been shown.
    var nextStepsCardsDemonstrationDays: Int {
        persistor.continueSetUpCardsNumberOfDaysDemonstrated
    }

    private var shouldHideNextStepsCards: Bool {
       persistor.continueSetUpCardsNumberOfDaysDemonstrated >= maxNextStepsCardsDemonstrationDays
    }

    @Published var isContinueSetUpCardsViewOutdated: Bool = false

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

                if shouldHideNextStepsCards {
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
        return (privacyConfigurationManager?.privacyConfig.isEnabled(featureKey: .newTabContinueSetUp) ?? true) && osVersion.majorVersion >= 12
    }

    func updateUserInterfaceStyle() {
        NSApp.appearance = themeAppearance.appearance
    }

    @Published var didChangeAnyNewTabPageCustomizationSetting: Bool {
        didSet {
            persistor.didChangeAnyNewTabPageCustomizationSetting = didChangeAnyNewTabPageCustomizationSetting
        }
    }

    func openNewTabPageBackgroundCustomizationSettings() {
        newTabPageNavigator.openNewTabPageBackgroundCustomizationSettings()
    }

    convenience init(
        keyValueStore: ThrowingKeyValueStoring,
        privacyConfigurationManager: PrivacyConfigurationManaging?,
        pixelFiring: PixelFiring? = nil,
        newTabPageNavigator: NewTabPageNavigator = DefaultNewTabPageNavigator(),
        dateTimeProvider: @escaping () -> Date = Date.init,
        featureFlagger: FeatureFlagger?,
        aiChatMenuConfig: AIChatMenuVisibilityConfigurable
    ) {
        self.init(
            persistor: AppearancePreferencesUserDefaultsPersistor(keyValueStore: keyValueStore),
            privacyConfigurationManager: privacyConfigurationManager,
            pixelFiring: pixelFiring,
            newTabPageNavigator: newTabPageNavigator,
            dateTimeProvider: dateTimeProvider,
            featureFlagger: featureFlagger,
            aiChatMenuConfig: aiChatMenuConfig
        )
    }

    init(
        persistor: AppearancePreferencesPersistor,
        privacyConfigurationManager: PrivacyConfigurationManaging?,
        pixelFiring: PixelFiring? = nil,
        newTabPageNavigator: NewTabPageNavigator = DefaultNewTabPageNavigator(),
        dateTimeProvider: @escaping () -> Date = Date.init,
        featureFlagger: FeatureFlagger?,
        aiChatMenuConfig: AIChatMenuVisibilityConfigurable
    ) {
        self.persistor = persistor
        self.privacyConfigurationManager = privacyConfigurationManager
        self.pixelFiring = pixelFiring
        self.newTabPageNavigator = newTabPageNavigator
        self.dateTimeProvider = dateTimeProvider
        self.featureFlagger = featureFlagger
        self.aiChatMenuConfig = aiChatMenuConfig

        /// when adding new properties, make sure to update `reload()` to include them there.
        continueSetUpCardsClosed = persistor.continueSetUpCardsClosed
        themeAppearance = .init(rawValue: persistor.themeAppearance) ?? .systemDefault
        themeName = .init(rawValue: persistor.themeName) ?? .default
        syncAppIconWithTheme = persistor.syncAppIconWithTheme
        showFullURL = persistor.showFullURL
        favoritesDisplayMode = persistor.favoritesDisplayMode.flatMap(FavoritesDisplayMode.init) ?? .default
        isOmnibarVisible = persistor.isOmnibarVisible
        isFavoriteVisible = persistor.isFavoriteVisible
        isProtectionsReportVisible = persistor.isProtectionsReportVisible
        showBookmarksBar = persistor.showBookmarksBar
        bookmarksBarAppearance = persistor.bookmarksBarAppearance
        homeButtonPosition = persistor.homeButtonPosition
        homePageCustomBackground = persistor.homePageCustomBackground.flatMap(CustomBackground.init)
        centerAlignedBookmarksBarBool = persistor.centerAlignedBookmarksBar
        showTabsAndBookmarksBarOnFullScreen = persistor.showTabsAndBookmarksBarOnFullScreen
        didChangeAnyNewTabPageCustomizationSetting = persistor.didChangeAnyNewTabPageCustomizationSetting

        isContinueSetUpCardsViewOutdated = shouldHideNextStepsCards
        subscribeToOmnibarFeatureFlagChanges()
        subscribeToNewTabPageCustomizationSettingChanges()
    }

    /// This function reloads preferences with persisted values.
    ///
    /// - Note: This is only used in the debug menu and shouldn't need to be called in the production code.
    func reload() {
        isContinueSetUpCardsViewOutdated = shouldHideNextStepsCards
        continueSetUpCardsClosed = persistor.continueSetUpCardsClosed
        themeAppearance = .init(rawValue: persistor.themeAppearance) ?? .systemDefault
        themeName = .init(rawValue: persistor.themeName) ?? .default
        syncAppIconWithTheme = persistor.syncAppIconWithTheme
        showFullURL = persistor.showFullURL
        favoritesDisplayMode = persistor.favoritesDisplayMode.flatMap(FavoritesDisplayMode.init) ?? .default
        isOmnibarVisible = persistor.isOmnibarVisible
        isFavoriteVisible = persistor.isFavoriteVisible
        isProtectionsReportVisible = persistor.isProtectionsReportVisible
        showBookmarksBar = persistor.showBookmarksBar
        bookmarksBarAppearance = persistor.bookmarksBarAppearance
        homeButtonPosition = persistor.homeButtonPosition
        homePageCustomBackground = persistor.homePageCustomBackground.flatMap(CustomBackground.init)
        centerAlignedBookmarksBarBool = persistor.centerAlignedBookmarksBar
        showTabsAndBookmarksBarOnFullScreen = persistor.showTabsAndBookmarksBarOnFullScreen
        didChangeAnyNewTabPageCustomizationSetting = persistor.didChangeAnyNewTabPageCustomizationSetting
    }

    private var persistor: AppearancePreferencesPersistor
    private let privacyConfigurationManager: PrivacyConfigurationManaging?
    private var pixelFiring: PixelFiring?
    private var newTabPageNavigator: NewTabPageNavigator
    private let dateTimeProvider: () -> Date
    private let featureFlagger: FeatureFlagger?
    private let aiChatMenuConfig: AIChatMenuVisibilityConfigurable
    private var cancellables = Set<AnyCancellable>()

    private func requestSync() {
        Task { @MainActor in
            guard let syncService = NSApp.delegateTyped.syncService else { return }
            Logger.sync.debug("Requesting sync if enabled")
            syncService.scheduler.notifyDataChanged()
        }
    }

    private func subscribeToOmnibarFeatureFlagChanges() {
        guard let overridesHandler = featureFlagger?.localOverrides?.actionHandler as? FeatureFlagOverridesPublishingHandler<FeatureFlag> else {
            return
        }

        overridesHandler.flagDidChangePublisher
            .filter { $0.0 == .newTabPageOmnibar }
            .sink { _ in
                self.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func subscribeToNewTabPageCustomizationSettingChanges() {
        let duckAISectionVisibilityPublisher = aiChatMenuConfig.valuesChangedPublisher
            .compactMap { [weak self] in
                self?.aiChatMenuConfig.shouldDisplayNewTabPageShortcut
            }
            .prepend(aiChatMenuConfig.shouldDisplayNewTabPageShortcut)
            .removeDuplicates()

        duckAISectionVisibilityPublisher
            .combineLatest($themeAppearance,
                           $themeName,
                           $homePageCustomBackground)
            .combineLatest($isOmnibarVisible,
                           $isFavoriteVisible,
                           $isProtectionsReportVisible)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !didChangeAnyNewTabPageCustomizationSetting else { return }
                didChangeAnyNewTabPageCustomizationSetting = true
            }
            .store(in: &cancellables)
    }
}
