//
//  ThemeManager.swift
//  DuckDuckGo
//
//  Copyright © 2018 DuckDuckGo. All rights reserved.
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

import UIKit
import Core
import DesignResourcesKit
import BrowserServicesKit

protocol ThemeManaging {
    var properties: ExperimentalThemingProperties { get }
    var currentTheme: Theme { get }
    var currentInterfaceStyle: UIUserInterfaceStyle { get }

    func updateColorScheme()
    func toggleExperimentalTheming()
    func setThemeStyle(_ style: ThemeStyle)

    func updateUserInterfaceStyle(window: UIWindow?)
    func updateUserInterfaceStyle()
}

class ThemeManager: ThemeManaging {

    enum ImageSet {
        case light
        case dark
        
        var trait: UITraitCollection {
            switch self {
            case .light:
                return UITraitCollection(userInterfaceStyle: .light)
            case .dark:
                return UITraitCollection(userInterfaceStyle: .dark)
            }
        }
    }
    
    public static let shared = ThemeManager()

    var properties: ExperimentalThemingProperties {
        themingManager.properties
    }

    private var appSettings: AppSettings
    private let themingManager: ExperimentalThemingManager

    private(set) var currentTheme: Theme = DefaultTheme()

    init(settings: AppSettings = AppUserDefaults(), featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        appSettings = settings
        self.themingManager = ExperimentalThemingManager(featureFlagger: featureFlagger)

        updateColorScheme()
    }

    public func updateColorScheme() {
        if properties.isExperimentalThemingEnabled {
            DesignSystemPalette.current = .experimental
        } else {
            DesignSystemPalette.current = .default
        }
    }

    public func toggleExperimentalTheming() {
        themingManager.toggleExperimentalTheming()
    }

    public func setThemeStyle(_ style: ThemeStyle) {
        appSettings.currentThemeStyle = style
        updateUserInterfaceStyle()
    }

    func updateUserInterfaceStyle(window: UIWindow? = UIApplication.shared.firstKeyWindow) {
        switch appSettings.currentThemeStyle {

        case .dark:
            window?.overrideUserInterfaceStyle = .dark

        case .light:
            window?.overrideUserInterfaceStyle = .light

        default:
            window?.overrideUserInterfaceStyle = .unspecified

        }
    }

    var currentInterfaceStyle: UIUserInterfaceStyle {
        UIApplication.shared.firstKeyWindow?.traitCollection.userInterfaceStyle ?? .light
    }
}

struct ExperimentalThemingProperties {
    let isExperimentalThemingEnabled: Bool
    let isRoundedCornersTreatmentEnabled: Bool
}

private extension ThemeManager {
    final class ExperimentalThemingManager {

        let featureFlagger: FeatureFlagger

        private(set) lazy var properties: ExperimentalThemingProperties = .init(
            isExperimentalThemingEnabled: isExperimentalThemingEnabled,
            isRoundedCornersTreatmentEnabled: isRoundedCornersTreatmentEnabled
        )

        init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
            self.featureFlagger = featureFlagger
        }

        func toggleExperimentalTheming() {
            featureFlagger.localOverrides?.toggleOverride(for: FeatureFlag.experimentalBrowserTheming)
        }

        // MARK: - Private

        private var isExperimentalThemingEnabled: Bool {
            featureFlagger.isFeatureOn(for: FeatureFlag.experimentalBrowserTheming, allowOverride: true)
        }

        private let isRoundedCornersTreatmentEnabled = false
    }
}

extension ThemeManaging {
    func updateUserInterfaceStyle() {
        updateUserInterfaceStyle(window: UIApplication.shared.firstKeyWindow)
    }
}
