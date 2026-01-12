//
//  MockThemeManager.swift
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
#if DEBUG
import Bookmarks
import Foundation
import AppKit
import PrivacyConfig

final class MockThemeManager: ThemeManaging {

    private let featureFlagger: FeatureFlagger
    @Published var appearance: ThemeAppearance
    @Published var theme: ThemeStyleProviding

    var appearancePublisher: Published<ThemeAppearance>.Publisher {
        $appearance
    }

    var themePublisher: Published<any ThemeStyleProviding>.Publisher {
        $theme
    }

    var themeName: ThemeName {
        get {
            theme.name
        }
        set {
            theme = ThemeStyle.buildThemeStyle(themeName: newValue, featureFlagger: featureFlagger)
        }
    }

    init(featureFlagger: FeatureFlagger = MockFeatureFlagger(), appearance: ThemeAppearance = .dark, themeName: ThemeName = .default, ) {
        self.featureFlagger = featureFlagger
        self.appearance = appearance
        self.theme = ThemeStyle.buildThemeStyle(themeName: themeName, featureFlagger: featureFlagger)
    }
}
#endif
