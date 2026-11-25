//
//  NewTabPageCustomizationModel.swift
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

import Combine
import Core
import FeatureFlags_iOS
import Foundation
import Persistence
import PixelKit

final class NewTabPageCustomizationModel: ObservableObject {

    @Published var isFavoritesSectionVisible: Bool {
        didSet {
            guard oldValue != isFavoritesSectionVisible else { return }
            persistor.isFavoritesSectionVisible = isFavoritesSectionVisible
            pixelFiring?.fire(NewTabPageCustomizationPixel.favoritesToggled(enabled: isFavoritesSectionVisible), frequency: .dailyAndCount)
        }
    }

    @Published var isMessagesSectionVisible: Bool {
        didSet {
            guard oldValue != isMessagesSectionVisible else { return }
            persistor.isMessagesSectionVisible = isMessagesSectionVisible
            pixelFiring?.fire(NewTabPageCustomizationPixel.messagesToggled, frequency: .dailyAndCount)
        }
    }

    @Published var theme: NewTabPageTheme {
        didSet {
            guard oldValue != theme else { return }
            persistor.theme = theme
        }
    }

    @Published var isKeyboardShownOnNewTab: Bool {
        didSet {
            guard oldValue != isKeyboardShownOnNewTab else { return }
            keyboardSettings.onNewTab = isKeyboardShownOnNewTab
            pixelFiring?.fire(NewTabPageCustomizationPixel.keyboardToggled(enabled: isKeyboardShownOnNewTab), frequency: .dailyAndCount)
        }
    }

    @Published var isReturnToLastTabEnabled: Bool {
        didSet {
            guard oldValue != isReturnToLastTabEnabled else { return }
            returnSettings.lastTabShortcutAdapter.setEnabled(isReturnToLastTabEnabled)
            pixelFiring?.fire(isReturnToLastTabEnabled ? Pixel.Event.ntpAfterIdleLastTabShortcutSettingEnabled : .ntpAfterIdleLastTabShortcutSettingDisabled,
                              frequency: .dailyAndCount)
        }
    }

    @Published var afterInactivityOption: AfterInactivityOption {
        didSet {
            returnSettings.afterInactivityOptionAdapter.afterInactivityOptionBinding.wrappedValue = afterInactivityOption
            guard oldValue != afterInactivityOption else { return }
            pixelFiring?.fire(afterInactivityOption == .newTab ? Pixel.Event.ntpAfterIdleSettingChangedToNewTab : .ntpAfterIdleSettingChangedToLastUsedTab,
                              frequency: .dailyAndCount)
        }
    }

    @Published var afterInactivityIdleInterval: AfterInactivityIdleInterval {
        didSet {
            try? idleReturnStorage.set(afterInactivityIdleInterval.seconds, for: \AfterInactivitySettingKeys.idleReturnIntervalSeconds)
            guard oldValue != afterInactivityIdleInterval else { return }
            pixelFiring?.fire(Pixel.Event.ntpAfterIdleSettingIdleIntervalChanged,
                              frequency: .dailyAndCount,
                              options: .parameters(["idle_interval_seconds": String(afterInactivityIdleInterval.seconds)]))
        }
    }

    var onAllSettingsSelected: (() -> Void)?

    var isIdleReturnSettingsVisible: Bool {
        returnSettings.featureFlagger.isFeatureOn(.showNTPAfterIdleReturn)
    }

    var afterInactivityFooterText: String {
        if afterInactivityOption == .lastUsedTab || afterInactivityIdleInterval == .none {
            return UserText.settingsAfterInactivityFooterNone
        }
        return String(format: UserText.settingsAfterInactivityFooterFormat, afterInactivityIdleInterval.description)
    }

    private let pixelFiring: (any PixelKitFiring)?

    private var persistor: NewTabPageCustomizationPersisting
    private var keyboardSettings: KeyboardSettings
    private let returnSettings: NewTabPageReturnSettings

    private var idleReturnStorage: any ThrowingKeyedStoring<AfterInactivitySettingKeys> {
        returnSettings.keyValueStore.throwingKeyedStoring()
    }

    init(persistor: NewTabPageCustomizationPersisting = NewTabPageCustomizationStore(),
         keyboardSettings: KeyboardSettings = KeyboardSettings(),
         returnSettings: NewTabPageReturnSettings,
         pixelFiring: (any PixelKitFiring)? = PixelKit.shared) {
        self.pixelFiring = pixelFiring
        self.persistor = persistor
        self.keyboardSettings = keyboardSettings
        self.returnSettings = returnSettings

        isFavoritesSectionVisible = persistor.isFavoritesSectionVisible
        isMessagesSectionVisible = persistor.isMessagesSectionVisible
        theme = persistor.theme
        isKeyboardShownOnNewTab = keyboardSettings.onNewTab
        isReturnToLastTabEnabled = returnSettings.lastTabShortcutAdapter.isEnabled
        afterInactivityOption = returnSettings.afterInactivityOptionAdapter.afterInactivityOption
        afterInactivityIdleInterval = AfterInactivityIdleInterval(rawValue: returnSettings.idleReturnEligibilityManager.idleThresholdSeconds()) ?? .default
    }

    func reportOpening() {
        pixelFiring?.fire(NewTabPageCustomizationPixel.opened, frequency: .dailyAndCount)
    }

    func selectAllSettings() {
        pixelFiring?.fire(NewTabPageCustomizationPixel.allSettingsOpened, frequency: .dailyAndCount)
        onAllSettingsSelected?()
    }
}
