//
//  DefaultTheme.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import UIKit
import DesignResourcesKit

// If you add a new colour here:
//  * and it uses the design system, please put it in Theme+DesignSystem instead
//  * and it doesn't use the design, please only do so with designer approval
struct DefaultTheme: Theme {
    let statusBarStyle: UIStatusBarStyle = .default
    let keyboardAppearance: UIKeyboardAppearance = .default
    let activityStyle: UIActivityIndicatorView.Style = .medium

    let destructiveColor = UIColor.red
}

extension UIColor {
    convenience init(lightColor: UIColor, darkColor: UIColor) {
        self.init {
            switch $0.userInterfaceStyle {
            case .dark: return darkColor
            case .light: return lightColor
            case .unspecified: return lightColor
            @unknown default: return lightColor
            }
        }
    }
}
