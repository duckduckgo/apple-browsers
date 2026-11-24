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

    /// Fill for the search card and focused input: tuned to the artwork when there is one, the standard surface on a flat page.
    var cardBackgroundColor: UIColor {
        switch self {
        case .blue: return UIColor(singleUseColor: .newTabPageSearchCardBackground)
        case .plain: return UIColor(designSystemColor: .surface)
        }
    }
}
