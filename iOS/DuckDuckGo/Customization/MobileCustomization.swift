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
import Core

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

    enum Button: String, Hashable, CaseIterable {

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
            case .fire:
                DesignSystemImages.Glyphs.Size24.fireSolid
            case .vpn:
                DesignSystemImages.Glyphs.Size24.vpn
            case .passwords:
                DesignSystemImages.Glyphs.Size24.key
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
            case .fire:
                DesignSystemImages.Glyphs.Size16.fireSolid
            case .vpn:
                DesignSystemImages.Glyphs.Size16.vpnOn
            case .passwords:
                DesignSystemImages.Glyphs.Size16.keyLogin
            case .downloads:
                DesignSystemImages.Glyphs.Size16.downloads
            }
        }

        // Generally address bar specific
        case share
        case addEditBookmark
        case addEditFavorite
        case zoom
        case none

        // Generally toolbar specific
        case home
        case newTab
        case bookmarks
        case downloads
        case passwords

        // Shared
        case fire
        case vpn
    }

    static let addressBarDefault: Button = .share
    static let toolbarDefault: Button = .fire

    static let addressBarButtons: [Button] = [
            .share,
            .addEditBookmark,
            .addEditFavorite,
            .fire,
            .vpn,
            .zoom,
            .none
        ]

    static let toolbarButtons: [Button] = [
            .fire,
            .bookmarks,
            .home,
            .newTab,
            .passwords,
            .share,
            .vpn,
            .downloads,
        ]

    var state: State {
        State(isEnabled: isEnabled,
              currentToolbarButton: current(forKey: .toolbarButton, containedIn: Self.toolbarButtons, Self.toolbarDefault),
              currentAddressBarButton: current(forKey: .addressBarButton, containedIn: Self.addressBarButtons.compactMap { $0 }, Self.addressBarDefault))
    }

    var hasFireButton: Bool {
        return state.currentToolbarButton == .fire || state.currentAddressBarButton == .fire
    }

    var isEnabled: Bool {
        !isPad
    }

    private let keyValueStore: ThrowingKeyValueStoring
    private let isPad: Bool
    private let postChangeNotification: (State) -> Void
    private let pixelFiring: PixelFiring.Type

    public weak var delegate: Delegate?

    enum StorageKeys: String {

        case toolbarButton = "mobileCustomizationToolbarButton"
        case addressBarButton = "mobileCustomizationAddressBarButton"

    }

    init(keyValueStore: ThrowingKeyValueStoring,
         isPad: Bool = UIDevice.current.userInterfaceIdiom == .pad,
         postChangeNotification: @escaping ((State) -> Void) = {
            NotificationCenter.default.post(name: AppUserDefaults.Notifications.customizationSettingsChanged, object: $0)
         },
         pixelFiring: PixelFiring.Type = Pixel.self
    ) {
        self.keyValueStore = keyValueStore
        self.isPad = isPad
        self.postChangeNotification = postChangeNotification
        self.pixelFiring = pixelFiring
    }

    /// Get the current button for the given storage key.  If the button isn't in the alloweed list then the default is returned.  This prevents migration problems if the options change.
    private func current(forKey key: StorageKeys, containedIn allowed: [Button], _ defaultButton: Button) -> Button {
        guard let value = try? keyValueStore.object(forKey: key.rawValue) as? String,
              let button = Button(rawValue: value),
              allowed.contains(button) else {
                  return defaultButton
              }

        return button
    }

    func persist(_ state: State) {
        setCurrentToolbarButton(state.currentToolbarButton)
        setCurrentAddressBarButton(state.currentAddressBarButton)
        postChangeNotification(state)
    }

    func fireAddressBarCustomizationStartedPixel() {
        pixelFiring.fire(.customizationAddressBarStarted, withAdditionalParameters: [:])
    }

    func fireAddressBarCustomizationSelectedPixel(oldValue: Button) {
        // Use all cases for this check as we don't want to return the default unless it was actually selected
        if oldValue != current(forKey: .addressBarButton, containedIn: Button.allCases, Self.addressBarDefault) {
            pixelFiring.fire(.customizationAddressBarSelected, withAdditionalParameters: [
                "selected": state.currentAddressBarButton.rawValue
            ])
        }
    }

    func fireToolbarCustomizationStartedPixel() {
        pixelFiring.fire(.customizationToolbarStarted, withAdditionalParameters: [:])
    }

    func fireToolbarCustomizationSelectedPixel(oldValue: Button) {
        // Use all cases for this check as we don't want to return the default unless it was actually selected
        if oldValue != current(forKey: .toolbarButton, containedIn: Button.allCases, Self.toolbarDefault) {
            pixelFiring.fire(.customizationToolbarSelected, withAdditionalParameters: [
                "selected": state.currentToolbarButton.rawValue
            ])
        }
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
