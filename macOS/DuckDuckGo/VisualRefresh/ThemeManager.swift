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

protocol ThemeManaging {
    var theme: ThemeStyleProviding { get }
    var themePublisher: Published<any ThemeStyleProviding>.Publisher { get }
}

final class ThemeManager: ObservableObject, ThemeManaging {
    private var cancellables = Set<AnyCancellable>()
    @Published private(set) var theme: ThemeStyleProviding

    var themePublisher: Published<any ThemeStyleProviding>.Publisher {
        $theme
    }

    init(appearancePreferences: AppearancePreferences) {
        theme = ThemeStyle.buildThemeStyle(themeName: appearancePreferences.themeName)
        subscribeToThemeNameChanges(appearancePreferences: appearancePreferences)
    }

    private func subscribeToThemeNameChanges(appearancePreferences: AppearancePreferences) {
        appearancePreferences.$themeName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] themeName in
                self?.switchToTheme(named: themeName)
            }
            .store(in: &cancellables)
    }
}

private extension ThemeManager {

    func switchToTheme(named themeName: ThemeName) {
        theme = ThemeStyle.buildThemeStyle(themeName: themeName)
    }
}
