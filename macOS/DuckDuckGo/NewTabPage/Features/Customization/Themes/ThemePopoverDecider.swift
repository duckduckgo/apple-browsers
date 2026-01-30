//
//  ThemePopoverDecider.swift
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
import FeatureFlags
import Persistence
import os.log

/// Protocol for deciding when to render the Themes Discoverability Popover
///
protocol ThemePopoverDeciding {
    var shouldShowPopover: Bool { get }
    func markPopoverShown()
}

/// Determines when the Themes Popover should be rendered:
///
///     - The `.themes` Feature Flag must be enabled
///     - The Popover must not have been shown before
///     - The default theme must be set (otherwise users already know about the feature!)
///     - At least two days must have elapsed since the Install Date
///
final class ThemePopoverDecider: ThemePopoverDeciding {
    private let appearancePreferences: AppearancePreferences
    private let featureFlagger: FeatureFlagger
    private let firstLaunchDate: Date
    private var persistor: ThemePopoverPersistor

    var shouldShowPopover: Bool {
        false
    }

    init(appearancePreferences: AppearancePreferences, featureFlagger: FeatureFlagger, firstLaunchDate: Date, persistor: ThemePopoverPersistor) {
        self.appearancePreferences = appearancePreferences
        self.featureFlagger = featureFlagger
        self.firstLaunchDate = firstLaunchDate
        self.persistor = persistor
    }

    func markPopoverShown() {
        guard shouldShowPopover, persistor.themePopoverShown == false else {
            return
        }

        persistor.themePopoverShown = true
    }
}

// MARK: - Persistor

protocol ThemePopoverPersistor {
    var themePopoverShown: Bool { get set }
}

final class ThemePopoverUserDefaultsPersistor: ThemePopoverPersistor {

    private enum Key {
        static let themePopoverShown = "theme-popover.shown"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var themePopoverShown: Bool {
        get {
            do {
                return try keyValueStore.object(forKey: Key.themePopoverShown) as? Bool ?? false
            } catch {
                Logger.general.error("Failed to read \(Key.themePopoverShown) from keyValueStore: \(error)")
                return false
            }
        }
        set {
            do {
                try keyValueStore.set(newValue, forKey: Key.themePopoverShown)
            } catch {
                Logger.general.error("Failed to write \(Key.themePopoverShown) to keyValueStore: \(error)")
            }
        }
    }
}
