//
//  AppIcon.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import SwiftUI
import UIKit

enum AppIcon: String, CaseIterable {
    case red = "AppIcon-red"
    case pink = "AppIcon-pink"
    case purple = "AppIcon-purple"
    case yellow = "AppIcon-yellow"
    case green = "AppIcon-green"
    case blue = "AppIcon-blue"
    case black = "AppIcon-black"
    case white = "AppIcon-white"

    var accessibilityName: String {
        switch self {
        case .red: "red"
        case .pink: "pink"
        case .yellow: "yellow"
        case .white: "white"
        case .green: "green"
        case .blue: "blue"
        case .purple: "purple"
        case .black: "black"
        }
    }

    static var defaultAppIcon: AppIcon {
        return .red
    }

    // These images not part of the design system
    var smallImage: UIImage {
        switch self {
        case .red:
            return UIImage(resource: .appIconRedSmall)
        case .pink:
            return UIImage(resource: .appIconPinkSmall)
        case .yellow:
            return UIImage(resource: .appIconYellowSmall)
        case .white:
            return UIImage(resource: .appIconWhiteSmall)
        case .green:
            return UIImage(resource: .appIconGreenSmall)
        case .blue:
            return UIImage(resource: .appIconBlueSmall)
        case .purple:
            return UIImage(resource: .appIconPurpleSmall)
        case .black:
            return UIImage(resource: .appIconBlackSmall)
        }
    }

    // These images not part of the design system
    var mediumImage: UIImage {
        switch self {
        case .red:
            return UIImage(resource: .appIconRedMedium)
        case .pink:
            return UIImage(resource: .appIconPinkMedium)
        case .yellow:
            return UIImage(resource: .appIconYellowMedium)
        case .white:
            return UIImage(resource: .appIconWhiteMedium)
        case .green:
            return UIImage(resource: .appIconGreenMedium)
        case .blue:
            return UIImage(resource: .appIconBlueMedium)
        case .purple:
            return UIImage(resource: .appIconPurpleMedium)
        case .black:
            return UIImage(resource: .appIconBlackMedium)
        }
    }

    var color: Color {
        switch self {
        case .red:
            return Color(0xF05F2B)
        case .pink:
            return Color(0xD577A5)
        case .yellow:
            return Color(0xE8952D)
        case .white:
            return Color(0xE6E6E6)
        case .green:
            return Color(0x247A64)
        case .blue:
            return Color(0x1074CC)
        case .purple:
            return Color(0x7D4794)
        case .black:
            return Color(0x222222)
        }
    }
}
