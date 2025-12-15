//
//  ThemeManager.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import AppKit
import DesignResourcesKit
import BrowserServicesKit
import FeatureFlags

protocol ThemeManaging {
    var theme: ThemeStyleProviding { get }
    var themePublisher: Published<any ThemeStyleProviding>.Publisher { get }
}

final class ThemeManager: ObservableObject, ThemeManaging {
    private var cancellables = Set<AnyCancellable>()
    private var appearancePreferences: AppearancePreferences
    private let featureFlagger: FeatureFlagger
    @Published private(set) var theme: ThemeStyleProviding {
        didSet {
            switchDesignSystemPalette(to: theme.name.designColorPalette)
        }
    }

    var themePublisher: Published<any ThemeStyleProviding>.Publisher {
        $theme
    }

    init(appearancePreferences: AppearancePreferences, internalUserDecider: InternalUserDecider, featureFlagger: FeatureFlagger) {
        self.appearancePreferences = appearancePreferences
        self.featureFlagger = featureFlagger
        self.theme = ThemeStyle.buildThemeStyle(themeName: appearancePreferences.themeName, featureFlagger: featureFlagger)

        switchDesignSystemPalette(to: theme.name.designColorPalette)
        subscribeToThemeNameChanges(appearancePreferences: appearancePreferences)
        subscribeToInternalUserChanges(internalUserDecider: internalUserDecider)
    }

    private func subscribeToThemeNameChanges(appearancePreferences: AppearancePreferences) {
        appearancePreferences.$themeName
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] themeName in
                self?.switchToTheme(named: themeName)
            }
            .store(in: &cancellables)
    }

    private func subscribeToInternalUserChanges(internalUserDecider: InternalUserDecider) {
        internalUserDecider.isInternalUserPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isInternalUser in
                self?.resetThemeNameIfNeeded(isInternalUser: isInternalUser)
            }
            .store(in: &cancellables)
    }
}

private extension ThemeManager {

    /// Relay the change to all of our observers
    func switchToTheme(named themeName: ThemeName) {
        theme = ThemeStyle.buildThemeStyle(themeName: themeName, featureFlagger: featureFlagger)
    }

    /// Required to get `DesignResourcesKit` instantiate new Colors with the new Palette
    func switchDesignSystemPalette(to palette: DesignResourcesKit.ColorPalette) {
        DesignSystemPalette.current = palette
    }

    /// Non Internal Users should only see the `.default` theme
    func resetThemeNameIfNeeded(isInternalUser: Bool) {
        if isInternalUser == false, appearancePreferences.themeName != .default {
            appearancePreferences.themeName = .default
        }
    }
}
