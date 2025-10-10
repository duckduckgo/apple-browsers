//
//  ThemeUpdateListening.swift
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

/// ThemeUpdateListening defines methods and properties we should implement in spots where the UI
/// may need to be refreshed, given a Theme Change.
@MainActor
protocol ThemeUpdateListening: AnyObject {

    /// Reference to our ThemingManager
    ///
    var themeManager: ThemeManaging { get }

    /// Stores the Combine Listener's Cancellable
    ///
    var themeUpdateCancellable: AnyCancellable? { get set }

    /// This method should apply a given Theme Style to the receiver's visual elements
    ///
    func applyThemeStyle(theme: ThemeStyleProviding)
}

extension ThemeUpdateListening {

    var theme: ThemeStyleProviding {
        themeManager.theme
    }

    /// Subscribes the receiver to Theme changes
    ///
    func subscribeToThemeChanges() {
        themeUpdateCancellable = themeManager.themePublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] theme in
                self?.applyThemeStyle(theme: theme)
            }
    }

    func applyThemeStyle() {
        applyThemeStyle(theme: theme)
    }
}
