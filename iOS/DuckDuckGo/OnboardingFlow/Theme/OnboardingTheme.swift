//
//  OnboardingTheme.swift
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

// MARK: - Theme

struct OnboardingTheme: Equatable {
    let typography: Typography
    let colorPalette: ColorPalette
}


// MARK: - Typography

enum FontFamily: Equatable {
    case system
    case duckSansDisplay
    case duckSansProduct
}

struct Typography: Equatable {
    let largeTitle: Font
    let title: Font
    let body: Font
    let row: Font
    let rowDetails: Font
    let small: Font

    private static func makeFont(size: CGFloat, family: FontFamily, weight: Font.Weight) -> Font {
        switch family {
        case .system:
            return .system(size: size, weight: weight)
        case .duckSansDisplay:
            return customFont(baseName: "DuckSansDisplay", weight: weight, size: size)
        case .duckSansProduct:
            return customFont(baseName: "DuckSansProduct", weight: weight, size: size)
        }
    }

    private static func customFont(baseName: String, weight: Font.Weight, size: CGFloat) -> Font {
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

        let fontName = "\(baseName)-\(weightSuffix)"
        return .custom(fontName, size: size)
    }
}

extension Typography {

    static let duckSans = Typography(
        largeTitle: makeFont(size: 44, family: .duckSansDisplay, weight: .bold),
        title: makeFont(size: 24, family: .duckSansDisplay, weight: .bold),
        body: makeFont(size: 18, family: .duckSansProduct, weight: .regular),
        row: makeFont(size: 16, family: .duckSansProduct, weight: .medium),
        rowDetails: makeFont(size: 14, family: .duckSansProduct, weight: .regular),
        small: makeFont(size: 14, family: .duckSansProduct, weight: .regular)
    )

    // System font fallback for testing/preview
    static let system = Typography(
        largeTitle: .system(size: 44, weight: .bold),
        title: .system(size: 24, weight: .bold),
        body: .system(size: 18, weight: .regular),
        row: .system(size: 16, weight: .medium),
        rowDetails: .system(size: 14, weight: .regular),
        small: .system(size: 14, weight: .regular)
    )

}

// MARK: - Colors

extension OnboardingTheme {

    struct ColorPalette: Equatable {
        let backgroundColor: Color
    }

}
