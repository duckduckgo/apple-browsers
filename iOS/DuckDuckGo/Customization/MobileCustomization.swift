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
import DesignResourcesKitIcons
import UIKit

/// Handles logic and persistence of customization options.  iPad is not supported so this returns false for `isEnabled` on iPad.
class MobileCustomization {

    protocol Delegate: AnyObject {
        func canEditBookmark() -> Bool
        func canEditFavorite() -> Bool
    }

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
            case .addEditBookmark:
                "Add Bookmark"
            case .addEditFavorite:
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
            case .downloads:
                "Downloads"
            }
        }

        var altLargeIcon: UIImage? {
            switch self {
            case .addEditBookmark: DesignSystemImages.Glyphs.Size24.bookmarkSolid
            case .addEditFavorite: DesignSystemImages.Glyphs.Size24.favoriteSolid
            default: nil
            }
        }

        var largeIcon: UIImage? {
            switch self {
            case .share:
                DesignSystemImages.Glyphs.Size24.shareApple
            case .addEditBookmark:
                DesignSystemImages.Glyphs.Size24.bookmark
            case .addEditFavorite:
                DesignSystemImages.Glyphs.Size24.favorite
            case .zoom:
                DesignSystemImages.Glyphs.Size24.typeSize
            case .none:
                nil
            case .home:
                DesignSystemImages.Glyphs.Size24.home
            case .newTab:
                DesignSystemImages.Glyphs.Size24.add
            case .bookmarks:
                DesignSystemImages.Glyphs.Size24.bookmarks
            case .duckAi:
                DesignSystemImages.Glyphs.Size24.aiChat
            case .fire:
                DesignSystemImages.Glyphs.Size24.fireSolid
            case .vpn:
                DesignSystemImages.Glyphs.Size24.vpn
            case .passwords:
                DesignSystemImages.Glyphs.Size24.key
            case .voiceSearch:
                DesignSystemImages.Glyphs.Size24.microphone
            case .downloads:
                DesignSystemImages.Glyphs.Size24.downloads
            }
        }

        var smallIcon: UIImage? {
            switch self {
            case .share:
                DesignSystemImages.Glyphs.Size16.shareApple
            case .addEditBookmark:
                DesignSystemImages.Glyphs.Size16.bookmark
            case .addEditFavorite:
                DesignSystemImages.Glyphs.Size16.favorite
            case .zoom:
                DesignSystemImages.Glyphs.Size16.typeSize
            case .none:
                nil
            case .home:
                DesignSystemImages.Glyphs.Size16.home
            case .newTab:
                DesignSystemImages.Glyphs.Size16.add
            case .bookmarks:
                DesignSystemImages.Glyphs.Size16.bookmarks
            case .duckAi:
                DesignSystemImages.Glyphs.Size16.aiChat
            case .fire:
                DesignSystemImages.Glyphs.Size16.fireSolid
            case .vpn:
                DesignSystemImages.Glyphs.Size16.vpnOn
            case .passwords:
                DesignSystemImages.Glyphs.Size16.keyLogin
            case .voiceSearch:
                DesignSystemImages.Glyphs.Size16.microphone
            case .downloads:
                DesignSystemImages.Glyphs.Size16.downloads
            }
        }

        // Generally address bar specific
        case share
        case addEditBookmark
        case addEditFavorite
        case voiceSearch
        case zoom
        case none

        // Generally toolbar specific
        case home
        case newTab
        case bookmarks
        case duckAi
        case downloads

        // Shared
        case fire
        case vpn
        case passwords
    }

    static let addressBarDefault: Button = .share
    static let toolbarDefault: Button = .fire

    static let addressBarButtons: [Button?] = {
        let sortedButtons: [Button] = [
            .addEditBookmark,
            .addEditFavorite,
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
            .vpn,
            .downloads,
        ].sorted(by: descriptionComparison)

        return [.fire] // default
            + sortedButtons

    }()

    var state: State {
        State(isEnabled: featureFlagger.isFeatureOn(.mobileCustomization) && !isPad,
              currentToolbarButton: current(forKey: .toolbarButton, Self.toolbarDefault),
              currentAddressBarButton: current(forKey: .addressBarButton, Self.addressBarDefault))
    }

    private let featureFlagger: FeatureFlagger
    private let keyValueStore: ThrowingKeyValueStoring
    private let isPad: Bool
    private let postChangeNotification: (State) -> Void

    public weak var delegate: Delegate?

    static func descriptionComparison(lhs: CustomStringConvertible, rhs: CustomStringConvertible) -> Bool {
        lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending
    }

    enum StorageKeys: String {

        case toolbarButton = "mobileCustomizationToolbarButton"
        case addressBarButton = "mobileCustomizationAddressBarButton"

    }

    init(featureFlagger: FeatureFlagger,
         keyValueStore: ThrowingKeyValueStoring,
         isPad: Bool = UIDevice.current.userInterfaceIdiom == .pad,
         postChangeNotification: @escaping ((State) -> Void) = {
            NotificationCenter.default.post(name: AppUserDefaults.Notifications.customizationSettingsChanged, object: $0)
        }
    ) {
        self.featureFlagger = featureFlagger
        self.keyValueStore = keyValueStore
        self.isPad = isPad
        self.postChangeNotification = postChangeNotification
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
        postChangeNotification(state)
    }

    private func setCurrentToolbarButton(_ button: Button) {
        try? keyValueStore.set(button.rawValue, forKey: StorageKeys.toolbarButton.rawValue)
    }

    private func setCurrentAddressBarButton(_ button: Button) {
        try? keyValueStore.set(button.rawValue, forKey: StorageKeys.addressBarButton.rawValue)
    }

    func largeIconForButton(_ button: Button) -> UIImage? {

        switch button {
        case .addEditBookmark:
            return delegate?.canEditBookmark() == true ? button.altLargeIcon : button.largeIcon

        case .addEditFavorite:
            return delegate?.canEditFavorite() == true ? button.altLargeIcon : button.largeIcon

        default:
            return button.largeIcon
        }

    }

}
