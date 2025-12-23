//
//  UIKitDynamicColor.swift
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

import SwiftUI

#if canImport(UIKit)
extension DynamicColor {
    var uiColor: UIColor {
        UIColor(dynamicProvider: dynamicProvider)
    }

    var dynamicProvider: (UITraitCollection) -> UIColor {
        { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .light: return UIColor(lightColor)
            case .dark: return UIColor(darkColor)
            case .unspecified: return UIColor(lightColor)
            @unknown default: return UIColor(lightColor)
            }
        }
    }

    var color: Color {
        Color(uiColor)
    }
}
#endif
