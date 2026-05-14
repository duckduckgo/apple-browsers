//
//  ScriptStyleProvider.swift
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
import Common

/// # Note: This component is used by HistoryView + SpecialErrorPages + PrivacyDashboardController
///
final class ScriptStyleProvider: ScriptStyleProviding {
    let themeManager: ThemeManaging

    var themeAppearance: String {
        themeManager.appearance.encodedForFrontend
    }

    var themeName: String {
        themeManager.theme.name.encodedForFrontend
    }

    var themeStylePublisher: AnyPublisher<(appearance: String, themeName: String), Never> {
        Publishers.CombineLatest(themeManager.appearancePublisher, themeManager.themePublisher)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .map { appearance, theme in
                (appearance.encodedForFrontend, theme.name.encodedForFrontend)
            }
            .removeDuplicates { previous, current in
                previous.0 == current.0 && previous.1 == current.1
            }
            .eraseToAnyPublisher()
    }

    init(themeManager: ThemeManaging) {
        self.themeManager = themeManager
    }
}

private extension ThemeAppearance {

    var encodedForFrontend: String {
        // Frontend expects `system` rather than `systemDefault`
        self == .systemDefault ? "system" : rawValue
    }
}

private extension ThemeName {

    var encodedForFrontend: String {
        rawValue
    }
}
