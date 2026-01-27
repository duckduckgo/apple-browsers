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

// MARK: - OnboardingTheme

struct OnboardingTheme: Equatable {
    let typography: Typography
    let colorPalette: ColorPalette
}

extension OnboardingTheme {

    static let rebranding2026 = OnboardingTheme(
        typography: .duckSans,
        colorPalette: ColorPalette(backgroundColor: .white)
    )

}

// MARK: - OnboardingTheme + Typography

extension OnboardingTheme {

    struct Typography: Equatable {
        let largeTitle: Font
        let title: Font
        let body: Font
        let row: Font
        let rowDetails: Font
        let small: Font

        private static func makeFont(size: CGFloat, family: Font.Family, weight: Font.Weight) -> Font {
            switch family {
            case .system:
                return .system(size: size, weight: weight)
            case .duckSansDisplay, .duckSansProduct:
                return Font.customFont(type: family, weight: weight, size: size)
            }
        }
    }

}

extension OnboardingTheme.Typography {

    static let duckSans = OnboardingTheme.Typography(
        largeTitle: makeFont(size: 44, family: .duckSansDisplay, weight: .bold),
        title: makeFont(size: 24, family: .duckSansDisplay, weight: .bold),
        body: makeFont(size: 18, family: .duckSansProduct, weight: .regular),
        row: makeFont(size: 16, family: .duckSansProduct, weight: .medium),
        rowDetails: makeFont(size: 14, family: .duckSansProduct, weight: .regular),
        small: makeFont(size: 14, family: .duckSansProduct, weight: .regular)
    )

    // System font fallback for testing/preview
    static let system = OnboardingTheme.Typography(
        largeTitle: .system(size: 44, weight: .bold),
        title: .system(size: 24, weight: .bold),
        body: .system(size: 18, weight: .regular),
        row: .system(size: 16, weight: .medium),
        rowDetails: .system(size: 14, weight: .regular),
        small: .system(size: 14, weight: .regular)
    )

}

// MARK: - OnboardingTheme + Colors

extension OnboardingTheme {

    struct ColorPalette: Equatable {
        let backgroundColor: Color
    }

}
