//
//  VisualStyleProviding.swift
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

import AppKit
import Combine
import BrowserServicesKit
import FeatureFlags
import NetworkProtectionUI
import DesignResourcesKit
import PixelKit

protocol VisualStyleProviding {
    var toolbarButtonsCornerRadius: CGFloat { get }
    var fireWindowGraphic: NSImage { get }
    var areNavigationBarCornersRound: Bool { get }
    var fireButtonSize: CGFloat { get }
    var navigationToolbarButtonsSpacing: CGFloat { get }
    var tabBarButtonSize: CGFloat { get }
    var addToolbarShadow: Bool { get }

    var addressBarStyleProvider: AddressBarStyleProviding { get }
    var tabStyleProvider: TabStyleProviding { get }
    var colorsProvider: ColorsProviding { get }
    var iconsProvider: IconsProviding { get }

    var isNewStyle: Bool { get }
}

protocol VisualStyleDecider {
    var style: any VisualStyleProviding { get }

    func shouldFirePixel(style: VisualStyleProviding) -> Bool
}

enum AddressBarSizeClass {
    case `default`
    case homePage
    case popUpWindow

    var logoWidth: CGFloat {
        switch self {
        case .homePage: 44
        case .popUpWindow, .default: 0
        }
    }

    var isLogoVisible: Bool {
        switch self {
        case .homePage: true
        case .popUpWindow, .default: false
        }
    }
}

struct VisualStyle: VisualStyleProviding {
    let toolbarButtonsCornerRadius: CGFloat
    let fireWindowGraphic: NSImage
    let areNavigationBarCornersRound: Bool

    let addressBarStyleProvider: AddressBarStyleProviding
    let tabStyleProvider: TabStyleProviding
    let colorsProvider: ColorsProviding
    let iconsProvider: IconsProviding
    let fireButtonSize: CGFloat
    let navigationToolbarButtonsSpacing: CGFloat
    let tabBarButtonSize: CGFloat
    let addToolbarShadow: Bool
    let isNewStyle: Bool

    static var legacy: VisualStyleProviding {
        return VisualStyle(toolbarButtonsCornerRadius: 4,
                           fireWindowGraphic: .burnerWindowGraphic,
                           areNavigationBarCornersRound: false,
                           addressBarStyleProvider: LegacyAddressBarStyleProvider(),
                           tabStyleProvider: LegacyTabStyleProvider(),
                           colorsProvider: LegacyColorsProviding(),
                           iconsProvider: LegacyIconsProvider(),
                           fireButtonSize: 28,
                           navigationToolbarButtonsSpacing: 0,
                           tabBarButtonSize: 28,
                           addToolbarShadow: false,
                           isNewStyle: false)
    }

    static var current: VisualStyleProviding {
        let palette = NewColorPalette()
        return VisualStyle(toolbarButtonsCornerRadius: 9,
                           fireWindowGraphic: .burnerWindowGraphicNew,
                           areNavigationBarCornersRound: true,
                           addressBarStyleProvider: CurrentAddressBarStyleProvider(),
                           tabStyleProvider: NewlineTabStyleProvider(palette: palette),
                           colorsProvider: NewColorsProviding(palette: palette),
                           iconsProvider: CurrentIconsProvider(),
                           fireButtonSize: 32,
                           navigationToolbarButtonsSpacing: 2,
                           tabBarButtonSize: 28,
                           addToolbarShadow: true,
                           isNewStyle: true)
    }
}

final class DefaultVisualStyleDecider: VisualStyleDecider {
    private let featureFlagger: FeatureFlagger
    private let internalUserDecider: InternalUserDecider

    init(featureFlagger: FeatureFlagger, internalUserDecider: InternalUserDecider) {
        self.featureFlagger = featureFlagger
        self.internalUserDecider = internalUserDecider
    }

    var style: any VisualStyleProviding {
        var isVisualRefreshEnabled: Bool = featureFlagger.isFeatureOn(.visualUpdates)

        if internalUserDecider.isInternalUser {
            isVisualRefreshEnabled = featureFlagger.isFeatureOn(.visualUpdatesInternalOnly)
        }

        return isVisualRefreshEnabled ? VisualStyle.current : VisualStyle.legacy
    }

    func shouldFirePixel(style: any VisualStyleProviding) -> Bool {
        return !internalUserDecider.isInternalUser && style.isNewStyle
    }
}

/// This enum keeps pixels related to the Visual Refresh
/// > Related links:
/// [Pixel Triage](https://app.asana.com/1/137249556945/project/69071770703008/task/1210516955340232)
enum VisualStylePixel: PixelKitEventV2 {

    /// This pixel will be fired once time per user. The logic will be fired at app launch if the user has the new UI enabled and it is not an internal user.
    case visualUpdatesEnabled

    var name: String {
        switch self {
        case .visualUpdatesEnabled:
            return "visual_update_enabled_u"
        }
    }

    var parameters: [String: String]? {
        nil
    }

    var error: (any Error)? {
        nil
    }
}
