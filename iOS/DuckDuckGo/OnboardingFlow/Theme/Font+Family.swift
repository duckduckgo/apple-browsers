//
//  FontFamily.swift
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

import SwiftUI

extension Font {

    enum Family: Equatable {
        case system
        case duckSansDisplay
        case duckSansProduct
    }

    static func customFont(type: Font.Family, weight: Font.Weight, size: CGFloat) -> Font {
        let weightSuffix: String
        switch weight {
        case .regular:
            weightSuffix = "Regular"
        case .medium:
            weightSuffix = "Medium"
        case .bold:
            weightSuffix = "Bold"
        default:
            // Fallback to Regular for any other weights
            weightSuffix = "Regular"
        }

        let baseName: String
        switch type {
        case .duckSansDisplay:
            baseName = "DuckSansDisplay"
        case .duckSansProduct:
            baseName = "DuckSansProduct"
        case .system:
            assertionFailure("customFont should not be called with .system")
            return .system(size: size, weight: weight)
        }

        let fontName = "\(baseName)-\(weightSuffix)"
        return .custom(fontName, size: size)
    }

}
