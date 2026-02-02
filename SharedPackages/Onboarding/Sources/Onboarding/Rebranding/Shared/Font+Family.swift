//
//  Font+Family.swift
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

// NOTE: This helper is currently colocated within Onboarding package while the rebranding is being validated there first.
// Keep the API generic so it can be moved to a shared typography module when rollout expands.
public extension Font {

    /// Font family selector used by app typography tokens.
    enum Family: Equatable {

        /// Custom app font families.
        public enum Custom {
            /// DuckSans Display family.
            case duckSansDisplay
            /// DuckSans Product family.
            case duckSansProduct
        }

        /// System font family.
        case system
        /// A custom font family.
        case custom(Custom)

        static let duckSansDisplay = Family.custom(.duckSansDisplay)
        static let duckSansProduct = Family.custom(.duckSansProduct)
    }

    /// Builds a concrete `Font` from a custom family, weight, and size.
    static func customFont(type: Font.Family.Custom, weight: Font.Weight, size: CGFloat) -> Font {
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
        }

        let fontName = "\(baseName)-\(weightSuffix)"
        return .custom(fontName, size: size)
    }

}
