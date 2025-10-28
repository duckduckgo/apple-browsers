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
    /// Is customization enabled as a feature?
    let isEnabled: Bool
    let keyValueStore: ThrowingKeyValueStoring

    static func descriptionComparison(lhs: CustomStringConvertible, rhs: CustomStringConvertible) -> Bool {
        lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending
    }

    enum StorageKeys: String {

        case toolbarButton = "mobileCustomizationToolbarButton"
        case addressBarButton = "mobileCustomizationAddressBarButton"

    }

    init(isEnabled: Bool, keyValueStore: ThrowingKeyValueStoring) {
        self.isEnabled = isEnabled
        self.keyValueStore = keyValueStore
    }

    private func current(forKey key: StorageKeys, _ defaultButton: Button) -> Button {
        if let value = try? keyValueStore.object(forKey: key.rawValue) as? String {
            Button(rawValue: value) ?? defaultButton
        } else {
            defaultButton
        }
    }

    public var currentAddressBarButton: Button {
        get {
            current(forKey: .addressBarButton, Self.addressBarDefault)
        }

        set {
            try? keyValueStore.set(newValue.rawValue, forKey: StorageKeys.addressBarButton.rawValue)
        }
    }

    public var currentToolbarButton: Button {
        get {
            current(forKey: .toolbarButton, Self.toolbarDefault)
        }

        set {
            try? keyValueStore.set(newValue.rawValue, forKey: StorageKeys.toolbarButton.rawValue)
        }
    }

}

// Using FeatureFlagger
extension MobileCustomization {

    /// @param featureFlagger - the app's feature flagger
    /// @param keyValueStore - the app's key value store
    static func load(featureFlagger: FeatureFlagger, keyValueStore: ThrowingKeyValueStoring) -> MobileCustomization {
        return MobileCustomization(
            isEnabled: featureFlagger.isFeatureOn(.mobileCustomization),
            keyValueStore: keyValueStore)
    }

}

// For SettingsState defaults
extension MobileCustomization {

    static var defaults: MobileCustomization {
        MobileCustomization(
            isEnabled: false,
            keyValueStore: NilKeyValueStore()
        )
    }

    private struct NilKeyValueStore: ThrowingKeyValueStoring {
        func object(forKey defaultName: String) throws -> Any? {
            return nil
        }
        
        func set(_ value: Any?, forKey defaultName: String) throws { }

        func removeObject(forKey defaultName: String) throws { }
    }
}
