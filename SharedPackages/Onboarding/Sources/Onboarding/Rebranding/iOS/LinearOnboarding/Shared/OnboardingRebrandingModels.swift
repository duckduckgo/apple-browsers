//
//  OnboardingRebrandingModels.swift
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

#if os(iOS)
import SwiftUI
import UIKit

public extension OnboardingRebranding {

    public enum AppIcon: String, CaseIterable {
        case red = "AppIcon-red"
        case pink = "AppIcon-pink"
        case yellow = "AppIcon-yellow"
        case green = "AppIcon-green"
        case blue = "AppIcon-blue"
        case purple = "AppIcon-purple"
        case black = "AppIcon-black"

        var accessibilityName: String {
            switch self {
            case .red: "red"
            case .pink: "pink"
            case .yellow: "yellow"
            case .green: "green"
            case .blue: "blue"
            case .purple: "purple"
            case .black: "black"
            }
        }

        static var defaultAppIcon: AppIcon {
            .red
        }

        var smallImage: UIImage {
            switch self {
            case .red: UIImage(resource: .appIconRedSmall)
            case .pink: UIImage(resource: .appIconPinkSmall)
            case .yellow: UIImage(resource: .appIconYellowSmall)
            case .green: UIImage(resource: .appIconGreenSmall)
            case .blue: UIImage(resource: .appIconBlueSmall)
            case .purple: UIImage(resource: .appIconPurpleSmall)
            case .black: UIImage(resource: .appIconBlackSmall)
            }
        }

        var mediumImage: UIImage {
            switch self {
            case .red: UIImage(resource: .appIconRedMedium)
            case .pink: UIImage(resource: .appIconPinkMedium)
            case .yellow: UIImage(resource: .appIconYellowMedium)
            case .green: UIImage(resource: .appIconGreenMedium)
            case .blue: UIImage(resource: .appIconBlueMedium)
            case .purple: UIImage(resource: .appIconPurpleMedium)
            case .black: UIImage(resource: .appIconBlackMedium)
            }
        }
    }

    public enum AddressBarPosition: String, CaseIterable {
        case top
        case bottom

        var isBottom: Bool {
            self == .bottom
        }
    }

    public protocol AppIconProviding {
        var appIcon: AppIcon { get }
    }

    public protocol AppIconManaging: AppIconProviding {
        func changeAppIcon(_ appIcon: AppIcon, completionHandler: ((Error?) -> Void)?)
    }

    public protocol AddressBarPositionManaging: AnyObject {
        var currentAddressBarPosition: AddressBarPosition { get set }
    }
}
#endif
