//
//  NewTabPageTheme.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import DesignResourcesKit
import UIKit

/// A background choice for the redesigned New Tab Page.
enum NewTabPageTheme: String, CaseIterable {

    case blue
    case plain

    static let `default` = NewTabPageTheme.blue

    /// Artwork behind the page, or `nil` for a flat page.
    var backgroundImage: UIImage? {
        switch self {
        case .blue: return UIImage(resource: .backgroundPond)
        case .plain: return nil
        }
    }

    /// Preview shown for this theme in the customization sheet.
    var tileImage: UIImage {
        switch self {
        case .blue: return UIImage(resource: .themeBlue)
        case .plain: return UIImage(resource: .themePlain)
        }
    }

    var title: String {
        switch self {
        case .blue: return UserText.newTabPageCustomizationThemeBlue
        case .plain: return UserText.newTabPageCustomizationThemePlain
        }
    }

    /// Tint of the search card and modules, tuned to this theme's artwork.
    var cardTint: NewTabPageThemeTint {
        switch self {
        case .blue: return .both(UIColor(singleUseColor: .newTabPageSearchCardBackground))
        case .plain: return .none
        }
    }

    /// Fill for the search card and modules: the theme's tint where it has one, the standard surface elsewhere.
    var cardBackgroundColor: UIColor {
        cardTint.color(over: UIColor(designSystemColor: .surface))
    }
}

/// A theme's surface tint. An appearance without a tint keeps the standard surface.
struct NewTabPageThemeTint {

    let light: UIColor?
    let dark: UIColor?

    static let none = NewTabPageThemeTint(light: nil, dark: nil)

    static func both(_ color: UIColor) -> NewTabPageThemeTint {
        NewTabPageThemeTint(light: color, dark: color)
    }

    static func darkOnly(_ color: UIColor) -> NewTabPageThemeTint {
        NewTabPageThemeTint(light: nil, dark: color)
    }

    func color(over standardColor: UIColor) -> UIColor {
        UIColor { traits in
            let tint = traits.userInterfaceStyle == .dark ? dark : light
            return (tint ?? standardColor).resolvedColor(with: traits)
        }
    }
}
