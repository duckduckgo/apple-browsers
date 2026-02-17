//
//  DarkReaderFeatureSettings.swift
//  DuckDuckGo
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

import Foundation
import PrivacyConfig

/// Provides access to the force dark mode feature configuration and user settings.
protocol DarkReaderFeatureSettings {

    /// Whether the force dark mode feature is available (gated by feature flag).
    var isFeatureEnabled: Bool { get }

    /// Whether the user has enabled force dark mode on websites.
    var isDarkModeEnabled: Bool { get }

    /// Updates the user's dark mode preference.
    func setDarkModeEnabled(_ enabled: Bool)
}

/// Concrete implementation that reads from feature flags and app settings.
final class AppDarkReaderFeatureSettings: DarkReaderFeatureSettings {

    private let featureFlagger: FeatureFlagger
    private let appSettings: AppSettings

    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         appSettings: AppSettings = AppDependencyProvider.shared.appSettings) {
        self.featureFlagger = featureFlagger
        self.appSettings = appSettings
    }

    var isFeatureEnabled: Bool {
        featureFlagger.isFeatureOn(.forceDarkModeOnWebsites)
    }

    var isDarkModeEnabled: Bool {
        appSettings.isAdaptiveDarkModeEnabled
    }

    func setDarkModeEnabled(_ enabled: Bool) {
        appSettings.isAdaptiveDarkModeEnabled = enabled
        NotificationCenter.default.post(name: AppUserDefaults.Notifications.adaptiveDarkModeChanged, object: nil)
    }
}
