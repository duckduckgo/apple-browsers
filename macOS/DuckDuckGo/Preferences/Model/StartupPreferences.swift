//
//  StartupPreferences.swift
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

import Foundation
import Combine
import BrowserServicesKit
import FeatureFlags
import Persistence

enum StartupWindowType: String, CaseIterable {
    case window = "window"
    case fireWindow = "fire-window"

    var displayName: String {
        switch self {
        case .window:
            return UserText.window
        case .fireWindow:
            return UserText.fireWindow
        }
    }

    /// Returns the corresponding BurnerMode for this window type
    /// - Parameter isFeatureEnabled: Whether the fire window by default feature is enabled
    /// - Returns: The appropriate BurnerMode
    func toBurnerMode(isFeatureEnabled: Bool) -> BurnerMode {
        switch self {
        case .window:
            return .regular
        case .fireWindow:
            return isFeatureEnabled ? BurnerMode(isBurner: true) : .regular
        }
    }
}

protocol StartupPreferencesPersistor {
    var restorePreviousSession: Bool { get set }
    var launchToCustomHomePage: Bool { get set }
    var customHomePageURL: String { get set }
    var startupWindowType: StartupWindowType { get set }
}

struct StartupPreferencesUserDefaultsPersistor: StartupPreferencesPersistor {
    enum Key: String {
        case startupWindowType = "startup-window-type"
    }

    @UserDefaultsWrapper(key: .restorePreviousSession, defaultValue: false)
    var restorePreviousSession: Bool

    @UserDefaultsWrapper(key: .launchToCustomHomePage, defaultValue: false)
    var launchToCustomHomePage: Bool

    @UserDefaultsWrapper(key: .customHomePageURL, defaultValue: URL.duckDuckGo.absoluteString)
    var customHomePageURL: String

    var startupWindowType: StartupWindowType {
        get {
            do {
                let value = try keyValueStore.object(forKey: Key.startupWindowType.rawValue) as? String ?? StartupWindowType.window.rawValue
                return StartupWindowType(rawValue: value) ?? .window
            } catch {
                return .window
            }
        }
        set { try? keyValueStore.set(newValue.rawValue, forKey: Key.startupWindowType.rawValue) }
    }

    /**
     * Initializes Startup Preferences persistor.
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

final class StartupPreferences: ObservableObject, PreferencesTabOpening {

    private let pinningManager: LocalPinningManager
    private var appearancePreferences: AppearancePreferences
    private var persistor: StartupPreferencesPersistor
    private var pinnedViewsNotificationCancellable: AnyCancellable?

    init(pinningManager: LocalPinningManager = .shared,
         persistor: StartupPreferencesPersistor,
         appearancePreferences: AppearancePreferences) {
        self.pinningManager = pinningManager
        self.appearancePreferences = appearancePreferences
        self.persistor = persistor
        restorePreviousSession = persistor.restorePreviousSession
        launchToCustomHomePage = persistor.launchToCustomHomePage
        customHomePageURL = persistor.customHomePageURL
        startupWindowType = persistor.startupWindowType
        updateHomeButtonState()
        listenToPinningManagerNotifications()
    }

    @Published var restorePreviousSession: Bool {
        didSet {
            persistor.restorePreviousSession = restorePreviousSession
        }
    }

    @Published var launchToCustomHomePage: Bool {
        didSet {
            persistor.launchToCustomHomePage = launchToCustomHomePage
        }
    }

    @Published var customHomePageURL: String {
        didSet {
            guard let urlWithScheme = urlWithScheme(customHomePageURL) else {
                return
            }
            if customHomePageURL != urlWithScheme {
                customHomePageURL = urlWithScheme
            }
            persistor.customHomePageURL = customHomePageURL
        }
    }

    @Published var startupWindowType: StartupWindowType {
        didSet {
            persistor.startupWindowType = startupWindowType
        }
    }

    @Published var homeButtonPosition: HomeButtonPosition = .hidden

    var formattedCustomHomePageURL: String {
        let trimmedURL = customHomePageURL.trimmingWhitespace()
        guard let url = URL(trimmedAddressBarString: trimmedURL) else {
            return URL.duckDuckGo.absoluteString
        }
        return url.absoluteString
    }

    var friendlyURL: String {
        var friendlyURL = customHomePageURL
        if friendlyURL.count > 30 {
            let index = friendlyURL.index(friendlyURL.startIndex, offsetBy: 27)
            friendlyURL = String(friendlyURL[..<index]) + "..."
        }
        return friendlyURL
    }

    /// Determines the appropriate BurnerMode for new windows based on startup preferences and feature flags
    /// - Parameter featureFlagger: The feature flag provider to check if fire window by default is enabled
    /// - Returns: The appropriate BurnerMode for the startup window
    func startupBurnerMode(featureFlagger: FeatureFlagger) -> BurnerMode {
        return startupWindowType.toBurnerMode(isFeatureEnabled: featureFlagger.isFeatureOn(.openFireWindowByDefault))
    }

    func isValidURL(_ text: String) -> Bool {
        guard let url = text.url else { return false }
        return !text.isEmpty && url.isValid
    }

    func updateHomeButton() {
        appearancePreferences.homeButtonPosition = homeButtonPosition
        if homeButtonPosition != .hidden {
            pinningManager.unpin(.homeButton)
            pinningManager.pin(.homeButton)
        } else {
            pinningManager.unpin(.homeButton)
        }
    }

    private func updateHomeButtonState() {
        homeButtonPosition = pinningManager.isPinned(.homeButton) ? appearancePreferences.homeButtonPosition : .hidden
    }

    private func listenToPinningManagerNotifications() {
        pinnedViewsNotificationCancellable = NotificationCenter.default.publisher(for: .PinnedViewsChanged).sink { [weak self] _ in
            guard let self = self else {
                return
            }
            self.updateHomeButtonState()
        }
    }

    private func urlWithScheme(_ urlString: String) -> String? {
        guard var urlWithScheme = urlString.url else {
            return nil
        }
        // Force 'https' if 'http' not explicitly set by user
        if urlWithScheme.isHttp && !urlString.hasPrefix(URL.NavigationalScheme.http.separated()) {
            urlWithScheme = urlWithScheme.toHttps() ?? urlWithScheme
        }
        return urlWithScheme.toString(decodePunycode: true, dropScheme: false, dropTrailingSlash: true)
    }

}
