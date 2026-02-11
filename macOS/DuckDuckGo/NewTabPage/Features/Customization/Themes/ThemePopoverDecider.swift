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

    func shouldDismissPopover(newTabPageDidAppearCount: Int) -> Bool
    func markPopoverDismissed()
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
        featureFlagger.isFeatureOn(.themes)
            && appearancePreferences.themeName == .default
            && persistor.themePopoverDismissed == false
            && firstLaunchDate.daysSinceNow() >= 2
    }

    init(appearancePreferences: AppearancePreferences, featureFlagger: FeatureFlagger, firstLaunchDate: Date, persistor: ThemePopoverPersistor) {
        self.appearancePreferences = appearancePreferences
        self.featureFlagger = featureFlagger
        self.firstLaunchDate = firstLaunchDate
        self.persistor = persistor
    }

    func markPopoverDismissed() {
        guard persistor.themePopoverDismissed == false else {
            return
        }

        persistor.themePopoverDismissed = true
    }

    func shouldDismissPopover(newTabPageDidAppearCount: Int) -> Bool {
        newTabPageDidAppearCount >= 4
    }
}

// MARK: - Persistor

protocol ThemePopoverPersistor {
    var themePopoverDismissed: Bool { get set }
}

final class ThemePopoverUserDefaultsPersistor: ThemePopoverPersistor {

    private enum Key {
        // Key preserved as "shown" for backwards compatibility with existing persisted values
        static let themePopoverDismissed = "theme-popover.shown"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var themePopoverDismissed: Bool {
        get {
            do {
                return try keyValueStore.object(forKey: Key.themePopoverDismissed) as? Bool ?? false
            } catch {
                Logger.general.error("Failed to read \(Key.themePopoverDismissed) from keyValueStore: \(error)")
                return false
            }
        }
        set {
            do {
                try keyValueStore.set(newValue, forKey: Key.themePopoverDismissed)
            } catch {
                Logger.general.error("Failed to write \(Key.themePopoverDismissed) to keyValueStore: \(error)")
            }
        }
    }
}
