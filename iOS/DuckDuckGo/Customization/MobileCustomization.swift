//
//  MobileCustomization.swift
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

import BrowserServicesKit

// This may change to a class, but is just to get the feature flag in and testable for now.
struct MobileCustomization {

    enum Button: String, CustomStringConvertible {

        var description: String {
            switch self {
            case .share:
                "Share"
            case .addRemoveBookmark:
                "Add Bookmark"
            case .addRemoveFavorite:
                "Add Favorite"
            case .zoom:
                "Zoom"
            case .none:
                "None"
            case .home:
                "Home"
            case .newTab:
                "New Tab"
            case .bookmarks:
                "Bookmarks"
            case .duckAi:
                "Duck.ai"
            case .fire:
                "Clear Tabs and Data"
            case .vpn:
                "VPN"
            case .passwords:
                "Passwords"
            case .voiceSearch:
                "Voice Search"
            }
        }

        // Generally address bar specific
        case share
        case addRemoveBookmark
        case addRemoveFavorite
        case voiceSearch
        case zoom
        case none

        // Generally toolbar specific
        case home
        case newTab
        case bookmarks
        case duckAi

        // Shared
        case fire
        case vpn
        case passwords
    }

    static let addressBarButtons: [Button?] = {
        let sortedButtons: [Button] = [
            .addRemoveBookmark,
            .addRemoveFavorite,
            .fire,
            .vpn,
            .zoom,
        ].sorted(by: descriptionComparison)

        return [.share] // default
            + sortedButtons
            + [nil, Button.none] // none is at the end after the divider
    } ()

    static let toolbarButtons: [Button] = {
        let sortedButtons: [Button] = [
            .bookmarks,
            .duckAi,
            .home,
            .newTab,
            .passwords,
            .share,
            .vpn
        ].sorted(by: descriptionComparison)

        return [.fire] // default
            + sortedButtons

    }()
    /// Is customization enabled as a feature?
    let isEnabled: Bool

    static func descriptionComparison(lhs: CustomStringConvertible, rhs: CustomStringConvertible) -> Bool {
        lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending
    }

}

// Using FeatureFlagger
extension MobileCustomization {

    static func load(featureFlagger: FeatureFlagger) -> MobileCustomization {
        return MobileCustomization(isEnabled: featureFlagger.isFeatureOn(.mobileCustomization))
    }

}

// For SettingsState defaults
extension MobileCustomization {

    static var defaults: MobileCustomization {
        MobileCustomization(
            isEnabled: false
        )
    }

}
