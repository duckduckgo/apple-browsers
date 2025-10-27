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
import Persistence

/// Handles logic and persistence of customization options.
class MobileCustomization {

    struct State {

        var isEnabled: Bool
        var currentToolbarButton: MobileCustomization.Button
        var currentAddressBarButton: MobileCustomization.Button

        static let `default` = State(isEnabled: false,
                                     currentToolbarButton: MobileCustomization.toolbarDefault,
                                     currentAddressBarButton: MobileCustomization.addressBarDefault)

    }

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

    static let addressBarDefault: Button = .share
    static let toolbarDefault: Button = .fire

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

    var state: State {
        State(isEnabled: featureFlagger.isFeatureOn(.mobileCustomization),
              currentToolbarButton: current(forKey: .toolbarButton, Self.toolbarDefault),
              currentAddressBarButton: current(forKey: .addressBarButton, Self.toolbarDefault))
    }

    private let featureFlagger: FeatureFlagger
    private let keyValueStore: ThrowingKeyValueStoring

    static func descriptionComparison(lhs: CustomStringConvertible, rhs: CustomStringConvertible) -> Bool {
        lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending
    }

    enum StorageKeys: String {

        case toolbarButton = "mobileCustomizationToolbarButton"
        case addressBarButton = "mobileCustomizationAddressBarButton"

    }

    init(featureFlagger: FeatureFlagger, keyValueStore: ThrowingKeyValueStoring) {
        self.featureFlagger = featureFlagger
        self.keyValueStore = keyValueStore
    }

    private func current(forKey key: StorageKeys, _ defaultButton: Button) -> Button {
        if let value = try? keyValueStore.object(forKey: key.rawValue) as? String {
            Button(rawValue: value) ?? defaultButton
        } else {
            defaultButton
        }
    }

    func persist(_ state: State) {
        setCurrentToolbarButton(state.currentToolbarButton)
        setCurrentAddressBarButton(state.currentAddressBarButton)
    }

    private func setCurrentToolbarButton(_ button: Button) {
        try? keyValueStore.set(button.rawValue, forKey: StorageKeys.toolbarButton.rawValue)
    }

    private func setCurrentAddressBarButton(_ button: Button) {
        try? keyValueStore.set(button.rawValue, forKey: StorageKeys.addressBarButton.rawValue)
    }

}
