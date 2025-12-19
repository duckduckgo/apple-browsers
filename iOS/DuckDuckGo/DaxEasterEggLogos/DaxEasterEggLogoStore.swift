//
//  DaxEasterEggLogoStore.swift
//  DuckDuckGo
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

import Core
import Foundation

/// Persists the user's selected Dax Easter Egg logo URL for display on SERP pages.
protocol DaxEasterEggLogoStoring {
    /// The stored logo URL, or nil if none is set.
    var logoURL: String? { get }
    /// Whether a logo is currently set.
    var hasLogo: Bool { get }
    /// Saves the logo URL.
    func setLogo(url: String)
    /// Removes the stored logo.
    func clearLogo()
}

extension NSNotification.Name {
    static let logoDidChangeNotification = Notification.Name("DaxEasterEggLogoStore.logoDidChange")
}

final class DaxEasterEggLogoStore: DaxEasterEggLogoStoring {

    @UserDefaultsWrapper(key: .daxEasterEggLogoURL, defaultValue: nil)
    private var storedLogoURL: String? {
        didSet {
            NotificationCenter.default.post(name: .logoDidChangeNotification, object: nil)
        }
    }

    var logoURL: String? { storedLogoURL }

    var hasLogo: Bool { storedLogoURL != nil }

    func setLogo(url: String) {
        storedLogoURL = url
    }

    func clearLogo() {
        storedLogoURL = nil
    }
}
