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
                           addToolbarShadow: true)
    }
}
