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
import PrivacyConfig
import FeatureFlags

protocol ThemeManaging {
    var appearance: ThemeAppearance { get }
    var appearancePublisher: Published<ThemeAppearance>.Publisher { get }

    var theme: ThemeStyleProviding { get }
    var themePublisher: Published<any ThemeStyleProviding>.Publisher { get }
}

final class ThemeManager: ObservableObject, ThemeManaging {
    private var cancellables = Set<AnyCancellable>()
    private var appearancePreferences: AppearancePreferences
    private let featureFlagger: FeatureFlagger

    @Published private(set) var appearance: ThemeAppearance

    var appearancePublisher: Published<ThemeAppearance>.Publisher {
        $appearance
    }

    @Published private(set) var theme: ThemeStyleProviding {
        didSet {
            switchDesignSystemPalette(to: theme.name.designColorPalette)
        }
    }

    var themePublisher: Published<any ThemeStyleProviding>.Publisher {
        $theme
    }

    @Published private(set) var designColorPalette: DesignResourcesKit.ColorPalette

    init(appearancePreferences: AppearancePreferences, featureFlagger: FeatureFlagger) {
        self.appearancePreferences = appearancePreferences
        self.featureFlagger = featureFlagger

        self.theme = ThemeStyle.buildThemeStyle(themeName: appearancePreferences.themeName, featureFlagger: featureFlagger)
        self.appearance = appearancePreferences.themeAppearance
        self.designColorPalette = appearancePreferences.themeName.designColorPalette

        switchDesignSystemPalette(to: theme.name.designColorPalette)
        subscribeToThemeNameChanges(appearancePreferences: appearancePreferences)
        subscribeToThemesFlagChanges(featureFlagger: featureFlagger)
        subscribeToSystemAppearance()

        resetThemeNameIfNeeded(featureFlagger: featureFlagger)
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

    private func subscribeToThemesFlagChanges(featureFlagger: FeatureFlagger) {
        featureFlagger.updatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.resetThemeNameIfNeeded(featureFlagger: featureFlagger)
            }
            .store(in: &cancellables)
    }

    private func subscribeToSystemAppearance() {
        appearancePreferences.$themeAppearance
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] appearance in
                self?.appearance = appearance
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
    /// We're also keeping a reference to the active `designColorPalette`, so that it's Observable in SwiftUI
    func switchDesignSystemPalette(to palette: DesignResourcesKit.ColorPalette) {
        DesignSystemPalette.current = palette
        designColorPalette = palette
    }

    /// Ensure the `.default` theme is set, whenever the `.themes` Feature Flag is disabled
    func resetThemeNameIfNeeded(featureFlagger: FeatureFlagger) {
        if featureFlagger.isFeatureOn(.themes) == false, appearancePreferences.themeName != .default {
            appearancePreferences.themeName = .default
        }
    }
}
